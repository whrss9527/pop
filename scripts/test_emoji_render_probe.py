import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("render_probe", Path(__file__).with_name("emoji-render-probe.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

VALID = """renderProbe.variant baseline
focusSounds.start 10 2
focusSounds 11 2
emojiSymbols.start 13 2
emojiSymbols 13.1 2
hang 13.2 2.86
renderProbe.end 22 2
"""


class RenderingProbeTests(unittest.TestCase):
    def testDiagnosticSampleBudgetIsReservedForTheTargetPhase(self):
        self.assertEqual(probe.target_stalls("stall 1 0.5\nring 2 6\n"), [])
        self.assertEqual(probe.target_stalls("stall 1 0.5\nemojiSymbols.start 10 2\nstall 9 0.5\nstall 11 0.5\n"), ["stall 11 0.5"])

    def testOriginalFullPrefixAndQuickStepContract(self):
        quick, fixture = probe.full_prefix_configuration()
        self.assertIn("emojiSymbols", quick)
        self.assertIn("focusSounds", quick)
        self.assertNotIn("ring", quick)
        for appearance, steps in fixture["appearances"].items():
            self.assertEqual(len(steps), 123)
            text = "renderProbe.workload full-prefix\n" + "\n".join(
                f"{name} {index + 1} {scale}" for index, (name, scale) in enumerate(steps))
            self.assertEqual(probe.verify_full_prefix(text, appearance), 123)
            for bad in [text.replace("loaded 2", "missing-step 2", 1),
                        text.replace("emojiSymbols 123 2.0", "emojiSymbols 123 6.0"),
                        text.replace("ring 1", "ring nan", 1),
                        text + "\nrenderProbe.workload full-prefix"]:
                with self.subTest(appearance=appearance, log=bad[:70]):
                    with self.assertRaises(ValueError):
                        probe.verify_full_prefix(bad, appearance)

    def testFailedPerformanceMeasurementRemainsFailed(self):
        result = probe.parse_demo(VALID, "baseline")
        self.assertEqual(result["emoji_max_hang"], 2.86)
        self.assertFalse(result["within_existing_two_second_limit"])

    def testExistingWatchdogPauseAnnotationRetainsItsAdjustedHangDuration(self):
        result = probe.parse_demo(VALID.replace("hang 13.2 2.86", "hang 13.2 2.86 paused 0.329"), "baseline")
        self.assertEqual(result["emoji_max_hang"], 2.86)
        self.assertFalse(result["within_existing_two_second_limit"])
        self.assertEqual(result["hangs"][0]["process_paused_seconds"], 0.329)
        for ending in ["pause 0.329", "paused", "paused nan", "paused -1"]:
            with self.subTest(ending=ending), self.assertRaises(ValueError):
                probe.parse_demo(VALID.replace("hang 13.2 2.86", "hang 13.2 2.86 " + ending), "baseline")

    def testIncompleteWrongOrNonfiniteRecordsCannotLookLikePassingMeasurements(self):
        samples = [VALID.replace("renderProbe.end 22 2", ""),
                   VALID.replace("baseline", "no-ghost"),
                   VALID + "emojiSymbols 23 2\n",
                   VALID.replace("emojiSymbols 13.1", "emojiSymbols 12"),
                   VALID.replace("hang 13.2 2.86", "hang nan 2.86"),
                   VALID.replace("hang 13.2 2.86", "hang 13.2 nan"),
                   VALID.replace("emojiSymbols 13.1", "emojiSymbols nan")]
        for sample in samples:
            with self.subTest(sample=sample), self.assertRaises(ValueError):
                probe.parse_demo(sample, "baseline")

    def testZeroExitWithoutCompletionAndProcessFailureBothPreserveEvidence(self):
        for exit_code in (0, 7):
            with self.subTest(exit_code=exit_code), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                binary = root / "Pop.app/Contents/MacOS/Pop"
                binary.parent.mkdir(parents=True)
                binary.write_text("#!/usr/bin/env python3\nimport os\nfrom pathlib import Path\n"
                                  "Path(os.environ['POP_DEMO_LOG']).write_text('renderProbe.variant baseline\\n')\n"
                                  f"raise SystemExit({exit_code})\n")
                binary.chmod(0o755)
                output = root / "evidence"
                with self.assertRaises((ValueError, RuntimeError)):
                    probe.measure(root / "Pop.app", output, "baseline", "light")
                result = json.loads((output / "result.json").read_text())
                self.assertEqual(result["exit_code"], exit_code)
                self.assertIn("error", result)
                self.assertTrue((output / "demo.log").exists())


if __name__ == "__main__":
    unittest.main()
