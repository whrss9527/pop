import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
IDENTITY = "a" * 40
NAME = "Developer ID Application: Test Only (ABCDE12345)"
MOCK = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
tool, args = Path(sys.argv[0]).name, sys.argv[1:]
state_file = Path(os.environ["FAKE_STATE"])
state = json.loads(state_file.read_text())
state.setdefault("calls", []).append([tool] + args[:2])
result = 0
if tool == "xcrun" and args[0] == "notarytool":
    if args[1] == "submit": print('{"id":"test-only"}')
    elif args[1] == "wait":
        print(json.dumps({"status":os.environ["FAKE_STATUS"]}))
        result = int(os.environ["FAKE_WAIT_RESULT"])
    else: print('{}')
elif tool == "xcrun" and args[0] == "stapler" and args[1] == "validate":
    count = state.get("validate", 0)
    state["validate"] = count + 1
    results = json.loads(os.environ["FAKE_VALIDATE"])
    result = results[min(count, len(results)-1)]
elif tool == "codesign":
    if args[0] == "--verify":
        state["verify_arguments"] = args
        result = int(os.environ["FAKE_SIGNATURE_RESULT"])
    else: print("Authority=" + os.environ["FAKE_AUTHORITY"])
elif tool == "ditto":
    if args[0] == "-x":
        if os.environ["FAKE_HAS_APP"] == "1": (Path(args[-1]) / "Pop.app").mkdir()
    else: Path(args[-1]).write_bytes(b"repacked-test-only")
elif tool == "spctl":
    if args[0] == "--status":
        print(os.environ["FAKE_POLICY"])
        result = int(os.environ["FAKE_POLICY_RESULT"])
    else:
        print("source=" + os.environ["FAKE_SOURCE"])
        result = int(os.environ["FAKE_ASSESSMENT_RESULT"])
elif tool == "gh":
    state["published"] = True
state_file.write_text(json.dumps(state))
sys.exit(result)
'''


class PublicSigningTests(unittest.TestCase):
    def run_gate(self, mode, overrides=None, pipeline=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            tools = root / "bin"
            tools.mkdir()
            mock = tools / "mock.py"
            mock.write_text(MOCK)
            mock.chmod(0o755)
            for tool in ("ditto", "codesign", "xcrun", "spctl", "sleep", "gh"):
                (tools / tool).symlink_to(mock)
            state = root / "state.json"
            state.write_text("{}")
            archive = root / "Pop-test-only.zip"
            archive.write_bytes(b"test-only")
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                       RUNNER_TEMP=str(root), FAKE_STATE=str(state),
                       CERTIFICATE_P12_BASE64="test-only", CERTIFICATE_PASSWORD="test-only",
                       NOTARY_KEY_P8="", NOTARY_KEY_ID="", NOTARY_ISSUER_ID="",
                       NOTARY_APPLE_ID="test@example.invalid", NOTARY_PASSWORD="test-only",
                       NOTARY_TEAM_ID="ABCDE12345", CODESIGN_IDENTITY=IDENTITY,
                       CODESIGN_NAME=NAME, NOTARIZED="1", FAKE_STATUS="Accepted", FAKE_WAIT_RESULT="0",
                       FAKE_VALIDATE="[0]", FAKE_SIGNATURE_RESULT="0", FAKE_AUTHORITY=NAME,
                       FAKE_SOURCE="Notarized Developer ID", FAKE_ASSESSMENT_RESULT="0",
                       FAKE_POLICY="assessments enabled", FAKE_POLICY_RESULT="0",
                       FAKE_HAS_APP="1")
            env.update(overrides or {})
            if pipeline:
                # 真正的门禁和公证脚本必须依次成功，才能到达发行命令替身。
                command = ["bash", "-euc", '''
                    bash "$1/check-public-signing.sh" credentials
                    bash "$1/check-public-signing.sh" identity
                    bash "$1/notarize.sh" "$2"
                    export NOTARIZED=1
                    bash "$1/check-public-signing.sh" archive "$2"
                    gh release create vtest-only
                ''', "test", str(SCRIPTS), str(archive)]
            else:
                command = ["bash", str(SCRIPTS / "check-public-signing.sh"), mode]
                if mode == "archive": command.append(str(archive))
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            remaining = list(root.glob("pop-public-signing.*"))
            return result, json.loads(state.read_text()), remaining

    def assert_stopped(self, overrides, pipeline=True):
        result, state, remaining = self.run_gate("archive", overrides, pipeline)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("published", state)
        self.assertFalse(remaining)
        return result, state

    def test_each_required_credential_stops_before_notary_and_publication(self):
        for name in ("CERTIFICATE_P12_BASE64", "CERTIFICATE_PASSWORD", "NOTARY_APPLE_ID",
                     "NOTARY_PASSWORD", "NOTARY_TEAM_ID"):
            with self.subTest(name=name):
                result, state = self.assert_stopped({name: ""})
                self.assertNotIn("calls", state)
                self.assertNotIn("test-only", result.stdout + result.stderr)

    def test_personal_and_team_api_key_modes_allow_optional_issuer(self):
        for issuer in ("", "test-only-issuer"):
            with self.subTest(issuer=issuer):
                result, _, _ = self.run_gate("credentials", {
                    "NOTARY_KEY_P8": "test-only", "NOTARY_KEY_ID": "test-only-id",
                    "NOTARY_ISSUER_ID": issuer, "NOTARY_APPLE_ID": "",
                    "NOTARY_PASSWORD": "", "NOTARY_TEAM_ID": ""})
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_incomplete_api_key_does_not_fall_back_to_apple_id(self):
        self.assert_stopped({"NOTARY_KEY_P8": "test-only", "NOTARY_KEY_ID": ""})

    def test_wrong_identity_stops_before_notary_and_publication(self):
        for overrides in ({"CODESIGN_IDENTITY": ""}, {"CODESIGN_IDENTITY": "-"},
                          {"CODESIGN_IDENTITY": "bad"}, {"CODESIGN_NAME": "Pop local test"},
                          {"CODESIGN_NAME": "Apple Development: Test Only"}):
            with self.subTest(overrides=overrides):
                _, state = self.assert_stopped(overrides)
                self.assertNotIn("calls", state)

    def test_apple_rejection_or_unknown_status_stops_publication(self):
        for status in ("Invalid", "In Progress", "", "Unknown"):
            with self.subTest(status=status):
                _, state = self.assert_stopped({"FAKE_STATUS": status})
                self.assertNotIn("validate", state)

    def test_failed_apple_wait_with_accepted_output_stops_publication(self):
        _, state = self.assert_stopped({"FAKE_WAIT_RESULT": "1"})
        self.assertNotIn("validate", state)

    def test_final_archive_requires_successful_notarization(self):
        _, state = self.assert_stopped({"NOTARIZED": ""}, pipeline=False)
        self.assertNotIn("calls", state)

    def test_final_archive_requires_matching_signature(self):
        for overrides in ({"FAKE_SIGNATURE_RESULT": "1"},
                          {"FAKE_AUTHORITY": "Developer ID Application: Other (OTHER12345)"},
                          {"FAKE_AUTHORITY": "Pop local test"}):
            with self.subTest(overrides=overrides): self.assert_stopped(overrides)

    def test_final_archive_requires_app_and_final_ticket(self):
        self.assert_stopped({"FAKE_HAS_APP": "0"}, pipeline=False)
        # 第一次 validate 是公证阶段，第二次是最终 zip 解压后的票据检查。
        _, state = self.assert_stopped({"FAKE_VALIDATE": "[0, 65]"})
        self.assertEqual(state["validate"], 2)

    def test_final_ticket_retries_only_network_error_and_exhaustion_fails(self):
        result, state, remaining = self.run_gate("archive", {"FAKE_VALIDATE": "[68, 0]"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(state["validate"], 2)
        self.assertFalse(remaining)
        _, state = self.assert_stopped({"FAKE_VALIDATE": "[68]"}, pipeline=False)
        self.assertEqual(state["validate"], 3)
        _, state = self.assert_stopped({"FAKE_VALIDATE": "[65]"}, pipeline=False)
        self.assertEqual(state["validate"], 1)

    def test_gatekeeper_rejection_disabled_or_unnotarized_stops_publication(self):
        for overrides in ({"FAKE_ASSESSMENT_RESULT": "3"}, {"FAKE_SOURCE": ""},
                          {"FAKE_SOURCE": "Unnotarized Developer ID"},
                          {"FAKE_SOURCE": "assessments disabled"},
                          {"FAKE_SOURCE": "Notarized Developer ID\noverride=security disabled"}):
            with self.subTest(overrides=overrides): self.assert_stopped(overrides)

    def test_gatekeeper_status_must_succeed_and_be_enabled_without_override(self):
        for overrides in ({"FAKE_POLICY": "assessments disabled"}, {"FAKE_POLICY": ""},
                          {"FAKE_POLICY": "unknown"}, {"FAKE_POLICY_RESULT": "1"},
                          {"FAKE_POLICY": "assessments enabled\noverride=security disabled"}):
            with self.subTest(overrides=overrides): self.assert_stopped(overrides)

    def test_accepted_final_archive_reaches_publication_and_checks_all_architectures(self):
        result, state, remaining = self.run_gate("archive", pipeline=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(state["published"])
        self.assertEqual(state["validate"], 2)
        self.assertIn("--all-architectures", state["verify_arguments"])
        self.assertIn("--strict", state["verify_arguments"])
        self.assertFalse(remaining)

    def test_workflow_binds_publication_to_final_verification_and_excludes_dry_run(self):
        workflow = (SCRIPTS.parent / ".github/workflows/release.yml").read_text()
        publication = workflow.split("      - name: Create GitHub release\n", 1)[1].split("      - name:", 1)[0]
        guard = publication.splitlines()[0]
        self.assertIn("steps.distribution.outputs.verified == 'true'", guard)
        self.assertIn("!inputs.dry_run", guard)
        self.assertIn("--all-architectures", (SCRIPTS / "check-public-signing.sh").read_text())
        self.assertIn('bash "$RUNNER_TEMP/notarize.sh"', workflow)
        self.assertIn('scripts/check-public-signing.sh scripts/notarize.sh "$RUNNER_TEMP/"', workflow)


if __name__ == "__main__":
    unittest.main()
