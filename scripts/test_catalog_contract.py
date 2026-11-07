import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
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


SOURCE = "0123456789abcdef0123456789abcdef01234567"


def evidence_fixture(root):
    for language in ("zh-Hans", "en"):
        folder = root / "exports" / language
        folder.mkdir(parents=True)
        value = fixture(language)
        value["buildID"] = SOURCE
        (folder / "snapshot.json").write_text(json.dumps(value))
        (folder / "manifest.json").write_text('{"tests": []}')
    (root / "metadata.json").write_text(json.dumps(dict(source=SOURCE, system="macOS 26", xcode="Xcode 26",
        scope="native metadata only; custom closure semantics and lazy loading not implemented")))


def export_evidence(root, source=SOURCE):
    return catalog.export_contract(root / "exports/zh-Hans", root / "exports/en", root / "metadata.json",
                                   source, root / "contract.json", root / "evidence.json")


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

    def testEvidenceCLIExportsAndRechecksOriginalFiles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence_fixture(root)
            script = str(Path(catalog.__file__).resolve())
            subprocess.run([sys.executable, script, "export", "--zh", str(root / "exports/zh-Hans"),
                            "--en", str(root / "exports/en"), "--metadata", str(root / "metadata.json"),
                            "--source", SOURCE, "--output", str(root / "contract.json"),
                            "--manifest", str(root / "evidence.json")], check=True, capture_output=True)
            subprocess.run([sys.executable, script, "verify", "--manifest", str(root / "evidence.json"),
                            "--source", SOURCE], check=True, capture_output=True)
            evidence = json.loads((root / "evidence.json").read_bytes())
            self.assertEqual(set(evidence["files"]), {"zh", "en", "metadata", "contract"})
            self.assertEqual(evidence["files"]["zh"]["path"], "exports/zh-Hans/snapshot.json")
            result = catalog.verify_manifest(root / "evidence.json", SOURCE)
            self.assertEqual(result["buildID"], SOURCE)

    def testFormalCLIRequiresMetadataAndExpectedSource(self):
        script = str(Path(catalog.__file__).resolve())
        result = subprocess.run([sys.executable, script, "export", "--zh", "zh", "--en", "en",
                                 "--output", "contract", "--manifest", "evidence"], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"--metadata", result.stderr)
        self.assertIn(b"--source", result.stderr)

    def testWrongSourceAndNativeBuildCannotPassBinding(self):
        for mutation in ("invalid-source", "wrong-source", "metadata", "native-build", "empty-system"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                evidence_fixture(root)
                source = SOURCE
                if mutation == "invalid-source": source = "dev"
                if mutation == "wrong-source": source = "f" * 40
                if mutation in ("metadata", "empty-system"):
                    path = root / "metadata.json"
                    value = json.loads(path.read_bytes())
                    value["source" if mutation == "metadata" else "system"] = "f" * 40 if mutation == "metadata" else ""
                    path.write_text(json.dumps(value))
                if mutation == "native-build":
                    for language in ("zh-Hans", "en"):
                        path = root / "exports" / language / "snapshot.json"
                        value = json.loads(path.read_bytes())
                        value["buildID"] = "dev"
                        path.write_text(json.dumps(value))
                with self.assertRaises(ValueError): export_evidence(root, source)
                self.assertFalse((root / "evidence.json").exists())

    def testAnyRawSnapshotMetadataOrContractChangeFailsSavedEvidence(self):
        for target in ("exports/zh-Hans/snapshot.json", "exports/en/snapshot.json", "metadata.json", "contract.json"):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                evidence_fixture(root)
                export_evidence(root)
                path = root / target
                # 合法JSON的同长度替换也不能绕过SHA256检查。
                data = path.read_bytes()
                old, new = (b"macOS 26", b"macOS 27") if target == "metadata.json" else (SOURCE.encode(), b"f" * 40)
                self.assertIn(old, data)
                path.write_bytes(data.replace(old, new, 1))
                with self.assertRaisesRegex(ValueError, "SHA256"):
                    catalog.verify_manifest(root / "evidence.json", SOURCE)

    def testSavedManifestRejectsWrongSourceLengthAndDigest(self):
        for mutation in ("source", "bytes", "sha256"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                evidence_fixture(root)
                export_evidence(root)
                path = root / "evidence.json"
                value = json.loads(path.read_bytes())
                if mutation == "source": value["source"] = "f" * 40
                if mutation == "bytes": value["files"]["en"]["bytes"] += 1
                if mutation == "sha256": value["files"]["en"]["sha256"] = "f" * 64
                path.write_text(json.dumps(value))
                with self.assertRaises(ValueError): catalog.verify_manifest(path, SOURCE)

    def testFileDigestsCannotReplaceSourceAndMergeChecks(self):
        for mutation in ("metadata-source", "native-build", "contract", "contract-bool-as-int"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                evidence_fixture(root)
                export_evidence(root)
                manifest = root / "evidence.json"
                evidence = json.loads(manifest.read_bytes())
                roles = {"native-build": ("zh", "en"), "metadata-source": ("metadata",), "contract": ("contract",),
                         "contract-bool-as-int": ("contract",)}[mutation]
                for role in roles:
                    entry = evidence["files"][role]
                    path = root / entry["path"]
                    value = json.loads(path.read_bytes())
                    if mutation == "native-build": value["buildID"] = "f" * 40
                    if mutation == "metadata-source": value["source"] = "f" * 40
                    if mutation == "contract": value["hostFunctions"][0]["name"]["en"] = "Different"
                    if mutation == "contract-bool-as-int": value["packages"][0]["functions"][0]["optionalContent"] = 0
                    data = json.dumps(value).encode()
                    path.write_bytes(data)
                    entry.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
                manifest.write_text(json.dumps(evidence))
                with self.assertRaises(ValueError): catalog.verify_manifest(manifest, SOURCE)

    def testEvidencePathsCannotEscapeOrOverwriteInputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "evidence"
            root.mkdir()
            evidence_fixture(root)
            with self.assertRaises(ValueError):
                catalog.export_contract(root / "exports/zh-Hans", root / "exports/en", root / "metadata.json",
                                        SOURCE, root / "metadata.json", root / "evidence.json")
            export_evidence(root)
            manifest = root / "evidence.json"
            original = manifest.read_bytes()
            outside = root.parent / "outside.json"
            outside.write_bytes((root / "metadata.json").read_bytes())
            (root / "linked.json").symlink_to(outside)
            for path in ("../outside.json", str(outside), "linked.json"):
                value = json.loads(original)
                value["files"]["metadata"]["path"] = path
                manifest.write_text(json.dumps(value))
                with self.subTest(path=path), self.assertRaises(ValueError):
                    catalog.verify_manifest(manifest, SOURCE)


if __name__ == "__main__":
    unittest.main()
