"""AU-04: drift must fail the same gate used by artifact verification."""

import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verify_au_adapter as adapter
from au_compat_check import find_au_source

# external/ may exist only in the original checkout; locate it from worktrees too.
AU1203 = find_au_source("12.0.3")
AU1241 = find_au_source("12.4.1")
REFERENCE_CORE = AU1203 / "A3A/addons/core" if AU1203 else None


class AdapterDriftTest(unittest.TestCase):
    def setUp(self):
        evidence = adapter.ROOT / ".hemttout/verification/au04"
        evidence.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=evidence)
        self.root = Path(self.temp.name)
        self.manifest = json.loads((adapter.ROOT / adapter.PIN / "manifest.json").read_text())
        paths = [adapter.PIN / "manifest.json", Path("addons/drones/config.cpp")]
        paths += [Path(row["adapter"]) for row in self.manifest["overrides"]]
        paths += [adapter.PIN / row["patch"] for row in self.manifest["overrides"]]
        paths += [Path(row["path"]) for row in self.manifest["build_headers"]]
        for relative in paths:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(adapter.ROOT / relative, target)

    def tearDown(self):
        self.temp.cleanup()

    def test_source_free_checkout_retains_explicit_evidence_limit(self):
        result = adapter.verify(self.root)
        self.assertEqual(result["override_count"], 6)
        self.assertEqual(result["upstream_checked"], "NOT SUPPLIED")

    def test_unrecorded_adapter_edit_outside_hunks_fails(self):
        path = self.root / self.manifest["overrides"][0]["adapter"]
        path.write_text(path.read_text() + "diag_log 'unreviewed';\n")
        with self.assertRaisesRegex(ValueError, "Unrecorded body drift"):
            adapter.verify(self.root)

    def test_unrecorded_edit_inside_hunk_fails(self):
        path = self.root / self.manifest["overrides"][0]["adapter"]
        path.write_text(path.read_text().replace("isRemoteExecutedJIP", "false", 1))
        with self.assertRaisesRegex(ValueError, "patch context"):
            adapter.verify(self.root)

    def test_exact_candidate_passes_then_changed_upstream_fails(self):
        if REFERENCE_CORE is None:
            self.skipTest("Candidate/dependency check requires the supplied upstream source")
        candidate = self.root / "candidate"
        for row in self.manifest["overrides"]:
            path = candidate / row["upstream"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(adapter.reverse_patch(adapter.normalized(self.root / row["adapter"]),
                                                   adapter.normalized(self.root / adapter.PIN / row["patch"])))
        for row in self.manifest["contracts"]:
            path = candidate / row["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REFERENCE_CORE / row["path"], path)
        self.assertEqual(adapter.verify(self.root, candidate)["override_count"], 6)
        path = candidate / self.manifest["overrides"][0]["upstream"]
        original = path.read_text()
        path.write_text(path.read_text() + "// upstream update\n")
        with self.assertRaisesRegex(ValueError, "Changed candidate upstream body"):
            adapter.verify(self.root, candidate)
        path.write_text(original)
        contract = candidate / "functions/Supports/fn_createSupport.sqf"
        contract.write_text(contract.read_text() + "// changed serialization/debit contract\n")
        with self.assertRaisesRegex(ValueError, "Changed AU contract"):
            adapter.verify(self.root, candidate)

    def test_reviewed_12_4_1_contracts_pass_and_mixed_versions_fail(self):
        if AU1203 is None or AU1241 is None:
            self.skipTest("Requires the supplied AU 12.0.3 and 12.4.1 sources")
        self.assertEqual(adapter.verify(self.root, AU1203 / "A3A/addons/core")["upstream_matches"], "12.0.3")
        self.assertEqual(adapter.verify(self.root, AU1241 / "A3A/addons/core")["upstream_matches"], "12.4.1")
        # A 12.4.1 registry with a 12.0.3 version header matches no reviewed release as a whole.
        mixed = self.root / "mixed"
        for row in self.manifest["overrides"]:
            path = mixed / row["upstream"]
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(AU1241 / "A3A/addons/core" / row["upstream"], path)
        for row in self.manifest["contracts"]:
            path = mixed / row["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            source = AU1203 if row["path"] == "Includes/script_version.hpp" else AU1241
            shutil.copyfile(source / "A3A/addons/core" / row["path"], path)
        with self.assertRaisesRegex(ValueError, "mixed reviewed versions"):
            adapter.verify(self.root, mixed)

    def test_explicit_missing_candidate_fails(self):
        with self.assertRaisesRegex(ValueError, "Missing candidate"):
            adapter.verify(self.root, self.root / "missing")

    def test_config_path_drift_fails(self):
        path = self.root / "addons/drones/config.cpp"
        path.write_text(path.read_text().replace("au_overrides\\fn_singleAttack.sqf", "foreign\\fn_singleAttack.sqf"))
        with self.assertRaisesRegex(ValueError, "Changed function path"):
            adapter.verify(self.root)

    def test_duplicate_category_fails(self):
        path = self.root / "addons/drones/config.cpp"
        path.write_text(path.read_text().replace("class CREATE {", "class Foreign {class singleAttack {};}; class CREATE {"))
        with self.assertRaisesRegex(ValueError, "Duplicate public declaration"):
            adapter.verify(self.root)

    def test_macro_snapshot_drift_fails(self):
        path = self.root / self.manifest["build_headers"][0]["path"]
        path.write_text(path.read_text() + "// changed macro source\n")
        with self.assertRaisesRegex(ValueError, "Changed build header"):
            adapter.verify(self.root)


if __name__ == "__main__":
    unittest.main()
