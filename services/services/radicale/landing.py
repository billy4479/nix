import os
import re
import secrets
from base64 import b64encode
from datetime import timedelta
from pathlib import Path

import radicale
from authlib.integrations.base_client import OAuthError
from authlib.integrations.flask_client import OAuth
from credentials import Credentials
from flask import Flask, abort, redirect, render_template, request, session
from joserfc.errors import JoseError
from requests.exceptions import RequestException
from werkzeug.wrappers import Request, Response


def create_app():
    origin = os.environ["CALENDAR_ORIGIN"]
    legacy_origin = os.environ.get("CALENDAR_LEGACY_ORIGIN")
    issuer = os.environ["OIDC_ISSUER"]
    store = Credentials(
        Path(os.environ["CALENDAR_STATE"]), os.environ["CREDENTIAL_KEY"]
    )
    app = Flask(__name__)
    app.config.update(
        SECRET_KEY=os.environ["SESSION_SECRET"],
        SESSION_COOKIE_NAME="calendar_setup",
        SESSION_COOKIE_PATH="/setup/",
        SESSION_COOKIE_SECURE=True,
        SESSION_COOKIE_SAMESITE="Lax",
        PERMANENT_SESSION_LIFETIME=timedelta(minutes=15),
        SESSION_REFRESH_EACH_REQUEST=False,
        MAX_CONTENT_LENGTH=4096,
    )
    oidc = OAuth(app).register(
        name="tsidp",
        client_id=os.environ["OIDC_CLIENT_ID"],
        client_secret=os.environ["OIDC_CLIENT_SECRET"],
        server_metadata_url=f"{issuer}/.well-known/openid-configuration",
        client_kwargs={
            "scope": "openid",
            "code_challenge_method": "S256",
            "token_endpoint_auth_method": "client_secret_post",
            "default_timeout": 10,
        },
    )

    @app.after_request
    def protect(response):
        response.headers["Cache-Control"] = "no-store"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Content-Security-Policy"] = (
            "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; "
            "frame-ancestors 'none'; base-uri 'none'"
        )
        return response

    @app.errorhandler(OAuthError)
    @app.errorhandler(JoseError)
    @app.errorhandler(RequestException)
    def oauth_failed(_error):
        session.clear()
        return 'Sign-in failed. <a href="/setup/">Try again</a>.', 400

    @app.get("/healthz")
    def health():
        return "ok\n"

    @app.get("/setup/")
    def setup():
        username = session.get("username")
        if username is None:
            # Keep the OAuth state cookie and callback on the same origin.
            # Never build a redirect URI from a client-controlled Host value.
            callback_origin = (
                legacy_origin if f"https://{request.host}" == legacy_origin else origin
            )
            return oidc.authorize_redirect(f"{callback_origin}/setup/callback")
        password = store.get(username)
        ensure_calendar(origin, username, password)
        return render_template(
            "setup.html",
            server=f"{origin}/",
            username=username,
            password=password,
            csrf=session["csrf"],
        )

    @app.get("/setup/callback")
    def callback():
        token = oidc.authorize_access_token(
            claims_options={"iss": {"values": [issuer]}}
        )
        # Authlib verifies the ID token signature, issuer, audience and nonce.
        # Do not use the opaque access token or a mutable email as identity.
        sub = (token.get("userinfo") or {}).get("sub")
        subject = (
            re.fullmatch(r"userid:([0-9]{1,20})", sub) if isinstance(sub, str) else None
        )
        if subject is None:
            abort(403)
        session.clear()
        session.permanent = True
        session["username"] = f"calendar-{subject[1]}"
        session["csrf"] = secrets.token_urlsafe(32)
        return redirect("/setup/", code=303)

    @app.post("/setup/reset")
    def reset():
        if "username" not in session or not secrets.compare_digest(
            request.form.get("csrf", "").encode(), session["csrf"].encode()
        ):
            abort(403)
        if request.form.get("confirm") != "yes":
            abort(400)
        store.get(session["username"], rotate=True)
        return redirect("/setup/", code=303)

    def dispatch(environ, start_response):
        path = environ["PATH_INFO"]
        if path in ("/setup", "/healthz") or path.startswith("/setup/"):
            if path == "/setup":
                return redirect("/setup/", code=308)(environ, start_response)
            return app(environ, start_response)
        # CalDAV is mounted at the root, never at a client-supplied prefix.
        environ.pop("HTTP_X_SCRIPT_NAME", None)
        environ["SCRIPT_NAME"] = ""
        return radicale.application(environ, start_response)

    return dispatch


def ensure_calendar(origin, username, password):
    # Provision a collection through standard CalDAV so clients that only
    # discover existing calendars have something to sync right away.
    basic = b64encode(f"{username}:{password}".encode()).decode()
    dav_request = Request.from_values(
        path=f"/{username}/calendar/",
        base_url=origin,
        method="MKCALENDAR",
        headers={"Authorization": f"Basic {basic}"},
        content_type="application/xml",
        data='<C:mkcalendar xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:D="DAV:">'
        "<D:set><D:prop><D:displayname>Calendar</D:displayname></D:prop></D:set>"
        "</C:mkcalendar>",
    )
    with Response.from_app(radicale.application, dav_request.environ) as response:
        status = response.status_code
    if status not in (201, 409):
        abort(503, "Could not prepare your calendar. Please refresh to try again.")
