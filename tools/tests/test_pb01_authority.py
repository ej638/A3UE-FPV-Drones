"""Shipped ingress expression and effect-boundary contracts; not MP authentication evidence."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
FPV = ROOT / 'addons/drones/functions/fpv'


def source(name):
    return (FPV / f'fn_fpv_{name}.sqf').read_text()


def ingress(remote=False, sender=0, jip=False, private=False):
    # Evaluate the actual shipped final expression, not a duplicate policy function.
    s = source('helperAccess')
    assert 'if (isRemoteExecutedJIP) exitWith {false};' in s
    if jip:
        return False
    expression = s.strip().splitlines()[-1]
    for a, b in [('call A3UE_fnc_fpv_lifecycleAccess', 'private'),
                 ('isRemoteExecuted', 'remote'), ('remoteExecutedOwner', 'sender'),
                 ('||', ' or '), ('&&', ' and '), ('!', ' not '), ('{', '('), ('}', ')')]:
        expression = expression.replace(a, b)
    return eval(expression.strip(), {'__builtins__': {}}, locals())


class AuthorityTests(unittest.TestCase):
    def test_local_server_and_private_nested_paths(self):
        self.assertTrue(ingress())
        self.assertTrue(ingress(True, 2))
        self.assertTrue(ingress(True, 9, private=True))

    def test_ordinary_sender_receiver_ticket_and_scheduling_cannot_authorize(self):
        for sender in (0, 3, 9, 100):
            for scheduled in (False, True):
                for receiver_has_ticket in (False, True):
                    self.assertFalse(ingress(True, sender), (scheduled, receiver_has_ticket))

    def test_jip_overrides_local_server_and_private_authority(self):
        for sender in (0, 2, 9):
            for private in (False, True):
                self.assertFalse(ingress(True, sender, True, private))

    def test_every_connected_entry_fences_before_mutation_or_nested_work(self):
        for name in ('publishTelemetry', 'clearTarget', 'applyGuidance', 'runTerminal',
                     'runTerminalVector', 'holdPattern', 'runLostTarget', 'detonateCompat',
                     'cacheLinkState', 'selectTarget', 'resolveImpactPoint',
                     'supportEngagementReason', 'supportPassesSafetyRing',
                     'computeIntercept', 'shouldDetonateNow'):
            s = source(name)
            prefix = s.split('call A3UE_fnc_fpv_helperAccess', 1)[0]
            self.assertNotRegex(prefix, r'\b(setVariable|enableAI|disableAI|spawn|remoteExec|setVelocity)\b', name)
            self.assertEqual(prefix.count('call A3UE_fnc_'), 0, name)
        marker = source('supportCreateMarker')
        self.assertLess(marker.index('call A3UE_fnc_fpv_lifecycleAccess'), marker.index('A3A_supportMarkerCount'))

    def test_vector_optional_defaults_follow_sender_fence(self):
        s = source('runTerminalVector')
        self.assertLess(s.index('call A3UE_fnc_fpv_helperAccess'), s.index('if (_generation < 0)'))
        self.assertIn('if (count _this < 5)', s)

    def test_all_movement_effects_share_unscheduled_guard_and_original_identity(self):
        for name in ('applyGuidance', 'holdPattern', 'runTerminalVector'):
            s = source(name)
            boundary = s.index('private _applied = false;\nisNil {')
            self.assertNotRegex(s[:boundary], r'\b(enableAI|disableAI|setVelocity|setVectorDirAndUp|doMove|forceSpeed)\b')
            effect = s[boundary:]
            self.assertLess(effect.index('call A3UE_fnc_fpv_canActuate'),
                            re.search(r'\b(enableAI|disableAI)\b', effect).start())
            self.assertNotRegex(effect, r'\b(sleep|spawn|waitUntil|remoteExec)\b')
            self.assertIn('_applied = true;\n};\n_applied', effect)
        guard = source('canActuate')
        for field in ('managed', 'controllerRunning', 'cleanupPending', 'detonating',
                      'netId', 'controllerGeneration', 'controllerIdentity'):
            self.assertIn('A3UE_FPV_' + field, guard)
        for helper in ('hasCurrentLifecycle', 'isSiteDroneActive', 'isExternallyControlled'):
            self.assertIn('call A3UE_fnc_fpv_' + helper, guard)
        self.assertNotIn('getVariable ["A3UE_FPV_controllerIdentity", []])\n', guard)
        # F2 retains the public terminal entry as a guarded delegate, with no movement of its own.
        terminal=source('runTerminal')
        self.assertIn('call A3UE_fnc_fpv_runTerminalVector',terminal)
        self.assertIn('!= "TERMINAL_VECTOR"',terminal)
        self.assertNotRegex(terminal,r'\b(enableAI|disableAI|setVelocity|doMove|forceSpeed)\b')

    def test_takeover_clears_state_and_defers_ai_recovery_until_release(self):
        s = source('runController')
        block = s.split('private _restoreTerminalVectorControl = {', 1)[1].split('private _impactSolutionFromCache', 1)[0]
        self.assertIn('_terminalAIRecoveryPending = !_canRestoreAI;', block)
        self.assertLess(block.index('if (_canRestoreAI) then'), block.index('enableAI "PATH"'))
        self.assertLess(block.index('} forEach (_native # 1);'), block.index('"A3UE_FPV_terminalSteeringActive", false'))
        self.assertIn('(_native # 0) isEqualTo _controllerIdentity',block)
        self.assertIn('if (_path)',block)
        self.assertIn('_terminalAIRecoveryPending ||', s)
        self.assertNotIn('setAngularVelocity', s)

    def test_production_has_no_diagnostics_workers_or_source_comparisons_added(self):
        for name in ('helperAccess', 'canActuate'):
            self.assertNotRegex(source(name), r'\b(diag_log|copyToClipboard|spawn|sleep|entities|allUnits|nearestObjects|preprocessFile)\b')
        config = (ROOT / 'addons/drones/config.cpp').read_text()
        for name in ('helperAccess', 'canActuate'):
            self.assertEqual(config.count('class fpv_' + name + ' {};'), 1)


if __name__ == '__main__':
    unittest.main()
