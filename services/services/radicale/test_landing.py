import base64
import hashlib
import json
import os
import re
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlencode, urlsplit

from cryptography.fernet import Fernet
from joserfc import jwt
from joserfc.jwk import RSAKey
from landing import create_app
from requests import Response
from werkzeug.test import Client

ORIGIN = "https://calendar.test"
ISSUER = "https://idp.test"
CONFIG = Path(sys.argv.pop(1)).read_text()


class CalendarTest(unittest.TestCase):
    def test_oidc_enrollment_and_caldav_reset(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "radicale.conf"
            config.write_text(CONFIG.replace("/data/", directory + "/"))
            with patch.dict(
                os.environ,
                CALENDAR_ORIGIN=ORIGIN,
                CALENDAR_STATE=directory,
                OIDC_ISSUER=ISSUER,
                OIDC_CLIENT_ID="calendar",
                OIDC_CLIENT_SECRET="test-secret",
                CREDENTIAL_KEY=Fernet.generate_key().decode(),
                SESSION_SECRET="test-session-secret",
                RADICALE_CONFIG=str(config),
            ):
                self.exercise(create_app(), Path(directory))

    def exercise(self, app, directory):
        client = Client(app)
        second = Client(app)
        self.assertEqual(client.get("/healthz", base_url=ORIGIN).status_code, 200)
        self.assertEqual(
            client.get("/setup/callback?code=fake", base_url=ORIGIN).status_code, 400
        )
        self.assertEqual(client.post("/setup/reset", base_url=ORIGIN).status_code, 403)
        key = RSAKey.generate_key(2048, parameters={"kid": "test-key"})
        self.login(client, "userid:12", key)
        self.login(second, "userid:34", key)

        def setup(browser):
            response = browser.get("/setup/", base_url=ORIGIN)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.headers["Cache-Control"], "no-store")
            self.assertIn(ORIGIN + "/", response.text)
            password = re.search(r'autocomplete="off" value="([^"]+)"', response.text)[
                1
            ]
            csrf = re.search(r'name="csrf" value="([^"]+)"', response.text)[1]
            return password, csrf

        def dav(password=None, path="/", user="calendar-12"):
            headers = {"Depth": "0"}
            if password is not None:
                encoded = base64.b64encode(f"{user}:{password}".encode()).decode()
                headers["Authorization"] = f"Basic {encoded}"
            return Client(app).open(
                path, method="PROPFIND", base_url=ORIGIN, headers=headers
            )

        password, csrf = setup(client)
        other, _ = setup(second)
        self.assertEqual(setup(client)[0], password)
        self.assertNotIn(password, (directory / "htpasswd").read_text())
        self.assertEqual((directory / "htpasswd").stat().st_mode & 0o777, 0o600)
        self.assertNotEqual(password, other)
        self.assertEqual(dav().status_code, 401)
        self.assertEqual(dav(password).status_code, 207)
        self.assertEqual(dav(password, "/calendar-12/calendar/").status_code, 207)
        self.assertNotEqual(dav(password, "/calendar-34/").status_code, 207)
        self.assertEqual(dav(other, user="calendar-34").status_code, 207)
        self.assertEqual(dav(password, "/.well-known/caldav").status_code, 301)
        self.assertEqual(
            client.post(
                "/setup/reset", base_url=ORIGIN, data={"confirm": "yes"}
            ).status_code,
            403,
        )
        self.assertEqual(
            client.post(
                "/setup/reset", base_url=ORIGIN, data={"csrf": csrf}
            ).status_code,
            400,
        )
        self.assertEqual(
            client.post(
                "/setup/reset", base_url=ORIGIN, data={"csrf": csrf, "confirm": "yes"}
            ).status_code,
            303,
        )
        new_password, _ = setup(client)
        self.assertNotEqual(new_password, password)
        self.assertEqual(dav(password).status_code, 401)
        self.assertEqual(dav(new_password, "/calendar-12/calendar/").status_code, 207)
        self.assertEqual(setup(second)[0], other)
        self.assertEqual(dav(other, user="calendar-34").status_code, 207)

    def login(self, client, subject, key):
        def idp(_session, request, **_kwargs):
            path = urlsplit(request.url).path
            if path == "/.well-known/openid-configuration":
                result = {
                    "issuer": ISSUER,
                    "authorization_endpoint": ISSUER + "/authorize",
                    "token_endpoint": ISSUER + "/token",
                    "jwks_uri": ISSUER + "/jwks",
                    "id_token_signing_alg_values_supported": ["RS256"],
                }
            elif path == "/token":
                self.assertEqual(request.method, "POST")
                data = parse_qs(request.body)
                self.assertEqual(data["client_secret"], ["test-secret"])
                challenge = (
                    base64.urlsafe_b64encode(
                        hashlib.sha256(data["code_verifier"][0].encode()).digest()
                    )
                    .decode()
                    .rstrip("=")
                )
                self.assertEqual(query["code_challenge"], [challenge])
                now = int(time.time())
                result = {
                    "access_token": "opaque",
                    "token_type": "Bearer",
                    "id_token": jwt.encode(
                        {"alg": "RS256", "kid": "test-key"},
                        {
                            "iss": ISSUER,
                            "aud": ["calendar"],
                            "sub": subject,
                            "nonce": query["nonce"][0],
                            "iat": now,
                            "exp": now + 60,
                        },
                        key,
                    ),
                }
            elif path == "/jwks":
                result = {"keys": [key.as_dict(private=False)]}
            else:
                self.fail(f"Unexpected IdP request: {request.url}")
            response = Response()
            response.status_code = 200
            response._content = json.dumps(result).encode()
            return response

        with patch("requests.Session.send", idp):
            response = client.get("/setup/", base_url=ORIGIN)
            self.assertEqual(response.status_code, 302)
            query = parse_qs(urlsplit(response.location).query)
            self.assertEqual(query["redirect_uri"], [ORIGIN + "/setup/callback"])
            self.assertEqual(query["code_challenge_method"], ["S256"])
            params = urlencode({"code": "example-code", "state": query["state"][0]})
            response = client.get("/setup/callback?" + params, base_url=ORIGIN)
            self.assertEqual(response.status_code, 303, response.text)


if __name__ == "__main__":
    unittest.main()
