import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from overlay_observer import configuration, prefix_plan, app_environment

spec = importlib.util.spec_from_file_location("observer_probe", Path(__file__).with_name("emoji-observer-probe.py"))
observer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observer)


class ObserverControlsTests(unittest.TestCase):
    def testOrdinaryDriverIgnoresIndividualTogglesAndRetainsPlan(self):
        self.assertIsNone(configuration({"POP_OBSERVER_READBACK": "0", "POP_OBSERVER_SAMPLING": "0"}))
        plan = [("ring", [1]), ("emojiSymbols", [3]), ("later", [3])]
        self.assertIs(prefix_plan(plan, None), plan)
        self.assertEqual(app_environment(None), [])

    def testExperimentRequiresHostedRunnerAndBothExplicitControls(self):
        base = {"POP_OBSERVER_PROBE": "1", "GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted",
                "POP_OBSERVER_READBACK": "1", "POP_OBSERVER_SAMPLING": "0"}
        self.assertEqual(configuration(base), {"readback": True, "sampling": False})
        for key in base:
            bad = base.copy()
            del bad[key]
            if key == "POP_OBSERVER_PROBE":
                self.assertIsNone(configuration(bad))
            else:
                with self.assertRaises(ValueError):
                    configuration(bad)
        with self.assertRaises(ValueError):
            configuration(dict(base, POP_OBSERVER_SAMPLING="unknown"))

    def testPrefixTrimPreservesOriginalOffsetsAndRejectsMissingTarget(self):
        plan = [("ring", [0.25, 1.4]), ("emojiSymbols", [3]), ("later", [3])]
        self.assertEqual(prefix_plan(plan, {}), plan[:2])
        self.assertEqual(len(plan), 3)
        with self.assertRaises(ValueError):
            prefix_plan(plan[:1], {})
        self.assertIn("POP_RENDER_PROBE_VARIANT=baseline", app_environment({}))

    def testOriginalGateFailureIsRetainedWhilePartialOrInconsistentDataRejectsCollection(self):
        fixture = Path(__file__).with_name("fixtures") / "emoji-full-prefix.json"
        for kind in ("complete-failed-gate", "partial", "false-green"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                driver = root / "overlay-screenshots.sh"
                driver.write_text("#!/usr/bin/env python3\nimport json, pathlib, sys\n"
                    f"fixture=json.loads(pathlib.Path({str(fixture)!r}).read_text())\n"
                    "out=pathlib.Path(sys.argv[2]); d=out/'diagnostics'; d.mkdir()\n"
                    "for appearance,steps in fixture['appearances'].items():\n"
                    " text='renderProbe.variant baseline\\nrenderProbe.workload full-prefix\\n'\n"
                    f" if {kind!r} != 'partial':\n"
                    "  text+='\\n'.join(f'{name} {i+1} {scale}' for i,(name,scale) in enumerate(steps))\n"
                    "  text+='\\nhang 122.5 2.90\\nrenderProbe.end 130 2\\n'\n"
                    " (d/f'demo-{appearance}.log').write_text(text)\n"
                    " (d/f'overlay-{appearance}.jsonl').write_text('{\"event\":\"ghostCreated\"}\\n')\n"
                    f"raise SystemExit({0 if kind == 'false-green' else 1})\n")
                driver.chmod(0o755)
                with patch.object(observer, "__file__", str(root / "probe.py")), patch.object(observer, "stop_app") as cleanup:
                    if kind == "complete-failed-gate":
                        result = observer.run_condition(root / "Pop.app", root / "out", "neither", False, False)
                        self.assertTrue(result["original_performance_gate_failed"])
                        self.assertEqual(result["driver_exit_code"], 1)
                        self.assertEqual(result["appearances"][0]["emoji_max_hang"], 2.90)
                    else:
                        with self.assertRaises(ValueError):
                            observer.run_condition(root / "Pop.app", root / "out", "neither", False, False)
                        self.assertIn("error", json.loads((root / "out/result.json").read_text()))
                    cleanup.assert_called_once()
                self.assertTrue((root / "out/diagnostics/demo-light.log").exists())


if __name__ == "__main__":
    unittest.main()
