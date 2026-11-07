"""Exercise the public health monitor state machine with a fake curl."""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(os.environ["MONITOR_SCRIPT"])

FAKE_CURL = """#!/bin/sh
printf '%s\\t' "$@" >>"$FAKE_ARGV"
printf '\\n' >>"$FAKE_ARGV"

config=
text_file=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      config="$2"
      shift 2
      ;;
    text@*)
      text_file="${1#text@}"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ -n "$config" ]; then
  exit_code="$(cat "$FAKE_TELEGRAM_EXIT")"
  if [ "$exit_code" -eq 0 ] && [ -n "$text_file" ]; then
    cat "$text_file" >>"$FAKE_MESSAGES"
    printf '\\n---\\n' >>"$FAKE_MESSAGES"
  fi
  exit "$exit_code"
fi

cat "$FAKE_PROBE_CODE"
exit "$(cat "$FAKE_PROBE_EXIT")"
"""


class PublicHealthMonitorTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.state_dir = self.root / "state"
        self.state = self.state_dir / "state"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.argv = self.root / "argv"
        self.messages = self.root / "messages"
        self.probe_code = self.root / "probe-code"
        self.probe_exit = self.root / "probe-exit"
        self.telegram_exit = self.root / "telegram-exit"
        self.token = self.root / "token"
        self.chat = self.root / "chat"

        self.argv.touch()
        self.messages.touch()
        self.probe_code.write_text("200")
        self.probe_exit.write_text("0")
        self.telegram_exit.write_text("0")
        self.token.write_text("123:test-token")
        self.chat.write_text("456")

        curl = self.bin / "curl"
        curl.write_text(FAKE_CURL)
        curl.chmod(0o755)

        self.environment = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "STATE_DIR": str(self.state_dir),
            "FAILURE_THRESHOLD": "3",
            "PROBE_HOST": "headscale.example.test",
            "PROBE_IP": "87.106.25.93",
            "PROBE_PATH": "/health",
            "PROBE_TIMEOUT": "10",
            "TELEGRAM_TOKEN_FILE": str(self.token),
            "TELEGRAM_CHAT_ID_FILE": str(self.chat),
            "TELEGRAM_ATTEMPTS": "3",
            "TELEGRAM_RETRY_DELAY": "0",
            "HOST_NAME": "vps-proxy",
            "FAKE_ARGV": str(self.argv),
            "FAKE_MESSAGES": str(self.messages),
            "FAKE_PROBE_CODE": str(self.probe_code),
            "FAKE_PROBE_EXIT": str(self.probe_exit),
            "FAKE_TELEGRAM_EXIT": str(self.telegram_exit),
        }

    def tearDown(self):
        self.temporary.cleanup()

    def run_monitor(self, probe_code=200, probe_exit=0, telegram_exit=0):
        self.probe_code.write_text(str(probe_code))
        self.probe_exit.write_text(str(probe_exit))
        self.telegram_exit.write_text(str(telegram_exit))
        result = subprocess.run(
            [str(SCRIPT)],
            env=self.environment,
            capture_output=True,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"stdout={result.stdout!r} stderr={result.stderr!r}",
        )
        return result

    def delivered(self):
        return [
            message.strip()
            for message in self.messages.read_text().split("---")
            if message.strip()
        ]

    def stored_state(self):
        values = {"failures": "0", "alerted": "0"}
        for line in self.state.read_text().splitlines():
            key, _, value = line.partition("=")
            values[key] = value
        return values

    def test_alert_after_three_failures_and_recover_once(self):
        for _ in range(2):
            self.run_monitor(probe_code=503)
        self.assertEqual(self.delivered(), [])
        self.assertEqual(self.stored_state(), {"failures": "2", "alerted": "0"})

        self.run_monitor(probe_code=503)
        messages = self.delivered()
        self.assertEqual(len(messages), 1)
        self.assertIn("PUBLIC ENDPOINT DOWN", messages[0])
        self.assertIn("HTTP 503", messages[0])
        self.assertIn("Consecutive failures: 3", messages[0])
        self.assertEqual(self.stored_state(), {"failures": "3", "alerted": "1"})
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o600)

        self.run_monitor(probe_code=503)
        self.assertEqual(len(self.delivered()), 1)
        self.assertEqual(self.stored_state(), {"failures": "4", "alerted": "1"})

        self.run_monitor(probe_code=200)
        messages = self.delivered()
        self.assertEqual(len(messages), 2)
        self.assertIn("PUBLIC ENDPOINT RECOVERED", messages[1])
        self.assertEqual(self.stored_state(), {"failures": "0", "alerted": "0"})

        self.run_monitor(probe_code=200)
        self.assertEqual(len(self.delivered()), 2)

    def test_transient_failure_below_threshold_does_not_notify(self):
        self.run_monitor(probe_code=503)
        self.run_monitor(probe_code=500, probe_exit=0)
        self.run_monitor(probe_code=200)
        self.assertEqual(self.delivered(), [])
        self.assertEqual(self.stored_state(), {"failures": "0", "alerted": "0"})

        for _ in range(3):
            self.run_monitor(probe_code=503)
        self.assertEqual(len(self.delivered()), 1)

    def test_connection_failure_is_reported_as_no_status(self):
        for _ in range(3):
            self.run_monitor(probe_code=200, probe_exit=7)
        messages = self.delivered()
        self.assertEqual(len(messages), 1)
        self.assertIn("HTTP 000", messages[0])

    def test_failed_telegram_delivery_is_retried_without_duplicates(self):
        for _ in range(4):
            self.run_monitor(probe_code=503, telegram_exit=1)
        self.assertEqual(self.delivered(), [])
        self.assertEqual(self.stored_state(), {"failures": "4", "alerted": "0"})

        self.run_monitor(probe_code=503, telegram_exit=0)
        self.assertEqual(len(self.delivered()), 1)
        self.assertEqual(self.stored_state(), {"failures": "5", "alerted": "1"})

        self.run_monitor(probe_code=503)
        self.assertEqual(len(self.delivered()), 1)

        self.run_monitor(probe_code=200)
        self.assertEqual(len(self.delivered()), 2)

    def test_failed_recovery_is_retried_on_the_next_success(self):
        for _ in range(3):
            self.run_monitor(probe_code=503)
        self.assertEqual(len(self.delivered()), 1)

        self.run_monitor(probe_code=200, telegram_exit=1)
        self.assertEqual(len(self.delivered()), 1)
        self.assertEqual(self.stored_state(), {"failures": "0", "alerted": "1"})

        self.run_monitor(probe_code=200)
        messages = self.delivered()
        self.assertEqual(len(messages), 2)
        self.assertIn("PUBLIC ENDPOINT RECOVERED", messages[1])
        self.assertEqual(self.stored_state(), {"failures": "0", "alerted": "0"})

    def test_secret_never_appears_in_curl_arguments(self):
        for _ in range(2):
            self.run_monitor(probe_code=503)
        result = self.run_monitor(probe_code=503)
        self.assertEqual(len(self.delivered()), 1)
        arguments = self.argv.read_text()
        self.assertNotIn("123:test-token", arguments)
        self.assertIn("--config", arguments)
        self.assertNotIn(b"123:test-token", result.stdout + result.stderr)
        self.assertEqual(list(self.state_dir.glob("curl-config.*")), [])
        self.assertEqual(list(self.state_dir.glob("telegram-message.*")), [])

    def test_missing_secret_fails_without_changing_state(self):
        self.token.unlink()
        result = subprocess.run(
            [str(SCRIPT)],
            env=self.environment,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"telegram secret files are not readable", result.stderr)
        self.assertFalse(self.state.exists())


if __name__ == "__main__":
    sys.exit(unittest.main())
