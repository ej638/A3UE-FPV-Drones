"""F4-2: missed-pass flip ("flip back") and tree/obstacle awareness.

Shipped SQF runs in SQF-VM through the commitment harness (f2_commitment_vm) and its explicit
engine substitutes. Obstacles are axis-aligned boxes over flat ground behind a substituted
lineIntersectsSurfaces. The closed-loop runs integrate the writer's commanded velocity (a perfect
actuator) and reproduce the controller's TERMINAL_VECTOR call order: navigation, missed-pass
rule, flip state, planning, writer. Native AI flight (flyInHeight) is recorded, not flown.
This is geometry/decision evidence only: no Arma physics, AI flight, airframe response,
rendering, scheduler or visual-quality claim (EJ's review decides that).
"""
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from f2_commitment_vm import VM, FPV, ROOT, script, engine_substitutes, adapt_helper

CFG = ('class CfgVehicles {class AllVehicles {};class Man: AllVehicles {}; class LandVehicle: AllVehicles {};'
       'class Air: AllVehicles {};class VMMan: Man {};class VMVehicle: LandVehicle {};class VMUAV: Air {};};')
NEW = ['attackReversal', 'attackLimits', 'obstacleProbe', 'transitHeight', 'attackClearLine', 'logDroneLoss']

PRE = r'''
missionNamespace setVariable ["A3UE_FPV_attackRun", true];
missionNamespace setVariable ["A3UE_FPV_QA_seed", 11];
FPV_getTerrainHeightASL = {0};
_uav setVariable ["A3UE_FPV_targetNetId", "person"];
_person setVariable ["position", [300,0,0]]; _person setVariable ["velocity", [0,0,0]];
_profile = createHashMapFromArray [["familyId","armafpv"],["roleId","AP"],["terminalVectorMaxSpeed",200]];
private _revision = _uav getVariable ["A3UE_FPV_targetRevision", 0];
// Obstacle world: boxes [[min xyz],[max xyz],object] and flat ground at z = 0. Sorted hits.
FPV_boxes = [];
FPV_tree = "VMVehicle" createVehicle [0,0,0]; FPV_tree setVariable ["kinds", []]; FPV_tree setVariable ["netId", "tree"];
FPV_truck = "VMVehicle" createVehicle [0,0,0]; FPV_truck setVariable ["netId", "truck"];
FPV_lineIntersectsSurfaces = {
  params ["_from", "_to", ["_i1", objNull], ["_i2", objNull], ["_sorted", true], ["_max", 1]];
  FPV_queries = FPV_queries + 1;
  private _d = _to vectorDiff _from;
  private _hits = [];
  {
    _x params ["_lo", "_hi", "_object"];
    private _t0 = 0; private _t1 = 1; private _ok = true;
    for "_k" from 0 to 2 do {
      private _dk = _d # _k; private _fk = _from # _k;
      if (abs _dk < 1e-9) then {
        if (_fk < (_lo # _k) || {_fk > (_hi # _k)}) then {_ok = false;};
      } else {
        private _a = ((_lo # _k) - _fk) / _dk; private _b = ((_hi # _k) - _fk) / _dk;
        _t0 = _t0 max (_a min _b); _t1 = _t1 min (_a max _b);
      };
    };
    if (_ok && {_t0 <= _t1} && {!(_object isEqualTo _i1)} && {!(_object isEqualTo _i2)}) then {
      _hits pushBack [_t0, [_from vectorAdd (_d vectorMultiply _t0), [0,0,1], _object, objNull]];
    };
  } forEach FPV_boxes;
  if ((_to # 2) < 0 && {(_from # 2) >= 0}) then {
    private _t = (_from # 2) / ((_from # 2) - (_to # 2));
    _hits pushBack [_t, [_from vectorAdd (_d vectorMultiply _t), [0,0,1], objNull, objNull]];
  };
  _hits sort true;
  (_hits apply {_x # 1}) select [0, _max]
};
FPV_inBox = {
  params ["_p"];
  (FPV_boxes findIf {
    private _lo = _x # 0; private _hi = _x # 1;
    (_p # 0) >= (_lo # 0) && {(_p # 0) <= (_hi # 0)} && {(_p # 1) >= (_lo # 1)} && {(_p # 1) <= (_hi # 1)}
      && {(_p # 2) >= (_lo # 2)} && {(_p # 2) <= (_hi # 2)}
  }) >= 0
};
private _setEngagement = {
  params ["_name", "_parameters", ["_stage", ""]];
  _uav setVariable ["A3UE_FPV_attackEngagement", [[+_identity, "person", _uav getVariable ["A3UE_FPV_targetRevision", 0]], _name, _parameters, _stage, 0, FPV_time]];
};
private _angle = {params ["_a", "_b"]; acos ((((vectorNormalized _a) vectorDotProduct (vectorNormalized _b)) max -1) min 1)};
// Closed-loop terminal run in the controller's TERMINAL_VECTOR order, perfect actuator.
private _run = {
  params ["_seed", "_intent", "_start", "_dir", ["_profileName", "DIRECT"], ["_steps", 420], ["_keepBudget", false],
    ["_targetVel", [0,0,0]], ["_speed", 25], ["_jukeRange", 0]];
  missionNamespace setVariable ["A3UE_FPV_QA_seed", _seed];
  missionNamespace setVariable ["A3UE_FPV_QA_forceIntent", _intent];
  FPV_moves = []; FPV_poses = []; FPV_time = 10; FPV_observed = 20; FPV_frame = 100;
  {_uav setVariable [_x, []];} forEach ["A3UE_FPV_trajectory","A3UE_FPV_terminalSteeringState",
    "A3UE_FPV_terminalPoseContext","A3UE_FPV_terminalPoseAttitude","A3UE_FPV_nativeControl"];
  [_profileName, [55, 32]] call _setEngagement;
  _uav setVariable ["A3UE_FPV_attackPass", createHashMap];
  _uav setVariable ["A3UE_FPV_attackReversal", createHashMap];
  if (!_keepBudget) then {_uav setVariable ["A3UE_FPV_attackReversalUsed", false];};
  {_uav setVariable [_x, 0];} forEach ["A3UE_FPV_terminalSteeringSerial","A3UE_FPV_terminalPoseSerial"];
  _uav setVariable ["A3UE_FPV_trajectoryAttemptAt", -1];
  _uav setVariable ["A3UE_FPV_mode", "TERMINAL_VECTOR"];
  _uav setVariable ["A3UE_FPV_terminalVectorEnteredAt", FPV_time];
  _uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", -1];
  private _enteredAt = FPV_time;
  private _tp = [300,0,0]; private _tv = +_targetVel;
  _person setVariable ["position", +_tp]; _person setVariable ["velocity", +_tv];
  private _p = +_start; private _v = _dir vectorMultiply _speed;
  _uav setVariable ["position", +_p]; _uav setVariable ["velocity", +_v];
  private _m = createHashMapFromArray [["end","RUN"],["closest",1e9],["events",[]],["logs",[]],["maxSpeed",0],
    ["flipMinZ",1e9],["flipMinSpeed",1e9],["flipMaxZ",-1e9],["maxPast",-1e9],
    ["minBoxClearance",1e9],["startedAt",-1],["redivedAt",-1],["endAt",-1],["startZ",0],["path",[]],["maxUpRate",0],["maxDirRate",0]];
  private _lastPose = []; private _lastPoseAt = -1; private _juked = false;
  for "_i" from 0 to _steps do {
    if ((_m get "end") != "RUN") exitWith {};
    FPV_time = FPV_time + 0.05; FPV_observed = FPV_observed + 0.05; FPV_frame = FPV_frame + 3;
    // Optional late dodge on the return pass: the target reverses its run.
    if (!_juked && {_jukeRange > 0} && {(_m get "redivedAt") > 0} && {(_p vectorDistance (_tp vectorAdd [0,0,1.15])) < _jukeRange}) then {
      _juked = true; _tv = _tv vectorMultiply -1; _person setVariable ["velocity", +_tv];
    };
    private _nav = [_uav,_person,_identity] call A3UE_fnc_fpv_targetNavigation;
    private _current = _p vectorDistance (_nav # 5);
    private _last = _uav getVariable ["A3UE_FPV_lastTerminalVectorDistance", _current];
    if (_last < 0) then {_last = _current;};
    private _missed = FPV_time > (_enteredAt + 0.15) && {_current > (_last + 8)};
    private _flip = ["OFF", ""];
    isNil {_flip = [_uav,_person,_identity,_nav,_last,_enteredAt] call A3UE_fnc_fpv_attackReversal;};
    switch (_flip # 0) do {
      case "STARTED": {_missed = false; (_m get "events") pushBack ["STARTED", FPV_time, _flip # 1]; _m set ["startedAt", FPV_time]; _m set ["startZ", _p # 2];};
      case "PULL": {_missed = false;};
      case "OVER": {_missed = false; if (((_m get "events") findIf {(_x # 0) == "OVER"}) < 0) then {(_m get "events") pushBack ["OVER", FPV_time];};};
      case "REDIVE": {_missed = false; _last = _current; _uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", -1];
        (_m get "events") pushBack ["REDIVE", FPV_time, _flip # 1]; _m set ["redivedAt", FPV_time];};
      case "ABORT": {_missed = true; (_m get "events") pushBack ["ABORT", FPV_time, _flip # 1];};
    };
    if (_missed) then {
      _m set ["end", "MISSED"]; _m set ["endAt", FPV_time]; _m set ["missWhy", _flip];
      _m set ["summary", [_uav, _person] call A3UE_fnc_fpv_attackPassSummary];
    } else {
      [_uav,_person,_profile,_identity # 3,_identity] call A3UE_fnc_fpv_prepareTrajectory;
      private _n = count FPV_moves; private _np = count FPV_poses;
      [[_uav,_person,_profile,_identity # 3,_identity] call A3UE_fnc_fpv_runTerminalVector, "writer admitted"] call _assert;
      if (count FPV_moves > _n) then {_v = FPV_moves select (count FPV_moves - 1);};
      if (count FPV_poses > _np) then {
        // Presented attitude rates between actual pose writes (deg/s).
        private _b = FPV_poses select (count FPV_poses - 1);
        if (_lastPose isNotEqualTo []) then {
          private _dtp = (FPV_time - _lastPoseAt) max 0.01;
          _m set ["maxUpRate", (_m get "maxUpRate") max (([_lastPose # 1, _b # 1] call _angle) / _dtp)];
          _m set ["maxDirRate", (_m get "maxDirRate") max (([_lastPose # 0, _b # 0] call _angle) / _dtp)];
        };
        _lastPose = _b; _lastPoseAt = FPV_time;
      };
      _uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", _last min _current];
      for "_k" from 1 to 5 do {
        if ((_m get "end") == "RUN") then {
          private _pk = _p vectorAdd (_v vectorMultiply (0.01 * _k));
          private _tk = (_tp vectorAdd (_tv vectorMultiply (0.01 * _k))) vectorAdd [0,0,1.15];
          private _d = _pk vectorDistance _tk;
          if (_d < (_m get "closest")) then {_m set ["closest", _d];};
          // True closest approach of the first pass (10 ms steps), until the flip starts.
          if ((_m get "startedAt") < 0) then {_m set ["firstClosest", (_m getOrDefault ["firstClosest", 1e9]) min _d];};
          if (_d <= 1.0) then {_m set ["end", "HIT"]; _m set ["endAt", FPV_time];};
          if ((_pk # 2) <= 0.3) then {_m set ["end", "GROUND"]; _m set ["endAt", FPV_time]; _m set ["ground", _pk vectorDiff _tp];};
          if ([_pk] call FPV_inBox) then {_m set ["end", "COLLISION"]; _m set ["endAt", FPV_time]; _m set ["collisionAt", +_pk];};
        };
      };
      _p = _p vectorAdd (_v vectorMultiply 0.05); _tp = _tp vectorAdd (_tv vectorMultiply 0.05);
      _person setVariable ["position", +_tp];
      _uav setVariable ["position", +_p]; _uav setVariable ["velocity", +_v];
      _m set ["maxSpeed", (_m get "maxSpeed") max (vectorMagnitude _v)];
      (_m get "path") pushBack +_p;
      {
        private _lo = _x # 0; private _hi = _x # 1;
        if ((_p # 0) >= (_lo # 0) && {(_p # 0) <= (_hi # 0)} && {(_p # 1) >= (_lo # 1)} && {(_p # 1) <= (_hi # 1)}) then {
          _m set ["minBoxClearance", (_m get "minBoxClearance") min ((_p # 2) - (_hi # 2))];
        };
      } forEach FPV_boxes;
      private _phase = (_uav getVariable ["A3UE_FPV_attackReversal", createHashMap]) getOrDefault ["phase", ""];
      if (_phase in ["PULL", "OVER"]) then {
        _m set ["flipMinZ", (_m get "flipMinZ") min (_p # 2)];
        _m set ["flipMaxZ", (_m get "flipMaxZ") max (_p # 2)];
        _m set ["flipMinSpeed", (_m get "flipMinSpeed") min (vectorMagnitude _v)];
        _m set ["maxPast", (_m get "maxPast") max ((_p # 0) - (_tp # 0))];
      };
    };
  };
  _m set ["pass", +(_uav getVariable ["A3UE_FPV_attackPass", createHashMap])];
  _m set ["flip", +(_uav getVariable ["A3UE_FPV_attackReversal", createHashMap])];
  _m
};
private _brief = {params ["_m"]; [_m get "end", _m get "closest", _m get "startedAt", _m get "redivedAt", _m get "endAt",
  _m get "maxPast", (_m get "flipMaxZ") - (_m get "startZ"), _m get "flipMinZ", _m get "flipMinSpeed",
  _m get "maxUpRate", _m get "maxDirRate", (_m get "pass") getOrDefault ["intent", ""], (_m get "pass") getOrDefault ["passIndex", -1],
  _m getOrDefault ["missWhy", []], _m get "events"]};
'''


def run(body, extra='', timeout=300):
    text = script(engine_substitutes(PRE + body), extra)
    with tempfile.TemporaryDirectory(prefix='fpv-f42-') as d:
        p = Path(d) / 'test.sqf'
        p.write_text(text)
        c = Path(d) / 'config.cpp'
        c.write_text(CFG)
        return subprocess.run([VM, '-a', '--suppress-welcome', '--no-execute-print', '--no-work-print',
                               '-m', '2000000', '--input-config', str(c), '-i', str(p)],
                              capture_output=True, text=True, timeout=timeout)


def load(names):
    return ''.join(f'A3UE_fnc_fpv_{n}={{{adapt_helper(n, (FPV / f"fn_fpv_{n}.sqf").read_text())}}};\n' for n in names)


def adapt_ai(name):
    """Native-flight helpers with their AI effects recorded instead of executed."""
    s = (FPV / f'fn_fpv_{name}.sqf').read_text()
    s = s.replace('_uav flyInHeight _trackingHeight;', 'FPV_fly pushBack _trackingHeight;')
    s = s.replace('_uav flyInHeight _searchHeight;', 'FPV_fly pushBack _searchHeight;')
    s = s.replace('_uav doMove _moveTargetAtl;', 'FPV_moveTo pushBack _moveTargetAtl;')
    s = s.replace('_uav doMove _holdTargetATL;', 'FPV_moveTo pushBack _holdTargetATL;')
    s = s.replace('_centerPos getPos [_holdRadius, random 360]', '(_centerPos vectorAdd [_holdRadius, 0, 0])')
    for effect in ['_uav enableAI "ALL";', '_uav setBehaviour "CARELESS";', '_uav setCombatMode "BLUE";',
                   '_uav setSpeedMode "FULL";', '_uav setSpeedMode "NORMAL";', '_uav forceSpeed (_trackingSpeed / 3.6);']:
        s = s.replace(effect, '')
    assert not re.search(r'\b(flyInHeight|doMove|enableAI|setBehaviour|setCombatMode|setSpeedMode|forceSpeed)\b|getPos \[', s), name
    return f'A3UE_fnc_fpv_{name}={{{engine_substitutes(s)}}};\n'


def adapt_loss():
    s = (FPV / 'fn_fpv_logDroneLoss.sqf').read_text()
    for old, new in [('!isServer', '!FPV_isServer'),
                     ('nearestTerrainObjects [_near, [], 12, true, true]', 'FPV_nearTerrain'),
                     ('nearestObjects [_near, ["Static"], 12, true]', 'FPV_nearStatic'),
                     ('boundingBoxReal _object', '(_object getVariable ["box", [[0,0,0],[0,0,0],0]])'),
                     ('(getModelInfo _object) param [0, ""]', '(_object getVariable ["model", ""])'),
                     ('typeOf _object', '(_object getVariable ["type", ""])'),
                     ('typeOf _unit', '(_unit getVariable ["type", "unit"])'),
                     ('diag_log format', 'FPV_lossLine = format')]:
        assert old in s, old
        s = s.replace(old, new)
    return f'A3UE_fnc_fpv_logDroneLoss={{{engine_substitutes(s)}}};\n'


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class F42FlipSQF(unittest.TestCase):
    def vm(self, body, extra=''):
        r = run(body, extra)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('COMMITMENT_TEST_OK', r.stdout, r.stdout[-4000:] + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout[-4000:])
        return r.stdout

    # ---- settings ------------------------------------------------------------------
    def test_settings_defaults_off_and_sanitising(self):
        self.vm(r'''
private _s = call A3UE_fnc_fpv_attackSettings;
[count _s == 15 && {(_s select [10, 5]) isEqualTo [true, true, 35, "", 1.2]}, format ["F4-2 defaults %1", _s]] call _assert;
missionNamespace setVariable ["A3UE_FPV_transitFloorAGL", 500];
missionNamespace setVariable ["A3UE_FPV_QA_forceReturnIntent", "LOOP"];
missionNamespace setVariable ["A3UE_FPV_attackReversal", 1];
_s = call A3UE_fnc_fpv_attackSettings;
[(_s # 12) == 120 && {(_s # 13) == ""} && {_s # 10}, "clamped, whitelisted, typed"] call _assert;
missionNamespace setVariable ["A3UE_FPV_QA_forceIntent", "OVER_SIDE"]; missionNamespace setVariable ["A3UE_FPV_QA_forceReturnIntent", "OVER_TOP"];
_s = call A3UE_fnc_fpv_attackSettings;
[(_s # 8) == "OVER_SIDE" && {(_s # 13) == "OVER_TOP"}, "near-miss styles can be forced"] call _assert;
missionNamespace setVariable ["A3UE_FPV_QA_forceIntent", ""]; missionNamespace setVariable ["A3UE_FPV_QA_forceReturnIntent", ""];
missionNamespace setVariable ["A3UE_FPV_attackRun", false];
[(call A3UE_fnc_fpv_attackSettings) isEqualTo [false,0,0,false,false,false,false,"","",-1,false,false,0,"",0], "master switch off"] call _assert;
''')

    # ---- flip ----------------------------------------------------------------------
    def test_flip_comes_round_and_hits_per_family(self):
        out = self.vm(r'''
missionNamespace setVariable ["A3UE_FPV_QA_forceReturnIntent", "DIRECT"];
private _rows = [];
{
  _x params ["_family", "_maxPast"];
  _profile = createHashMapFromArray [["familyId",_family],["roleId","AP"],["terminalVectorMaxSpeed",200]];
  {
    private _m = [_x, "OVER", [0,0,10], [1,0,0]] call _run;
    private _b = [_m] call _brief;
    _rows pushBack [_family, _x, _b select [0, 11]];
    private _events = _m get "events";
    private _started = _events select {(_x # 0) == "STARTED"};
    [count _started == 1 && {count (_events select {(_x # 0) == "REDIVE"}) == 1} && {(_events findIf {(_x # 0) == "ABORT"}) < 0},
      format ["%1 flip sequence %2", _family, _events]] call _assert;
    [(((_started # 0) # 2) find "intent=OVER") > 0 && {(((_started # 0) # 2) find "pass=1") > 0}, "the missed first pass is logged"] call _assert;
    [(_m get "end") == "HIT", format ["%1 return pass hits: %2", _family, _b]] call _assert;
    [((_m get "pass") get "passIndex") == 1 && {((_m get "pass") get "intent") == "DIRECT"}, "the return pass is a pass of its own"] call _assert;
    private _flipTime = (_m get "redivedAt") - (_m get "startedAt");
    private _total = (_m get "endAt") - (_m get "startedAt");
    [_flipTime <= 2.2 && {_total <= 4.5}, format ["%1 quick: flip %2 s, hit %3 s after the miss", _family, _flipTime, _total]] call _assert;
    [(_m get "maxPast") >= 8 && {(_m get "maxPast") <= _maxPast}, format ["%1 overshoot %2 m", _family, _m get "maxPast"]] call _assert;
    private _climb = (_m get "flipMaxZ") - (_m get "startZ");
    [_climb >= 6 && {_climb <= 16}, format ["%1 climb %2 m", _family, _climb]] call _assert;
    // The near miss now passes at head height or just above (about 2-2.6 m); the pull-up never
    // sinks the drone towards the ground (the flip's own LOW guard is 1.2 m).
    [(_m get "flipMinZ") >= 1.6, format ["%1 no sag into the ground: %2 m", _family, _m get "flipMinZ"]] call _assert;
    [(_m get "flipMinSpeed") >= 5 && {(_m get "flipMinSpeed") <= 12}, "slow over the top"] call _assert;
    // Continuous presentation and steering: rate-limited nose, roll guard, no steering reset.
    [(_m get "maxDirRate") <= 180 && {(_m get "maxUpRate") <= 560}, format ["%1 attitude rates %2 / %3 deg/s", _family, _m get "maxDirRate", _m get "maxUpRate"]] call _assert;
    [(_uav getVariable ["A3UE_FPV_terminalSteeringSerial", 0]) == 1, "one steering episode through the flip"] call _assert;
    [(_uav getVariable ["A3UE_FPV_attackReversalUsed", false]) isEqualTo true, "budget spent"] call _assert;
  } forEach [11, 300, 2047];
} forEach [["armafpv", 21], ["kvn", 24], ["fpv_ua", 19]];
diag_log ["FLIP_ROWS", _rows];
''')
        self.assertIn('FLIP_ROWS', out)

    def test_near_miss_styles_flip_and_hit_per_family(self):
        out = self.vm(r'''
// Third engine pass (EJ: "OMG, it just missed me"): just over the head (OVER_TOP) or just beside
// it (OVER_SIDE), then the flip and the return hit, for every family. The RPT closestM is the
// true closest approach (segment between guidance samples), not the nearest sample.
missionNamespace setVariable ["A3UE_FPV_QA_forceReturnIntent", "DIRECT"];
private _rows = [];
{
  _x params ["_family", "_style", "_low", "_high"];
  _profile = createHashMapFromArray [["familyId",_family],["roleId","AP"],["terminalVectorMaxSpeed",200]];
  {
    private _m = [_x, _style, [0,0,10], [1,0,0]] call _run;
    private _started = (_m get "events") select {(_x # 0) == "STARTED"};
    [count _started == 1 && {(_m get "end") == "HIT"}, format ["%1 %2 seed %3 flips and hits: %4", _family, _style, _x, [_m] call _brief]] call _assert;
    private _line = (_started # 0) # 2;
    [(_line find format ["intent=%1", _style]) >= 0, format ["style logged: %1", _line]] call _assert;
    private _reported = parseNumber (((_line select [(_line find "closestM=") + 9]) splitString " ") # 0);
    private _true = _m get "firstClosest";
    [_true >= _low && {_true <= _high}, format ["%1 %2 seed %3 misses by %4 m", _family, _style, _x, _true]] call _assert;
    [abs (_reported - _true) <= 0.12, format ["reported closestM %1 vs true %2", _reported, _true]] call _assert;
    _rows pushBack [_family, _style, _x, _true, _reported];
  } forEach [11, 2047];
} forEach [["armafpv","OVER_TOP",1.05,1.6],["armafpv","OVER_SIDE",1.2,1.9],["kvn","OVER_TOP",1.05,1.6],["kvn","OVER_SIDE",1.2,1.9],
  ["fpv_ua","OVER_TOP",1.05,1.6],["fpv_ua","OVER_SIDE",1.2,1.9]];
diag_log ["NEAR_MISS_ROWS", _rows];
''')
        self.assertIn('NEAR_MISS_ROWS', out)

    def test_second_miss_never_flips_and_budget_survives_new_controller(self):
        self.vm(r'''
// A steep return pass cannot go over the head: a forced OVER ends on the ground near the target.
missionNamespace setVariable ["A3UE_FPV_QA_forceReturnIntent", "OVER"];
private _steep = [11, "OVER", [0,0,10], [1,0,0]] call _run;
[(_steep get "end") == "GROUND", format ["steep return OVER %1", [_steep] call _brief]] call _assert;
// A late dodge beats the return pass too; being steep, it strikes the ground beside the runner
// (the contact fuse's GROUND_CONTACT in the engine) and never starts a second flip. The
// decision for a return pass that flies on (DIVE -> BUDGET) is in test_flip_decisions_*.
missionNamespace setVariable ["A3UE_FPV_QA_forceReturnIntent", "DIRECT"];
private _m = [11, "OVER", [0,0,10], [1,0,0], "DIRECT", 420, false, [0,5,0], 25, 8] call _run;
private _g = _m getOrDefault ["ground", [99,99,0]];
[(_m get "end") == "GROUND" && {(_m get "closest") > 1} && {(sqrt (((_g # 0) ^ 2) + ((_g # 1) ^ 2))) < 6}
  && {count ((_m get "events") select {(_x # 0) == "STARTED"}) == 1} && {((_m get "flip") get "phase") == "DIVE"},
  format ["dodged return pass %1", [_m] call _brief]] call _assert;
// A spent budget survives a new controller generation and a new pass.
_identity = [1,2,1,2]; _uav setVariable ["A3UE_FPV_controllerIdentity", _identity]; _uav setVariable ["A3UE_FPV_controllerGeneration", 2];
missionNamespace setVariable ["A3UE_FPV_QA_forceReturnIntent", ""];
private _again = [11, "OVER", [0,0,10], [1,0,0], "DIRECT", 420, true] call _run;
[(_again get "end") == "MISSED" && {(_again get "missWhy") isEqualTo ["NONE", "BUDGET"]}
  && {((_again get "events") findIf {(_x # 0) == "STARTED"}) < 0}, format ["no flip after hand-off %1", [_again] call _brief]] call _assert;
''')

    def test_flip_decisions_fences_and_abort(self):
        self.vm(r'''
_person setVariable ["position", [300,0,0]];
_uav setVariable ["A3UE_FPV_mode", "TERMINAL_VECTOR"];
FPV_time = 20; _uav setVariable ["A3UE_FPV_terminalVectorEnteredAt", 10];
private _decide = {
  params ["_pos", "_vel", ["_closest", 3], ["_fresh", true]];
  _uav setVariable ["position", _pos]; _uav setVariable ["velocity", _vel];
  if (_fresh) then {_uav setVariable ["A3UE_FPV_attackReversal", createHashMap];};
  private _nav = [_uav,_person,_identity] call A3UE_fnc_fpv_targetNavigation;
  private _r = ["OFF",""];
  isNil {_r = [_uav,_person,_identity,_nav,_closest,_uav getVariable "A3UE_FPV_terminalVectorEnteredAt"] call A3UE_fnc_fpv_attackReversal;};
  _r
};
_uav setVariable ["A3UE_FPV_attackReversalUsed", false];
[(([[305,0,4],[30,0,0]] call _decide) # 0) == "STARTED", "an eligible close miss flips"] call _assert;
[(_uav getVariable "A3UE_FPV_attackReversalUsed") isEqualTo true && {((_uav getVariable "A3UE_FPV_attackReversal") get "phase") == "PULL"}, "budget and state"] call _assert;
// Phase changes: nose high enough -> over the top; facing the target -> return pass.
[([[306,0,6],[10,0,20],3,false] call _decide) isEqualTo ["OVER",""], "pull -> over"] call _assert;
private _redive = [[306,0,14],[-15,0,-8],3,false] call _decide;
[(_redive # 0) == "REDIVE" && {((_redive # 1) find "turnS=") == 0}, format ["over -> return pass %1", _redive]] call _assert;
[((_uav getVariable "A3UE_FPV_attackReversal") get "passIndex") == 1, "return pass index"] call _assert;
[([[306,0,14],[-15,0,-8],3,false] call _decide) isEqualTo ["DIVE","BUDGET"], "return pass in progress"] call _assert;
// Declines, each decided once.
[([[305,0,4],[30,0,0]] call _decide) isEqualTo ["NONE","BUDGET"], "one flip per drone"] call _assert;
_uav setVariable ["A3UE_FPV_attackReversalUsed", false];
[([[320,0,4],[30,0,0],12] call _decide) isEqualTo ["NONE","FAR"], "not a close miss"] call _assert;
[([[305,0,4],[5,0,0]] call _decide) isEqualTo ["NONE","SLOW"], "too slow to need a flip"] call _assert;
[([[305,0,2],[30,0,-8]] call _decide) isEqualTo ["NONE","LOW"], "sinking into the ground"] call _assert;
missionNamespace setVariable ["A3UE_FPV_reversalMinAGL", 50];
[([[305,0,4],[30,0,0]] call _decide) isEqualTo ["NONE","LOW"], "tunable minimum height"] call _assert;
missionNamespace setVariable ["A3UE_FPV_reversalMinAGL", 1.2];
FPV_boxes = [[[312,-6,0],[316,6,20],FPV_tree]];
[([[305,0,4],[30,0,0]] call _decide) isEqualTo ["NONE","OBSTACLE"], "a tree in the flip"] call _assert;
private _q = FPV_queries;
[([[307,0,4],[30,0,0],3,false] call _decide) isEqualTo ["NONE","OBSTACLE"] && {FPV_queries == _q}, "decided once, no repeated probes"] call _assert;
missionNamespace setVariable ["A3UE_FPV_obstacleAvoid", false];
[(([[305,0,4],[30,0,0]] call _decide) # 0) == "STARTED", "no clearance probe with obstacle awareness off"] call _assert;
missionNamespace setVariable ["A3UE_FPV_obstacleAvoid", true]; FPV_boxes = [];
// Not a miss yet: still closing, or too soon after entry.
_uav setVariable ["A3UE_FPV_attackReversalUsed", false];
[([[296,0,4],[30,0,0],5.7] call _decide) isEqualTo ["NONE",""], "closing"] call _assert;
_uav setVariable ["A3UE_FPV_terminalVectorEnteredAt", 19.8];
[([[305,0,4],[30,0,0]] call _decide) isEqualTo ["NONE",""], "too soon after entry"] call _assert;
_uav setVariable ["A3UE_FPV_terminalVectorEnteredAt", 10];
// A time gap during the flip aborts to the ordinary reacquire.
[(([[305,0,4],[30,0,0]] call _decide) # 0) == "STARTED", "flip again (budget reset by the test)"] call _assert;
FPV_time = FPV_time + 5;
private _abort = [[306,0,6],[20,0,5],3,false] call _decide;
[(_abort # 0) == "ABORT" && {((_abort # 1) find "reason=TIMEOUT") == 0}, format ["time gap aborts %1", _abort]] call _assert;
// Fences: not applicable, nothing written.
_uav setVariable ["A3UE_FPV_attackReversalUsed", false];
private _offCase = {params ["_label"];
  _uav setVariable ["A3UE_FPV_attackReversal", createHashMap];
  private _r = [[305,0,4],[30,0,0],3,false] call _decide;
  [_r isEqualTo ["OFF",""] && {(_uav getVariable "A3UE_FPV_attackReversalUsed") isEqualTo false}
    && {count (_uav getVariable "A3UE_FPV_attackReversal") == 0}, _label] call _assert;};
missionNamespace setVariable ["A3UE_FPV_attackReversal", false]; ["flip off"] call _offCase;
missionNamespace setVariable ["A3UE_FPV_attackReversal", true];
missionNamespace setVariable ["A3UE_FPV_attackRun", false]; ["attack run off"] call _offCase;
missionNamespace setVariable ["A3UE_FPV_attackRun", true];
_person setVariable ["kinds", ["Air","AllVehicles"]]; ["air target"] call _offCase; _person setVariable ["kinds", ["Man","AllVehicles"]];
_uav setVariable ["local", false]; ["remote owner"] call _offCase; _uav setVariable ["local", true];
_uav setVariable ["A3UE_FPV_mode", "TRACKING"]; ["not diving"] call _offCase; _uav setVariable ["A3UE_FPV_mode", "TERMINAL_VECTOR"];
private _real = +_identity; _identity = [9,9,9,9]; ["foreign controller"] call _offCase; _identity = _real;
''')

    def test_flip_limits(self):
        self.vm(r'''
private _base = [_profile] call A3UE_fnc_fpv_trajectoryLimits;
private _key = [+_identity, "person", _revision, _uav getVariable "A3UE_FPV_terminalVectorEnteredAt"];
private _with = {params ["_phase", ["_family", "armafpv"]];
  private _p = createHashMapFromArray [["familyId",_family],["roleId","AP"],["terminalVectorMaxSpeed",200]];
  _uav setVariable ["A3UE_FPV_attackReversal", createHashMapFromArray [["key", +_key], ["phase", _phase]]];
  [[_p] call A3UE_fnc_fpv_trajectoryLimits, [_uav,_person,_identity,_p,[_p] call A3UE_fnc_fpv_trajectoryLimits] call A3UE_fnc_fpv_attackLimits]};
_uav setVariable ["A3UE_FPV_attackReversal", createHashMap];
[([_uav,_person,_identity,_profile,_base] call A3UE_fnc_fpv_attackLimits) isEqualTo _base, "no flip: unchanged"] call _assert;
{
  _x params ["_family", "_row"];
  (["PULL", _family] call _with) params ["_dive", "_pull"];
  [(_pull # 0) == (_row # 0) && {(_pull # 2) == (_row # 1)} && {(_pull # 3) == (_row # 2)} && {(_pull # 5) == (_row # 3)}
    && {(_pull # 6) == (_row # 4)} && {(_pull # 1) == (_dive # 1)} && {(_pull # 4) == (_dive # 4)} && {(_pull select [7, 3]) isEqualTo (_dive select [7, 3])},
    format ["%1 flip envelope %2", _family, _pull]] call _assert;
  (["OVER", _family] call _with) params ["_unused", "_over"];
  [_over isEqualTo _pull, "same envelope over the top"] call _assert;
  (["DIVE", _family] call _with) params ["_unused2", "_return"];
  [((_return select [0, 5]) isEqualTo (_dive select [0, 5])) && {(_return # 5) == (_row # 3)} && {(_return # 6) == (_row # 4)},
    format ["%1 return pass: dive envelope, carried turn %2", _family, _return]] call _assert;
} forEach [["armafpv", [7, 28, 34, 3, 12]], ["kvn", [9, 20, 24, 2.3, 8]], ["fpv_ua", [8, 25, 30, 2.7, 10]]];
(["DECLINED"] call _with) params ["_d0", "_d1"]; [_d0 isEqualTo _d1, "declined: unchanged"] call _assert;
_key set [2, _revision + 1]; (["PULL"] call _with) params ["_s0", "_s1"]; [_s0 isEqualTo _s1, "stale key: unchanged"] call _assert;
_key set [2, _revision];
missionNamespace setVariable ["A3UE_FPV_attackReversal", false]; (["PULL"] call _with) params ["_o0", "_o1"]; [_o0 isEqualTo _o1, "flip off"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackReversal", true];
missionNamespace setVariable ["A3UE_FPV_attackRun", false]; (["PULL"] call _with) params ["_r0", "_r1"]; [_r0 isEqualTo _r1, "attack run off"] call _assert;
''')

    def test_return_pass_plan(self):
        self.vm(r'''
["DIRECT", []] call _setEngagement;
private _key = [+_identity, "person", _revision, _uav getVariable "A3UE_FPV_terminalVectorEnteredAt"];
private _divedAt = FPV_time - 0.5;
_uav setVariable ["A3UE_FPV_attackReversal", createHashMapFromArray [["key", +_key], ["phase", "DIVE"], ["passIndex", 1], ["divedAt", _divedAt]]];
private _planOf = {params ["_seed"]; missionNamespace setVariable ["A3UE_FPV_QA_seed", _seed];
  _uav setVariable ["A3UE_FPV_attackPass", createHashMap]; [_uav, _person, _identity] call A3UE_fnc_fpv_attackPass};
private _counts = createHashMapFromArray [["DIRECT",0],["GROUND_SHORT",0],["GROUND_SIDE",0],["OVER",0]]; private _n = 0;
for "_s" from 0 to 4095 step 7 do {private _i = ([_s] call _planOf) get "intent"; _counts set [_i, (_counts get _i) + 1]; _n = _n + 1;};
private _direct = (_counts get "DIRECT") / _n;
diag_log ["RETURN_INTENTS", _direct, (_counts get "GROUND_SHORT") / _n, (_counts get "GROUND_SIDE") / _n, (_counts get "OVER") / _n];
[abs (_direct - 0.85) < 0.05 && {(_counts get "OVER") == 0}, format ["return weights %1", _counts]] call _assert;
private _p = [5] call _planOf;
[(_p get "key") isEqualTo (_key + [1]) && {(_p get "start") == _divedAt} && {(_p get "passIndex") == 1}, "keyed and timed as the return pass"] call _assert;
missionNamespace setVariable ["A3UE_FPV_QA_forceIntent", "OVER"];
private _forcedFirst = 0;
for "_s" from 0 to 4095 step 97 do {if ((([_s] call _planOf) get "intent") == "OVER") then {_forcedFirst = _forcedFirst + 1;};};
[_forcedFirst == 0, "the first-pass QA force does not apply to the return pass"] call _assert;
missionNamespace setVariable ["A3UE_FPV_QA_forceReturnIntent", "GROUND_SHORT"];
[(([5] call _planOf) get "intent") == "GROUND_SHORT", "return-pass QA force"] call _assert;
// The first pass of the same entry is unchanged (index 0, its own seed).
_uav setVariable ["A3UE_FPV_attackReversal", createHashMap];
missionNamespace setVariable ["A3UE_FPV_QA_forceIntent", ""]; missionNamespace setVariable ["A3UE_FPV_QA_forceReturnIntent", ""];
private _first = [5] call _planOf;
[(_first get "passIndex") == 0 && {((_first get "key") # 4) == 0} && {(_first get "seed") != (_p get "seed")}, "first pass"] call _assert;
// The summary says which pass and how many obstacle hops.
_first set ["lifts", 2];
private _summary = [_uav, _person] call A3UE_fnc_fpv_attackPassSummary;
[(_summary find "pass=1 lifts=2") > 0 && {count _summary <= 128}, _summary] call _assert;
''')

    # ---- obstacles -----------------------------------------------------------------
    def test_obstacle_probe(self):
        self.vm(r'''
FPV_boxes = [[[100,-3,0],[104,3,22],FPV_tree]];
private _hit = [_uav, objNull, [0,0,15], [200,0,15], false, true] call A3UE_fnc_fpv_obstacleProbe;
[count _hit == 4 && {abs (((_hit # 0) # 0) - 100) < 0.01} && {abs ((_hit # 1) - 22) < 0.01} && {(_hit # 2) isEqualTo FPV_tree} && {(_hit # 3) == 0},
  format ["tree hit and top %1", _hit]] call _assert;
[(([_uav, objNull, [0,0,15], [200,0,15], false, false] call A3UE_fnc_fpv_obstacleProbe) # 1) == 15, "no top probe unless asked"] call _assert;
[([_uav, objNull, [0,0,30], [200,0,30], false, true] call A3UE_fnc_fpv_obstacleProbe) isEqualTo [], "over the tree: clear"] call _assert;
// Terrain: reported unless ignored.
private _ground = [_uav, objNull, [0,0,10], [100,0,-10], false, true] call A3UE_fnc_fpv_obstacleProbe;
[isNull (_ground # 2) && {abs (((_ground # 0) # 0) - 50) < 0.01}, "terrain hit"] call _assert;
[([_uav, objNull, [0,0,10], [100,0,-10], true, true] call A3UE_fnc_fpv_obstacleProbe) isEqualTo [], "terrain ignored"] call _assert;
// Moving things are not static obstacles; the target is ignored.
FPV_truck setVariable ["kinds", ["LandVehicle","AllVehicles"]];
FPV_boxes = [[[100,-3,0],[104,3,3],FPV_truck]];
[([_uav, objNull, [0,0,2], [200,0,2], true, true] call A3UE_fnc_fpv_obstacleProbe) isEqualTo [], "a vehicle is skipped"] call _assert;
FPV_boxes = [[[100,-3,0],[104,3,3],_person]];
[([_uav, _person, [0,0,2], [200,0,2], true, true] call A3UE_fnc_fpv_obstacleProbe) isEqualTo [], "the target is ignored"] call _assert;
[([_uav, objNull, [0,0,2], [0,0,2], false, true] call A3UE_fnc_fpv_obstacleProbe) isEqualTo [], "zero-length"] call _assert;
''')

    def test_transit_height_floor_and_probe(self):
        self.vm(r'''
_uav setVariable ["position", [40,0,35]]; _uav setVariable ["velocity", [25,0,0]];
_uav setVariable ["A3UE_FPV_transitProbe", []];
[([_uav] call A3UE_fnc_fpv_transitHeight) == 35, "canopy-clearing floor"] call _assert;
// A 50 m tower within 4 s at the drone's own height: clear its top by 12 m for 6 s.
FPV_boxes = [[[100,-5,0],[110,5,50],FPV_tree]];
FPV_time = FPV_time + 0.6;
[([_uav] call A3UE_fnc_fpv_transitHeight) == 62, "raised over the tower"] call _assert;
private _q = FPV_queries; FPV_time = FPV_time + 0.2;
[([_uav] call A3UE_fnc_fpv_transitHeight) == 62 && {FPV_queries == _q}, "at most one probe per 0.5 s"] call _assert;
FPV_boxes = []; FPV_time = FPV_time + 0.4;
[([_uav] call A3UE_fnc_fpv_transitHeight) == 62, "held after the last sighting"] call _assert;
FPV_time = FPV_time + 6;
[([_uav] call A3UE_fnc_fpv_transitHeight) == 35, "back to the floor"] call _assert;
// Terrain ahead is the AI's own business (flyInHeight follows it).
_uav setVariable ["position", [40,0,5]]; _uav setVariable ["velocity", [25,0,-5]]; FPV_time = FPV_time + 0.6;
[([_uav] call A3UE_fnc_fpv_transitHeight) == 35, "terrain does not raise"] call _assert;
// Hover: no probe.
_uav setVariable ["position", [40,0,35]]; _uav setVariable ["velocity", [0.5,0,0]]; FPV_time = FPV_time + 0.6;
_q = FPV_queries; [_uav] call A3UE_fnc_fpv_transitHeight; [FPV_queries == _q, "no probe while hovering"] call _assert;
_uav setVariable ["velocity", [25,0,0]];
missionNamespace setVariable ["A3UE_FPV_obstacleAvoid", false]; FPV_time = FPV_time + 0.6; _q = FPV_queries;
[([_uav] call A3UE_fnc_fpv_transitHeight) == 35 && {FPV_queries == _q}, "awareness off: floor only"] call _assert;
missionNamespace setVariable ["A3UE_FPV_transitFloorAGL", 0];
[([_uav] call A3UE_fnc_fpv_transitHeight) == 0, "both off: F4-1 heights"] call _assert;
missionNamespace setVariable ["A3UE_FPV_obstacleAvoid", true]; missionNamespace setVariable ["A3UE_FPV_transitFloorAGL", 35];
_uav setVariable ["local", false]; _uav setVariable ["A3UE_FPV_transitProbe", []]; FPV_time = FPV_time + 0.6;
[([_uav] call A3UE_fnc_fpv_transitHeight) == 35 && {(_uav getVariable "A3UE_FPV_transitProbe") isEqualTo []}, "remote: floor, no writes"] call _assert;
_uav setVariable ["local", true];
missionNamespace setVariable ["A3UE_FPV_attackRun", false];
[([_uav] call A3UE_fnc_fpv_transitHeight) == 0, "attack run off"] call _assert;
''')

    def test_native_flight_uses_the_floor(self):
        self.vm(r'''
FPV_fly = []; FPV_moveTo = [];
_uav setVariable ["position", [0,0,15]]; _uav setVariable ["velocity", [20,0,0]];
_uav setVariable ["A3UE_FPV_mode", "LOST_TARGET"];
private _guide = {_uav setVariable ["A3UE_FPV_lastMoveUpdate", -1]; [_uav, [200,0,15], _profile] call A3UE_fnc_fpv_applyGuidance};
[(call _guide) && {(FPV_fly # (count FPV_fly - 1)) == 35}, format ["guidance at the floor %1", FPV_fly]] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackRun", false];
[(call _guide) && {(FPV_fly # (count FPV_fly - 1)) == 15}, "off: the 15 m doctrine height"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackRun", true];
_uav setVariable ["A3UE_FPV_siteType", "Resource"]; _uav setVariable ["A3UE_FPV_siteMarker", ""];
[([_uav, createHashMap] call A3UE_fnc_fpv_holdPattern) && {(FPV_fly # (count FPV_fly - 1)) == 35}, "loiter at the floor"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackRun", false];
[([_uav, createHashMap] call A3UE_fnc_fpv_holdPattern) && {(FPV_fly # (count FPV_fly - 1)) == 25}, "off: Resource 25 m"] call _assert;
missionNamespace setVariable ["A3UE_FPV_attackRun", true];
_uav setVariable ["A3UE_FPV_siteType", "Airport"];
[([_uav, createHashMap] call A3UE_fnc_fpv_holdPattern) && {(FPV_fly # (count FPV_fly - 1)) == 45}, "higher site heights kept"] call _assert;
''', adapt_ai('applyGuidance') + adapt_ai('holdPattern'))

    def test_dive_waits_for_a_clear_line(self):
        self.vm(r'''
_person setVariable ["position", [300,0,0]];
FPV_boxes = [[[175,-40,0],[185,40,24],FPV_tree]];
["DIRECT", []] call _setEngagement;
private _enter = {params ["_pos","_vel"]; _uav setVariable ["position", _pos]; _uav setVariable ["velocity", _vel];
  _uav setVariable ["A3UE_FPV_attackClearLine", []]; [_uav,_person,_profile] call A3UE_fnc_fpv_shouldEnterTerminal};
[!([[0,0,35],[25,0,0]] call _enter), "a tree line on the dive line holds the dive"] call _assert;
[[[140,0,35],[25,0,0]] call _enter, "dives once the line clears the trees"] call _assert;
[[[250,0,8],[25,0,0]] call _enter, "inside 60 m the cover rules decide"] call _assert;
["HIGH_DIVE", [55, 32]] call _setEngagement;
[!([[0,0,60],[25,0,0]] call _enter), "profile gates still first"] call _assert;
["DIRECT", []] call _setEngagement;
missionNamespace setVariable ["A3UE_FPV_obstacleAvoid", false];
[[[0,0,35],[25,0,0]] call _enter, "awareness off: F4-1 entry"] call _assert;
missionNamespace setVariable ["A3UE_FPV_obstacleAvoid", true];
// One probe per 0.25 s per target.
_uav setVariable ["position", [0,0,35]]; _uav setVariable ["A3UE_FPV_attackClearLine", []];
[!([_uav,_person] call A3UE_fnc_fpv_attackClearLine), "blocked"] call _assert;
private _q = FPV_queries; FPV_time = FPV_time + 0.1;
[!([_uav,_person] call A3UE_fnc_fpv_attackClearLine) && {FPV_queries == _q}, "cached"] call _assert;
FPV_time = FPV_time + 0.2; [_uav,_person] call A3UE_fnc_fpv_attackClearLine;
[FPV_queries > _q, "refreshed"] call _assert;
// A vehicle on the line is not a static obstacle.
FPV_truck setVariable ["kinds", ["LandVehicle","AllVehicles"]];
FPV_boxes = [[[175,-4,0],[185,4,40],FPV_truck]];
[[[0,0,35],[25,0,0]] call _enter, "vehicles do not hold the dive"] call _assert;
''', load(['shouldEnterTerminal']))

    def test_dive_hops_a_tree_line(self):
        out = self.vm(r'''
missionNamespace setVariable ["A3UE_FPV_attackReversal", false];
FPV_boxes = [[[175,-40,0],[185,40,24],FPV_tree]];
missionNamespace setVariable ["A3UE_FPV_obstacleAvoid", false];
private _blind = [11, "DIRECT", [0,0,30], [1,0,0]] call _run;
[(_blind get "end") == "COLLISION", format ["without the lift the dive flies into the trees: %1", [_blind] call _brief]] call _assert;
missionNamespace setVariable ["A3UE_FPV_obstacleAvoid", true];
private _rows = [];
{
  private _m = [_x, "DIRECT", [0,0,30], [1,0,0]] call _run;
  _rows pushBack [_x, _m get "end", _m get "minBoxClearance", (_m get "pass") getOrDefault ["lifts", 0], _m get "closest"];
  [(_m get "end") in ["HIT", "GROUND"] && {(_m get "minBoxClearance") > 0.5}, format ["hops the tree line and attacks: %1", [_m] call _brief]] call _assert;
  [((_m get "pass") getOrDefault ["lifts", 0]) >= 1, "the hop is counted"] call _assert;
} forEach [11, 300, 2047];
diag_log ["HOPS", _rows];
// A tree beside the path is not in the way.
FPV_boxes = [[[175,30,0],[185,40,24],FPV_tree]];
private _side = [11, "DIRECT", [0,0,30], [1,0,0]] call _run;
[(_side get "end") == "HIT" && {((_side get "pass") getOrDefault ["lifts", 0]) == 0}, "no hop for a tree off the path"] call _assert;
// Objects at the target stay with the cover and fuse rules.
FPV_boxes = [[[292,-3,0],[294,3,6],FPV_tree]];
private _cover = [11, "DIRECT", [0,0,30], [1,0,0]] call _run;
[((_cover get "pass") getOrDefault ["lifts", 0]) == 0, "no hop over the target's own cover"] call _assert;
''')
        self.assertIn('HOPS', out)

    def test_drone_loss_evidence_line(self):
        self.vm(r'''
FPV_isServer = true; FPV_lossLine = "";
FPV_tree setVariable ["model", "t_picea2s.p3d"]; FPV_tree setVariable ["box", [[-3,-3,0],[3,3,22.4],5]];
FPV_nearTerrain = [FPV_tree]; FPV_nearStatic = [];
A3UE_FPV_lifecycles = createHashMapFromArray [["7", createHashMapFromArray [["phase","live"],["managed",true],["site","Outpost_5"],["support",""]]]];
_uav setVariable ["position", [10,20,18.4]]; _uav setVariable ["velocity", [20,0,0]]; _uav setVariable ["A3UE_FPV_mode", "TRACKING"];
[[_uav, objNull, objNull, 7] call A3UE_fnc_fpv_logDroneLoss, "logged"] call _assert;
diag_log ["LOSS", FPV_lossLine];
{[(FPV_lossLine find _x) >= 0, _x] call _assert;} forEach ["[A3UE_FPV] droneLost id=uav", "lifecycle=7", "mode=TRACKING", "site=Outpost_5",
  "killer=none", "aglM=18.4", "speed=20", "terrainObject=t_picea2s.p3d@0m/h22.4m", "missionObject=none", "via=KILLED"];
// One line per drone: a lethal KVN hit can raise both its hit handler and MPKilled.
FPV_lossLine = "";
[!([_uav, objNull, objNull, 7, "KVN_HIT"] call A3UE_fnc_fpv_logDroneLoss) && {FPV_lossLine == ""}, "logged once"] call _assert;
// KVN's native detonate-and-delete path names itself and the hitting object.
private _other = "VMUAV" createVehicle [0,0,0]; _other setVariable ["type", "frtz_B_KVN_AT_25KM"];
_uav setVariable ["A3UE_FPV_lossLogged", false];
[[_uav, _other, objNull, 7, "KVN_HIT"] call A3UE_fnc_fpv_logDroneLoss && {(FPV_lossLine find "killer=frtz_B_KVN_AT_25KM") >= 0}
  && {(FPV_lossLine find "via=KVN_HIT") >= 0}, FPV_lossLine] call _assert;
// Never for a settled strike, a native drone, a client or an unknown lifecycle.
FPV_lossLine = "";
_uav setVariable ["A3UE_FPV_lossLogged", false];
(A3UE_FPV_lifecycles get "7") set ["phase", "closed"];
[!([_uav, objNull, objNull, 7] call A3UE_fnc_fpv_logDroneLoss), "settled strike"] call _assert;
(A3UE_FPV_lifecycles get "7") set ["phase", "live"]; (A3UE_FPV_lifecycles get "7") set ["managed", false];
[!([_uav, objNull, objNull, 7] call A3UE_fnc_fpv_logDroneLoss), "native drone"] call _assert;
(A3UE_FPV_lifecycles get "7") set ["managed", true];
[!([_uav, objNull, objNull, -1] call A3UE_fnc_fpv_logDroneLoss), "unknown lifecycle"] call _assert;
FPV_isServer = false;
[!([_uav, objNull, objNull, 7] call A3UE_fnc_fpv_logDroneLoss) && {FPV_lossLine == ""}, "client"] call _assert;
[!(_uav getVariable ["A3UE_FPV_lossLogged", false]), "refusals do not mark the drone"] call _assert;
''', adapt_loss())


class F42Source(unittest.TestCase):
    def src(self, name):
        return (FPV / f'fn_fpv_{name}.sqf').read_text()

    def code(self, name):
        return '\n'.join(line.split('//', 1)[0] for line in self.src(name).splitlines())

    def test_functions_registered_and_present(self):
        config = (ROOT / 'addons/drones/config.cpp').read_text()
        for name in NEW:
            self.assertIn(f'class fpv_{name} {{}};', config)
            self.assertTrue((FPV / f'fn_fpv_{name}.sqf').is_file(), name)

    def test_cost_and_authority_contracts(self):
        for name in NEW:
            s = self.code(name)
            self.assertNotRegex(s, r'\b(remoteExec|remoteExecCall|spawn|sleep|publicVariable|hint|hintSilent|addMissionEventHandler|random)\b', name)
            self.assertNotRegex(s, r'\b(allUnits|entities|nearEntities)\b', name)
            if name != 'obstacleProbe':
                self.assertNotIn('lineIntersectsSurfaces', s, name)
            if name != 'logDroneLoss':
                self.assertNotRegex(s, r'\b(nearestObjects|nearestTerrainObjects)\b', name)
        self.assertEqual(self.code('obstacleProbe').count('lineIntersectsSurfaces'), 2)
        # Broadcasts are the three-argument form [name, value, true]; local flags are not.
        broadcasts = {n: re.findall(r'setVariable \["[^"]*",[^\]]*,\s*true\]', self.code(n)) for n in NEW}
        self.assertEqual(broadcasts.pop('attackReversal'), ['setVariable ["A3UE_FPV_attackReversalUsed", true, true]'])
        self.assertFalse(any(broadcasts.values()), broadcasts)
        for name in ['attackNavigation', 'attackReversal', 'transitHeight', 'attackClearLine']:
            self.assertIn('A3UE_fnc_fpv_obstacleProbe', self.code(name), name)
        # Probe rates: transit 0.5 s, entry line 0.25 s, dive lift 0.1 s.
        self.assertIn('_nextAt = _now + 0.5;', self.code('transitHeight'))
        self.assertIn('_now - (_cache # 1) < 0.25', self.code('attackClearLine'))
        self.assertIn('_pass set ["liftNextAt", _now + 0.1];', self.code('attackNavigation'))

    def test_controller_wiring(self):
        c = self.code('runController')
        vector = c.split('case "TERMINAL_VECTOR": {', 1)[1]
        self.assertIn('isNil {_flip = [_uav,_target,_controllerIdentity,_navigation,_lastDistance,_enteredAt] call A3UE_fnc_fpv_attackReversal;};', vector)
        self.assertLess(vector.index('fpv_attackReversal'), vector.index('if (_missedPass) then {'))
        self.assertIn('case "ABORT": {_missedPass = true;};', vector)
        redive = vector.split('case "REDIVE": {', 1)[1].split('case "ABORT"', 1)[0]
        self.assertIn('_uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", -1];', redive)
        for line in ['outcome=MISSED %3 nowM=%4 next=FLIP', 'attackFlip id=%1 target=%2 result=REDIVE %3',
                     'attackFlip id=%1 target=%2 result=ABORT %3', 'outcome=MISSED %3 nowM=%4 next=REACQUIRE flip=%5']:
            self.assertIn(line, vector)

    def test_native_writer_and_lifecycle_hooks(self):
        guidance = self.code('applyGuidance')
        self.assertLess(guidance.index('_trackingHeight max ([_uav] call A3UE_fnc_fpv_transitHeight)'), guidance.index('flyInHeight _trackingHeight'))
        hold = self.code('holdPattern')
        self.assertLess(hold.index('_searchHeight max ([_uav] call A3UE_fnc_fpv_transitHeight)'), hold.index('flyInHeight _searchHeight'))
        for name in ['runTerminalVector', 'prepareTrajectory']:
            s = self.code(name)
            limits = s.index('private _limits = [_profile] call A3UE_fnc_fpv_trajectoryLimits;')
            wrapped = s.index('_limits = [_uav,_target,_controllerIdentity,_profile,_limits] call A3UE_fnc_fpv_attackLimits;', limits)
            self.assertEqual(s[limits:wrapped].count(';'), 1, name)
        enter = self.code('shouldEnterTerminal')
        self.assertIn('exitWith {_inRange};', enter)
        self.assertLess(enter.index('if (!_gate) exitWith {false};'), enter.index('A3UE_fnc_fpv_attackClearLine'))
        self.assertIn('(_settings # 11) && {_horizontal > 60}', enter)
        killed = self.code('registerLifecycle').split('"MPKilled"', 1)[1]
        self.assertLess(killed.index('A3UE_fnc_fpv_logDroneLoss'), killed.index('A3UE_fnc_fpv_endLifecycle'))

    def test_rpt_lines_are_info_level(self):
        self.assertIn('[A3UE_FPV] droneLost id=%1', self.code('logDroneLoss'))
        for name in NEW + ['runController']:
            self.assertNotRegex(self.code(name), r'\bhint(Silent|C)?\b', name)


if __name__ == '__main__':
    unittest.main()
