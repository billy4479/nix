"""Read-only Gmail access and explicit Telegram delivery for a scheduled agent."""

import argparse
import base64
import fcntl
import hashlib
import json
import os
import secrets
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from contextlib import contextmanager
from pathlib import Path

SCOPE = "https://www.googleapis.com/auth/gmail.readonly"
REDIRECT = "http://127.0.0.1:8765/"
ROOT = Path.home() / ".config/mail-watch"
STATE = Path.home() / ".local/state/mail-watch"


def request(url, data=None, headers=None, form=False):
    headers = dict(headers or {})
    if data is not None:
        if form:
            data = urllib.parse.urlencode(data).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(data).encode()
            headers["Content-Type"] = "application/json"
    try:
        with urllib.request.urlopen(
            urllib.request.Request(url, data=data, headers=headers), timeout=60
        ) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"Remote API returned HTTP {error.code}") from None
    except (urllib.error.URLError, TimeoutError):
        # Exception URLs can contain the Telegram bot token.
        raise RuntimeError("Remote API connection failed") from None


def save(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(value, handle)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def load(path):
    return json.loads(path.read_text())


@contextmanager
def locked():
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (STATE / "lock").open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def authorize(client_file):
    client = load(Path(client_file)).get("installed")
    if not client:
        raise RuntimeError("Download an OAuth Desktop app client JSON file")
    verifier = secrets.token_urlsafe(48)
    state = secrets.token_urlsafe(32)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest())
    params = {
        "client_id": client["client_id"],
        "redirect_uri": REDIRECT,
        "response_type": "code",
        "scope": SCOPE,
        "access_type": "offline",
        "prompt": "consent",
        "state": state,
        "code_challenge": challenge.decode().rstrip("="),
        "code_challenge_method": "S256",
    }
    print("Open this URL in your browser:\n")
    print(
        "https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode(params)
    )
    print(
        "\nThe final localhost page will not load. Copy its FULL URL from the address bar."
    )
    response = urllib.parse.urlsplit(input("Paste callback URL: ").strip())
    query = urllib.parse.parse_qs(response.query)
    if (
        response.scheme != "http"
        or response.netloc != "127.0.0.1:8765"
        or query.get("state") != [state]
        or not query.get("code")
    ):
        raise RuntimeError("Invalid authorization callback")
    token = request(
        "https://oauth2.googleapis.com/token",
        {
            "client_id": client["client_id"],
            "client_secret": client["client_secret"],
            "code": query["code"][0],
            "code_verifier": verifier,
            "redirect_uri": REDIRECT,
            "grant_type": "authorization_code",
        },
        form=True,
    )
    if not token.get("refresh_token"):
        raise RuntimeError("Google did not provide an offline refresh token")
    save(
        ROOT / "credentials.json",
        {
            "client_id": client["client_id"],
            "client_secret": client["client_secret"],
            "refresh_token": token["refresh_token"],
        },
    )
    print("Gmail authorized. Credentials saved privately.")


class Gmail:
    def __init__(self):
        credentials = load(ROOT / "credentials.json")
        token = request(
            "https://oauth2.googleapis.com/token",
            {**credentials, "grant_type": "refresh_token"},
            form=True,
        )
        self.headers = {"Authorization": "Bearer " + token["access_token"]}

    def get(self, path, **params):
        url = "https://gmail.googleapis.com/gmail/v1/users/me/" + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        return request(url, headers=self.headers)

    def label(self, name):
        for label in self.get("labels").get("labels", []):
            if label["name"] == name:
                return label["id"]
        raise RuntimeError("Gmail label not found (names are case-sensitive)")

    def messages(self, label):
        page = ""
        while True:
            result = self.get(
                "messages", labelIds=label, maxResults=500, pageToken=page
            )
            yield from result.get("messages", [])
            page = result.get("nextPageToken")
            if not page:
                break


def text_parts(part):
    # Attachments and HTML are deliberately not supplied to the agent.
    if part.get("filename"):
        return []
    if part.get("mimeType") == "text/plain":
        data = part.get("body", {}).get("data", "")
        return [
            base64.urlsafe_b64decode(data + "=" * (-len(data) % 4)).decode(
                "utf-8", "replace"
            )
        ]
    return [text for child in part.get("parts", []) for text in text_parts(child)]


def reviewed():
    path = STATE / "reviewed.json"
    return load(path) if path.exists() else {}


def pending(limit):
    config = load(ROOT / "config.json")
    name = config.get("label")
    if not name:
        raise RuntimeError("Set label in ~/.config/mail-watch/config.json first")
    gmail = Gmail()
    label = gmail.label(name)
    with locked():
        seen = reviewed()
    remaining = [m for m in gmail.messages(label) if m["id"] not in seen]
    messages = []
    for item in remaining[:limit]:
        message = gmail.get("messages/" + item["id"], format="full")
        payload = message.get("payload", {})
        headers = {
            h["name"].lower(): h["value"]
            for h in payload.get("headers", [])
            if h["name"].lower() in {"from", "to", "subject", "date"}
        }
        body = "\n".join(text_parts(payload))
        messages.append(
            {
                "id": message["id"],
                "headers": headers,
                "url": "https://mail.google.com/mail/u/0/#all/" + message["threadId"],
                "body": body[:30000] if body else message.get("snippet", ""),
                "body_truncated": len(body) > 30000,
                "snippet_only": not bool(body),
            }
        )
    print(
        json.dumps(
            {
                "untrusted_email_content": True,
                "messages": messages,
                "remaining": max(0, len(remaining) - limit),
            },
            ensure_ascii=False,
        )
    )


def mark(ids, notify=False):
    with locked():
        seen = reviewed()
        fresh = [message_id for message_id in ids if message_id not in seen]
        if not fresh:
            print("Already reviewed; no notification sent.")
            return
        if notify:
            text = sys.stdin.read().strip()
            if not text or len(text) > 4000:
                raise RuntimeError("Notification must contain 1 to 4000 characters")
            token = (
                Path(
                    os.environ.get(
                        "MAIL_WATCH_TELEGRAM_TOKEN_FILE",
                        "/run/secrets/telegram-bot-token",
                    )
                )
                .read_text()
                .strip()
            )
            chat = (
                Path(
                    os.environ.get(
                        "MAIL_WATCH_TELEGRAM_CHAT_FILE",
                        "/run/secrets/telegram-bot-chat-id",
                    )
                )
                .read_text()
                .strip()
            )
            result = request(
                f"https://api.telegram.org/bot{token}/sendMessage",
                {
                    "chat_id": chat,
                    "text": text,
                    "link_preview_options": {"is_disabled": True},
                },
            )
            if result.get("ok") is not True:
                raise RuntimeError(
                    "Telegram rejected notification; messages remain unreviewed"
                )
        for message_id in fresh:
            seen[message_id] = "notified" if notify else "dismissed"
        save(STATE / "reviewed.json", seen)
    print("Notification sent." if notify else "Messages marked reviewed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("authorize").add_argument("client_json")
    pending_parser = commands.add_parser("pending")
    pending_parser.add_argument("--limit", type=int, default=50)
    for name in ("notify", "dismiss"):
        commands.add_parser(name).add_argument("ids", nargs="+")
    args = parser.parse_args()
    try:
        if args.command == "authorize":
            authorize(args.client_json)
        elif args.command == "pending":
            if not 1 <= args.limit <= 100:
                raise RuntimeError("Limit must be between 1 and 100")
            pending(args.limit)
        else:
            if any(
                not value or any(c not in "0123456789abcdef" for c in value)
                for value in args.ids
            ):
                raise RuntimeError("Expected Gmail message IDs")
            mark(args.ids, notify=args.command == "notify")
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print(f"mail-watch: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
