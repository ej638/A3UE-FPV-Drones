"""AU update check: reviewed AU sources pass, and each kind of integration break is caught.

Uses the supplied AU source references (external/A3-Antistasi-Ultimate-<version>, located in the
original checkout from a worktree, or FPV_AU_SOURCES). Mutations run on a small synthetic copy of
AU 12.4.1 that holds only the files the checker reads. Static source checks only.
"""
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import au_compat_check as check  # noqa: E402

AU1203 = check.find_au_source("12.0.3")
AU1241 = check.find_au_source("12.4.1")


def worst(findings):
    return max(check.RANK[f.verdict] for f in findings)


def has(findings, verdict, section, text):
    return any(f.verdict == verdict and f.section == section and text in f.message for f in findings)


@unittest.skipUnless(AU1203 and AU1241, "AU 12.0.3/12.4.1 source references not found")
class ReviewedVersions(unittest.TestCase):
    def test_reviewed_12_0_3_passes_on_legacy_route(self):
        findings = check.run_checks(AU1203)
        self.assertEqual(worst(findings), 0, [f for f in findings if f.verdict != "OK"])
        self.assertTrue(has(findings, "OK", "events", "locationSpawned -> LEGACY"))
        self.assertTrue(has(findings, "INFO", "extender", "no extender compatibility check"))

    def test_reviewed_12_4_1_passes_on_cba_route_with_extender_declaration(self):
        findings = check.run_checks(AU1241)
        self.assertEqual(worst(findings), 0, [f for f in findings if f.verdict != "OK"])
        self.assertTrue(has(findings, "OK", "events", "locationSpawned -> CBA A3A_event_serverSpawnLocation"))
        self.assertTrue(has(findings, "OK", "extender", "declares {12, 4}"))
        self.assertTrue(has(findings, "OK", "gates", "AU 12.4.1 is in the reviewed list"))


@unittest.skipUnless(AU1241, "AU 12.4.1 source reference not found")
class Mutations(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fpv-aucheck-")
        self.au = Path(self.temp.name) / "au"
        for rel in check.required_paths(AU1241):
            if (AU1241 / rel).is_file():
                (self.au / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(AU1241 / rel, self.au / rel)

    def tearDown(self):
        self.temp.cleanup()

    def edit(self, rel, old, new):
        path = self.au / rel
        body = path.read_text(encoding="utf-8-sig")
        self.assertIn(old, body, rel)
        path.write_text(body.replace(old, new))

    def test_unmodified_synthetic_tree_has_no_integration_findings(self):
        findings = check.run_checks(self.au)
        bad = [f for f in findings if f.section != "globals" and check.RANK[f.verdict] > 0]
        self.assertEqual(bad, [])

    def test_site_event_moved_to_spawn_fails(self):
        self.edit("A3A/addons/core/functions/CREATE/fn_createAIOutposts.sqf",
                  '"Outpost", true]] call FUNCMAIN(triggerLocalEvent)', '"Outpost", true]] spawn FUNCMAIN(triggerLocalEvent)')
        self.assertTrue(has(check.run_checks(self.au), "FAIL", "events", "Outpost raises the site event via spawn"))

    def test_site_event_no_longer_raised_fails(self):
        self.edit("A3A/addons/core/functions/CREATE/fn_createAIResources.sqf",
                  '[CBA_EVENT_SERVER_SPAWN_LOCATION, [_markerX, "Resource", true]]', '[QGVAR(other), [_markerX, "Resource", true]]')
        self.assertTrue(has(check.run_checks(self.au), "FAIL", "events", "Resource no longer raises"))

    def test_site_function_not_scheduled_fails(self):
        self.edit("A3A/addons/core/functions/Base/fn_distance.sqf",
                  '"A3A_fnc_createAIOutposts"] call A3A_fnc_scheduler', '"A3A_fnc_createAIOutposts"] spawn A3A_fnc_createAIOutposts')
        self.assertTrue(has(check.run_checks(self.au), "FAIL", "sites", "Outpost: A3A_fnc_createAIOutposts is no longer scheduled"))

    def test_changed_dependency_needs_review(self):
        rel = "A3A/addons/core/functions/CREATE/fn_createVehicleCrew.sqf"
        (self.au / rel).write_text((self.au / rel).read_text() + "\n// upstream change\n")
        findings = check.run_checks(self.au)
        self.assertTrue(any(f.verdict == "REVIEW" and f.path == rel and "changed since reviewed" in f.message for f in findings))

    def test_removed_called_function_fails(self):
        (self.au / "A3A/addons/core/functions/AI/fn_canFight.sqf").unlink()
        self.assertTrue(has(check.run_checks(self.au), "FAIL", "deps", "AU no longer defines a3a_fnc_canfight"))

    def test_au_defining_our_function_name_fails(self):
        rel = self.au / "A3A/addons/core/functions/Supports/fn_SUP_FPV.sqf"
        rel.write_text("// AU's own FPV support\n")
        self.assertTrue(has(check.run_checks(self.au), "FAIL", "deps", "AU now defines a3a_fnc_sup_fpv itself"))

    def test_new_au_minor_warns_extender_dialog(self):
        self.edit("A3A/addons/core/Includes/script_version.hpp", "#define MINOR 4", "#define MINOR 5")
        findings = check.run_checks(self.au)
        self.assertTrue(has(findings, "WARN", "extender", "compatibility version is lower than our version"))
        self.assertTrue(has(findings, "REVIEW", "pins", "Changed AU contract"))

    def test_unlisted_au_patch_asks_for_review_but_switches_nothing_off(self):
        self.edit("A3A/addons/core/Includes/script_version.hpp", "#define PATCHLVL 1", "#define PATCHLVL 2")
        findings = check.run_checks(self.au)
        self.assertTrue(has(findings, "REVIEW", "gates", "AU 12.4.2 is not in the reviewed list"))
        self.assertTrue(has(findings, "REVIEW", "gates", "Nothing switches off for players"))
        self.assertFalse([f for f in findings if f.section == "gates" and f.verdict in ("WARN", "FAIL")])
        # AU exempts patch releases from its extender rule.
        self.assertTrue(has(findings, "OK", "extender", "declares {12, 4}"))

    def test_any_au_version_gate_fails(self):
        anchor = '\tprivate _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];'
        gates = {
            # 1.0.2 form, hard-coded version.
            'if (_ready && {getText (configFile >> "CfgPatches" >> "A3A_core" >> "versionStr") != "12.0.3"}) then {_reason = "UNREVIEWED_AU_VERSION";};':
                "AU version gate",
            # au124-compat-002 form, reviewed list.
            'if (_ready && {!(([] call A3UE_fnc_fpv_auReviewedVersion) # 2)}) then {_reason = "UNREVIEWED_AU_VERSION";};':
                "AU version gate",
            # Same list under another reason name.
            'if (_ready && {!(([] call A3UE_fnc_fpv_auReviewedVersion) # 2)}) then {_reason = "OLD_AU";};':
                "reviewed-AU list read outside the startup report",
        }
        for gate, message in gates.items():
            with self.subTest(gate=gate):
                addon = Path(self.temp.name) / "addon"
                shutil.rmtree(addon, ignore_errors=True)
                shutil.copytree(check.ADDON, addon)
                rivals = addon / "functions/fpv/fn_fpv_installRivalsHooks.sqf"
                body = rivals.read_text()
                self.assertIn(anchor, body)
                rivals.write_text(body.replace(anchor, "\t" + gate + "\n" + anchor))
                findings = check.run_checks(self.au, addon=addon)
                self.assertTrue(any(f.verdict == "FAIL" and f.section == "gates" and message in f.message
                                    and f.path == "functions/fpv/fn_fpv_installRivalsHooks.sqf" for f in findings),
                                [f for f in findings if f.section == "gates"])

    def test_missing_declaration_warns_extender_dialog(self):
        addon = Path(self.temp.name) / "addon"
        shutil.copytree(check.ADDON, addon)
        config = addon / "config.cpp"
        body = config.read_text()
        self.assertIn("A3A_compatibility[] = {12, 4};", body)
        config.write_text(body.replace("A3A_compatibility[] = {12, 4};", ""))
        self.assertTrue(has(check.run_checks(self.au, addon=addon), "WARN", "extender", "missing A3A_compatibility"))

    def test_mapping_to_undefined_cba_event_fails(self):
        self.edit("A3A/addons/events/Events.hpp", "REPLACE_EVENT(locationSpawned,CBA_EVENT_SERVER_SPAWN_LOCATION)",
                  "REPLACE_EVENT(locationSpawned,CBA_EVENT_SERVER_GONE)")
        self.assertTrue(has(check.run_checks(self.au), "FAIL", "events", "which cba_events.hpp does not define"))

    def test_legacy_api_removed_uses_built_in_names_then_fails_without_any_api(self):
        events = self.au / "A3A/addons/events/Events.hpp"
        events.write_text("class Events {};\n")
        (self.au / "A3A/addons/events/functions/fn_addEventListener.sqf").unlink()
        findings = check.run_checks(self.au)
        self.assertTrue(has(findings, "OK", "events", "locationSpawned -> CBA A3A_event_serverSpawnLocation"))
        (self.au / "A3A/addons/core/functions/Events/fn_addEventHandler.sqf").unlink()
        self.assertTrue(has(check.run_checks(self.au), "FAIL", "events", "neither the legacy listener API"))

    def test_trigger_wrapper_spawning_fails(self):
        self.edit("A3A/addons/core/functions/Events/fn_triggerLocalEvent.sqf", "call CBA_fnc_localEvent", "spawn CBA_fnc_localEvent")
        self.assertTrue(has(check.run_checks(self.au), "FAIL", "events", "no longer a plain call"))


class Locator(unittest.TestCase):
    def test_worktree_resolves_original_checkout(self):
        main = check.main_checkout()
        if (check.ROOT / ".git").is_file():
            self.assertIsNotNone(main)
            self.assertTrue((main / ".git").is_dir())
        else:
            self.assertIsNone(main)


if __name__ == "__main__":
    unittest.main()
