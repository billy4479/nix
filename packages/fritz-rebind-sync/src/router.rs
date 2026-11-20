use anyhow::{Context, Result, ensure};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use reqwest::{
    Method,
    blocking::Client,
    header::{AUTHORIZATION, CONTENT_LENGTH, CONTENT_TYPE, HeaderValue, TRANSFER_ENCODING},
};
use rustls::{
    ClientConfig, DigitallySignedStruct, Error, SignatureScheme,
    client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
    crypto::{WebPkiSupportedAlgorithms, verify_tls12_signature, verify_tls13_signature},
    pki_types::{CertificateDer, ServerName, UnixTime},
    server::ParsedCertificate,
};
use sha2::{Digest, Sha256};
use std::{
    error::Error as StdError,
    io::{self, Read},
    net::Ipv4Addr,
    sync::Arc,
    time::Duration,
};

#[derive(Debug)]
struct PinnedKey {
    hash: [u8; 32],
    algorithms: WebPkiSupportedAlgorithms,
}

impl ServerCertVerifier for PinnedKey {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _: &[CertificateDer<'_>],
        _: &ServerName<'_>,
        _: &[u8],
        _: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        let cert = ParsedCertificate::try_from(end_entity)?;
        let actual: [u8; 32] = Sha256::digest(cert.subject_public_key_info().as_ref()).into();
        if actual == self.hash {
            Ok(ServerCertVerified::assertion())
        } else {
            Err(Error::General(
                "FRITZ!Box TLS public-key pin mismatch".into(),
            ))
        }
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        signature: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        verify_tls12_signature(message, cert, signature, &self.algorithms)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        signature: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        verify_tls13_signature(message, cert, signature, &self.algorithms)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algorithms.supported_schemes()
    }
}

pub struct Router {
    base: String,
    client: Client,
}

impl Router {
    pub fn new(address: Ipv4Addr, pin: &str) -> Result<Self> {
        let digest = STANDARD
            .decode(
                pin.strip_prefix("sha256//")
                    .context("HTTPS public-key pin required")?,
            )
            .context("invalid public-key pin encoding")?;
        let hash = digest
            .try_into()
            .map_err(|_| anyhow::anyhow!("public-key pin must be a SHA-256 digest"))?;
        let provider = rustls::crypto::ring::default_provider();
        let algorithms = provider.signature_verification_algorithms;
        let tls = ClientConfig::builder_with_provider(Arc::new(provider))
            .with_safe_default_protocol_versions()?
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(PinnedKey { hash, algorithms }))
            .with_no_client_auth();
        let client = Client::builder()
            .use_preconfigured_tls(tls)
            .https_only(true)
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .retry(reqwest::retry::never())
            .connect_timeout(Duration::from_secs(3))
            .timeout(Duration::from_secs(8))
            .build()?;
        Ok(Self {
            base: format!("https://{address}"),
            client,
        })
    }

    pub fn request(
        &self,
        method: Method,
        path: &str,
        sid: Option<&str>,
        data: Option<(&str, &str)>,
    ) -> Result<String> {
        let mut request = self
            .client
            .request(method.clone(), format!("{}{path}", self.base));
        if let Some(sid) = sid {
            let mut token = HeaderValue::from_str(&format!("AVM-SID {sid}"))?;
            token.set_sensitive(true);
            request = request.header(AUTHORIZATION, token);
        }
        if let Some((mime, body)) = data {
            request = request.header(CONTENT_TYPE, mime).body(body.to_owned());
        }
        let mut response = request
            .send()
            .with_context(|| format!("router {method} {path}"))?;
        let status = response.status();
        ensure!(
            status.is_success(),
            "router {method} {path} returned HTTP {status}"
        );
        let close_delimited = !response.headers().contains_key(CONTENT_LENGTH)
            && !response.headers().contains_key(TRANSFER_ENCODING);
        let mut body = Vec::new();
        if let Err(error) = response.read_to_end(&mut body) {
            // FRITZ!OS login may end a close-delimited HTTP/1.1 body without TLS close_notify.
            // The caller still parses the entire XML/JSON reply or verifies the write by rereading.
            if !close_delimited || !unexpected_eof(&error) {
                return Err(error).with_context(|| format!("read router {method} {path} response"));
            }
        }
        String::from_utf8(body).context("router response was not UTF-8")
    }
}

fn unexpected_eof(error: &(dyn StdError + 'static)) -> bool {
    if let Some(error) = error.downcast_ref::<io::Error>() {
        if error.kind() == io::ErrorKind::UnexpectedEof {
            return true;
        }
        if let Some(inner) = error.get_ref() {
            return unexpected_eof(inner);
        }
    }
    error.source().is_some_and(unexpected_eof)
}
