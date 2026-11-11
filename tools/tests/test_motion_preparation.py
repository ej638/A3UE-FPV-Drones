"""Offline lexical and transactional contracts. Real Arma execution is NOT RUN."""
import copy
import importlib.util
from pathlib import Path
import random
import re
import tempfile
import unittest

ROOT = Path(__file__).parent/'ua_dive'
spec = importlib.util.spec_from_file_location('preparation_model', ROOT/'motion_admission.py')
model = importlib.util.module_from_spec(spec)
spec.loader.exec_module(model)


class MotionPreparationTests(unittest.TestCase):
    def setUp(self):
        self.audit = model.PreparationModel()
        self.reviewed = {'shared': dict(source='header\n', forms=['{private _x = 1;}']),
                         'callback': dict(source='callback\n', forms=['{_this # 0;}'])}
        self.sources = {k: v['source'] for k, v in self.reviewed.items()}
        self.bindings = {k: v['forms'][0] for k, v in self.reviewed.items()}
        self.registry = ['callback']

    def run_audit(self, **kwargs):
        return self.audit.prepare('policy+providers+contents', self.reviewed, self.sources,
                                  self.bindings, self.registry, **kwargs)

    def test_cold_completes_and_warm_reuses_content_not_names(self):
        self.assertEqual(self.run_audit(costs={'shared': 2, 'callback': 1}), ('PREPARED_ONLY', (2, 0)))
        self.assertEqual(self.run_audit(), ('PREPARED_ONLY', (0, 2)))
        self.bindings['callback'] = '{(_this # 0) setVelocity [0,0,0];}'
        self.assertEqual(self.run_audit()[0], 'BODY_UNQUALIFIED')
        self.assertFalse(self.audit.ready)

    def test_policy_provider_or_content_identity_invalidates_sources(self):
        self.run_audit()
        original = copy.deepcopy(self.audit.cache)
        self.sources['shared'] = 'changed\n'
        for identity in ('new-policy', 'new-provider', 'new-source-content'):
            result = self.audit.prepare(identity, self.reviewed, self.sources, self.bindings, self.registry)
            self.assertEqual(result[0], 'SOURCE_UNQUALIFIED')
            self.assertEqual(self.audit.cache, original)

    def test_mutable_file_patched_provider_is_reread_even_when_body_is_unchanged(self):
        self.run_audit()
        self.sources['shared'] = 'file-patched drift'
        self.assertEqual(self.run_audit(mounted_immutable=False)[0], 'SOURCE_UNQUALIFIED')
        self.assertFalse(self.audit.ready)

    def test_partial_failure_does_not_publish_or_admit(self):
        self.sources['callback'] = 'wrong'
        self.assertEqual(self.run_audit()[0], 'SOURCE_UNQUALIFIED')
        self.assertEqual(self.audit.cache, {})
        self.assertFalse(self.audit.active)
        self.assertEqual(self.audit.revalidate(self.bindings, self.registry), 'PREPARATION_REQUIRED')

    def test_unknown_registry_refuses_even_with_a_warm_material_cache(self):
        self.run_audit()
        old = copy.deepcopy(self.audit.cache)
        self.assertEqual(self.run_audit(unknown=True)[0], 'UNKNOWN_CALLBACK')
        self.assertEqual(self.audit.cache, old)
        self.assertFalse(self.audit.ready)

    def test_final_freshness_and_existing_specimen_boundaries(self):
        self.assertEqual(self.run_audit(final_bindings={})[0], 'FUNCTION_CHANGED')
        self.assertEqual(self.run_audit(final_registry=['foreign'])[0], 'REGISTRY_CHANGED')
        self.run_audit()
        self.assertEqual(self.audit.revalidate({}, self.registry), 'FUNCTION_CHANGED')
        self.assertEqual(self.audit.revalidate(self.bindings, ['foreign']), 'REGISTRY_CHANGED')
        self.assertEqual(self.audit.revalidate(self.bindings, self.registry, ['foreign'], ['callback']), 'OBJECT_CALLBACKS_CHANGED')
        self.assertEqual(self.audit.revalidate(self.bindings, self.registry, conditions=False), 'COMPATIBILITY_CONDITION')

    def test_deadline_cancellation_cleanup_and_mission_reset(self):
        for kwargs, reason in ((dict(costs={'shared': 30}), 'DEADLINE'),
                               (dict(interrupt='callback'), 'CANCELLED')):
            self.assertEqual(self.run_audit(**kwargs)[0], reason)
            self.assertFalse(self.audit.active)
            self.assertEqual(self.audit.cache, {})
        self.assertEqual(self.run_audit()[0], 'PREPARED_ONLY')
        self.assertEqual(model.PreparationModel().cache, {})

    def test_mutual_exclusion_does_not_overwrite_an_active_job(self):
        for busy in (True, False):
            self.audit.active = not busy
            self.assertEqual(self.run_audit(busy=busy)[0], 'BUSY')
            self.assertEqual(self.audit.cache, {})

    def test_regex_spans_match_character_specification(self):
        policy = model.load_policy()
        text = [p['source_lf'] for p in policy['pins']] + [c['body'] for c in policy['callbacks']]
        # Valid lexical cases with quote escaping, comments containing quotes,
        # boundaries, strings containing directives/comments, select and numbers.
        text += ['private/**/_x=1; _x setVariable [\'a"b\'\'c\',"MiXeD"];',
                 'foo /* "ignored" */ bar;//"ignored"\n_this # 0;',
                 '"// #line /*x*/"; PRIVATE\t_x = 1.2e-3;',
                 "'it''s a string';a/**/b;", '#line 9 "x"\n{_this select 0;}']
        rng = random.Random(13)
        for _ in range(100):
            text.append(''.join(rng.choice(['foo', 'BAR', '_x', '#', '0', ';', ' ', '\n', '/**/', "'X'", '"Y"']) for _ in range(40)))
        for source in text:
            self.assertEqual(model.canonical_spans(source), model.canonical(source))

    def test_generated_material_retains_original_source_pins_and_dependencies(self):
        policy = model.load_policy()
        for pin in policy['pins']:
            self.assertEqual(model.fingerprint(pin['source_lf']), pin['fingerprint'])
            self.assertEqual(len(pin['pbo_sha256']), 64)
            self.assertEqual(len(pin['source_sha256']), 64)
        self.assertEqual(model.render_policy(policy), (ROOT/'motion_policy_data.sqf').read_text(encoding='utf-8'))

    def test_actual_sqf_lexeme_pattern_matches_the_offline_corpus(self):
        sqf = (ROOT/'motion_policy.sqf').read_text()
        pattern = re.search(r'_lexemes = _text regexFind \["((?:""|[^"])*)"\]', sqf)[1].replace('""', '"')
        self.assertTrue(pattern.endswith('/g'))  # explicit global, case-sensitive engine flags
        compiled = re.compile(pattern[:-2])
        text = 'foo/*"ignored"*/bar;"MiXeD";\'a"b\'\'c\';//tail\n#line 8 "file"\n{}'
        self.assertEqual([m.group() for m in compiled.finditer(text)],
                         ['/*"ignored"*/', '"MiXeD"', '\'a"b\'\'c\'', '//tail', '#line 8 "file"'])

    def test_generator_refuses_changed_reviewed_source(self):
        import hashlib
        import json
        generator_spec = importlib.util.spec_from_file_location('generator', ROOT/'generate_motion_policy.py')
        generator = importlib.util.module_from_spec(generator_spec)
        # Generator's ordinary CLI import; share the same loaded policy module.
        import sys
        sys.modules['motion_admission'] = model
        generator_spec.loader.exec_module(generator)
        with tempfile.TemporaryDirectory() as directory:
            inspection = Path(directory)
            source = inspection/'sources/provider/a.sqf'
            source.parent.mkdir(parents=True)
            source.write_bytes(b'abc\r\n')
            pin = dict(path='\\provider\\a.sqf', pbo_sha256='p'*64,
                       source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                       span=[], fingerprint=model.fingerprint('abc\n'))
            manifest = [dict(pbo='provider.pbo', pbo_sha256='p'*64, properties=dict(prefix='provider'),
                             entries=[dict(entry='a.sqf')])]
            (inspection/'sources.json').write_text(json.dumps(manifest))
            self.assertEqual(generator.enrich(dict(pins=[pin]), inspection)['pins'][0]['source_lf'], 'abc\n')
            source.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'Changed reviewed provider/source'):
                generator.enrich(dict(pins=[pin]), inspection)

    def test_engine_source_contract_has_no_character_fingerprint_or_cached_admission(self):
        policy = (ROOT/'motion_policy.sqf').read_text()
        prepare = (ROOT/'motion_prepare.sqf').read_text()
        fixture = (ROOT/'motion_fixture.sqf').read_text()
        self.assertNotIn('mod 65521', policy)
        self.assertIn('_checked isNotEqualTo _expectedLF', policy)
        self.assertIn('_raw isEqualTo (_saved # 0)', policy)
        self.assertIn('200000', policy)
        self.assertIn('call _budget}} do', policy)
        self.assertNotIn('createVehicle', prepare)
        self.assertLess(prepare.index('PREPARATION_ACKNOWLEDGED'), prepare.index('private _policy ='))
        self.assertLess(prepare.index('if (_ok) then {missionNamespace'), prepare.index('_state set ["active",false]'))
        self.assertIn('["admit",_class,_worker]', fixture)
        for name in ('capture', 'launch', 'startup'):
            self.assertIn('A3UE_FPV_QA_motionPreparation', (ROOT/(name+'.sqf')).read_text())


if __name__ == '__main__':
    unittest.main()
