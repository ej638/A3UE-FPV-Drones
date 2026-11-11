"""LT-1 load-tolerant dive (2026-11-10 dedicated hover). Shipped SQF in SQF-VM via the
commitment harness plus source contracts. No scheduler, physics or engine timing claim:
these pin the writer's decisions for given clocks, not how late Arma actually runs."""
import re
import unittest
from pathlib import Path

from f2_commitment_vm import VM, FPV, execute

CONTROLLER = (FPV / 'fn_fpv_runController.sqf').read_text()


def isnil_block(source, anchor):
    """The isNil { ... } block that follows anchor, braces matched."""
    start = source.index('isNil {', source.index(anchor))
    depth = 0
    for i in range(start + len('isNil '), len(source)):
        if source[i] == '{':
            depth += 1
        elif source[i] == '}':
            depth -= 1
            if depth == 0:
                return source[start:i + 1]
    raise AssertionError('unbalanced isNil block after ' + anchor)


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class LoadTolerantWriterSQF(unittest.TestCase):
    def sqf(self, body):
        r = execute(body)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('COMMITMENT_TEST_OK', r.stdout, r.stdout + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout)
        return r.stdout

    ENTRY_THEN_LATE = '''
[[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"entry"] call _assert;
[FPV_moves isEqualTo [] && {(_uav getVariable ["A3UE_FPV_nativeControl",[]]) isEqualTo []},"entry is zero dt, native AI still flying"] call _assert;
FPV_time=FPV_time+0.4;FPV_observed=FPV_observed+0.4;FPV_frame=FPV_frame+10;
[[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"late pass applied"] call _assert;
'''

    def test_late_pass_after_entry_writes_and_takes_the_airframe(self):
        # The dedicated failure: entry, then the next controller pass 0.4 s late.
        self.sqf(self.ENTRY_THEN_LATE + '''
[count FPV_moves==1,"a late pass still writes the dive"] call _assert;
[(_uav getVariable ["A3UE_FPV_nativeControl",[]]) isNotEqualTo [],"and takes the airframe from the native AI"] call _assert;
[((_uav getVariable ["A3UE_FPV_terminalSteeringState",[]]) # 8)=="STALL","never-driven state re-seeds (STALL)"] call _assert;
[(_uav getVariable ["A3UE_FPV_terminalVectorDt",-1])==0.25,"integrates the 0.25 s cap, not the 0.4 s gap"] call _assert;
''')

    def test_switch_off_reproduces_the_rc_no_write(self):
        self.sqf('missionNamespace setVariable ["A3UE_FPV_loadTolerantDive",false];\n' + self.ENTRY_THEN_LATE + '''
[FPV_moves isEqualTo [],"legacy GAP: no velocity write"] call _assert;
[(_uav getVariable ["A3UE_FPV_nativeControl",[]]) isEqualTo [],"legacy GAP: native AI keeps the airframe (hover)"] call _assert;
''')

    def test_late_continues_bounded_and_stalled_simulation_still_resets(self):
        self.sqf('''
private _speed={vectorMagnitude _this};
[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector;
FPV_time=FPV_time+0.02;FPV_observed=FPV_observed+0.02;FPV_frame=FPV_frame+1;
[[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"step"] call _assert;
[count FPV_moves==1,"on-time step writes"] call _assert;
private _serial=_uav getVariable ["A3UE_FPV_terminalSteeringSerial",0];
FPV_time=FPV_time+0.4;FPV_observed=FPV_observed+0.4;FPV_frame=FPV_frame+10;
[[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"late"] call _assert;
[count FPV_moves==2,"late step writes"] call _assert;
[(_uav getVariable ["A3UE_FPV_terminalSteeringSerial",0])==_serial,"LATE continues the logical state (no re-seed)"] call _assert;
private _jump=((FPV_moves # 1) call _speed)-((FPV_moves # 0) call _speed);
[_jump <= (_limits # 1)*0.25+0.001 && {_jump >= -(_limits # 2)*0.25-0.001},format ["speed change bounded by the 0.25 s cap: %1",_jump]] call _assert;
FPV_time=FPV_time+0.4;FPV_observed=FPV_observed+1.4;FPV_frame=FPV_frame+10;
[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector;
[count FPV_moves==2,"simulation stalled behind real time: still a reset, no write"] call _assert;
[(_uav getVariable ["A3UE_FPV_terminalSteeringSerial",0])==_serial+1,"that reset re-seeds"] call _assert;
FPV_time=FPV_time+1.5;FPV_observed=FPV_observed+1.5;FPV_frame=FPV_frame+40;
[[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector,"long gap"] call _assert;
[count FPV_moves==3 && {((_uav getVariable ["A3UE_FPV_terminalSteeringState",[]]) # 8)=="STALL"},"a >1 s gap re-seeds and still writes"] call _assert;
''')

    def test_step_stats_reach_the_attack_pass_line(self):
        self.sqf('''
missionNamespace setVariable ["A3UE_FPV_attackRun",true];
[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector;
FPV_time=FPV_time+0.02;FPV_observed=FPV_observed+0.02;FPV_frame=FPV_frame+1;
[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector;
FPV_time=FPV_time+0.4;FPV_observed=FPV_observed+0.4;FPV_frame=FPV_frame+10;
[_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector;
private _pass=_uav getVariable ["A3UE_FPV_attackPass",createHashMap];
private _steps=if ("steps" in _pass) then {_pass get "steps"} else {[]};
[_steps isEqualTo [2,1,1,0,400],str _steps] call _assert;
private _summary=[_uav,_target] call A3UE_fnc_fpv_attackPassSummary;
[(_summary find " step=2/1/1/0/400") > 0 && {count _summary <= 140},_summary] call _assert;
''')


class LoadTolerantSourceContracts(unittest.TestCase):
    def test_dive_pass_plans_steps_and_records_progress_in_one_slice(self):
        block = isnil_block(CONTROLLER, '// LT-1: plan, step and progress share one unscheduled slice')
        for term in ['call A3UE_fnc_fpv_prepareTrajectory', 'call A3UE_fnc_fpv_runTerminalVector',
                     'A3UE_FPV_lastTerminalVectorDistance', 'isEqualTo (_planning # 2)']:
            self.assertIn(term, block)

    def test_ingress_plans_and_enters_in_one_slice(self):
        ingress = CONTROLLER.split('private _attemptIngress = {', 1)[1].split('private _restoreInvalidNavigation', 1)[0]
        block = isnil_block(ingress, '// LT-1: plan and enter in one unscheduled slice')
        self.assertIn('call A3UE_fnc_fpv_prepareTrajectory', block)
        self.assertIn('call A3UE_fnc_fpv_runTerminalVector', block)
        self.assertEqual(ingress.count('call A3UE_fnc_fpv_prepareTrajectory'), 1)

    def test_slice_helpers_never_suspend(self):
        for name in ['prepareTrajectory', 'runTerminalVector', 'planTrajectory', 'followTrajectory',
                     'trajectorySteering', 'stepTerminalSteering', 'terminalSteeringStatus', 'targetNavigation',
                     'attackNavigation', 'attackLimits', 'trajectoryLimits', 'attackPass', 'attackPassSummary']:
            source = re.sub(r'//[^\n]*', '', (FPV / f'fn_fpv_{name}.sqf').read_text())
            self.assertNotRegex(source, r'\b(sleep|uiSleep|waitUntil|spawn|execVM)\b', name)

    def test_refused_passes_are_counted_and_lines_keep_their_prefixes(self):
        refused = CONTROLLER.split('// LT-1 attackPass diagnostics: a dive pass refused', 1)[1].split('_restoreInvalidNavigation;', 1)[0]
        self.assertIn('_stats set [3, (_stats # 3) + 1];', refused)
        summary = (FPV / 'fn_fpv_attackPassSummary.sqf').read_text()
        self.assertIn('lifts=%8 step=%9', summary)
        self.assertIn('_steps joinString "/"', summary)


if __name__ == '__main__':
    unittest.main()
