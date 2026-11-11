"""Synthetic admission decisions. No Python claim of Arma/CBA execution."""
import copy
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location("motion_admission", HERE / "ua_dive/motion_admission.py")
model = importlib.util.module_from_spec(spec)
spec.loader.exec_module(model)


class MotionAdmissionPolicyTests(unittest.TestCase):
    def setUp(self):
        self.policy = model.load_policy()
        self.by_id = {c["id"]: c for c in self.policy["callbacks"]}

    def snapshot(self, names=("ace_fcs", "ims_bayonet", "ace_common_effects", "cba_statuseffects_effects")):
        rows = []
        for name in names:
            callback = self.by_id[name]
            rows.append(dict(path=callback["path"], body=callback["body"], code_id=name,
                             specimen="crew" if name == "ims_bayonet" else "vehicle"))
        return dict(cba=True, dispatch_qualified=True, is_server=True, is_dedicated=False,
                    native=[dict(path="native/init", body="call cba_xeh_fnc_init"),
                            dict(path="native/local", body="call cba_xeh_fnc_local")],
                    config=rows, registered=[dict(code_id=n) for n in names],
                    verified_conditions=model.specimen_conditions(crew=[{}]))

    def test_reviewed_dispatch_keeps_callbacks_and_requires_specimen_conditions(self):
        s = self.snapshot()
        decision, conditions = model.decide(s)
        self.assertEqual(decision, "ADMITTED_POLICY_ONLY")
        self.assertIn("UNARMED_CREW", conditions)
        self.assertIn("CBA_EFFECTS_UNDEFINED", conditions)
        self.assertEqual(len(s["registered"]), 4)

    def test_unknown_vehicle_crew_and_local_callbacks(self):
        for subject, route in (("vehicle", "init"), ("crew", "initpost"), ("crew", "local")):
            with self.subTest(subject=subject, route=route):
                s = self.snapshot(())
                s["config"].append(dict(path="Extended_" + route + "/unknown", body="call foreign_fnc_control",
                                        code_id="unknown", specimen=subject))
                s["registered"].append(dict(code_id="unknown"))
                self.assertEqual(model.decide(s)[0], "UNKNOWN_CALLBACK")

    def test_unknown_dynamic_registration(self):
        s = self.snapshot()
        s["registered"].append(dict(code_id="runtime-writer"))
        self.assertEqual(model.decide(s)[0], "UNKNOWN_DYNAMIC_CALLBACK")

    def test_inspected_direct_and_inline_dynamic_handlers_require_pins(self):
        for ident in ("ace_menu_init", "cba_network_Local", "cba_disposable_unit"):
            s = self.snapshot()
            row = dict(code_id=ident, reviewed_dynamic_id=ident, source_qualified=True, function_qualified=True)
            s["registered"].append(row)
            self.assertEqual(model.decide(s)[0], "ADMITTED_POLICY_ONLY")
            row["source_qualified"] = False
            self.assertEqual(model.decide(s)[0], "UNKNOWN_DYNAMIC_CALLBACK")
        s = self.snapshot()
        s["registered"].append(dict(code_id="headless-controller", reviewed_dynamic_id="ace_headless"))
        self.assertEqual(model.decide(s)[0], "UNKNOWN_DYNAMIC_CALLBACK")

    def test_forwarder_is_not_a_blanket_allowlist(self):
        s = self.snapshot()
        s["dispatch_qualified"] = False
        self.assertEqual(model.decide(s)[0], "CBA_FORWARDER_UNQUALIFIED")
        s["dispatch_qualified"] = True
        s["config"][0]["body"] += "; (_this # 0) setVelocity [0,0,0]"
        self.assertEqual(model.decide(s)[0], "UNKNOWN_CALLBACK")

    def test_changed_source_or_loaded_function(self):
        for key in ("source_qualified", "function_qualified"):
            s = self.snapshot()
            s["config"][0][key] = False
            self.assertEqual(model.decide(s)[0], "IMPLEMENTATION_UNQUALIFIED")

    def test_roles_include_client_on_host_and_headless_not_on_dedicated(self):
        row = dict(role="client")
        self.assertTrue(model.applicable(row, is_server=True, is_dedicated=False))
        self.assertTrue(model.applicable(row, is_server=False, is_dedicated=False))  # CBA HC rule, no hasInterface test
        self.assertFalse(model.applicable(row, is_server=True, is_dedicated=True))
        self.assertFalse(model.applicable(dict(role="server"), is_server=False, is_dedicated=False))

    def test_metadata_inheritance_exclusion_and_override_are_not_executed(self):
        for kwargs in (dict(metadata=True), dict(inherit=False, exact_class=False),
                       dict(excluded=True), dict(overridden=True), dict(class_match=False)):
            with self.subTest(kwargs=kwargs):
                self.assertFalse(model.applicable(kwargs, is_server=True, is_dedicated=False))
        s = self.snapshot()
        s["config"].append(dict(path="onRespawn", body="true", metadata=True, code_id="metadata"))
        self.assertEqual(model.decide(s)[0], "ADMITTED_POLICY_ONLY")

    def test_actual_armed_crew_refused_without_modifying_gear(self):
        crew = [dict(primary="arifle_MX_F")]
        before = copy.deepcopy(crew)
        s = self.snapshot()
        s["verified_conditions"] = model.specimen_conditions(crew=crew)
        self.assertEqual(model.decide(s)[0], "COMPATIBILITY_CONDITION:UNARMED_CREW")
        self.assertEqual(crew, before)

    def test_defined_zero_effect_still_replays_and_is_refused(self):
        s = self.snapshot()
        s["verified_conditions"] = model.specimen_conditions(crew=[{}], effects=[("disableAI", 0)])
        self.assertTrue(model.decide(s)[0].startswith("COMPATIBILITY_CONDITION:"))
        self.assertNotIn("ACE_EFFECTS_UNDEFINED", s["verified_conditions"])

    def test_conscious_captives_radio_fcs_and_rallypoint_failures(self):
        for callback, fields, condition in (("wbk_reactions", dict(crew=[dict(unconscious=True)]), "CONSCIOUS_CREW"),
                                            ("ace_captives_local", dict(captive=True), "NO_CAPTIVE_STATE"),
                                            ("klpq_radio", dict(radio=True), "RADIO_OFF"),
                                            ("ace_fcs", dict(fcs=True), "FCS_DISABLED"),
                                            ("ace_respawn", dict(rallypoint=True), "NO_RALLYPOINT")):
            with self.subTest(callback=callback):
                s = self.snapshot((callback,))
                s["verified_conditions"] = model.specimen_conditions(**(dict(crew=[{}]) | fields))
                self.assertEqual(model.decide(s)[0], "COMPATIBILITY_CONDITION:" + condition)

    def test_no_cba_vanilla_path_and_unknown_native_still_refused(self):
        s = dict(cba=False, native=[dict(path="native/init", body="")])
        self.assertEqual(model.decide(s)[0], "ADMITTED_POLICY_ONLY")
        s["native"].append(dict(path="native/init", body="call foreign_fnc_move"))
        self.assertEqual(model.decide(s)[0], "UNKNOWN_NATIVE_CALLBACK")

    def test_policy_data_and_pin_dependencies_are_complete(self):
        self.assertEqual(model.render_policy(self.policy), (HERE / "ua_dive/motion_policy_data.sqf").read_text(encoding="utf-8"))
        ids = {p["id"] for p in self.policy["pins"]}
        for callback in self.policy["callbacks"]:
            self.assertTrue(set(callback["pins"]) <= ids)
        for pin in self.policy["pins"]:
            self.assertTrue(set(pin["dependencies"]) <= ids)
        self.assertEqual(model.fingerprint("abc\r\n"), model.fingerprint("abc\n"))
        self.assertNotEqual(model.fingerprint("doMove"), model.fingerprint("enableAI"))

    def test_code_comparison_preserves_tokens_array_select_strings_and_writers(self):
        a = 'private _x = _this # 0; _x setVariable ["MiXeD", false];'
        b = '#line 1 "file"\nPRIVATE /* annotation */ _x=_this#0;_x setVariable [\'MiXeD\',false];'
        self.assertEqual(model.canonical(a), model.canonical(b))
        self.assertNotEqual(model.canonical(a), model.canonical(a.replace('private _x', 'private_x')))
        self.assertNotEqual(model.canonical(a), model.canonical(a.replace('MiXeD', 'mixed')))
        self.assertNotEqual(model.canonical(a), model.canonical(a.replace('setVariable', 'setVelocity')))
        self.assertNotEqual(model.canonical('{_this # 0; setVelocity [0,0,0]}'), model.canonical('{_this # 0;}'))


if __name__ == "__main__":
    unittest.main()
