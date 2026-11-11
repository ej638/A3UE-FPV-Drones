"""Source-driven policy gates and modeled admission races; no Arma execution/physics."""
from copy import deepcopy
import json
import math
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
FPV = ROOT / 'addons/drones/functions/fpv'
GUIDANCE = (FPV / 'fn_fpv_applyGuidance.sqf').read_text()
CONTROLLER = (FPV / 'fn_fpv_runController.sqf').read_text()
DOCTRINE = (FPV / 'fn_fpv_buildDoctrine.sqf').read_text()


def scalar(x):
    return type(x) in (int, float)


def boolean(expression, values):
    """Translate the shipped Boolean gates only, with lazy SQF blocks preserved."""
    for a, b in [('isNotEqualTo', '!='), ('isEqualTo', '=='),
                 ('&&', ' and '), ('||', ' or '), ('!', ' not '),
                 ('{', '('), ('}', ')')]:
        # Do not replace the ! in !=.
        if a == '!':
            expression = re.sub(r'!(?!=)', b, expression)
        else:
            expression = expression.replace(a, b)
    return eval(' '.join(expression.split()), {'__builtins__': {}}, values)


def interval(value=.15):
    check = re.search(r'if \((.*?)\) then \{\s*_moveInterval = ([\d.]+);',
                      GUIDANCE.split('private _moveInterval =', 1)[1], re.S)
    expr = check[1].replace('_moveInterval isEqualType 0', 'scalar(value)')
    expr = expr.replace('finite _moveInterval', 'math.isfinite(value)').replace('_moveInterval', 'value')
    return float(check[2]) if boolean(expr, dict(value=value, scalar=scalar, math=math)) else value


def context_ready(context, identity, target):
    expr = re.search(r'private _contextReady = (.*?);', GUIDANCE, re.S)[1]
    expr = expr.replace('_orderContext isEqualType []', 'isinstance(context, list)')
    expr = expr.replace('count _orderContext', 'len(context)')
    expr = expr.replace('_orderContext # 0', 'context[0]').replace('_orderContext # 1', 'context[1]')
    expr = expr.replace('_helperIdentity', 'identity').replace('_targetNetId', 'target')
    return boolean(expr, dict(context=context, identity=identity, target=target, isinstance=isinstance, list=list, len=len))


def cache_ready(goal, stamp, now):
    expr = re.search(r'private _cacheReady = (.*?);', GUIDANCE, re.S)[1]
    predicate = re.search(r'\(_lastMoveTarget findIf \{(.*?)\}\)', expr)[0]
    expr = expr.replace(predicate, 'bad_index')
    expr = expr.replace('_lastMoveTarget isEqualType []', 'isinstance(goal, list)').replace('count _lastMoveTarget', 'len(goal)')
    expr = expr.replace('_lastMoveUpdate isEqualType 0', 'scalar(stamp)').replace('finite _lastMoveUpdate', 'math.isfinite(stamp)')
    expr = expr.replace('_lastMoveUpdate', 'stamp').replace('time', 'now')
    bad_index = next((i for i, x in enumerate(goal) if not scalar(x) or not math.isfinite(x)), -1) if isinstance(goal, list) else -1
    return boolean(expr, dict(goal=goal, stamp=stamp, now=now, bad_index=bad_index,
                             isinstance=isinstance, list=list, len=len, scalar=scalar, math=math))


def due(cache, context, tracking, old, goal, stamp, now, policy, delta=8):
    # F2 coalesces native settings inside this same unchanged destination predicate.
    expr = re.search(r'if \((!_cacheReady.*?)\) then \{', GUIDANCE, re.S)[1]
    expr = expr.replace('_lastMoveTarget distance2D _moveTargetAtl', 'distance')
    distance = math.dist(old[:2], goal[:2]) if cache else 0
    values = dict(_cacheReady=cache, _contextReady=context, _tracking=tracking,
                  distance=distance, _moveDelta=delta, time=now,
                  _lastMoveUpdate=stamp, _moveInterval=policy)
    return boolean(expr, values)


def doctrine_profiles(apply_site_ap=True):
    """Read authored cells and model the existing deep support-template copies.

    These are profile policy contracts, not an SQF interpreter or flight model.
    The source-order assertions below bind the final site-only mutation.
    """
    authored = DOCTRINE.split('private _behaviorAuthoring = createHashMapFromArray ', 1)[1].split(';', 1)[0]
    sites = dict(json.loads(authored))
    for site, data in re.findall(r'_behaviorAuthoring set \["([^"]+)", (\[.*?\])\];', DOCTRINE, re.S):
        sites[site] = json.loads(data)
    profiles = {site: {(family, role): dict(specs) for family, roles in families
                       for role, specs in roles} for site, families in sites.items()}
    for context, template in re.findall(r'\["(\w+Support)", "(\w+)", "support_\w+",', DOCTRINE):
        profiles[context] = deepcopy(profiles[template])
    if apply_site_ap:
        block = DOCTRINE.split('// Site-only AP cadence:', 1)[1]
        family = re.search(r'_profiles getOrDefault \["([^"]+)"', block)[1]
        role = re.search(r'\) getOrDefault \["([^"]+)"', block.split('private _apProfile =', 1)[1])[1]
        key, value = re.search(r'_apProfile set \["([^"]+)", ([\d.]+)\]', block).groups()
        for site in json.loads(re.search(r'forEach (\[.*?\]);', block)[1]):
            if (family, role) in profiles.get(site, {}):
                profiles[site][family, role][key] = float(value)
    return profiles


class Worker:
    """Mock engine effects around the actual shipped cache/order gates."""
    def __init__(self):
        self.identity = [1, 2, 1, 1]
        self.target = 'target-a'
        self.mode = 'TRACKING'
        self.context = []
        self.goal = []
        self.stamp = -1
        self.orders = self.ai_passes = self.writes = 0
        self.admitted = True

    def update(self, now, goal=None, policy=1, original=None, intent=None, pause=None, explicit=True):
        original = deepcopy(self.identity if original is None else original)
        intent = self.target if intent is None else intent
        mode = self.mode
        if not self.admitted or original != self.identity:
            return False
        policy = interval(policy)
        if pause:
            pause(self)
        # Mode/target checked with the original identity at the single effect boundary.
        if (not self.admitted or original != self.identity or intent != self.target
                or mode != self.mode or (explicit and mode != 'TRACKING')):
            return False
        goal = [100, 100, 15] if goal is None else goal
        tracking = mode == 'TRACKING'
        self.ai_passes += 1
        if due(cache_ready(self.goal, self.stamp, now), context_ready(self.context, original, intent),
               tracking, self.goal, goal, self.stamp, now, policy if tracking else .15):
            self.orders += 1
            self.goal = list(goal)
            self.stamp = now
            if tracking:
                self.context = [original, intent]
                self.writes += 1
        return True

    def reset(self, original, generation=None, local=True):
        generation = original[3] if generation is None else generation
        if local and self.identity[3] == generation and self.identity == original and self.context != []:
            self.context = []
            self.writes += 1


class TrackingPolicyTests(unittest.TestCase):
    def test_legacy_fallback_rejects_types_nonfinite_and_bounds_without_clamping(self):
        for x in [None, True, False, '1', [], {}, -.1, 0, .149999, 1.000001,
                  float('nan'), float('inf'), -float('inf')]:
            self.assertEqual(interval(x), .15, repr(x))
        for x in [.15, .150001, .5, 1]:
            self.assertEqual(interval(x), x)
        self.assertIn('[_profile, "trackingMoveInterval", 0.15]', GUIDANCE)
        self.assertEqual(interval(), .15)

    def test_exact_authored_scope_and_existing_merge_precedence(self):
        authored = DOCTRINE.split('private _behaviorAuthoring = createHashMapFromArray ', 1)[1].split(';', 1)[0]
        cells = {(site, family, role): dict(specs) for site, families in json.loads(authored)
                 for family, roles in families for role, specs in roles}
        opted = {key: value['trackingMoveInterval'] for key, value in cells.items() if 'trackingMoveInterval' in value}
        self.assertEqual(opted, {(site, 'armafpv', 'AT'): 1 for site in ['Airport', 'Outpost', 'Resource']})
        self.assertEqual(authored.count('"trackingMoveInterval"'), 3)
        self.assertEqual(DOCTRINE.count('"trackingMoveInterval"'), 4)
        build = DOCTRINE.split('private _buildBehaviorProfile = {', 1)[1]
        self.assertLess(build.index('_siteSearchProfiles'), build.index('createHashMapFromArray _authoredSpecs'))
        self.assertLess(build.index('_roleBehaviorDefaults'), build.index('createHashMapFromArray _authoredSpecs'))
        resolver = (FPV / 'fn_fpv_getProfile.sqf').read_text()
        self.assertLess(resolver.index('"search"'), resolver.index('"lostTarget"'))
        self.assertLess(resolver.index('"lostTarget"'), resolver.index('_familyProfiles getOrDefault [_payloadRole'))
        # Apply that existing last-writer merge order to all 27 primary cells.
        for key, specs in cells.items():
            resolved = {'trackingMoveInterval': .4}
            resolved.update({'trackingMoveInterval': .5})
            resolved.update(specs)
            self.assertEqual(interval(resolved['trackingMoveInterval']), 1 if key in opted else .5)
            self.assertEqual(interval(specs.get('trackingMoveInterval', .15)), 1 if key in opted else .15)
        for text in [GUIDANCE, (ROOT / 'addons/drones/config.cpp').read_text()]:
            self.assertNotIn('O_Crocus', text)
        self.assertNotIn('trackingMoveInterval', (ROOT / 'addons/drones/config.cpp').read_text())

    def test_f0_exact_site_ap_extension_preserves_all_neighbor_and_support_profiles(self):
        before, after = doctrine_profiles(False), doctrine_profiles()
        self.assertEqual(len(after), 12)
        changed = []
        for site, profiles in after.items():
            self.assertEqual(set(profiles), set(before[site]))
            for (family, role), profile in profiles.items():
                old = before[site][family, role]
                if profile != old:
                    changed.append((site, family, role))
                    self.assertNotIn('trackingMoveInterval', old)
                    self.assertEqual(profile, dict(old, trackingMoveInterval=1.0))
        expected = {(site, 'armafpv', 'AP') for site in ['Airport', 'Outpost', 'Resource']}
        self.assertEqual(set(changed), expected)
        self.assertEqual(len(changed), 3)
        for site in after:
            for family, role in after[site]:
                selected = (site, family, role) in expected
                self.assertEqual(interval(after[site][family, role].get('trackingMoveInterval', .15)),
                                 1 if selected else interval(before[site][family, role].get('trackingMoveInterval', .15)))
        # A shallow copy or an earlier override would leak into three support contexts.
        copier = DOCTRINE.split('private _copyProfileTree = {', 1)[1].split('private _applyBehaviorProfileOverrides', 1)[0]
        self.assertIn('[_y] call _copyMap', copier)
        block = DOCTRINE.split('// Site-only AP cadence:', 1)[1]
        self.assertGreater(DOCTRINE.index('// Site-only AP cadence:'), DOCTRINE.rindex('] call _buildSupportEntryFromTemplate;'))
        self.assertIn('if (count _apProfile > 0)', block)  # soft-detection: absent family remains absent
        self.assertLess(block.index('_apProfile set'), block.index('missionNamespace setVariable'))
        self.assertNotIn('profileId', block)  # preserve existing profile metadata as well as values

    def test_resolved_ap_and_at_policies_keep_immediate_delta_and_strict_time_gates(self):
        profiles = doctrine_profiles()
        for site in ['Airport', 'Outpost', 'Resource']:
            for role in ['AP', 'AT']:
                policy = profiles[site]['armafpv', role]['trackingMoveInterval']
                w = Worker()
                for now, expected in [(10, 1), (10, 1), (10.15, 1), (11, 1), (11.00001, 2)]:
                    self.assertTrue(w.update(now, policy=policy))
                    self.assertEqual(w.orders, expected, (site, role, now))
                w.update(11.1, [108, 100, 100], policy=policy)
                self.assertEqual(w.orders, 2)  # exact XY threshold, height alone does not bypass
                w.update(11.1, [108.01, 100, 15], policy=policy)
                self.assertEqual(w.orders, 3)
                w.target = 'replacement'
                w.update(11.1, [108.01, 100, 15], policy=policy)
                self.assertEqual(w.orders, 4)
                w.mode = 'LOST_TARGET'; w.reset(w.identity)
                w.update(11.25, [108.01, 100, 15], policy=policy, explicit=False)
                self.assertEqual(w.orders, 4)  # strict legacy boundary, no movement bypass
                w.update(11.251, [108.01, 100, 15], policy=policy, explicit=False)
                self.assertEqual(w.orders, 5)  # legacy lost-target timing, even for selected AP/AT

    def test_first_repeated_strict_expiry_and_material_xy_change(self):
        w = Worker()
        for t, orders in [(10, 1), (10, 1), (10.5, 1), (11, 1), (11.00001, 2)]:
            self.assertTrue(w.update(t)); self.assertEqual(w.orders, orders)
        self.assertTrue(w.update(11.1, [108, 100, 900])); self.assertEqual(w.orders, 2)
        self.assertTrue(w.update(11.1, [108.001, 100, 15])); self.assertEqual(w.orders, 3)
        self.assertEqual(w.ai_passes, 7)  # unchanged AI work still occurs every admitted guidance pass

    def test_invalid_context_cache_sentinels_and_clock_reversal(self):
        for context in [None, 'bad', 7, [], [1], [[1,2,1], 'target-a'], [[1,2,1,1], 8], [[1,2,1,1], 'target-a', 0]]:
            w = Worker(); w.update(10); w.context = context
            self.assertTrue(w.update(10)); self.assertEqual(w.orders, 2, context)
        for goal, stamp in [([], 10), ([1,2], 10), ('bad', 10), ([1,2,float('nan')], 10),
                            ([1,2,3], '10'), ([1,2,3], -1), ([1,2,3], float('inf')), ([1,2,3], 11)]:
            w = Worker(); w.update(10); w.goal = goal; w.stamp = stamp
            self.assertTrue(w.update(10)); self.assertEqual(w.orders, 2)
        w = Worker(); w.update(10); w.update(9); self.assertEqual(w.orders, 2)

    def test_target_switch_same_or_near_coordinates_and_reentry_are_immediate(self):
        for goal in [[100,100,15], [101,101,15]]:
            w = Worker(); w.update(10); w.target = 'replacement'
            w.update(10, goal); self.assertEqual(w.orders, 2)
            self.assertEqual(w.context[1], 'replacement')
        for mode in ['IDLE', 'SEARCHING', 'LOST_TARGET', 'TERMINAL_ATTACK', 'TERMINAL_VECTOR', 'SAFETY_HOLD', 'SAFETY_ABORT']:
            w = Worker(); w.update(10); w.mode = mode; w.reset(w.identity)
            self.assertEqual((w.goal, w.stamp), ([100,100,15], 10))
            w.mode = 'TRACKING'; w.update(10); self.assertEqual(w.orders, 2)

    def test_all_identity_components_force_first_order_and_fence_old_workers(self):
        for i in range(4):
            w = Worker(); w.update(10); old = list(w.identity); w.identity[i] += 1
            before = deepcopy(w.__dict__)
            self.assertFalse(w.update(10, original=old)); self.assertEqual(w.__dict__, before)
            w.update(10); self.assertEqual(w.orders, 2)

    def test_preempted_workers_read_current_cache_and_never_relabel_old_intent(self):
        w = Worker()
        self.assertTrue(w.update(10, pause=lambda w: w.update(10)))
        self.assertEqual(w.orders, 1)  # no cache read before the atomic boundary
        for change in [lambda w: setattr(w, 'identity', [1,2,1,2]),
                       lambda w: setattr(w, 'target', 'replacement'),
                       lambda w: setattr(w, 'mode', 'LOST_TARGET'),
                       lambda w: setattr(w, 'admitted', False)]:
            w = Worker(); w.update(10)
            before = (deepcopy(w.context), list(w.goal), w.stamp, w.orders, w.ai_passes)
            self.assertFalse(w.update(12, pause=change))
            self.assertEqual((w.context, w.goal, w.stamp, w.orders, w.ai_passes), before)

    def test_stale_reset_no_locality_and_empty_context_do_not_write(self):
        w = Worker(); w.update(10); old = list(w.identity)
        for index in range(4):
            stale = list(old); stale[index] += 1
            before = deepcopy(w.__dict__); w.reset(stale); self.assertEqual(w.__dict__, before)
        before = deepcopy(w.__dict__); w.reset(old, local=False); self.assertEqual(w.__dict__, before)
        w.reset(old); writes = w.writes; w.reset(old); self.assertEqual(w.writes, writes)

    def test_legacy_callers_lost_target_and_external_control(self):
        w = Worker(); self.assertTrue(w.update(10, explicit=False))
        w.mode = 'LOST_TARGET'; w.reset(w.identity)
        w.update(10.1, explicit=False); self.assertEqual(w.orders, 1)
        w.update(10.151, explicit=False); self.assertEqual(w.orders, 2)
        self.assertEqual(w.context, [])
        before = deepcopy(w.__dict__); w.admitted = False; before['admitted'] = False
        self.assertFalse(w.update(12, explicit=False)); self.assertEqual(w.__dict__, before)
        w.reset(w.identity); w.admitted = True; w.mode = 'TRACKING'; w.update(10.152)
        self.assertEqual(w.orders, 3)
        self.assertIn('[_uav, _predictedPosAsl, _profile] call A3UE_fnc_fpv_applyGuidance;', (FPV/'fn_fpv_runLostTarget.sqf').read_text())

    def test_source_effect_fences_and_transition_integration(self):
        boundary = GUIDANCE.index('private _applied = false;\nisNil {')
        effect = GUIDANCE[boundary:]
        for key in ['lastMoveTarget', 'lastMoveUpdate', 'trackingOrderContext']:
            self.assertNotIn('getVariable ["A3UE_FPV_' + key, GUIDANCE[:boundary])
            self.assertGreater(effect.index('getVariable ["A3UE_FPV_' + key), effect.index('call A3UE_fnc_fpv_canActuate'))
        self.assertLess(effect.index('isNotEqualTo _targetNetId'), effect.index('enableAI'))
        self.assertLess(effect.index('doMove'), effect.index('setVariable ["A3UE_FPV_lastMoveUpdate"'))
        self.assertLess(effect.index('if (!_cacheReady'),effect.index('_uav flyInHeight'))
        self.assertLess(effect.index('if (!_cacheReady'),effect.index('_uav forceSpeed'))
        self.assertNotRegex(effect, r'\b(sleep|spawn|remoteExec|diag_log|copyToClipboard)\b')
        self.assertNotRegex(GUIDANCE, r'findIf\s*\{[^}]*exitWith')
        self.assertIn('[_uav, _intercept, _profile, netId _target,_guidanceRevision] call A3UE_fnc_fpv_applyGuidance;', CONTROLLER)
        reset = CONTROLLER.split('private _clearTrackingOrderContext = {',1)[1].split('private _clearTerminalPoseContext',1)[0]
        for s in ['isNil {', 'local _uav', '== _generation', 'isEqualTo _controllerIdentity', 'isNotEqualTo []']:
            self.assertIn(s, reset)
        self.assertNotRegex(reset, r'\b(enableAI|forceSpeed|doMove|remoteExec)\b')
        self.assertIn('if (_mode != "TRACKING") then {call _clearTrackingOrderContext;};', CONTROLLER)
        self.assertIn('if (_activeMode != "TRACKING") then {call _clearTrackingOrderContext;};', CONTROLLER)
        suspension = CONTROLLER.split('if (_externalControl ||',1)[1].split('} else {',1)[0]
        self.assertLess(suspension.index('call _clearTrackingOrderContext'), suspension.index('call _restoreTerminalVectorControl'))
        self.assertIn('call _clearTrackingOrderContext;', CONTROLLER.split('_linkState == "EW_DENIED"',1)[1].split('} else {',1)[0])


if __name__ == '__main__':
    unittest.main()
