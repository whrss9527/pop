import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


MOCK = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
state_file = Path(os.environ["FAKE_STATE"])
state = json.loads(state_file.read_text())
if tool == "xcrun" and args[0] == "notarytool":
    if args[1] == "submit": print('{"id":"test"}')
    elif args[1] == "wait": print(json.dumps({"status":os.environ["FAKE_NOTARY_STATUS"]}))
    else: print('{}')
elif tool == "xcrun" and args[0] == "stapler":
    action = args[1]
    calls = state.get(action, 0)
    state[action] = calls + 1
    state.setdefault("actions", []).append(action)
    results = json.loads(os.environ["FAKE_" + action.upper() + "_RESULTS"])
    state_file.write_text(json.dumps(state))
    sys.exit(results[min(calls, len(results)-1)])
elif tool == "ditto":
    if args[0] == "-x":
        if os.environ["FAKE_PLUGIN_ONLY"] != "1":
            (Path(args[-1]) / "Pop.app").mkdir()
    else: Path(args[-1]).write_bytes(b"repacked")
elif tool == "spctl":
    state["assessments"] = state.get("assessments", 0) + 1
    state_file.write_text(json.dumps(state))
    sys.exit(int(os.environ["FAKE_SPCTL_RESULT"]))
elif tool == "sleep":
    state.setdefault("sleeps", []).append(args)
    state_file.write_text(json.dumps(state))
'''


class NotarizationTests(unittest.TestCase):
    def run_notary(self, staple=(0,), validate=(0,), status="Accepted",
                   plugin_only=False, assessment=0):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            tools = root / "bin"
            tools.mkdir()
            mock = tools / "mock.py"
            mock.write_text(MOCK)
            mock.chmod(0o755)
            for name in ("xcrun", "ditto", "spctl", "sleep"):
                (tools / name).symlink_to(mock)
            state = root / "state.json"
            state.write_text("{}")
            archive = root / "Sample.zip"
            archive.write_bytes(b"original")
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                       RUNNER_TEMP=str(root / "runner"), NOTARY_KEY_P8="",
                       NOTARY_APPLE_ID="test@example.invalid", NOTARY_PASSWORD="test-only",
                       NOTARY_TEAM_ID="ABCDE12345", FAKE_STATE=str(state),
                       FAKE_STAPLE_RESULTS=json.dumps(staple),
                       FAKE_VALIDATE_RESULTS=json.dumps(validate), FAKE_NOTARY_STATUS=status,
                       FAKE_PLUGIN_ONLY="1" if plugin_only else "0",
                       FAKE_SPCTL_RESULT=str(assessment))
            script = Path(__file__).resolve().parent / "notarize.sh"
            result = subprocess.run(["bash", str(script), str(archive)], env=env,
                                    capture_output=True, text=True)
            return result, json.loads(state.read_text()), archive.read_bytes()

    def test_network_failures_retry_both_actions_then_repack(self):
        result, state, archive = self.run_notary(staple=(68, 0), validate=(68, 0))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(state["actions"], ["staple", "staple", "validate", "validate"])
        self.assertEqual(state["sleeps"], [["5"], ["5"]])
        self.assertEqual(state["assessments"], 1)
        self.assertEqual(archive, b"repacked")

    def test_staple_exhaustion_stops_after_three_and_keeps_archive(self):
        result, state, archive = self.run_notary(staple=(68,))
        self.assertEqual(result.returncode, 68)
        self.assertEqual(state["actions"], ["staple"] * 3)
        self.assertEqual(state["sleeps"], [["5"], ["5"]])
        self.assertNotIn("assessments", state)
        self.assertEqual(archive, b"original")

    def test_validate_exhaustion_keeps_archive(self):
        result, state, archive = self.run_notary(validate=(68,))
        self.assertEqual(result.returncode, 68)
        self.assertEqual(state["actions"], ["staple"] + ["validate"] * 3)
        self.assertEqual(state["sleeps"], [["5"], ["5"]])
        self.assertNotIn("assessments", state)
        self.assertEqual(archive, b"original")

    def test_permanent_errors_stop_immediately(self):
        for action in ("staple", "validate"):
            with self.subTest(action=action):
                result, state, archive = self.run_notary(**{action: (65,)})
                self.assertEqual(result.returncode, 65)
                self.assertEqual(state["actions"], ["staple"] if action == "staple"
                                 else ["staple", "validate"])
                self.assertNotIn("sleeps", state)
                self.assertEqual(archive, b"original")

    def test_rejected_notarization_never_staples_or_repacks(self):
        result, state, archive = self.run_notary(status="Invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("actions", state)
        self.assertNotIn("assessments", state)
        self.assertEqual(archive, b"original")

    def test_plugin_only_archive_is_not_stapled_or_repacked(self):
        result, state, archive = self.run_notary(plugin_only=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("actions", state)
        self.assertNotIn("assessments", state)
        self.assertEqual(archive, b"original")

    def test_gatekeeper_rejection_still_fails_and_keeps_archive(self):
        result, state, archive = self.run_notary(assessment=3)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(state["actions"], ["staple", "validate"])
        self.assertEqual(state["assessments"], 1)
        self.assertEqual(archive, b"original")
