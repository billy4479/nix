import base64
import contextlib
import importlib.util
import io
import json
import os
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "mail_watch", Path(__file__).with_name("mail-watch.py")
)
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)


class MailWatchTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.enterContext(patch.object(watch, "ROOT", root / "config"))
        self.enterContext(patch.object(watch, "STATE", root / "state"))
        watch.save(watch.ROOT / "config.json", {"label": "Agent"})
        self.token = root / "token"
        self.chat = root / "chat"
        self.token.write_text("SECRET")
        self.chat.write_text("123")
        self.enterContext(
            patch.dict(
                os.environ,
                {
                    "MAIL_WATCH_TELEGRAM_TOKEN_FILE": str(self.token),
                    "MAIL_WATCH_TELEGRAM_CHAT_FILE": str(self.chat),
                },
            )
        )

    def test_pending_filters_reviewed_and_decodes_body_without_attachments(self):
        watch.save(watch.STATE / "reviewed.json", {"a": "dismissed"})
        encoded = (
            base64.urlsafe_b64encode(b"Please reply tomorrow").decode().rstrip("=")
        )
        with patch.object(watch, "Gmail") as factory:
            gmail = factory.return_value
            gmail.label.return_value = "Label_1"
            gmail.messages.return_value = [{"id": "a"}, {"id": "b"}, {"id": "c"}]
            gmail.get.return_value = {
                "id": "b",
                "threadId": "f",
                "payload": {
                    "mimeType": "multipart/mixed",
                    "headers": [{"name": "Subject", "value": "A deadline"}],
                    "parts": [
                        {"mimeType": "text/plain", "body": {"data": encoded}},
                        {
                            "mimeType": "text/plain",
                            "filename": "secret.txt",
                            "body": {"data": encoded},
                        },
                        {"mimeType": "text/html", "body": {"data": encoded}},
                    ],
                },
            }
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                watch.pending(1)
        result = json.loads(output.getvalue())
        self.assertEqual(result["remaining"], 1)
        self.assertEqual(result["messages"][0]["body"], "Please reply tomorrow")
        self.assertEqual(result["messages"][0]["headers"], {"subject": "A deadline"})
        self.assertEqual(watch.reviewed(), {"a": "dismissed"})
        self.assertTrue(result["untrusted_email_content"])

    def test_pagination_preserves_label_filter(self):
        gmail = object.__new__(watch.Gmail)
        with patch.object(
            gmail,
            "get",
            side_effect=[
                {"messages": [{"id": "a"}], "nextPageToken": "next"},
                {"messages": [{"id": "b"}]},
            ],
        ) as get:
            self.assertEqual(
                list(gmail.messages("Label_1")), [{"id": "a"}, {"id": "b"}]
            )
        self.assertEqual(
            get.call_args.kwargs,
            {"labelIds": "Label_1", "maxResults": 500, "pageToken": "next"},
        )

    def test_notify_only_marks_after_success_and_deduplicates(self):
        with patch.object(watch, "request", return_value={"ok": True}) as send:
            with patch("sys.stdin", io.StringIO("Deadline tomorrow")):
                watch.mark(["ab"], notify=True)
            watch.mark(["ab"], notify=True)
        self.assertEqual(send.call_count, 1)
        self.assertEqual(send.call_args.args[1]["text"], "Deadline tomorrow")
        self.assertEqual(watch.reviewed(), {"ab": "notified"})
        self.assertEqual((watch.STATE / "reviewed.json").stat().st_mode & 0o777, 0o600)

    def test_delivery_failure_leaves_messages_pending(self):
        for response in ({"ok": False},):
            with patch.object(watch, "request", return_value=response):
                with patch("sys.stdin", io.StringIO("Important")):
                    with self.assertRaises(RuntimeError):
                        watch.mark(["ab"], notify=True)
        self.assertEqual(watch.reviewed(), {})

    def test_dismiss_does_not_call_telegram(self):
        with patch.object(watch, "request") as send:
            watch.mark(["ab"])
        send.assert_not_called()
        self.assertEqual(watch.reviewed(), {"ab": "dismissed"})

    def test_network_errors_do_not_leak_bot_token(self):
        with patch(
            "urllib.request.urlopen", side_effect=urllib.error.URLError("SECRET")
        ):
            with self.assertRaisesRegex(RuntimeError, "^Remote API connection failed$"):
                watch.request("https://api.telegram.org/botSECRET/sendMessage")

    def test_authorization_checks_state_before_exchanging_code(self):
        client = Path(self.temporary.name) / "client.json"
        watch.save(
            client, {"installed": {"client_id": "id", "client_secret": "secret"}}
        )
        with patch(
            "builtins.input",
            return_value="http://127.0.0.1:8765/?code=code&state=wrong",
        ):
            with patch.object(watch, "request") as exchange:
                with self.assertRaisesRegex(
                    RuntimeError, "Invalid authorization callback"
                ):
                    watch.authorize(client)
        exchange.assert_not_called()


if __name__ == "__main__":
    unittest.main()
