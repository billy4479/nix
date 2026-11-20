mod router;

use anyhow::{Context, Result, bail, ensure};
use reqwest::Method;
use router::Router;
use serde::Deserialize;
use std::{collections::BTreeSet, fs};

const LOGIN: &str = "/login_sid.lua?version=2";
const API: &str = "/api/v0/generic/dns_excepted_domains";

#[derive(Deserialize)]
struct Config {
    address: std::net::Ipv4Addr,
    pin: String,
    zone: String,
    names: BTreeSet<String>,
    #[serde(default)]
    prune: bool,
}

#[derive(Deserialize)]
struct Entry {
    name: String,
    #[serde(rename = "UID")]
    uid: String,
}

#[derive(Deserialize)]
struct Entries {
    domain: Vec<Entry>,
}

fn form(router: &Router, fields: &[(&str, &str)]) -> Result<String> {
    let data = form_urlencoded::Serializer::new(String::new())
        .extend_pairs(fields)
        .finish();
    router.request(
        Method::POST,
        LOGIN,
        None,
        Some(("application/x-www-form-urlencoded", &data)),
    )
}

fn challenge_response(challenge: &str, password: &[u8]) -> Result<String> {
    let ["2", a, salt1, b, salt2] = challenge.split('$').collect::<Vec<_>>()[..] else {
        bail!("router did not provide a version 2 login challenge");
    };
    let (a, b): (u32, u32) = (a.parse()?, b.parse()?);
    ensure!(
        (1..=2_000_000).contains(&a) && (1..=2_000_000).contains(&b),
        "invalid login iteration count"
    );
    let key = pbkdf2::pbkdf2_hmac_array::<sha2::Sha256, 32>(password, &hex::decode(salt1)?, a);
    let response = pbkdf2::pbkdf2_hmac_array::<sha2::Sha256, 32>(&key, &hex::decode(salt2)?, b);
    Ok(format!("{salt2}${}", hex::encode(response)))
}

fn tag<'a>(doc: &'a roxmltree::Document<'_>, name: &str) -> Result<&'a str> {
    doc.root_element()
        .children()
        .find(|node| node.has_tag_name(name))
        .and_then(|node| node.text())
        .with_context(|| format!("missing {name} in login response"))
}

fn login(router: &Router, username: &str, password: &[u8]) -> Result<String> {
    let xml = router.request(Method::GET, LOGIN, None, None)?;
    let doc = roxmltree::Document::parse(&xml).context("parse login challenge")?;
    ensure!(
        tag(&doc, "BlockTime")? == "0",
        "router temporarily blocked login; not retrying"
    );
    let response = challenge_response(tag(&doc, "Challenge")?, password)?;
    let xml = form(router, &[("username", username), ("response", &response)])?;
    let doc = roxmltree::Document::parse(&xml).context("parse login result")?;
    let sid = tag(&doc, "SID")?;
    ensure!(
        sid.len() == 16 && sid.bytes().all(|b| b.is_ascii_hexdigit()) && sid != "0000000000000000",
        "router rejected login"
    );
    Ok(sid.into())
}

fn valid_name(name: &str) -> bool {
    name.len() <= 253
        && name.split('.').all(|label| {
            !label.is_empty()
                && label.len() <= 63
                && label
                    .bytes()
                    .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
                && !label.starts_with('-')
                && !label.ends_with('-')
        })
}

fn in_zone(name: &str, zone: &str) -> bool {
    name == zone
        || name
            .strip_suffix(zone)
            .is_some_and(|prefix| prefix.ends_with('.'))
}

fn list(router: &Router, sid: &str) -> Result<Vec<Entry>> {
    let response = router.request(Method::GET, API, Some(sid), None)?;
    let mut entries: Entries =
        serde_json::from_str(&response).context("unexpected rebind list response")?;
    for entry in &mut entries.domain {
        entry.name.make_ascii_lowercase();
        ensure!(
            !entry.uid.is_empty() && entry.uid.bytes().all(|b| b.is_ascii_alphanumeric()),
            "invalid router entry ID"
        );
    }
    Ok(entries.domain)
}

fn plan<'a>(config: &'a Config, entries: &'a [Entry]) -> (Vec<&'a str>, Vec<&'a Entry>) {
    let present: BTreeSet<_> = entries.iter().map(|entry| entry.name.as_str()).collect();
    let add = config
        .names
        .iter()
        .map(String::as_str)
        .filter(|name| !present.contains(name))
        .collect();
    let remove = entries
        .iter()
        .filter(|entry| {
            config.prune
                && in_zone(&entry.name, &config.zone)
                && !config.names.contains(&entry.name)
        })
        .collect();
    (add, remove)
}

fn sync(config: &Config, router: &Router, sid: &str, apply: bool) -> Result<()> {
    let before = list(router, sid)?;
    let (add, remove) = plan(config, &before);
    for name in &add {
        println!("add {name}");
        if apply {
            let body = serde_json::json!({ "name": name }).to_string();
            router.request(
                Method::POST,
                &format!("{API}/domain"),
                Some(sid),
                Some(("application/json", &body)),
            )?;
        }
    }
    if apply && !add.is_empty() {
        ensure!(
            plan(config, &list(router, sid)?).0.is_empty(),
            "router did not save all additions; not pruning"
        );
    }
    for entry in &remove {
        println!("remove {}", entry.name);
        if apply {
            router.request(
                Method::DELETE,
                &format!("{API}/domain/{}", entry.uid),
                Some(sid),
                None,
            )?;
        }
    }
    if apply && !remove.is_empty() {
        let after = list(router, sid)?;
        let (add, remove) = plan(config, &after);
        ensure!(
            add.is_empty() && remove.is_empty(),
            "router did not converge"
        );
    }
    if add.is_empty() && remove.is_empty() {
        println!("DNS rebind exceptions already in sync");
    }
    Ok(())
}

fn main() -> Result<()> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    let [mode, manifest, credential] = &args[..] else {
        bail!("usage: fritz-rebind-sync --dry-run|--apply MANIFEST CREDENTIAL")
    };
    ensure!(
        matches!(mode.as_str(), "--dry-run" | "--apply"),
        "invalid mode"
    );
    let config: Config = serde_json::from_slice(&fs::read(manifest)?)?;
    let router = Router::new(config.address, &config.pin)?;
    ensure!(
        valid_name(&config.zone)
            && config.zone.contains('.')
            && !config.names.is_empty()
            && config
                .names
                .iter()
                .all(|name| valid_name(name) && in_zone(name, &config.zone)),
        "invalid manifest names or scope"
    );
    let secret = fs::read_to_string(credential).context("read router credential")?;
    let (username, password) = secret
        .trim_end_matches(['\n', '\r'])
        .split_once('\n')
        .context("credential must be username and password on separate lines")?;
    ensure!(
        !username.is_empty() && !password.is_empty(),
        "empty router credential"
    );
    let sid = login(
        &router,
        username.trim_end_matches('\r'),
        password.as_bytes(),
    )?;
    let result = sync(&config, &router, &sid, mode == "--apply");
    if form(&router, &[("logout", "1"), ("sid", &sid)]).is_err() {
        eprintln!("warning: could not close router session");
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reconcile_only_owned_zone_when_pruning() {
        let mut config = Config {
            address: "192.168.2.1".parse().unwrap(),
            pin: String::new(),
            zone: "example.org".into(),
            names: ["example.org".into(), "app.example.org".into()].into(),
            prune: true,
        };
        let entries: Vec<_> = ["example.org", "old.example.org", "notexample.org"]
            .into_iter()
            .map(|name| Entry {
                name: name.into(),
                uid: name.into(),
            })
            .collect();
        let (add, remove) = plan(&config, &entries);
        assert_eq!(add, ["app.example.org"]);
        assert_eq!(
            remove
                .iter()
                .map(|entry| entry.name.as_str())
                .collect::<Vec<_>>(),
            ["old.example.org"]
        );
        config.prune = false;
        assert!(plan(&config, &entries).1.is_empty());
    }
}
