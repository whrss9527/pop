"""对真实保存脚本/退出钩子做故障注入，不启动 macOS 或改变截图阈值。"""
import importlib.util
import json
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock


SCRIPTS = pathlib.Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("overlay_diagnostics", SCRIPTS / "overlay-diagnostics.py")
DIAGNOSTICS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DIAGNOSTICS)


class PreservationTests(unittest.TestCase):
    def test_preserves_raw_logs_samples_and_summary_but_not_images_or_unrelated_files(self):
        with tempfile.TemporaryDirectory(prefix="pop overlay ' ") as folder:
            root = pathlib.Path(folder)
            work, output = root / "work", root / "out"
            work.mkdir()
            originals = {
                "demo-light.log": "emojiSymbols.start 1\nhang 1 2.970\n",
                "overlay-light.jsonl": '{"event":"resizeApplied","width":476}\n',
                "hangs.txt": "light 2.97 emojiSymbols.start → emojiSymbols\n",
                "stalls.txt": "RenderBox wait_for_allocations\n",
                "samples-light/1.txt": "Call graph:\n 原始采样\n",
                "samples-light/1.log": "sample 命令输出\n",
                "demo-dark.log": "emojiSymbols 2\n",
            }
            for name, value in originals.items():
                path = work / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(value)
            (work / "shot.png").write_bytes(b"image")
            (work / "unexpected.txt").write_text("不属于诊断资料")
            manifest = DIAGNOSTICS.preserve(work, output, 1)
            self.assertEqual(manifest["screenshot_exit_status"], 1)
            self.assertEqual({item["file"] for item in manifest["files"]}, set(originals))
            for name in originals:
                self.assertEqual((output / name).read_bytes(), (work / name).read_bytes())
            self.assertFalse((output / "shot.png").exists())
            self.assertFalse((output / "unexpected.txt").exists())
            self.assertEqual(json.loads((output / "manifest.json").read_text()), manifest)

    def invoke_exit_hook(self, root, status, invalid_output=False):
        work, output = root / "work", root / "out"
        work.mkdir()
        (work / "demo-light.log").write_text("已出现的原始场景\n")
        (work / "samples-light").mkdir()
        (work / "samples-light" / "1.log").write_text("尚未完成的采样\n")
        if invalid_output:
            output.write_text("输出不是目录")
        env = dict(os.environ, SCRIPTS=str(SCRIPTS), WORK=str(work), DIAGNOSTICS=str(output), EXIT_STATUS=str(status))
        code = '''set -euo pipefail
source "$SCRIPTS/overlay-diagnostics.sh"
trap 'save_overlay_diagnostics "$?"' EXIT
exit "$EXIT_STATUS"
'''
        return subprocess.run(["bash", "-c", code], env=env, capture_output=True, text=True, timeout=5), output

    def test_early_failure_exit_hook_retains_original_status_and_partial_samples(self):
        with tempfile.TemporaryDirectory(prefix="pop failed ' ") as folder:
            result, output = self.invoke_exit_hook(pathlib.Path(folder), 7)
            self.assertEqual(result.returncode, 7, result.stderr)
            manifest = json.loads((output / "manifest.json").read_text())
            self.assertEqual(manifest["screenshot_exit_status"], 7)
            self.assertEqual((output / "samples-light" / "1.log").read_text(), "尚未完成的采样\n")

    def test_success_exit_hook_does_not_turn_success_into_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            result, output = self.invoke_exit_hook(pathlib.Path(folder), 0)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads((output / "manifest.json").read_text())["screenshot_exit_status"], 0)

    def test_preservation_failure_never_changes_original_exit_status(self):
        for status in (0, 1, 9):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as folder:
                result, _ = self.invoke_exit_hook(pathlib.Path(folder), status, invalid_output=True)
                self.assertEqual(result.returncode, status)
                self.assertIn("保存浮窗诊断资料失败", result.stderr)

    def test_missing_files_still_write_failure_manifest(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            manifest = DIAGNOSTICS.preserve(root / "missing", root / "out", 1)
            self.assertEqual(manifest, {"screenshot_exit_status": 1, "files": []})

    def test_symlink_is_not_used_as_diagnostic_input(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            work = root / "work"
            work.mkdir()
            target = root / "outside"
            target.write_text("不应跟随")
            (work / "demo-light.log").symlink_to(target)
            self.assertEqual(DIAGNOSTICS.preserve(work, root / "out", 0)["files"], [])


class EnvironmentTests(unittest.TestCase):
    def test_environment_is_allowlisted_and_collected_before_measurement(self):
        with tempfile.TemporaryDirectory() as folder:
            output = pathlib.Path(folder)
            env = {"GITHUB_SHA": "abc", "GITHUB_RUN_ID": "12", "GITHUB_RUN_ATTEMPT": "2",
                   "GH_TOKEN": "must-not-be-recorded", "CERTIFICATE_PASSWORD": "must-not-be-recorded"}
            with mock.patch.object(DIAGNOSTICS, "command_result", return_value={"status": 0, "stdout": "GPU"}) as run:
                DIAGNOSTICS.collect_environment(output, env)
            data = json.loads((output / "environment.json").read_text())
            self.assertEqual(data["github"], {key: env[key] for key in ("GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT")})
            self.assertNotIn("must-not-be-recorded", (output / "environment.json").read_text())
            self.assertEqual(set(data["commands"]), {"system", "architecture", "xcode", "displays"})
            self.assertEqual(run.call_count, 4)

    def test_environment_command_failure_and_timeout_are_explicit(self):
        for error in (FileNotFoundError(), subprocess.TimeoutExpired(["diagnostic"], 20)):
            with self.subTest(error=type(error).__name__), mock.patch.object(DIAGNOSTICS.subprocess, "run", side_effect=error):
                result = DIAGNOSTICS.command_result(["diagnostic"])
                self.assertEqual(result["unavailable"], type(error).__name__)


if __name__ == "__main__":
    unittest.main()
