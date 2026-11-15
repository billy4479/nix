"""Display-mode transitions with mocked compositor, menu and user services.

Run with python3 tests/display-mode.py (requires bash and jq).
"""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = (
    Path(__file__).resolve().parents[1] / "user/modules/desktops/niri/display-mode.sh"
)
MOCK = r"""#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['CALLS'], 'a') as log:
    log.write(json.dumps([name, *args]) + '\n')
if name == 'rofi' and '-dmenu' in args:
    sys.stdin.read()
    prompt = args[-1]
    value = os.environ['MODE' if prompt == 'Display mode' else 'TARGET']
    if value == 'cancel':
        sys.exit(1)
    print(value)
elif name == 'niri' and args == ['msg', '--json', 'outputs']:
    print(os.environ['OUTPUTS'])
elif name == 'systemctl' and 'is-active' in args:
    sys.exit(0 if os.environ['ACTIVE'] == '1' else 3)
"""


class DisplayModeTest(unittest.TestCase):
    def run_mode(
        self, mode, outputs=("eDP-1", "HDMI-A-1"), target="HDMI-A-1", active=False
    ):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("niri", "rofi", "systemctl", "systemd-run", "wl-mirror"):
                executable = root / name
                executable.write_text(MOCK)
                executable.chmod(0o755)
            calls = root / "calls"
            env = dict(
                os.environ,
                PATH=f"{root}:{os.environ['PATH']}",
                CALLS=str(calls),
                MODE=mode,
                TARGET=target,
                ACTIVE=str(int(active)),
                OUTPUTS=json.dumps(dict.fromkeys(outputs, {})),
                WAYLAND_DISPLAY="wayland-1",
            )
            result = subprocess.run(
                ["bash", "-euo", "pipefail", str(SCRIPT)],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.stderr, "")
            return result.returncode, [
                json.loads(line) for line in calls.read_text().splitlines()
            ]

    @staticmethod
    def changes(calls):
        return [call for call in calls if call[:3] == ["niri", "msg", "output"]]

    def test_laptop_only_stops_mirror_and_enables_before_disabling(self):
        code, calls = self.run_mode("Laptop only", active=True)
        self.assertEqual(code, 0)
        stop = ["systemctl", "--user", "stop", "niri-display-mirror.service"]
        self.assertLess(
            calls.index(stop), calls.index(["niri", "msg", "output", "eDP-1", "on"])
        )
        self.assertEqual(
            self.changes(calls),
            [
                ["niri", "msg", "output", "eDP-1", "on"],
                ["niri", "msg", "output", "HDMI-A-1", "off"],
            ],
        )

    def test_external_only_selects_monitor_and_disables_others(self):
        code, calls = self.run_mode("External only", ("eDP-1", "DP-2", "HDMI-A-1"))
        self.assertEqual(code, 0)
        self.assertEqual(
            self.changes(calls),
            [
                ["niri", "msg", "output", "HDMI-A-1", "on"],
                ["niri", "msg", "output", "eDP-1", "off"],
                ["niri", "msg", "output", "DP-2", "off"],
            ],
        )

    def test_extend_enables_all_outputs_without_mirror(self):
        code, calls = self.run_mode("Extend")
        self.assertEqual(code, 0)
        self.assertEqual(len(self.changes(calls)), 2)
        self.assertTrue(all(call[-1] == "on" for call in self.changes(calls)))
        self.assertFalse(any(call[0] == "systemd-run" for call in calls))

    def test_duplicate_starts_fullscreen_mirror_on_external(self):
        code, calls = self.run_mode("Duplicate")
        self.assertEqual(code, 0)
        (launch,) = [call for call in calls if call[0] == "systemd-run"]
        self.assertEqual(launch[-3:], ["--fullscreen-output", "HDMI-A-1", "eDP-1"])
        self.assertIn("--setenv=WAYLAND_DISPLAY=wayland-1", launch)
        self.assertEqual(calls[-1], ["niri", "msg", "action", "focus-monitor", "eDP-1"])

    def test_cancellation_does_not_change_outputs_or_stop_mirror(self):
        for mode, target in (("cancel", "HDMI-A-1"), ("Duplicate", "cancel")):
            with self.subTest(mode=mode):
                code, calls = self.run_mode(mode, ("eDP-1", "DP-2", "HDMI-A-1"), target)
                self.assertEqual(code, 0)
                self.assertEqual(self.changes(calls), [])
                self.assertFalse(any(call[0] == "systemctl" for call in calls))

    def test_missing_displays_fail_without_changing_outputs(self):
        for outputs in (("eDP-1",), ("HDMI-A-1",)):
            with self.subTest(outputs=outputs):
                code, calls = self.run_mode("Duplicate", outputs)
                self.assertEqual(code, 1)
                self.assertEqual(self.changes(calls), [])
                self.assertTrue(any(call[:2] == ["rofi", "-e"] for call in calls))

    def test_laptop_only_works_without_external(self):
        code, calls = self.run_mode("Laptop only", ("eDP-1",))
        self.assertEqual(code, 0)
        self.assertEqual(
            self.changes(calls), [["niri", "msg", "output", "eDP-1", "on"]]
        )


if __name__ == "__main__":
    unittest.main()
