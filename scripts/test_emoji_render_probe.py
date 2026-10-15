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
    def testFailedPerformanceMeasurementRemainsFailed(self):
        result = probe.parse_demo(VALID, "baseline")
        self.assertEqual(result["emoji_max_hang"], 2.86)
        self.assertFalse(result["within_existing_two_second_limit"])

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
