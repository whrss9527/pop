import base64
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
SECRETS = ("APPSTORE_PROVISIONING_PROFILE", "APPSTORE_WIDGET_PROVISIONING_PROFILE")


class AppStoreProfilesTests(unittest.TestCase):
    def run_prepare(self, root, overrides=None):
        # 普通测试字节，不使用或输出证书、描述文件和真实凭据。
        payloads = (b"fixture-host-profile", b"fixture-widget-profile")
        env = dict(os.environ, RUNNER_TEMP=str(root), GITHUB_ENV=str(root / "environment"))
        env.update({name: base64.b64encode(data).decode() for name, data in zip(SECRETS, payloads)})
        env.update(overrides or {})
        result = subprocess.run(["python3", str(SCRIPTS / "prepare-appstore-profiles.py")],
                                env=env, capture_output=True, text=True)
        for data in payloads:
            self.assertNotIn(data.decode(), result.stdout + result.stderr)
            self.assertNotIn(base64.b64encode(data).decode(), result.stdout + result.stderr)
        return result, payloads

    def test_both_profiles_are_private_and_exported_as_distinct_paths(self):
        with tempfile.TemporaryDirectory(prefix="profiles with spaces ") as directory:
            root = Path(directory)
            (root / "environment").write_text("EXISTING=value\n")
            result, payloads = self.run_prepare(root)
            self.assertEqual(result.returncode, 0, result.stderr)
            paths = (root / "Pop.provisionprofile", root / "PopWidgets.provisionprofile")
            for path, data in zip(paths, payloads):
                self.assertEqual(path.read_bytes(), data)
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            values = dict(line.split("=", 1) for line in (root / "environment").read_text().splitlines())
            self.assertEqual(values, {"EXISTING": "value", "APPSTORE_PROFILE": str(paths[0]),
                                      "WIDGET_PROVISIONING_PROFILE": str(paths[1])})

    def test_wrapped_base64_is_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            encoded = base64.b64encode(b"wrapped-fixture-profile").decode()
            result, _ = self.run_prepare(Path(directory), {SECRETS[1]: encoded[:8] + "\n" + encoded[8:] + "\n"})
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((Path(directory) / "PopWidgets.provisionprofile").read_bytes(),
                             b"wrapped-fixture-profile")

    def test_missing_or_invalid_secret_leaves_no_partial_files_or_exports(self):
        for name in SECRETS:
            for value in ("", " \n", "not-valid-base64!", "===="):
                with self.subTest(name=name, case="empty" if not value.strip() else "invalid"):
                    with tempfile.TemporaryDirectory() as directory:
                        root = Path(directory)
                        result, _ = self.run_prepare(root, {name: value})
                        self.assertNotEqual(result.returncode, 0)
                        self.assertFalse(list(root.iterdir()))
                        if value.strip():
                            self.assertNotIn(value.strip(), result.stderr)

    def test_existing_profile_is_preserved_and_owned_partial_file_removed(self):
        for filename in ("Pop.provisionprofile", "PopWidgets.provisionprofile"):
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                existing = root / filename
                existing.write_bytes(b"preexisting-file")
                result, _ = self.run_prepare(root)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(existing.read_bytes(), b"preexisting-file")
                self.assertEqual(list(root.iterdir()), [existing])

    def test_failed_environment_export_removes_new_profiles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result, _ = self.run_prepare(root, {"GITHUB_ENV": str(root / "missing" / "environment")})
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(list(root.iterdir()))

    def test_workflow_binds_both_secrets_and_calls_the_tested_preparation(self):
        workflow = (SCRIPTS.parent / ".github/workflows/app-store.yml").read_text()
        for name in SECRETS:
            self.assertIn(f"{name}: ${{{{ secrets.{name} }}}}", workflow)
            check = workflow.split("      - name: Check secrets\n", 1)[1].split("      - uses:", 1)[0]
            self.assertIn(name, check)
        prepare = workflow.split("      - name: Import certificates and profile\n", 1)[1].split("      - name:", 1)[0]
        self.assertIn("python3 scripts/prepare-appstore-profiles.py", prepare)
        self.assertNotIn('echo "APPSTORE_PROFILE=', prepare)
        cleanup = workflow.split("      - name: Clean up\n", 1)[1].split("  listing:", 1)[0]
        self.assertIn('"$RUNNER_TEMP/Pop.provisionprofile"', cleanup)
        self.assertIn('"$RUNNER_TEMP/PopWidgets.provisionprofile"', cleanup)

    def test_missing_widget_profile_stops_packaging_before_external_tools(self):
        for value in ("", "missing.provisionprofile"):
            with self.subTest(case="unset" if not value else "missing"), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                host = root / "host.provisionprofile"
                host.write_bytes(b"fixture-host-profile")
                tools = root / "tools"
                tools.mkdir()
                security = tools / "security"
                security.write_text('#!/bin/sh\ntouch "$EXTERNAL_TOOL_CALLED"\nexit 1\n')
                security.chmod(0o755)
                env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                           APPSTORE_PROFILE=str(host), WIDGET_PROVISIONING_PROFILE=value, ADHOC="0",
                           APP_SIGN_IDENTITY="fixture-identity", INSTALLER_SIGN_IDENTITY="fixture-installer",
                           EXTERNAL_TOOL_CALLED=str(root / "called"))
                result = subprocess.run(["bash", str(SCRIPTS / "build-app-store.sh"), "0.0.0-ci"],
                                        env=env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("WIDGET_PROVISIONING_PROFILE", result.stderr)
                self.assertNotIn("构建 App Store 版", result.stdout)
                self.assertFalse((root / "called").exists())


if __name__ == "__main__":
    unittest.main()
