"""Actual shipped pure SQF helpers in SQF-VM; no emulated Arma physics claim.

Set FPV_SQFVM to the official interpreter executable. Its unimplemented finite
primitive has a test-only scalar shim; shipped numeric equations are unchanged.
"""
import os
from pathlib import Path
import subprocess
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FPV = ROOT / 'addons/drones/functions/fpv'
VM = os.environ.get('FPV_SQFVM')


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class ActualSQFTrajectory(unittest.TestCase):
    def sqf(self, body):
        helpers = ['profileValue', 'trajectoryLimits', 'planTrajectory', 'followTrajectory',
                   'stepTerminalSteering', 'terminalSteeringStatus']
        script = 'private _fpvFinite = {_this isEqualType 0 && {abs _this < 1e38}};\n'
        for name in helpers:
            source = (FPV / f'fn_fpv_{name}.sqf').read_text()
            source = re.sub(r'\bfinite (_[A-Za-z0-9]+)', r'(\1 call _fpvFinite)', source)
            script += 'A3UE_fnc_fpv_' + name + ' = {\n' + source + '\n};\n'
        script += '''
private _assert = {params ["_value","_name"]; if (!_value) then {throw _name;};};
private _limits = [24,8,10,10,12,0.8,3,0.6,3,2];
''' + body + '\ndiag_log "F2_TEST_OK";\n'
        with tempfile.TemporaryDirectory(prefix='fpv-f2-') as d:
            source = Path(d)/'actual.sqf'; source.write_text(script)
            run = subprocess.run([VM, '-a', '--suppress-welcome', '--no-execute-print',
                                  '--no-work-print', '-m', '15000', '-i', str(source)],
                                 capture_output=True, text=True, timeout=20)
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertIn('F2_TEST_OK', run.stdout, run.stdout+run.stderr)
        self.assertNotIn('[ERR]', run.stdout, run.stdout)
        return run.stdout

    def test_static_and_offset_corridors_end_on_surface(self):
        self.sqf('''
{ private _surface = _x;
  private _p = [[0,0,50],[1,0,0],10,_surface,[0,0,0],_limits] call A3UE_fnc_fpv_planTrajectory;
  [_p # 0,"admitted"] call _assert;
  [count (_p # 1) == 9 && {count (_p # 2) == 9},"bounded"] call _assert;
  [((_p # 1 # 8) vectorDistance _surface) < 0.001,"exact surface"] call _assert;
  [((_p # 1 # 0) vectorDistance [0,0,50]) < 0.001,"actual entry"] call _assert;
  [(selectMin (_p # 2)) >= 4 && {(selectMax (_p # 2)) <= 24},"speed envelope"] call _assert;
} forEach [[250,0,1.2],[250,60,1.2],[200,-80,20]];
''')

    def test_lead_bounded_and_tends_to_contact(self):
        self.sqf('''
{ _x params ["_range","_velocity"];
  private _p = [[0,0,10],[1,0,0],20,[_range,0,10],_velocity,_limits] call A3UE_fnc_fpv_planTrajectory;
  [_p # 0,"moving admitted"] call _assert;
  [(_p # 5) <= 1.5 && {(_p # 5) <= _range / 20 + 0.001},"lead time"] call _assert;
  [((_p # 4) vectorDistance [_range,0,10]) <= 25.001,"lead displacement"] call _assert;
} forEach [[200,[0,5,0]],[50,[0,20,0]],[5,[0,1,0]],[1,[0,0.1,0]]];
''')

    def test_infeasible_heading_height_cusp_and_invalid_numbers(self):
        self.sqf('''
{private _p = _x call A3UE_fnc_fpv_planTrajectory; [!(_p # 0),"must reject"] call _assert;} forEach [
 [[0,0,50],[-1,0,0],10,[100,0,0],[0,0,0],_limits],
 [[0,0,50],[0,0,-1],30,[0,0,0],[0,0,0],_limits],
 [[0,0,1],[1,0,0],20,[2,5,1],[0,0,0],_limits],
 [[0,0,1],[0,0,0],0,[50,0,1],[0,0,0],_limits],
 [[0,0,1],[1,0,0],-1,[50,0,1],[0,0,0],_limits]
];
private _vertical = [[0,0,50],[0,0,-1],5,[0,0,0],[0,0,0],_limits] call A3UE_fnc_fpv_planTrajectory;
[_vertical # 0,"deterministic vertical"] call _assert;
''')

    def test_analytic_curvature_caps_bound_dense_curve_samples(self):
        self.sqf('''
private _pos = [0,0,50]; private _end = [180,50,2]; private _dir = vectorNormalized [1,0.2,0];
private _p = [_pos,_dir,8,_end,[0,0,0],_limits] call A3UE_fnc_fpv_planTrajectory;
[_p # 0,"curve admitted"] call _assert;
private _control = _pos vectorAdd (_dir vectorMultiply ((_pos vectorDistance _end) * 0.5));
private _d0 = (_control vectorDiff _pos) vectorMultiply 2;
private _d1 = (_end vectorDiff _control) vectorMultiply 2;
private _dd = _d1 vectorDiff _d0;
for "_j" from 0 to 800 do {
 private _t = _j / 800; private _i = (floor (_t * 8)) min 7;
 private _d = _d0 vectorAdd (_dd vectorMultiply _t);
 private _k = vectorMagnitude (_d vectorCrossProduct _dd) / ((vectorMagnitude _d) ^ 3);
 private _cap = (_p # 2 # _i) min (_p # 2 # (_i + 1));
 [_cap * _cap * _k <= 10.001,"lateral"] call _assert;
 [_cap * _k <= 0.8001,"turn"] call _assert;
 [_cap * abs ((vectorNormalized _d) # 2) <= 12.001,"descent"] call _assert;
};
''')

    def test_native_seed_zero_time_and_persistent_bounded_handoff(self):
        self.sqf('''
private _d = vectorNormalized [1,0.1,-0.1]; private _u = [0,0,1];
private _s = [_d,_u,9,[0,0,0],[1,0,-0.3],24,8,10,0.18,0.35,0,0.8,3] call A3UE_fnc_fpv_stepTerminalSteering;
[(_s # 2) == 9 && {(_s # 0) vectorDistance _d < 0.001},"zero-dt handoff"] call _assert;
{private _dt = _x; private _old = +_s;
 _s = [_s # 0,_s # 1,_s # 2,_s # 3,[1,0,-0.3],24,8,10,0.18,0.35,_dt,0.4,3] call A3UE_fnc_fpv_stepTerminalSteering;
 [count _s == 6,"finite step"] call _assert;
 [abs ((_s # 2)-(_old # 2)) <= 10 * _dt + 0.001,"speed continuity"] call _assert;
 [vectorMagnitude (_s # 3) <= 0.4001,"rate"] call _assert;
 [(_s # 3) vectorDistance (_old # 3) <= 3 * _dt + 0.001,"rate slew"] call _assert;
} forEach [0.02,0.03,0,0.08,0.12,0.2];
''')

    def test_actual_followers_static_moving_offset_receding_paths(self):
        self.sqf('''
{_x params ["_target","_tv"];
 private _pos = [0,0,50]; private _d=[1,0,0]; private _u=[0,0,1]; private _speed=9; private _rate=[0,0,0];
 private _elapsed=0; private _nextPlan=0; private _plan=[]; private _min=1e6;
 for "_i" from 0 to 1400 do {
  private _dt = [0.02,0.03,0.05,0.04] # (_i mod 4);
  private _range = _pos vectorDistance _target;
  _min = _min min _range;
  if (_range < 3) exitWith {};
  if (_elapsed >= _nextPlan) then {
   _plan=[_pos,_d,_speed,_target,_tv,_limits] call A3UE_fnc_fpv_planTrajectory;
   [_plan # 0,format ["replan rejected at %1: %2",_range,_plan # 7]] call _assert;
   _nextPlan=_elapsed+0.2;
  };
  private _f=[_plan,_pos,_speed,_limits] call A3UE_fnc_fpv_followTrajectory;
  [count _f == 5,"follow"] call _assert;
  private _rateMagnitude=vectorMagnitude _rate;
  private _targetSpeed=(_f # 1) min (10 / (_rateMagnitude max 0.0001));
  private _ceiling=_speed max (_speed+((_targetSpeed-_speed) max (-10*_dt) min (8*_dt)));
  private _limit=(0.8 min (10/(_ceiling max 1))) max _rateMagnitude;
  private _s=[_d,_u,_speed,_rate,_f # 0,_targetSpeed,8,10,0.18,0.35,_dt,_limit,3] call A3UE_fnc_fpv_stepTerminalSteering;
  [count _s == 6,"integration"] call _assert;
  _d=_s # 0; _u=_s # 1; _speed=_s # 2; _rate=_s # 3;
  [_speed * vectorMagnitude _rate <= 10.01,"coupled lateral envelope"] call _assert;
  [abs ((_d # 2)*_speed) <= 12.1,"command descent"] call _assert;
  _pos=_pos vectorAdd (_d vectorMultiply (_speed*_dt));
  _target=_target vectorAdd (_tv vectorMultiply _dt); _elapsed=_elapsed+_dt;
 };
 [_min < 3,format ["did not converge: %1",_min]] call _assert;
} forEach [[[250,0,1.2],[0,0,0]],[[250,60,1.2],[0,3,0]],[[250,-40,1.2],[2,-1,0]]];
''')

    def test_actual_clock_identity_target_site_and_control_resets(self):
        self.sqf('''
private _key = [[1,2,3,4],"object","id","TERMINAL_VECTOR",["epoch","site","east"],1,["DIRECT_HULL","surface","vehicle"],"support","event"];
private _s = [_key,10,20,[1,0,0],[0,0,1],9,[0,0,0],1,"INIT",0,[1,0,0],[9,0,0]];
// LT-1: a late step is capped at 0.25 s (never the missed time); STALL re-seeds a never-driven
// state, LATE continues a driven one up to 1 s; a stalled simulation or the switch-off is a GAP.
private _driven = +_s; _driven set [9, 0.02];
{_x params ["_state","_sim","_obs","_expected"];
 private _result=[_state,_key,_sim,_obs] call A3UE_fnc_fpv_terminalSteeringStatus;
 [(_result # 0) == _expected,format ["clock status %1 %2 %3", _sim, _obs, _result]] call _assert;
 switch (_expected) do {
  case "STEP": {};
  case "LATE"; case "STALL": {[(_result # 1) == 0.25,"capped late step, no catchup"] call _assert;};
  default {[(_result # 1) == 0,"no catchup"] call _assert;};
 };
} forEach [[_s,10,20,"DUPLICATE"],[_s,10.02,20.02,"STEP"],[_s,10.3,20.3,"STALL"],[_s,10.1,20.6,"PAUSE"],[_s,9,20,"TIME_REVERSE"],
  [_driven,10.3,20.3,"LATE"],[_driven,11,21,"LATE"],[_driven,11.01,21.01,"STALL"],[_driven,10.6,21.2,"GAP"]];
[(([_driven,_key,10.3,20.3,false] call A3UE_fnc_fpv_terminalSteeringStatus) isEqualTo ["GAP",0]),"switch off = legacy GAP"] call _assert;
[((([_driven,_key,10.3,20.3,"garbage"] call A3UE_fnc_fpv_terminalSteeringStatus) # 0) == "LATE"),"only an explicit false switches off"] call _assert;
[((([_driven,_key,10.2,20.2,false] call A3UE_fnc_fpv_terminalSteeringStatus) # 0) == "STEP"),"switch never touches on-time steps"] call _assert;
{private _changed=+_key; _changed set [_x,"replacement"];
 [(([_s,_changed,10.02,20.02] call A3UE_fnc_fpv_terminalSteeringStatus) # 0) == "KEY","identity/intent reset"] call _assert;
} forEach [0,1,2,3,4,5,6,7,8];
private _release=[[],_key,15,25] call A3UE_fnc_fpv_terminalSteeringStatus;
[_release isEqualTo ["INIT",0],"cleared control release"] call _assert;
''')

    def test_actual_opposite_vertical_and_zero_speed_fallbacks(self):
        self.sqf('''
{_x params ["_dir","_up","_aim"];
 private _s=[_dir,_up,0,[0,0,0],_aim,10,8,10,0.18,0.35,0.1,0.7,3] call A3UE_fnc_fpv_stepTerminalSteering;
 [count _s == 6,"fallback finite"] call _assert;
 [abs (vectorMagnitude (_s # 0)-1)<0.001 && {abs ((_s # 0) vectorDotProduct (_s # 1))<0.001},"orthogonal"] call _assert;
 [(_s # 2)<=0.801,"no entry kick"] call _assert;
} forEach [[[1,0,0],[0,0,1],[-1,0,0]],[[0,0,1],[0,1,0],[0,0,-1]]];
''')


class F2SourceBoundaries(unittest.TestCase):
    def test_single_writer_no_overlay_and_owned_native_settings(self):
        s=(FPV/'fn_fpv_runTerminalVector.sqf').read_text()
        for removed in ['terminalVerticalGain','terminalDescentMinRate','flyInHeight','doMove','enableAI "ALL"']:
            self.assertNotIn(removed,s)
        self.assertEqual(s.count('setVelocity _desiredVelocity'),1)
        self.assertIn('getForcedSpeed _uav',s)
        self.assertIn('checkAIFeature "PATH"',s)
        self.assertIn('_poseFrame - (_poseContext # 5) >= 3 && {_poseNow - (_poseContext # 4) >= 0.05}',s)
        controller=(FPV/'fn_fpv_runController.sqf').read_text()
        self.assertNotIn('call A3UE_fnc_fpv_runTerminal;',controller)
        self.assertIn('_uav forceSpeed (_native # 2)',controller)
        self.assertIn('if (_path) then',controller)

    def test_fresh_plan_compare_and_swap_and_full_authority(self):
        s=(FPV/'fn_fpv_prepareTrajectory.sqf').read_text()
        for term in ['helperAccess','canActuate','hasCurrentLifecycle','isEqualTo _before',
                     'isEqualTo _steering','fpv_targetNavigation','call _keyNow','EW_DENIED',
                     'objectFromNetId','fpv_resolveTarget']:
            self.assertIn(term,s)
        self.assertNotRegex(s,r'\b(spawn|sleep|nearestObjects|allUnits|remoteExec|diag_log|random)\b')
        s=(FPV/'fn_fpv_runTerminalVector.sqf').read_text()
        for term in ['isEqualTo _trajectoryBefore','isEqualTo _steeringBefore','isEqualTo _steeringKey',
                     'time - (_trajectoryBefore # 1) > 0.25','isExternallyControlled']:
            self.assertIn(term,s)
        controller=(FPV/'fn_fpv_runController.sqf').read_text()
        self.assertNotIn('_abortTrajectory',controller)
        nav=(FPV/'fn_fpv_targetNavigation.sqf').read_text()
        for term in ['siteEpoch','siteMarker','siteSide','supportName','rivalEventId','targetRevision']:
            self.assertIn(term,nav)
        progress=controller.split('// Progress belongs only to that exact plan',1)[1].split('if (_qa)',1)[0]
        for term in ['isNil {','canActuate','isEqualTo (_planning # 2)','== _enteredAt','EW_DENIED']:
            self.assertIn(term,progress)
        ingress=controller.split('private _attemptIngress = {',1)[1].split('while {',1)[0]
        self.assertIn('call A3UE_fnc_fpv_runTerminalVector',ingress)
        self.assertIn('call A3UE_fnc_fpv_targetNavigation',ingress)

    def test_fixed_cost_and_no_dwell_or_lifetime_extension(self):
        s=(FPV/'fn_fpv_prepareTrajectory.sqf').read_text()
        self.assertIn('_at - _lastAttempt < 0.2',s)
        for query in ['lineIntersectsSurfaces','terrainIntersectASL','getTerrainHeightASL']:
            self.assertNotIn(query,s)
        self.assertIn('for "_i" from 0 to 8',(FPV/'fn_fpv_planTrajectory.sqf').read_text())
        c=(FPV/'fn_fpv_runController.sqf').read_text()
        self.assertNotIn('_deadline = time + 3',c)
        self.assertNotIn('setVariable ["A3UE_FPV_ingressDeadline"',c)
        for field in ['payloadSpent','lifetime','expiresAt']:
            self.assertNotIn('setVariable ["A3UE_FPV_'+field,c)


if __name__ == '__main__':
    unittest.main()
