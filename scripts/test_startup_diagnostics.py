import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location("startup_diagnostics", Path(__file__).with_name("startup-diagnostics.py"))
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)


class StartupDiagnosticsTests(unittest.TestCase):
    def testClockBoundaryCannotHideAnInstalledEventFromTheOwnedProcess(self):
        records = [
            {"processID": 54, "timestamp": "2026-10-15 20:12:45.500", "eventMessage": "installed plugin old"},
            {"processID": 55, "timestamp": "2026-10-15 20:12:44.893", "eventMessage": "installed plugin teleprompter"},
        ]

        def query(command, **kwargs):
            available = records
            if "--start" in command:
                lower = command[command.index("--start") + 1]
                available = [item for item in available if item["timestamp"] >= lower]
            return subprocess.CompletedProcess(command, 0, json.dumps(available), "")

        result = diagnostics.process_logs({55}, runner=query)
        self.assertEqual([item["eventMessage"] for item in result], ["installed plugin teleprompter"])
        self.assertIn("Pop[55:", diagnostics.render_logs(result))

    def testOtherProcessCannotSatisfyTheCurrentInstallAssertion(self):
        def query(command, **kwargs):
            return subprocess.CompletedProcess(command, 0, json.dumps([
                {"processID": 54, "eventMessage": "installed plugin teleprompter"}]), "")
        self.assertEqual(diagnostics.process_logs({55}, runner=query), [])

    def testFailedReadCannotReturnApparentlySuccessfulPartialLogs(self):
        def query(command, **kwargs):
            return subprocess.CompletedProcess(command, 7, json.dumps([
                {"processID": 55, "eventMessage": "installed plugin teleprompter"}]), "log store unavailable")
        with self.assertRaises(RuntimeError):
            diagnostics.process_logs({55}, runner=query)

    def testUnknownLogSchemaAndMissingProcessIdentityFailClosed(self):
        for payload in ("not JSON", "{}", '[{"eventMessage":"installed plugin teleprompter"}]'):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                diagnostics.process_logs({55}, runner=lambda command, **kwargs:
                                         subprocess.CompletedProcess(command, 0, payload, ""))
        with self.assertRaises(ValueError):
            diagnostics.process_logs(set())

    def invoke_exit_hook(self, root, status, broken_output=False):
        output = root / "out"
        if broken_output:
            output.write_text("输出是文件")
        else:
            output.mkdir()
            (output / "startup-hangs.txt").write_text("hang 1 2.040\n")
        scripts = Path(__file__).resolve().parent
        fixture = root / "fixture/scripts"
        fixture.mkdir(parents=True)
        (fixture / "startup-diagnostics.py").write_text('''import json, pathlib, sys
output = pathlib.Path(sys.argv[sys.argv.index('--output') + 1])
(output / 'metadata.json').write_text(json.dumps({'commands': {'source': sys.argv}}))
''')
        environment = dict(os.environ, ROOT=str(fixture.parent), DIAGNOSTICS=str(output),
                           SCRIPTS=str(scripts), APP=str(root / "Pop.app"),
                           DIAGNOSTIC_START="2026-10-15 00:00:00", ORIGINAL_STATUS=str(status))
        result = subprocess.run(["bash", "-c", '''set -euo pipefail
source "$SCRIPTS/startup-diagnostics.sh"
trap preserve_startup_diagnostics EXIT
exit "$ORIGINAL_STATUS"
'''], env=environment, capture_output=True, text=True, timeout=10)
        return result, output

    def test_exit_hook_preserves_failure_and_success_with_raw_hangs(self):
        for status in (0, 1, 7):
            with self.subTest(status=status), tempfile.TemporaryDirectory(prefix="startup ' ") as temporary:
                result, output = self.invoke_exit_hook(Path(temporary), status)
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual((output / "exit-status.txt").read_text().strip(), str(status))
                self.assertEqual((output / "startup-hangs.txt").read_text(), "hang 1 2.040\n")
                metadata = json.loads((output / "metadata.json").read_text())
                self.assertIn("source", metadata["commands"])

    def test_exit_hook_storage_failure_never_changes_original_gate(self):
        for status in (0, 1, 9):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as temporary:
                result, _ = self.invoke_exit_hook(Path(temporary), status, broken_output=True)
                self.assertEqual(result.returncode, status)
                self.assertIn("启动诊断归档未完整生成", result.stderr)

    def test_duplicate_and_malformed_stalls_cannot_escape_or_exceed_sample_budget(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            hang = root / "hang.txt"
            hang.write_text("stall ../escape\nstall 1\nstall 1\nstall 2\nstall 3\nstall 4\nhang 5 2.040\n")
            tool = root / "sample"
            tool.write_text(f"#!{sys.executable}\nimport pathlib,sys\npathlib.Path(sys.argv[-1]).write_text('raw sample')\n")
            tool.chmod(0o755)
            output = root / "out"
            results = diagnostics.watch(hang, output, duration=1, sample_tool=str(tool),
                                        pid_command=[sys.executable, "-c", "print(123)"])
            self.assertEqual([item["stall"] for item in results], ["1", "2", "3"])
            self.assertEqual(len(list(output.glob("*.log"))), 3)
            self.assertEqual((output / "1.txt").read_text(), "raw sample")
            self.assertFalse((root / "escape.txt").exists())
            self.assertEqual(json.loads((output / "samples.json").read_text()), results)

    def test_no_stall_produces_no_sample(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            hang = root / "hang.txt"
            hang.write_text("hang 1 0.300\n")
            results = diagnostics.watch(hang, root / "out", duration=0.1, sample_tool="/missing-tool",
                                        pid_command=[sys.executable, "-c", "print(123)"])
            self.assertEqual(results, [])

    def test_tool_timeout_preserves_partial_output_and_bounds_work(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "sample.log"
            started = time.monotonic()
            result = diagnostics.capture([sys.executable, "-u", "-c",
                                          "import time; print('attached'); time.sleep(30)"], path, timeout=0.3)
            self.assertTrue(result["timed_out"])
            self.assertIn("attached", path.read_text())
            self.assertLess(time.monotonic() - started, 5)

    def test_nonzero_and_missing_tool_are_recorded_without_deleting_raw_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = diagnostics.capture([sys.executable, "-c", "print('permission denied'); exit(7)"], root / "denied.log")
            self.assertEqual(result["exit_code"], 7)
            self.assertIn("permission denied", (root / "denied.log").read_text())
            result = diagnostics.capture(["/missing-startup-sampler"], root / "missing.log")
            self.assertIn("error", result)


if __name__ == "__main__":
    unittest.main()
