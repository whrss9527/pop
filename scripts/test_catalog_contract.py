import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("catalog", Path(__file__).with_name("catalog-contract.py"))
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


def fixture(language):
    def function(identifier, category):
        return dict(id=identifier, name="名字" if language == "zh-Hans" else "Name", summary="说明",
                    symbol="doc", category=category, accepts=["text"], pattern=r"\p{L}+",
                    minLength=1, maxLength=100, source="builtin", hidesOverlay=False,
                    optionalContent=False, check={"kind": "custom", "id": "chart"})
    return dict(schemaVersion=1, language=language, appVersion="0.70.3", buildID="dev",
                packages=[dict(id="example", bundleName="PopExample", name="包", summary="说明", symbol="doc",
                               category="text", independentVersion=None, functions=[function("example", "text")],
                               defaultsKeys=["pref"], keychainAccounts=["account"], dataFolders=["Data/Example"])],
                hostFunctions=[function("host", "other")], displayOrder=["host", "example"])


class CatalogContractTests(unittest.TestCase):
    def testBilingualMergeKeepsActualConstraintsOwnershipAndCleanup(self):
        zh, en = fixture("zh-Hans"), fixture("en")
        original = copy.deepcopy(zh)
        result = catalog.merge(zh, en)
        self.assertEqual(result["packages"][0]["functions"][0]["name"], {"zh-Hans": "名字", "en": "Name"})
        self.assertEqual(result["packages"][0]["functions"][0]["pattern"], r"\p{L}+")
        self.assertEqual(result["packages"][0]["defaultsKeys"], ["pref"])
        self.assertEqual(result["hostFunctions"][0]["id"], "host")
        self.assertEqual(zh, original)

    def testUnknownFieldsAndSchemaAreRejectedAtEveryLevel(self):
        for level in ("top", "package", "function"):
            value = fixture("en")
            target = value if level == "top" else value["packages"][0]
            if level == "function":
                target = target["functions"][0]
            target["unknown"] = True
            with self.subTest(level=level), self.assertRaises(ValueError):
                catalog.validate_snapshot(value)
        for schema in (True, "1", 0, 2):
            value = fixture("en")
            value["schemaVersion"] = schema
            with self.subTest(schema=schema), self.assertRaises(ValueError):
                catalog.validate_snapshot(value)

    def testDuplicatePackagesAndCrossScopeFunctionsCannotHideOwnership(self):
        value = fixture("en")
        value["packages"].append(copy.deepcopy(value["packages"][0]))
        with self.assertRaises(ValueError):
            catalog.validate_snapshot(value)
        value = fixture("en")
        value["hostFunctions"][0]["id"] = "example"
        with self.assertRaises(ValueError):
            catalog.validate_snapshot(value)

    def testInvalidTypesLengthsChecksAndEmptyTranslationsReject(self):
        mutations = [("minLength", -1), ("maxLength", True), ("maxLength", 0),
                     ("name", ""), ("source", "user"), ("accepts", ["unknown"]),
                     ("optionalContent", 1), ("check", {"kind": "custom", "id": "unknown"}),
                     ("check", {"kind": "folder", "code": "do not execute"})]
        for key, bad in mutations:
            value = fixture("en")
            value["packages"][0]["functions"][0][key] = bad
            with self.subTest(key=key, bad=bad), self.assertRaises(ValueError):
                catalog.validate_snapshot(value)

    def testPackagePathsStayRelativeAndBundleNamesAreNotPaths(self):
        for path in ("/outside", "../outside", "a/../b", "a\\b", "./a", "a//b", "nul\0x"):
            value = fixture("en")
            value["packages"][0]["dataFolders"] = [path]
            with self.subTest(path=path), self.assertRaises(ValueError):
                catalog.validate_snapshot(value)
        value = fixture("en")
        value["packages"][0]["bundleName"] = "../PopExample"
        with self.assertRaises(ValueError):
            catalog.validate_snapshot(value)

    def testLanguageBuildOrRoutingDriftCannotMergeIntoOneCatalog(self):
        for mutation in ("build", "length", "same-language", "order"):
            zh, en = fixture("zh-Hans"), fixture("en")
            if mutation == "build": en["buildID"] = "other"
            if mutation == "length": en["packages"][0]["functions"][0]["maxLength"] = 99
            if mutation == "same-language": en["language"] = "zh-Hans"
            if mutation == "order": en["displayOrder"].reverse()
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                catalog.merge(zh, en)

    def testAttachmentDiscoveryRejectsPartialOrAmbiguousExports(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "manifest.json").write_text('{"tests":[]}')
            with self.assertRaises(ValueError): catalog.load_snapshot(root)
            (root / "snapshot.json").write_text(json.dumps(fixture("en")))
            self.assertEqual(catalog.load_snapshot(root)["language"], "en")
            (root / "second.json").write_text(json.dumps(fixture("en")))
            with self.assertRaises(ValueError): catalog.load_snapshot(root)


if __name__ == "__main__":
    unittest.main()
