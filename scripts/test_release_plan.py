import datetime as dt
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("release_plan", pathlib.Path(__file__).with_name("release-plan.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleasePlanTests(unittest.TestCase):
    now = dt.datetime.fromisoformat("2026-10-06T10:00:00+00:00")

    def release(self, published, prerelease=False, draft=False, tag="v0.68.0"):
        return dict(tag_name=tag, published_at=published, prerelease=prerelease, draft=draft)

    def test_unreleased_only_publishes_beta(self):
        self.assertEqual(module.plan("## 未发布\n- 改动", "0.69.0", [], self.now, "push", 12),
                         dict(version="", beta="0.69.0-beta.12"))

    def test_promoted_version_publishes_stable_and_beta(self):
        result = module.plan("## 0.69.0（2026-10-06）", "0.69.0", [], self.now, "push", 12)
        self.assertEqual(result, dict(version="0.69.0", beta="0.69.0-beta.12"))

    def test_daily_cap_uses_shanghai_calendar(self):
        self.assertFalse(module.stable_allowed([self.release("2026-10-05T16:30:00Z")], self.now))
        self.assertTrue(module.stable_allowed([self.release("2026-10-05T15:30:00Z")], self.now))
        self.assertTrue(module.stable_allowed([self.release("2026-10-06T01:00:00Z", prerelease=True)], self.now))
        self.assertTrue(module.stable_allowed([self.release(None, draft=True)], self.now))
        self.assertFalse(module.stable_allowed([self.release(None)], self.now))

    def test_weekends_do_not_publish_stable(self):
        saturday = dt.datetime.fromisoformat("2026-10-10T03:00:00+00:00")
        result = module.plan("## 0.69.0", "0.69.0", [], saturday, "push", 13)
        self.assertEqual(result, dict(version="", beta="0.69.0-beta.13"))

    def test_existing_versions_and_reruns_are_idempotent(self):
        releases = [self.release("2026-10-05T01:00:00Z", tag="v0.69.0"),
                    self.release("2026-10-06T01:00:00Z", prerelease=True, tag="v0.69.0-beta.12")]
        self.assertEqual(module.plan("## 0.69.0", "0.69.0", releases, self.now, "push", 12),
                         dict(version="", beta=""))

    def test_scheduled_retry_publishes_only_pending_stable(self):
        self.assertEqual(module.plan("## 0.69.0", "0.69.0", [], self.now, "schedule", 15),
                         dict(version="0.69.0", beta=""))

    def test_malformed_or_mismatched_versions_stop_publication(self):
        for text, version in [("## 说明", "0.69.0"), ("## 0.69.0", "0.68.0"), ("## 未发布", "bad")]:
            with self.assertRaises(ValueError):
                module.plan(text, version, [], self.now, "push", 12)
