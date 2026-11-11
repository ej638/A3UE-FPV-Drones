"""Offline Cargo review/cleanup contracts; no claim of native engine execution."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).parent/'ua_dive'
spec = importlib.util.spec_from_file_location('cargo_model', ROOT/'motion_admission.py')
model = importlib.util.module_from_spec(spec)
spec.loader.exec_module(model)


class MotionCargoTests(unittest.TestCase):
    def setUp(self):
        self.policy = model.load_policy()

    def check(self, name='O_UAFPV_PG7VL_AT', config=None, actual=None, **kw):
        has, space = (0, 0) if name == 'B_UAV_01_F' else (1, 8)
        return model.cargo_condition(name, config or dict(has_cargo=has, space=space, configured=[]),
                                     actual or {}, policy=self.policy, **kw)

    def test_disabled_vanilla_and_enabled_empty_vendors_are_separate_paths(self):
        self.assertEqual(self.check('B_UAV_01_F'), 'DISABLED')
        for name in ('O_UAFPV_PG7VL_AT', 'frtz_O_KVN_AT_20KM'):
            self.assertEqual(self.check(name, actual=dict(init=True), initialized=True), 'ENABLED_EMPTY')
            self.assertEqual(self.check(name, initialized=True), 'NATIVE_INIT_PENDING')

    def test_actual_override_types_agreement_and_path_switches(self):
        for name, agreeing in (('B_UAV_01_F', False), ('O_UAFPV_PG7VL_AT', True)):
            self.assertIn(self.check(name, actual=dict(has_cargo=agreeing)), ('DISABLED', 'ENABLED_EMPTY'))
            for value in (not agreeing, 0, 1, 'true', []):
                with self.subTest(name=name, value=value):
                    self.assertEqual(self.check(name, actual=dict(has_cargo=value)), 'HAS_CARGO_OVERRIDE')
        for fields in (dict(space=9), dict(space='8'), dict(space=True), dict(can_load=False),
                       dict(size=0), dict(setspace_jip=True), dict(init='true')):
            self.assertNotIn(self.check(actual=fields), ('DISABLED', 'ENABLED_EMPTY'))

    def test_configured_cargo_even_zero_amount_and_config_drift_are_refused(self):
        for config in (dict(has_cargo=1, space=8, configured=[['ACE_Wheel', 0]]),
                       dict(has_cargo=1, space=9, configured=[]), dict(has_cargo=0, space=8, configured=[])):
            self.assertEqual(self.check(config=config), 'CARGO_CONFIG_UNQUALIFIED')
        self.assertEqual(self.check('unknown_UAV'), 'CARGO_CONFIG_UNQUALIFIED')

    def test_nonempty_virtual_object_or_malformed_actual_cargo_refuses_cleanup(self):
        for cargo in (['ACE_Wheel'], ['foreign_object'], 0, None, {}):
            actual = dict(loaded=cargo)
            before = copy.deepcopy(actual)
            result = self.check(actual=actual)
            self.assertEqual(result, 'LOADED_OR_ATTACHED_RESOURCE')
            self.assertFalse(model.cargo_cleanup_allowed(result))
            self.assertEqual(actual, before)

    def test_changed_mass_attachments_viv_and_active_cargo_services_refused(self):
        for actual, reason in ((dict(mass=2), 'MASS_CHANGED'),
                               (dict(mass=1, attached=['foreign']), 'LOADED_OR_ATTACHED_RESOURCE'),
                               (dict(mass=1, attached_to='carrier'), 'LOADED_OR_ATTACHED_RESOURCE'),
                               (dict(mass=1, vehicle_cargo=['object']), 'LOADED_OR_ATTACHED_RESOURCE'),
                               (dict(mass=1, cargo_parent='carrier'), 'LOADED_OR_ATTACHED_RESOURCE'),
                               (dict(mass=1, interaction=True), 'CARGO_INTERACTION_OR_DEPLOYMENT'),
                               (dict(mass=1, preview=True), 'CARGO_INTERACTION_OR_DEPLOYMENT'),
                               (dict(mass=1, deploy_pfh=0), 'CARGO_INTERACTION_OR_DEPLOYMENT')):
            self.assertEqual(self.check(actual=actual, baseline_mass=1), reason)

    def test_retained_crew_containers_and_sticky_unsafe_cleanup(self):
        foreign = dict(loaded=['foreign'])
        before = copy.deepcopy(foreign)
        result = self.check(retained_resources=[foreign])
        self.assertFalse(model.cargo_cleanup_allowed(result))
        self.assertEqual(foreign, before)
        self.assertFalse(model.cargo_cleanup_allowed(self.check(), previously_unsafe=True))
        self.assertEqual(self.check(retained_resources=[{}]*32), 'CONTAINER_BOUND')

    def test_cargo_dynamic_requires_full_source_and_function_qualification(self):
        row = dict(code_id='cargo', reviewed_dynamic_id='ace_cargo_vehicle', source_qualified=True, function_qualified=True)
        snapshot = dict(cba=True, dispatch_qualified=True, registered=[row], verified_conditions=['ACE_CARGO_EMPTY'])
        self.assertEqual(model.decide(snapshot)[0], 'ADMITTED_POLICY_ONLY')
        for key in ('source_qualified', 'function_qualified'):
            changed = copy.deepcopy(snapshot); changed['registered'][0][key] = False
            self.assertEqual(model.decide(changed)[0], 'UNKNOWN_DYNAMIC_CALLBACK')
        snapshot['verified_conditions'] = []
        self.assertEqual(model.decide(snapshot)[0], 'COMPATIBILITY_CONDITION:ACE_CARGO_EMPTY')
        # A changed raw binding remains refused after successful cached preparation.
        audit = model.PreparationModel()
        reviewed = {'cargo':dict(source='reviewed', forms=['{params ["_vehicle"]; }'])}
        args = ('cargo-policy', reviewed, {'cargo':'reviewed'}, {'cargo':'{params ["_vehicle"]; }'}, ['cargo'])
        self.assertEqual(audit.prepare(*args)[0], 'PREPARED_ONLY')
        drift = list(args); drift[3] = {'cargo':'{params ["_vehicle"]; _vehicle setVelocity [0,0,0];}'}
        self.assertEqual(audit.prepare(*drift)[0], 'BODY_UNQUALIFIED')

    def test_complete_captured_batch_classifies_every_row_without_admitting_prefixes(self):
        batch = json.loads((ROOT/'motion_callback_batch.json').read_text())
        targets = {c['id']:c for c in self.policy['callbacks']+self.policy['dynamic_callbacks']}
        pins = {p['id']:p for p in self.policy['pins']}
        self.assertEqual(batch['observed_rows'], 83)
        self.assertEqual(len(batch['entries']), 29)
        self.assertEqual(sum(len(r['subjects']) for r in batch['entries']), 83)
        self.assertEqual(sum(r['classification']=='CARGO_ADDITION' for r in batch['entries']), 1)
        for row in batch['entries']:
            target = targets[row['policy_target']]
            self.assertEqual(row['pins'], target['pins'])
            self.assertEqual(row['conditions'], target['conditions'])
            self.assertEqual(row['engine_full_body'], 'PENDING')
            self.assertGreater(len(target['pins']), 0)
            for ident in target['pins']:
                pin = pins[ident]
                self.assertEqual(model.fingerprint(pin['source_lf']), pin['fingerprint'])
                self.assertEqual(len(pin['source_sha256']), 64)
            # Discovery labels, indices and prefixes grant zero admission rights.
            snapshot = dict(cba=True, dispatch_qualified=True, registered=[dict(code_id=row['observed_prefix'])])
            self.assertEqual(model.decide(snapshot)[0], 'UNKNOWN_DYNAMIC_CALLBACK')
        source = (ROOT/'motion_policy.sqf').read_text()
        self.assertIn('getText (_x >> "gunnerType")', source)
        self.assertIn('[_x >> "Turrets",_depth+1] call _turrets', source)

    def test_progress_and_actual_refusal_identity_are_distinct_and_bounded(self):
        code = '{#line 18 "\\z\\ace\\addons\\cargo\\functions\\fnc_initVehicle.sqf"\nprivate _secret="never log";}'
        identity = model.unmatched_identity(code, self.policy)
        self.assertEqual(identity[0], 'SOURCE_LABEL_ONLY')
        self.assertEqual(identity[2], 'ace_cargo_fnc_initVehicle')
        self.assertNotIn('never log', str(identity))
        self.assertEqual(model.unmatched_identity('{foreign secret body}'), ['UNIDENTIFIED'])
        preparation = (ROOT/'motion_prepare.sqf').read_text()
        policy = (ROOT/'motion_policy.sqf').read_text()
        self.assertIn('["progressItem",_state get "item"]', preparation)
        self.assertIn('["unmatchedCallback",_state getOrDefault ["unmatched",[]]]', preparation)
        self.assertIn('[_specClass,_var,_registrationIndex,_identity,[count _codeText]]', policy)

    def test_cargo_guards_run_at_existing_boundaries_and_cleanup_before_deletion(self):
        fixture = (ROOT/'motion_fixture.sqf').read_text()
        policy = (ROOT/'motion_policy.sqf').read_text()
        self.assertIn('["cargoMass",getMass _u]', fixture)
        self.assertIn('case "ACE_CARGO_EMPTY"', policy)
        self.assertIn('private _failure = [_policy] call _cargoStatic', policy)
        self.assertIn('NATIVE_INIT_PENDING', policy)
        cleanup = fixture.split('case "cleanup":', 1)[1].split('case "finish":', 1)[0]
        self.assertLess(cleanup.index('["cargoCleanup"'), cleanup.index('deleteVehicle _u'))
        self.assertLess(cleanup.index('["foreignUnsafe",true]'), cleanup.index('deleteVehicle _u'))
        self.assertIn('[_u]+(_spec get "crew")', cleanup)
        self.assertNotIn('setVariable ["ace_cargo_', fixture+policy)
        self.assertNotIn('call ace_cargo_fnc_initVehicle', fixture+policy)
        self.assertNotIn('deleteVehicle', policy)


if __name__ == '__main__':
    unittest.main()
