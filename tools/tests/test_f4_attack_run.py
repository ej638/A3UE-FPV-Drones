"""F4-1 attack run: committed dive speed, approach profiles, correction weave, pilot reaction,
outcome intents and the contact fuse.

Shipped SQF runs in SQF-VM through the commitment harness (f2_commitment_vm) and its explicit
engine substitutes. The closed-loop dives integrate the writer's own commanded velocity, i.e. a
perfect actuator on flat ground. This is geometry/decision evidence only: no Arma physics,
airframe response, rendering, scheduler or visual-quality claim (EJ's review decides that).
"""
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from f2_commitment_vm import VM, FPV, ROOT, script, engine_substitutes, adapt_helper

BASE = '84393b8'  # F2C-L field fixes, engine-tested 2026-11-08
CFG = ('class CfgVehicles {class AllVehicles {};class Man: AllVehicles {}; class LandVehicle: AllVehicles {};'
       'class Air: AllVehicles {};class VMMan: Man {};class VMVehicle: LandVehicle {};class VMUAV: Air {};};')
ATTACK = ['attackSettings', 'attackEngagement', 'attackApproach', 'attackPass', 'attackAimOffset',
          'attackNavigation', 'attackPassSummary']

PRE = r'''
missionNamespace setVariable ["A3UE_FPV_attackRun", true];
missionNamespace setVariable ["A3UE_FPV_QA_seed", 11];
FPV_getTerrainHeightASL = {0};
_uav setVariable ["A3UE_FPV_targetNetId", "person"];
_person setVariable ["position", [300,0,0]]; _person setVariable ["velocity", [0,0,0]];
_profile = createHashMapFromArray [["familyId","armafpv"],["roleId","AP"],["terminalVectorMaxSpeed",200]];
private _revision = _uav getVariable ["A3UE_FPV_targetRevision", 0];
private _setEngagement = {
  params ["_name", "_parameters", ["_stage", ""]];
  _uav setVariable ["A3UE_FPV_attackEngagement", [[+_identity, "person", _uav getVariable ["A3UE_FPV_targetRevision", 0]], _name, _parameters, _stage, 0, FPV_time]];
};
// Closed-loop terminal dive: the writer's commanded velocity is applied exactly.
private _sim = {
  params ["_seed", "_intent", "_start", "_dir", "_targetStart", "_targetVel", "_jukeRange", "_reaction", "_profileName", ["_steps", 500]];
  missionNamespace setVariable ["A3UE_FPV_QA_seed", _seed];
  missionNamespace setVariable ["A3UE_FPV_QA_forceIntent", _intent];
  missionNamespace setVariable ["A3UE_FPV_pilotReaction", _reaction];
  FPV_moves = []; FPV_poses = []; FPV_time = 10; FPV_observed = 20; FPV_frame = 100;
  {_uav setVariable [_x, []];} forEach ["A3UE_FPV_trajectory","A3UE_FPV_terminalSteeringState",
    "A3UE_FPV_terminalPoseContext","A3UE_FPV_terminalPoseAttitude","A3UE_FPV_nativeControl"];
  [_profileName, [55, 32]] call _setEngagement;
  _uav setVariable ["A3UE_FPV_attackPass", createHashMap];
  {_uav setVariable [_x, 0];} forEach ["A3UE_FPV_terminalSteeringSerial","A3UE_FPV_terminalPoseSerial"];
  _uav setVariable ["A3UE_FPV_trajectoryAttemptAt", -1];
  _uav setVariable ["A3UE_FPV_terminalVectorEnteredAt", FPV_time];
  private _tp = +_targetStart; private _tv = +_targetVel; private _juked = false;
  _person setVariable ["position", +_tp]; _person setVariable ["velocity", +_tv];
  _uav setVariable ["position", +_start]; _uav setVariable ["velocity", _dir vectorMultiply 25];
  private _p = +_start; private _v = _dir vectorMultiply 25;
  private _closest = 1e9; private _closestAt = []; private _maxSpeed = 0; private _end = "RUN"; private _maxDive = 0;
  private _ground = []; private _lateral = []; private _turns = 0; private _lastTurn = 0; private _prevDir = [];
  // Where the drone is pointing 20 m out: closest approach of its straight velocity line to the body point.
  private _lineMiss20 = -1;
  for "_i" from 0 to _steps do {
    if (_end != "RUN") exitWith {};
    FPV_time = FPV_time + 0.05; FPV_observed = FPV_observed + 0.05; FPV_frame = FPV_frame + 3;
    if (!_juked && {_jukeRange > 0} && {(_p vectorDistance (_tp vectorAdd [0,0,1.15])) < _jukeRange}) then {
      _juked = true; _tv = _tv vectorMultiply -1; _person setVariable ["velocity", +_tv];
    };
    [_uav,_person,_profile,1,_identity] call A3UE_fnc_fpv_prepareTrajectory;
    private _n = count FPV_moves;
    [[_uav,_person,_profile,1,_identity] call A3UE_fnc_fpv_runTerminalVector, "writer admitted"] call _assert;
    if (count FPV_moves > _n) then {_v = FPV_moves select (count FPV_moves - 1);};
    for "_k" from 1 to 5 do {
      private _pk = _p vectorAdd (_v vectorMultiply (0.01 * _k));
      private _tk = (_tp vectorAdd (_tv vectorMultiply (0.01 * _k))) vectorAdd [0,0,1.15];
      private _d = _pk vectorDistance _tk;
      if (_d < _closest) then {_closest = _d; _closestAt = _pk vectorDiff (_tk vectorAdd [0,0,-1.15]);};
    };
    if (_lineMiss20 < 0 && {(_p vectorDistance (_tp vectorAdd [0,0,1.15])) < 20} && {vectorMagnitude _v > 1}) then {
      private _r = (_tp vectorAdd [0,0,1.15]) vectorDiff _p; private _u = vectorNormalized _v;
      _lineMiss20 = vectorMagnitude (_r vectorDiff (_u vectorMultiply (_r vectorDotProduct _u)));
    };
    _p = _p vectorAdd (_v vectorMultiply 0.05); _tp = _tp vectorAdd (_tv vectorMultiply 0.05);
    _person setVariable ["position", +_tp];
    _uav setVariable ["position", +_p]; _uav setVariable ["velocity", +_v];
    _maxSpeed = _maxSpeed max (vectorMagnitude _v);
    private _h = sqrt (((_v # 0) ^ 2) + ((_v # 1) ^ 2));
    _maxDive = _maxDive max ((-(_v # 2)) atan2 _h);
    _lateral pushBack (_p # 1);
    // Heading changes of sign in the horizontal plane (weave corrections).
    private _flat = [_v # 0, _v # 1, 0];
    if (_prevDir isNotEqualTo [] && {vectorMagnitude _flat > 1}) then {
      private _cross = ((_prevDir # 0) * (_flat # 1)) - ((_prevDir # 1) * (_flat # 0));
      private _sign = if (_cross > 0.001) then {1} else {if (_cross < -0.001) then {-1} else {0}};
      if (_sign != 0 && {_sign != _lastTurn}) then {_turns = _turns + 1; _lastTurn = _sign;};
    };
    if (vectorMagnitude _flat > 1) then {_prevDir = vectorNormalized _flat;};
    if ((_p # 2) <= 0.3) then {_end = "GROUND"; _ground = _p vectorDiff _tp;};
    if (((_p vectorDiff _tp) vectorDotProduct _dir) > 30) then {_end = "PAST";};
  };
  private _pass = _uav getVariable ["A3UE_FPV_attackPass", createHashMap];
  [_closest, _maxSpeed, _maxDive, _end, _ground, (selectMax _lateral) - (selectMin _lateral), _turns,
   _pass getOrDefault ["intent", ""], _closestAt, _lineMiss20, _pass getOrDefault ["overStyle", ""]]
};
'''


def run(body, extra='', timeout=240):
    text = script(engine_substitutes(PRE + body), extra)
    with tempfile.TemporaryDirectory(prefix='fpv-f4-') as d:
        p = Path(d) / 'test.sqf'
        p.write_text(text)
        c = Path(d) / 'config.cpp'
        c.write_text(CFG)
        return subprocess.run([VM, '-a', '--suppress-welcome', '--no-execute-print', '--no-work-print',
                               '-m', '900000', '--input-config', str(c), '-i', str(p)],
                              capture_output=True, text=True, timeout=timeout)


def base_source(name):
    return subprocess.check_output(['git', 'show', f'{BASE}:addons/drones/functions/fpv/fn_fpv_{name}.sqf'],
                                   cwd=ROOT, text=True)


def load(names):
    return ''.join(f'A3UE_fnc_fpv_{n}={{{adapt_helper(n, (FPV / f"fn_fpv_{n}.sqf").read_text())}}};\n' for n in names)


def load_base(name, alias):
    return f'{alias}={{{adapt_helper(name, base_source(name))}}};\n'


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class F4AttackRunSQF(unittest.TestCase):
    def vm(self, body, extra=''):
        r = run(body, extra)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('COMMITMENT_TEST_OK', r.stdout, r.stdout[-4000:] + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout[-4000:])
        return r.stdout

    # ---- regression boundary -------------------------------------------------------
    def test_off_switch_is_identical_to_f2cl(self):
        extra = load(['shouldEnterTerminal', 'evaluateImpactWindow'])
        extra += load_base('trajectoryLimits', 'FPV_baseLimits')
        extra += load_base('prepareTrajectory', 'FPV_basePrepare')
        extra += load_base('runTerminalVector', 'FPV_baseWriter')
        extra += load_base('shouldEnterTerminal', 'FPV_baseEnter')
        extra += load_base('evaluateImpactWindow', 'FPV_baseEvaluate')
        self.vm(r'''
private _profiles = [createHashMap, createHashMapFromArray [["familyId","kvn"],["roleId","AT"]],
  createHashMapFromArray [["familyId","fpv_ua"],["trackingSpeed",100],["terminalVectorMaxSpeed",111]],
  createHashMapFromArray [["familyId","armafpv"],["roleId","AP"],["terminalVectorAccel",30],["terminalVectorMaxSpeed",173]]];
{
  missionNamespace setVariable ["A3UE_FPV_attackRun", false];
  [([_x] call A3UE_fnc_fpv_trajectoryLimits) isEqualTo ([_x] call FPV_baseLimits), "limits off"] call _assert;
  missionNamespace setVariable ["A3UE_FPV_attackRun", true];
  missionNamespace setVariable ["A3UE_FPV_attackSpeedScale", 0];
  [([_x] call A3UE_fnc_fpv_trajectoryLimits) isEqualTo ([_x] call FPV_baseLimits), "limits at scale 0"] call _assert;
  missionNamespace setVariable ["A3UE_FPV_attackSpeedScale", 1];
} forEach _profiles;
missionNamespace setVariable ["A3UE_FPV_attackRun", false];
// Writer A/B against the engine-tested F2C-L commit: commands, poses and logical state.
_uav setVariable ["A3UE_FPV_targetNetId", "target"];
_uav setVariable ["A3UE_FPV_terminalImpactMode","DIRECT_HULL"];
_uav setVariable ["A3UE_FPV_lastImpactValid",true];_uav setVariable ["A3UE_FPV_lastImpactTargetNetId","target"];
_uav setVariable ["A3UE_FPV_lastImpactSurfaceType","vehicle"];_uav setVariable ["A3UE_FPV_impactAnchorObject",_target];
_uav setVariable ["A3UE_FPV_lastImpactPointASL",[250,0,2.4]];
_uav setVariable ["position",[0,0,50]]; _uav setVariable ["velocity",[0,10,0]];
private _runWriter = {
  params ["_prepare", "_writer"];
  FPV_moves=[]; FPV_poses=[]; FPV_time=10; FPV_observed=20; FPV_frame=100;
  _uav setVariable ["A3UE_FPV_lastImpactTelemetryAt",FPV_time];
  {_uav setVariable [_x,[]];} forEach ["A3UE_FPV_trajectory","A3UE_FPV_terminalSteeringState",
    "A3UE_FPV_terminalPoseContext","A3UE_FPV_terminalPoseAttitude","A3UE_FPV_nativeControl"];
  {_uav setVariable [_x,0];} forEach ["A3UE_FPV_terminalSteeringSerial","A3UE_FPV_terminalPoseSerial"];
  _uav setVariable ["A3UE_FPV_trajectoryAttemptAt",-1];
  private _states=[];
  for "_i" from 0 to 15 do {
    FPV_time=FPV_time+0.06; FPV_observed=FPV_observed+0.06; FPV_frame=FPV_frame+3;
    _uav setVariable ["A3UE_FPV_lastImpactTelemetryAt",FPV_time];
    [_uav,_target,_profile,1,_identity] call _prepare;
    [[_uav,_target,_profile,1,_identity] call _writer,"writer admitted"] call _assert;
    _states pushBack +(_uav getVariable ["A3UE_FPV_terminalSteeringState",[]]);
  };
  [+FPV_moves,+FPV_poses,_states]
};
private _old=[FPV_basePrepare, FPV_baseWriter] call _runWriter;
private _new=[A3UE_fnc_fpv_prepareTrajectory, A3UE_fnc_fpv_runTerminalVector] call _runWriter;
[count (_old # 0) >= 12 && {(_old # 0) isEqualTo (_new # 0)}, "identical commanded velocity"] call _assert;
[(_old # 1) isEqualTo (_new # 1), "identical presented poses"] call _assert;
[(_old # 2) isEqualTo (_new # 2), "identical logical steering state"] call _assert;
// Entry gate and fuse decisions are the F2C-L ones when off.
_uav setVariable ["A3UE_FPV_targetNetId", "person"];
{
  _uav setVariable ["position", _x # 0]; _uav setVariable ["velocity", _x # 1];
  [([_uav,_person,_profile] call A3UE_fnc_fpv_shouldEnterTerminal) isEqualTo ([_uav,_person,_profile] call FPV_baseEnter), "entry off"] call _assert;
} forEach [[[0,100,10],[0,-20,0]], [[0,300,60],[0,20,0]], [[50,50,2],[3,0,-1]]];
_uav setVariable ["A3UE_FPV_lastImpactValid", true]; _uav setVariable ["A3UE_FPV_lastImpactTargetNetId", "person"];
_uav setVariable ["A3UE_FPV_terminalImpactMode", "DIRECT_BODY"]; _uav setVariable ["A3UE_FPV_impactAnchorObject", _person];
_uav setVariable ["A3UE_FPV_lastImpactPointASL", [300,0,1.15]];
{
  _uav setVariable ["position", _x # 0]; _uav setVariable ["velocity", _x # 1];
  private _keys = ["approved","detonationReason","fallbackReason","closingDot","timeToContact","impactDistance","impactMode"];
  private _new = [_uav,_person,_profile] call A3UE_fnc_fpv_evaluateImpactWindow;
  private _old = [_uav,_person,_profile] call FPV_baseEvaluate;
  [(_keys apply {_new get _x}) isEqualTo (_keys apply {_old get _x}), "fuse off"] call _assert;
} forEach [[[297,0,1.15],[30,0,0]], [[300.5,1.8,1.15],[30,0,0]], [[302,1,0.5],[10,0,-1]], [[310,0,6],[30,0,0]]];
''', extra)

    # ---- E3 envelope ---------------------------------------------------------------
    def test_attack_limits_table_and_scale(self):
        self.vm(r'''
private _l = {params ["_family", "_role", ["_extra", []]];
  [createHashMapFromArray ([["familyId",_family],["roleId",_role],["terminalVectorMaxSpeed",200]] + _extra)] call A3UE_fnc_fpv_trajectoryLimits};
private _near = {params ["_a","_b"]; abs (_a - _b) < 1e-4};
{
  _x params ["_family","_role","_cruise","_lateral","_descent","_turn","_accel"];
  private _limits = [_family,_role] call _l;
  [[_limits # 0, _cruise] call _near, format ["%1 %2 dive speed %3", _family, _role, _limits # 0]] call _assert;
  [[_limits # 3, _lateral] call _near && {[_limits # 4, _descent] call _near} && {[_limits # 5, _turn] call _near}, "agility"] call _assert;
  [[_limits # 1, _accel] call _near, "committed acceleration"] call _assert;
} forEach [["armafpv","AP",34,14,24,1,12],["armafpv","AT",32,14,24,1,12],["kvn","AP",30,11,21,0.85,9],
           ["kvn","AT",28,11,21,0.85,9],["fpv_ua","AP",28,12,19.6,0.9,10],["fpv_ua","RECON",28,12,19.6,0.9,10]];
// The dive may exceed the approach speed but never the airframe/doctrine terminal cap.
[[(["fpv_ua","AP",[["trackingSpeed",90]]] call _l) # 0, 28] call _near, "dive above approach"] call _assert;
private _capped = [createHashMapFromArray [["familyId","kvn"],["terminalVectorMaxSpeed",90]]] call A3UE_fnc_fpv_trajectoryLimits;
[[_capped # 0, 25] call _near, "doctrine cap kept"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackSpeedScale", 0.5];
[[(["fpv_ua","AP"] call _l) # 0, 24] call _near, "half scale interpolates"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackSpeedScale", 9];
[[(["fpv_ua","AP"] call _l) # 0, 32] call _near, "scale clamps at 1.5"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackSpeedScale", "fast"];
[[(["fpv_ua","AP"] call _l) # 0, 28] call _near, "invalid scale is 1"] call _assert;
''')

    # ---- approach profiles ---------------------------------------------------------
    def test_engagement_profiles_eligibility_determinism_and_weights(self):
        self.vm(r'''
private _sample = {
  params ["_seed", "_uavPos"];
  missionNamespace setVariable ["A3UE_FPV_QA_seed", _seed];
  _uav setVariable ["A3UE_FPV_attackEngagement", []];
  _uav setVariable ["position", _uavPos];
  [_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement
};
_person setVariable ["position", [0,0,0]];
private _first = [77, [0,400,40]] call _sample;
[(count _first == 6) && {(_first # 0) isEqualTo [_identity, "person", _revision]}, "record keyed by engagement"] call _assert;
[([_uav, _person, _identity, false] call A3UE_fnc_fpv_attackEngagement) isEqualTo _first, "reused, not resampled"] call _assert;
[([77, [0,400,40]] call _sample) isEqualTo _first, "QA seed reproduces"] call _assert;
private _counts = createHashMapFromArray [["DIRECT",0],["HIGH_DIVE",0],["FLANK",0]];
private _n = 0;
for "_s" from 0 to 4095 step 7 do {
  private _r = [_s, [0,400,40]] call _sample;
  _counts set [_r # 1, (_counts get (_r # 1)) + 1]; _n = _n + 1;
  if ((_r # 1) == "HIGH_DIVE") then {[((_r # 2 # 0) >= 40) && {(_r # 2 # 0) <= 65} && {(_r # 2 # 1) >= 28} && {(_r # 2 # 1) <= 36}, "dive parameters"] call _assert;};
  if ((_r # 1) == "FLANK") then {[((abs (_r # 2 # 0)) == 1) && {(_r # 2 # 1) >= 35} && {(_r # 2 # 1) <= 60} && {(_r # 2 # 2) == 220} && {(_r # 3) == "LEG"}, "flank parameters"] call _assert;};
};
diag_log ["PROFILE_FREQUENCIES", _n, _counts get "DIRECT", _counts get "HIGH_DIVE", _counts get "FLANK"];
[abs (((_counts get "DIRECT") / _n) - 0.4) < 0.06, "DIRECT about 40%"] call _assert;
[abs (((_counts get "HIGH_DIVE") / _n) - 0.3) < 0.06, "HIGH_DIVE about 30%"] call _assert;
[abs (((_counts get "FLANK") / _n) - 0.3) < 0.06, "FLANK about 30%"] call _assert;
// Too close for a flank or a climb: DIRECT only. A high drone may still dive steeply.
for "_s" from 0 to 4095 step 97 do {
  [(([_s, [0,150,5]] call _sample) # 1) == "DIRECT", "near low engagement is DIRECT"] call _assert;
  [(([_s, [0,120,40]] call _sample) # 1) in ["DIRECT","HIGH_DIVE"], "near high engagement never flanks"] call _assert;
};
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", "FLANK"];
[(([3, [0,400,40]] call _sample) # 1) == "FLANK", "QA force"] call _assert;
missionNamespace setVariable ["A3UE_FPV_QA_forceProfile", ""];
missionNamespace setVariable ["A3UE_FPV_attackProfiles", false];
[(([3, [0,400,40]] call _sample) # 1) == "DIRECT", "profiles off"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackProfiles", true];
_person setVariable ["kinds", ["Air","AllVehicles"]];
[(([3, [0,400,40]] call _sample) # 1) == "DIRECT", "air targets are DIRECT"] call _assert;
_person setVariable ["kinds", ["Man","AllVehicles"]];
// Only the current owner-local controller samples.
_uav setVariable ["A3UE_FPV_attackEngagement", []];
[([_uav, _person, [9,9,9,9], true] call A3UE_fnc_fpv_attackEngagement) isEqualTo [], "foreign identity refused"] call _assert;
_uav setVariable ["local", false];
[([_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement) isEqualTo [], "remote refused"] call _assert;
_uav setVariable ["local", true];
[(_uav getVariable ["A3UE_FPV_attackEngagement", []]) isEqualTo [], "nothing written"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackRun", false];
[([_uav, _person, _identity, true] call A3UE_fnc_fpv_attackEngagement) isEqualTo [], "off"] call _assert;
''')

    def test_approach_waypoints_and_entry_gates(self):
        self.vm(r'''
_person setVariable ["position", [0,0,0]];
// HIGH_DIVE holds a high approach.
["HIGH_DIVE", [55, 32]] call _setEngagement;
_uav setVariable ["position", [0,400,40]];
private _w = [_uav, _person, _identity, [3,10,12]] call A3UE_fnc_fpv_attackApproach;
[(_w # 0) == 3 && {(_w # 1) == 10} && {(_w # 2) == 55}, format ["high approach %1", _w]] call _assert;
// FLANK detours to the side bearing on its ring, then turns in once there.
["FLANK", [1, 45, 200], "LEG"] call _setEngagement;
_w = [_uav, _person, _identity, [0,10,12]] call A3UE_fnc_fpv_attackApproach;
[((_w vectorDiff [200 * sin 45, 200 * cos 45, 12]) call {vectorMagnitude _this}) < 0.01, format ["flank waypoint %1", _w]] call _assert;
_uav setVariable ["position", [180 * sin 40, 180 * cos 40, 30]];
_w = [_uav, _person, _identity, [0,10,12]] call A3UE_fnc_fpv_attackApproach;
[_w isEqualTo [0,10,12] && {((_uav getVariable "A3UE_FPV_attackEngagement") # 3) == "IN"}, "turn in at the side"] call _assert;
// Entry gates (object distance is 0 in the VM, so only the F4 gates decide here).
private _enter = {params ["_pos", "_vel"]; _uav setVariable ["position", _pos]; _uav setVariable ["velocity", _vel];
  [_uav, _person, _profile] call A3UE_fnc_fpv_shouldEnterTerminal};
["FLANK", [1, 45, 200], "LEG"] call _setEngagement;
[!([[0,200,10],[0,-20,0]] call _enter), "flank leg holds the dive"] call _assert;
[[[0,80,10],[0,-20,0]] call _enter, "a close target cuts the flank short"] call _assert;
["FLANK", [1, 45, 200], "IN"] call _setEngagement;
[[[0,200,10],[0,-20,0]] call _enter, "turned in: ordinary entry"] call _assert;
["HIGH_DIVE", [55, 32]] call _setEngagement;
private _threshold = (55 / (tan 32)) + 20;
[!([[0,_threshold + 5,55],[0,-20,0]] call _enter), "high: not yet"] call _assert;
[[[0,_threshold - 5,55],[0,-20,0]] call _enter, "high: steep, flyable dive"] call _assert;
[!([[0,120,10],[0,-20,0]] call _enter), "low: keep closing"] call _assert;
[[[0,100,10],[0,-20,0]] call _enter, "low: late dive"] call _assert;
["DIRECT", []] call _setEngagement;
[[[0,300,10],[0,-20,0]] call _enter, "DIRECT keeps the F2C-L budget"] call _assert;
// A drone that just flew past turns back under native tracking first.
_uav setVariable ["A3UE_FPV_attackLastMissAt", FPV_time - 2];
[!([[0,50,10],[0,20,0]] call _enter), "outbound after a miss"] call _assert;
[[[0,50,10],[0,-20,0]] call _enter, "facing the target again"] call _assert;
_uav setVariable ["A3UE_FPV_attackLastMissAt", FPV_time - 11];
[[[0,50,10],[0,20,0]] call _enter, "miss gate expires"] call _assert;
''', load(['shouldEnterTerminal']))

    # ---- pass plan -----------------------------------------------------------------
    def test_pass_intents_and_weights(self):
        self.vm(r'''
private _intentOf = {
  params ["_seed"];
  missionNamespace setVariable ["A3UE_FPV_QA_seed", _seed];
  _uav setVariable ["A3UE_FPV_attackPass", createHashMap];
  ([_uav, _person, _identity] call A3UE_fnc_fpv_attackPass) get "intent"
};
private _frequencies = {
  params ["_label"];
  private _counts = createHashMapFromArray [["DIRECT",0],["GROUND_SHORT",0],["GROUND_SIDE",0],["OVER",0]];
  private _n = 0;
  for "_s" from 0 to 4095 step 7 do {private _i = [_s] call _intentOf; _counts set [_i, (_counts get _i) + 1]; _n = _n + 1;};
  private _f = [(_counts get "DIRECT") / _n, ((_counts get "GROUND_SHORT") + (_counts get "GROUND_SIDE")) / _n, (_counts get "OVER") / _n,
    (_counts get "GROUND_SHORT") / _n];
  diag_log ["INTENT_FREQUENCIES", _label, _f];
  _f
};
["DIRECT", []] call _setEngagement;
private _check = {params ["_f","_d","_g","_o","_label"];
  [abs ((_f # 0) - _d) < 0.06 && {abs ((_f # 1) - _g) < 0.06} && {abs ((_f # 2) - _o) < 0.05}, format ["%1 weights %2", _label, _f]] call _assert;};
[["standing man"] call _frequencies, 0.75, 0.15, 0.10, "standing"] call _check;
private _f = ["standing man"] call _frequencies;
[abs ((_f # 3) - ((_f # 1) / 2)) < 0.05, "ground split short/side"] call _assert;
_person setVariable ["velocity", [3,0,0]];
[["moving man"] call _frequencies, 0.60, 0.25, 0.15, "moving"] call _check;
_person setVariable ["velocity", [0,0,0]];
// Vehicles never get an over-the-head pass.
_uav setVariable ["A3UE_FPV_targetNetId", "target"]; _target setVariable ["velocity", [12,0,0]];
private _intentVehicle = {params ["_seed"]; missionNamespace setVariable ["A3UE_FPV_QA_seed", _seed];
  _uav setVariable ["A3UE_FPV_attackPass", createHashMap]; ([_uav, _target, _identity] call A3UE_fnc_fpv_attackPass) get "intent"};
private _over = 0; private _ground = 0; private _n = 0;
for "_s" from 0 to 4095 step 7 do {private _i = [_s] call _intentVehicle; _n = _n + 1;
  if (_i == "OVER") then {_over = _over + 1;}; if (_i in ["GROUND_SHORT","GROUND_SIDE"]) then {_ground = _ground + 1;};};
[_over == 0 && {abs ((_ground / _n) - 0.40) < 0.06}, format ["fast vehicle %1 %2", _over, _ground / _n]] call _assert;
_uav setVariable ["A3UE_FPV_targetNetId", "person"];
// A steep dive cannot pass over the head: those passes go short instead.
["HIGH_DIVE", [55, 32]] call _setEngagement;
missionNamespace setVariable ["A3UE_FPV_QA_forceIntent", "OVER"];
[([1] call _intentOf) == "GROUND_SHORT", "steep OVER becomes GROUND_SHORT"] call _assert;
["DIRECT", []] call _setEngagement;
[([1] call _intentOf) == "OVER", "QA force"] call _assert;
missionNamespace setVariable ["A3UE_FPV_QA_forceIntent", ""];
missionNamespace setVariable ["A3UE_FPV_outcomeIntents", false];
for "_s" from 0 to 4095 step 301 do {[([_s] call _intentOf) == "DIRECT", "intents off"] call _assert;};
missionNamespace setVariable ["A3UE_FPV_outcomeIntents", true];
// Pass record: keyed, bounded, deterministic; refused for a foreign identity.
missionNamespace setVariable ["A3UE_FPV_QA_seed", 5];
_uav setVariable ["A3UE_FPV_attackPass", createHashMap];
private _p = [_uav, _person, _identity] call A3UE_fnc_fpv_attackPass;
[(_p get "key") isEqualTo [_identity, "person", _revision, _uav getVariable "A3UE_FPV_terminalVectorEnteredAt", 0], "pass key"] call _assert;
[count (_p get "segTimes") == 24 && {((_p get "segYaw") findIf {abs _x > 1 || {abs _x < 0.6}}) < 0}
  && {((_p get "segPitch") findIf {_x < -0.25 || {_x > 0.75}}) < 0}, "bounded program"] call _assert;
[(_p get "groundDist") >= 0.8 && {(_p get "groundDist") <= 2.5} && {(_p get "overLead") >= 1.5} && {(_p get "overLead") <= 3}
  && {((_p get "overStyle") == "TOP" && {(_p get "overClear") >= 0.55} && {(_p get "overClear") <= 0.95} && {(abs (_p get "overSide")) <= 0.4})
    || {(_p get "overStyle") == "SIDE" && {(_p get "overClear") >= 0.05} && {(_p get "overClear") <= 0.45} && {(abs (_p get "overSide")) >= 1.1} && {(abs (_p get "overSide")) <= 1.5}}},
  "bounded outcomes"] call _assert;
private _again = [_uav, _person, _identity] call A3UE_fnc_fpv_attackPass;
[(_again get "segYaw") isEqualTo (_p get "segYaw"), "pass reused within the pass"] call _assert;
_uav setVariable ["A3UE_FPV_attackPass", createHashMap];
[count ([_uav, _person, [9,9,9,9]] call A3UE_fnc_fpv_attackPass) == 0, "foreign identity refused"] call _assert;
[count (_uav getVariable ["A3UE_FPV_attackPass", createHashMap]) == 0, "nothing written"] call _assert;
''')

    def test_aim_offset_program_is_bounded_alternating_and_converging(self):
        self.vm(r'''
missionNamespace setVariable ["A3UE_FPV_QA_seed", 21];
_uav setVariable ["A3UE_FPV_attackPass", createHashMap];
private _p = [_uav, _person, _identity] call A3UE_fnc_fpv_attackPass;
private _eval = {params ["_elapsed", "_ttg", ["_scale", 1]];
  [_p get "segTimes", _p get "segYaw", _p get "segPitch", 0.35, _elapsed, _ttg, _scale, 0.35, 1.0] call A3UE_fnc_fpv_attackAimOffset};
private _prev = []; private _maxStep = 0; private _signs = 0; private _last = 0; private _maxFar = 0;
for "_i" from 0 to 800 do {
  private _t = _i * 0.01;
  private _ttg = 8 - _t;
  private _o = [_t, _ttg] call _eval;
  [abs (_o # 0) <= 8.0001 && {abs (_o # 1) <= 1.5001}, "bounded by 8 deg / 1.5 deg"] call _assert;
  if (_ttg <= 1) then {[abs (_o # 0) <= 3.0001, "3 deg inside the last second"] call _assert;};
  if (_ttg <= 0.35) then {[(_o # 2) == 0 && {(_o # 0) == 0} && {(_o # 1) == 0}, "converged"] call _assert;};
  if (_prev isNotEqualTo []) then {_maxStep = _maxStep max abs ((_o # 0) - (_prev # 0));};
  private _sign = if ((_o # 0) > 0.5) then {1} else {if ((_o # 0) < -0.5) then {-1} else {0}};
  if (_sign != 0 && {_sign != _last}) then {_signs = _signs + 1; _last = _sign;};
  if (_ttg > 5) then {_maxFar = _maxFar max abs (_o # 0);};
  _prev = _o;
};
diag_log ["AIM_PROGRAM", _maxStep, _signs, _maxFar];
[_maxStep < 0.7, format ["smooth: %1 deg per 10 ms", _maxStep]] call _assert;
[_signs >= 3, format ["corrections alternate: %1", _signs]] call _assert;
[_maxFar >= 3, "a visible aim error far out"] call _assert;
[(([2, 3, 0] call _eval) # 0) == 0, "weave scale 0 is no weave"] call _assert;
[([2, 3] call _eval) isEqualTo ([2, 3] call _eval), "pure"] call _assert;
[([[], [], [], 0.35, 1, 3, 1, 0.35, 1] call A3UE_fnc_fpv_attackAimOffset) isEqualTo [0,0,0], "empty program"] call _assert;
''')

    # ---- closed-loop dives ---------------------------------------------------------
    def test_closed_loop_dives_hit_weave_and_intended_misses(self):
        out = self.vm(r'''
private _results = [];
{
  private _r = [_x, "DIRECT", [0,0,10], [1,0,0], [300,0,0], [0,0,0], 0, true, "DIRECT"] call _sim;
  _results pushBack _r;
  [(_r # 0) <= 1.0, format ["direct hit seed %1: %2", _x, _r # 0]] call _assert;
  [(_r # 1) >= 33.5, format ["reaches the 34 m/s dive speed: %1", _r # 1]] call _assert;
  [(_r # 5) >= 2, format ["visible weave: %1 m", _r # 5]] call _assert;
  [(_r # 6) >= 2, format ["heading corrections: %1", _r # 6]] call _assert;
} forEach [11, 200, 3000, 777];
diag_log ["DIRECT", _results];
private _short = [11, "GROUND_SHORT", [0,0,10], [1,0,0], [300,0,0], [0,0,0], 0, true, "DIRECT"] call _sim;
private _side = [11, "GROUND_SIDE", [0,0,10], [1,0,0], [300,0,0], [0,0,0], 0, true, "DIRECT"] call _sim;
private _over = [11, "OVER", [0,0,10], [1,0,0], [300,0,0], [0,0,0], 0, true, "DIRECT"] call _sim;
diag_log ["INTENDED", _short, _side, _over];
{
  private _g = _x # 4;
  private _d = sqrt (((_g # 0) ^ 2) + ((_g # 1) ^ 2));
  [(_x # 3) == "GROUND" && {_d >= 0.5} && {_d <= 4.5}, format ["ground strike %1 m from the target", _d]] call _assert;
  [(_x # 0) > 1.0, "no body contact on a ground pass"] call _assert;
} forEach [_short, _side];
[(((_side # 4) # 1) call {abs _this}) >= 0.5, "side strike is to the side"] call _assert;
// Near miss (third engine pass, EJ: "OMG, it just missed me"). It stays on a hit-looking line
// until late: 20 m out the drone still points within 1.4 m of the body point (a direct hit,
// same seed, for comparison). Then it passes just over the head (TOP: 0.3-0.85 m above it) or
// just beside it (SIDE: 0.9-1.5 m to one side at head height), always outside the 1 m contact
// sphere around the body point and within 1.8 m of it. Both styles occur.
private _overRows = [];
private _styles = [];
{
  private _o = [_x, "OVER", [0,0,10], [1,0,0], [300,0,0], [0,0,0], 0, true, "DIRECT"] call _sim;
  private _d = [_x, "DIRECT", [0,0,10], [1,0,0], [300,0,0], [0,0,0], 0, true, "DIRECT"] call _sim;
  private _at = _o # 8; private _style = _o # 10;
  _styles pushBackUnique _style;
  _overRows pushBack [_x, _style, _o # 0, _at, _o # 9, _d # 9];
  [(_o # 0) > 1.05 && {(_o # 0) <= 1.8}, format ["near miss seed %1 (%2): %3 m from the body point at %4", _x, _style, _o # 0, _at]] call _assert;
  [(_o # 9) >= 0 && {(_o # 9) <= 1.4} && {(_d # 9) <= 0.8}, format ["on a hit-looking line 20 m out, seed %1: %2 (direct %3)", _x, _o # 9, _d # 9]] call _assert;
  if (_style == "TOP") then {
    [(_at # 2) >= 2.15 && {(_at # 2) <= 2.7} && {(abs (_at # 1)) <= 0.6}, format ["just over the head, seed %1: %2", _x, _at]] call _assert;
  } else {
    [_style == "SIDE" && {(abs (_at # 1)) >= 0.9} && {(abs (_at # 1)) <= 1.5} && {(_at # 2) >= 1.7} && {(_at # 2) <= 2.45},
      format ["just beside the head, seed %1: %2", _x, _at]] call _assert;
  };
} forEach [11, 200, 3000, 777, 5, 2047, 99, 1234, 4000, 640];
[("TOP" in _styles) && {"SIDE" in _styles}, format ["both styles occur %1", _styles]] call _assert;
// QA can force each style.
[(([200, "OVER_SIDE", [0,0,10], [1,0,0], [300,0,0], [0,0,0], 0, true, "DIRECT"] call _sim) # 10) == "SIDE"
  && {(([11, "OVER_TOP", [0,0,10], [1,0,0], [300,0,0], [0,0,0], 0, true, "DIRECT"] call _sim) # 10) == "TOP"}, "forced styles"] call _assert;
diag_log ["OVER_ROWS", _overRows];
// High dive: steep, fast and still a direct hit.
private _high = [5, "DIRECT", [300 - ((55 / (tan 32)) + 20), 0, 55], [1,0,0], [300,0,0], [0,0,0], 0, true, "HIGH_DIVE"] call _sim;
diag_log ["HIGH_DIVE", _high];
[(_high # 0) <= 1.0 && {(_high # 2) >= 25} && {(_high # 1) >= 30}, format ["steep high dive hit %1", _high]] call _assert;
''')
        self.assertIn('INTENDED', out)

    def test_dodges_are_earned_not_rolled(self):
        self.vm(r'''
private _seeds = [3, 40, 900, 2222];
{
  private _steady = [_x, "DIRECT", [0,0,10], [1,0,0], [300,-20,0], [0,5,0], 0, true, "DIRECT"] call _sim;
  [(_steady # 0) <= 1.0, format ["a steady runner is hit: %1", _steady # 0]] call _assert;
  private _late = [_x, "DIRECT", [0,0,10], [1,0,0], [300,-20,0], [0,5,0], 20, true, "DIRECT"] call _sim;
  [(_late # 0) > 1.5, format ["a late reversal escapes: %1", _late # 0]] call _assert;
  private _early = [_x, "DIRECT", [0,0,10], [1,0,0], [300,-20,0], [0,5,0], 70, true, "DIRECT"] call _sim;
  [(_early # 0) <= 1.0, format ["an early reversal is caught: %1", _early # 0]] call _assert;
} forEach _seeds;
// Reaction lag widens the window: at 45 m, lag on misses at least as often as perfect tracking.
private _missOn = 0; private _missOff = 0;
{
  if ((([_x, "DIRECT", [0,0,10], [1,0,0], [300,-20,0], [0,5,0], 45, true, "DIRECT"] call _sim) # 0) > 1) then {_missOn = _missOn + 1;};
  if ((([_x, "DIRECT", [0,0,10], [1,0,0], [300,-20,0], [0,5,0], 45, false, "DIRECT"] call _sim) # 0) > 1) then {_missOff = _missOff + 1;};
} forEach [3, 40, 900, 2222, 77, 1500];
diag_log ["DODGE_45M", _missOn, _missOff];
[_missOn >= _missOff && {_missOn >= 2}, format ["reaction lag matters: %1 vs %2", _missOn, _missOff]] call _assert;
''')

    # ---- fuse and delivery ---------------------------------------------------------
    def test_contact_fuse_rules(self):
        self.vm(r'''
_person setVariable ["position", [0,0,0]];
_uav setVariable ["A3UE_FPV_lastImpactValid", true]; _uav setVariable ["A3UE_FPV_lastImpactTargetNetId", "person"];
_uav setVariable ["A3UE_FPV_terminalImpactMode", "DIRECT_BODY"]; _uav setVariable ["A3UE_FPV_impactAnchorObject", _person];
_uav setVariable ["A3UE_FPV_lastImpactPointASL", [0,0,1.15]];
private _fuse = {params ["_pos", "_vel"]; _uav setVariable ["position", _pos]; _uav setVariable ["velocity", _vel];
  private _e = [_uav, _person, _profile] call A3UE_fnc_fpv_evaluateImpactWindow;
  [_e get "approved", _e get "detonationReason", _e get "fallbackReason"]};
[([[-3,0,1.15],[30,0,0]] call _fuse) isEqualTo [true, "PREDICTED_IMPACT", "NONE"], "swept contact"] call _assert;
[([[-0.5,0,1.15],[30,0,0]] call _fuse) isEqualTo [true, "DIRECT_CONTACT", "NONE"], "contact"] call _assert;
[!(([[-3,1.8,1.15],[30,0,0]] call _fuse) # 0), "a 1.8 m lateral pass does not fire"] call _assert;
[!(([[0.5,1.8,1.15],[30,0,0]] call _fuse) # 0), "no overshoot rescue"] call _assert;
[!(([[2,0,4],[30,0,0]] call _fuse) # 0), "no airburst over the head"] call _assert;
[([[2,1,0.5],[10,0,-1]] call _fuse) isEqualTo [true, "GROUND_CONTACT", "NONE"], "ground contact near the target"] call _assert;
[([[3,0,1.5],[-5,0,-15]] call _fuse) isEqualTo [true, "GROUND_CONTACT", "NONE"], "ground contact swept"] call _assert;
[!(([[20,0,0.5],[10,0,-1]] call _fuse) # 0), "no ground fuse beyond 15 m"] call _assert;
// F2C-L rules when the contact fuse is off: the overshoot fallback still fires.
missionNamespace setVariable ["A3UE_FPV_fuseContactOnly", false];
[([[0.5,1.8,1.15],[30,0,0]] call _fuse) isEqualTo [true, "MISSED_PASS_FALLBACK", "OVERSHOOT_IMMINENT"], "F2C-L overshoot fallback"] call _assert;
missionNamespace setVariable ["A3UE_FPV_fuseContactOnly", true];
// Cover and air policy are unchanged.
_uav setVariable ["A3UE_FPV_terminalImpactMode", "OBSTRUCTION_SURFACE"]; _uav setVariable ["A3UE_FPV_lastImpactPointASL", [-2,0,1]];
_uav setVariable ["A3UE_FPV_impactAnchorObject", objNull];
[([[-8,0,1.2],[30,0,0]] call _fuse) isEqualTo [true, "OBSTRUCTION_FALLBACK", "TARGET_DUCKED_BEHIND_OBSTRUCTION"], "cover"] call _assert;
_uav setVariable ["A3UE_FPV_terminalImpactMode", "AIR_PROXIMITY"]; _uav setVariable ["A3UE_FPV_lastImpactPointASL", [0,0,30]];
[([[5,0,1],[30,0,0]] call _fuse) isEqualTo [true, "PROXIMITY_FAILSAFE", "AIR_TARGET_PROXIMITY_POLICY"], "air policy"] call _assert;
''', load(['evaluateImpactWindow']))

    def test_ground_contact_delivery_and_pass_summary(self):
        self.vm(r'''
FPV_lastSend = [];
A3UE_fnc_fpv_sendLifecycle = {FPV_lastSend = +_this; true};
missionNamespace setVariable ["A3UE_FPV_QA_seed", 9];
_person setVariable ["position", [0,0,0]];
_uav setVariable ["position", [2,1,1.5]]; _uav setVariable ["velocity", [10,0,-15]];
_uav setVariable ["A3UE_FPV_attackPass", createHashMap];
[_uav, _person, _identity] call A3UE_fnc_fpv_attackPass;
[[_uav, _person, "GROUND_CONTACT", "NONE", _revision] call A3UE_fnc_fpv_detonateCompat, "proposal sent"] call _assert;
private _strike = FPV_lastSend # 2 # 0;
private _delivery = _strike get "deliveryPosASL";
diag_log ["GROUND_STRIKE", _delivery, _strike get "attackPass"];
[abs ((_delivery # 2) - 0.2) < 0.01 && {abs ((_delivery # 0) - (2 + 10 * 1.3 / 15)) < 0.01}, "touch-down point below the drone"] call _assert;
[(_strike get "deliveryMode") == "GROUND_POINT" && {(_strike get "strikePathClass") == "GROUND_CONTACT"}
  && {(_strike get "approvalPolicyClass") == "SURFACE_PRIMARY"} && {_strike get "deliveryPolicyMatch"}, "classified"] call _assert;
private _summary = _strike get "attackPass";
[(_summary find "profile=") == 0 && {(_summary find "intent=") > 0} && {count _summary <= 128} && {count _strike <= 32}, "bounded summary"] call _assert;
// A summary only for this exact target revision.
_uav setVariable ["A3UE_FPV_targetRevision", _revision + 1];
[([_uav, _person] call A3UE_fnc_fpv_attackPassSummary) == "", "stale pass not reported"] call _assert;
''')

    def test_navigation_wrapper_fences_and_memo(self):
        self.vm(r'''
_uav setVariable ["position", [0,0,10]]; _uav setVariable ["velocity", [30,0,0]];
_uav setVariable ["A3UE_FPV_attackPass", createHashMap];
private _nav = [_uav, _person, _identity] call A3UE_fnc_fpv_targetNavigation;
[count _nav == 6, "navigation"] call _assert;
private _wrapped = [_uav, _person, _identity, _nav] call A3UE_fnc_fpv_attackNavigation;
[(_wrapped # 0) isEqualTo (_nav # 0) && {(_wrapped # 1) isEqualTo (_nav # 1)} && {(_wrapped # 2) isEqualTo (_nav # 2)}
  && {(_wrapped # 5) isEqualTo (_nav # 5)}, "key, clocks and true reference unchanged"] call _assert;
// Memo: one evaluation per instant even if the world moves within the tick.
_person setVariable ["position", [300,5,0]];
private _again = [_uav, _person, _identity, _nav] call A3UE_fnc_fpv_attackNavigation;
[_again isEqualTo _wrapped, "same instant, same answer"] call _assert;
_uav setVariable ["A3UE_FPV_mode", "TRACKING"];
[([_uav, _person, _identity, _nav] call A3UE_fnc_fpv_attackNavigation) isEqualTo _nav, "native phases untouched"] call _assert;
_uav setVariable ["A3UE_FPV_mode", "TERMINAL_VECTOR"];
_person setVariable ["kinds", ["Air","AllVehicles"]];
[([_uav, _person, _identity, _nav] call A3UE_fnc_fpv_attackNavigation) isEqualTo _nav, "air targets untouched"] call _assert;
_person setVariable ["kinds", ["Man","AllVehicles"]];
_uav setVariable ["A3UE_FPV_attackPass", createHashMap];
[([_uav, _person, [9,9,9,9], _nav] call A3UE_fnc_fpv_attackNavigation) isEqualTo _nav, "foreign identity untouched"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackRun", false];
[([_uav, _person, _identity, _nav] call A3UE_fnc_fpv_attackNavigation) isEqualTo _nav, "off"] call _assert;
[([_uav, _person, _identity, []] call A3UE_fnc_fpv_attackNavigation) isEqualTo [], "empty stays empty"] call _assert;
''')


class F4AttackRunSource(unittest.TestCase):
    def src(self, name):
        return (FPV / f'fn_fpv_{name}.sqf').read_text()

    def code(self, name):
        return '\n'.join(line.split('//', 1)[0] for line in self.src(name).splitlines())

    def test_functions_registered_and_present(self):
        config = (ROOT / 'addons/drones/config.cpp').read_text()
        for name in ATTACK:
            self.assertIn(f'class fpv_{name} {{}};', config)
            self.assertTrue((FPV / f'fn_fpv_{name}.sqf').is_file(), name)

    def test_no_workers_broadcasts_or_per_frame_random(self):
        for name in ATTACK:
            s = self.code(name)
            self.assertNotRegex(s, r'\b(remoteExec|remoteExecCall|spawn|sleep|publicVariable|hint|hintSilent|addMissionEventHandler)\b', name)
            self.assertNotRegex(s, r'setVariable \[[^\]]*,\s*true\]', name)
            self.assertNotRegex(s, r'\b(nearestObjects|allUnits|entities|lineIntersectsSurfaces)\b', name)
        for name in ['attackSettings', 'attackApproach', 'attackAimOffset', 'attackNavigation', 'attackPassSummary']:
            self.assertNotIn('random', self.code(name), name)
        for name in ['attackEngagement', 'attackPass']:
            # One global draw per drone lifetime (the salt), everything else from the LCG.
            self.assertEqual(self.code(name).count('random'), 1, name)
            self.assertIn('_salt = floor (random 4096);', self.code(name))
            self.assertIn('((1597 * _rng) + 51) mod 4096', self.code(name))
        self.assertIn('((1597 * (_pass get "rng")) + 51) mod 4096', self.code('attackNavigation'))

    def test_controller_wiring_and_writer_contracts(self):
        c = self.code('runController')
        tracking = c.split('case "TRACKING": {', 1)[1].split('case "LOST_TARGET": {', 1)[0]
        self.assertLess(tracking.index('fpv_attackEngagement'), tracking.index('fpv_shouldEnterTerminal'))
        self.assertLess(tracking.index('fpv_computeIntercept'), tracking.index('fpv_attackApproach'))
        self.assertLess(tracking.index('fpv_attackApproach'), tracking.index('fpv_applyGuidance'))
        missed = c.split('if (_missedPass) then {', 1)[1].split('call _storeTargetMemory;', 1)[0]
        for term in ['fpv_attackPassSummary', 'call _loseTarget', '== "LOST_TARGET"', 'A3UE_FPV_attackLastMissAt',
                     'outcome=MISSED', 'diag_log format']:
            self.assertIn(term, missed)
        self.assertLess(missed.index('call _loseTarget'), missed.index('A3UE_FPV_attackLastMissAt'))
        prepare = self.code('prepareTrajectory')
        self.assertLess(prepare.index('fpv_targetNavigation'), prepare.index('fpv_attackNavigation'))
        self.assertNotRegex(prepare, r'\b(spawn|sleep|nearestObjects|allUnits|remoteExec|diag_log|random)\b')
        writer = self.code('runTerminalVector')
        self.assertEqual(writer.count('fpv_attackNavigation'), 2)
        self.assertEqual(writer.count('setVelocity _desiredVelocity'), 1)
        self.assertEqual(writer.count('setVectorDirAndUp'), 1)

    def test_fuse_commit_and_delivery_contracts(self):
        fuse = self.code('evaluateImpactWindow')
        self.assertIn('call A3UE_fnc_fpv_attackSettings', fuse)
        self.assertIn('_attackSettings # 6', fuse)
        self.assertIn('!_isAirPolicyMode', fuse)
        self.assertIn('"GROUND_CONTACT"', fuse)
        self.assertIn('(_uavPosAsl distance2D _targetPosAsl) <= 15', fuse)
        contact = fuse.split('if (_contactOnly) then {', 1)[1].split('} else {\n', 1)[0]
        for removed in ['MISSED_PASS_FALLBACK', 'PROXIMITY_FAILSAFE', 'CLOSURE_QUALIFIED']:
            self.assertNotIn(removed, contact)
        commit = self.code('commitDetonation')
        self.assertIn('"PROXIMITY_FAILSAFE", "GROUND_CONTACT"]', commit)
        self.assertIn('[A3UE_FPV] attackPass id=%1 target=%2 outcome=%3 %4', commit)
        self.assertLess(commit.index('triggerAmmo _missile;'), commit.index('attackPass id='))
        self.assertLess(commit.index('_strike deleteAt "attackPass";'), commit.index('_recent pushBack _strike;'))
        compat = self.code('detonateCompat')
        self.assertIn('_deliveryMode = "GROUND_POINT";', compat)
        self.assertIn('min 0.25', compat)

    def test_off_path_preserves_f2cl_text(self):
        limits = self.src('trajectoryLimits')
        base = base_source('trajectoryLimits')
        returned = base.split('// cruise, acceleration', 1)[1].strip()
        self.assertIn(returned.replace('\r\n', '\n'), limits.replace('\r\n', '\n'))
        self.assertIn('"A3UE_FPV_attackRun"', limits)
        self.assertIn('"A3UE_FPV_attackSpeedScale"', limits)
        enter = self.src('shouldEnterTerminal')
        self.assertIn('exitWith {_inRange};', enter)

    def test_rpt_lines_are_info_level(self):
        for name, line in [('runController', 'attackPass id=%1 target=%2 outcome=MISSED'),
                           ('commitDetonation', 'attackPass id=%1 target=%2 outcome=%3')]:
            s = self.code(name)
            self.assertIn(line, s)
            self.assertNotRegex(s, r'\bhint(Silent|C)?\b')


if __name__ == '__main__':
    unittest.main()
