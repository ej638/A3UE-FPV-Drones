"""F2C-L field fixes (FS-01 roll, FS-02/03 launch standoff, FS-04 site stock, FS-05 logging).

Shipped SQF runs in SQF-VM with explicit engine substitutes (markers, terrain, water,
sorting nested arrays, hashmap iteration, getDir/getPos), listed in adapt() below.
This is geometry/accounting evidence only: no Arma physics, rendering, scheduler
or replication claim, and no visual-quality claim (EJ's review decides that).
"""
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from f2_commitment_vm import VM, FPV, ROOT, execute, engine_substitutes, adapt_helper

PUBLISHED_F2C = '3ebedea'
CFG = ('class CfgVehicles {class AllVehicles {};class Man: AllVehicles {}; class LandVehicle: AllVehicles {};'
       'class Air: AllVehicles {};class VMMan: Man {};class VMVehicle: LandVehicle {};class VMUAV: Air {};};')

PRELUDE = r'''
FPV_time=100; FPV_observed=200; FPV_frame=100; FPV_sender=2; FPV_jip=false; FPV_remote=false;
FPV_finite={_this isEqualType 0 && {abs _this < 1e38}};
FPV_getOrDefault={params ["_map","_args"];if ((_args # 0) in _map) then {_map get (_args # 0)} else {_args # 1}};
FPV_setVariable={params ["_o","_args"];_o setVariable [_args # 0,_args # 1];};
FPV_alive={!isNull _this && {_this getVariable ["alive",true]}};
FPV_water={false}; FPV_getTerrainHeightASL={0}; FPV_terrainIntersectASL={false};
FPV_getDir={params ["_a","_b"]; ((((_b # 0)-(_a # 0)) atan2 ((_b # 1)-(_a # 1))) + 360) mod 360};
FPV_getPosRel={params ["_p","_d","_b"]; [(_p # 0) + _d * sin _b, (_p # 1) + _d * cos _b, 0]};
FPV_sortTrue={params ["_a"];private _n=count _a;
 for "_i" from 0 to _n-2 do {for "_j" from 0 to _n-2-_i do {
  private _l=_a # _j; private _r=_a # (_j+1);
  if ((_l # 0) > (_r # 0)) then {_a set [_j,_r];_a set [_j+1,_l];};}};};
FPV_markers=createHashMap; FPV_areas=createHashMap;
FPV_markerPos={if (_this in FPV_markers) then {+(FPV_markers get _this)} else {[0,0,0]}};
FPV_markerShape={if (_this in FPV_markers) then {"ELLIPSE"} else {""}};
FPV_inArea={params ["_p","_m"]; (_m in FPV_areas) && {(_p distance2D (FPV_markers get _m)) <= (FPV_areas get _m)}};
A3UE_fnc_fpv_isSiteDroneActive={(_this # 0) getVariable ["siteActive",true]};
A3UE_fnc_fpv_getHostileSides={[west]};
private _assert={params ["_ok","_label"];if (!_ok) then {throw _label;};};
'''


def adapt(name, source=None):
    """Shipped source with the test-only engine substitutes; equations unchanged."""
    s = source if source is not None else (FPV / f'fn_fpv_{name}.sqf').read_text()
    s = re.sub(r'\bisServer\b', 'true', s)
    s = re.sub(r'\bsurfaceIsWater (_\w+)', r'(\1 call FPV_water)', s)
    s = re.sub(r'\bmarkerPos (_\w+)', r'(\1 call FPV_markerPos)', s)
    s = re.sub(r'\bmarkerShape (_\w+)', r'(\1 call FPV_markerShape)', s)
    s = re.sub(r'(_\w+) inArea (_\w+)', r'([\1,\2] call FPV_inArea)', s)
    s = s.replace('private _edge = _targPos getPos [_radius, _originPos getDir _targPos];',
                  'private _edge = [_targPos,_radius,[_originPos,_targPos] call FPV_getDir] call FPV_getPosRel;')
    s = re.sub(r'(_\w+) getDir (_\w+)', r'([\1,\2] call FPV_getDir)', s)
    s = re.sub(r'(_\w+) sort true;', r'[\1] call FPV_sortTrue;', s)
    # SQF-VM cannot iterate hashmaps: equivalent key iteration for the two lifecycle/origin loops.
    s = s.replace('private _state = _y;',
                  'private _state = (missionNamespace getVariable ["A3UE_FPV_siteLifecycle", createHashMap]) get _x;')
    s = s.replace('} forEach (missionNamespace getVariable ["A3UE_FPV_siteLifecycle", createHashMap]);',
                  '} forEach keys (missionNamespace getVariable ["A3UE_FPV_siteLifecycle", createHashMap]);')
    s = s.replace('} forEach _origins;', '} forEach keys _origins;')
    s = s.replace('(entities "HeadlessClient_F") apply {owner _x}', '[]')
    return engine_substitutes(s)


def run_vm(script):
    with tempfile.TemporaryDirectory(prefix='fpv-f2cl-') as d:
        p = Path(d) / 'test.sqf'
        p.write_text(script)
        c = Path(d) / 'config.cpp'
        c.write_text(CFG)
        return subprocess.run([VM, '-a', '--suppress-welcome', '--no-execute-print', '--no-work-print',
                               '-m', '40000', '--input-config', str(c), '-i', str(p)],
                              capture_output=True, text=True, timeout=60)


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class F2CLFieldFixesSQF(unittest.TestCase):
    def vm(self, names, body, stubs=''):
        script = PRELUDE + stubs
        for name in names:
            script += f'A3UE_fnc_fpv_{name}={{{adapt(name)}}};\n'
        r = run_vm(script + body + '\ndiag_log "F2CL_TEST_OK";')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('F2CL_TEST_OK', r.stdout, r.stdout + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout)
        return r.stdout

    # ---- FS-01 / F2C-L -------------------------------------------------------------
    ROLL = r'''
private _roll = {
  params ["_d","_u"];
  private _h = sqrt (((_d # 0) ^ 2) + ((_d # 1) ^ 2));
  if (_h < 0.05) exitWith {0};
  private _right = vectorNormalized [_d # 1, -(_d # 0), 0];
  private _level = vectorNormalized (_right vectorCrossProduct _d);
  ((_level vectorCrossProduct _u) vectorDotProduct _d) atan2 (_level vectorDotProduct _u)
};
'''

    def test_level_roll_and_bounded_bank_in_turning_dives(self):
        out = self.vm(['stepTerminalSteering', 'terminalPresentationUp'], self.ROLL + r'''
private _results = [];
{
  private _offset = _x;
  private _pos = [0,0,35]; private _d = [0,1,0]; private _u = [0,0,1]; private _speed = 28; private _rate = [0,0,0];
  private _target = [40 * sin _offset, 40 * cos _offset, 0];
  private _prev = []; private _prevUp = []; private _maxF2C = 0; private _maxL = 0; private _maxBankStep = 0; private _prevBank = 0;
  private _maxNose = 0; private _run = 0; private _maxRun = 0; private _finalF2C = 0; private _finalL = 0;
  for "_i" from 0 to 400 do {
    if ((_pos # 2) <= 0.5 || {(_pos vectorDistance _target) < 1}) exitWith {};
    private _aim = vectorNormalized (_target vectorDiff _pos);
    private _s = [_d,_u,_speed,_rate,_aim,28,8,10,0.18,0.35,0.05,2.1,-1] call A3UE_fnc_fpv_stepTerminalSteering;
    [count _s == 6,"step"] call _assert;
    _d = _s # 0; _u = _s # 1; _speed = _s # 2; _rate = _s # 3;
    private _p = [_d,_rate,_speed,_prev,0.05] call A3UE_fnc_fpv_terminalPresentationUp;
    [count _p == 2,"presentation"] call _assert;
    private _up = _p # 0;
    [abs ((vectorMagnitude _up) - 1) < 1e-4 && {abs (_up vectorDotProduct _d) < 1e-4},"orthonormal"] call _assert;
    if (_prevUp isNotEqualTo []) then {
      private _carried = vectorNormalized (_prevUp vectorDiff (_d vectorMultiply (_prevUp vectorDotProduct _d)));
      _maxNose = _maxNose max abs (((_carried vectorCrossProduct _up) vectorDotProduct _d) atan2 (_carried vectorDotProduct _up));
    };
    _finalF2C = abs ([_d,_u] call _roll); _finalL = abs ([_d,_up] call _roll);
    _maxF2C = _maxF2C max _finalF2C;
    _maxL = _maxL max _finalL;
    _run = if (_finalL > 30.5) then {_run + 1} else {0}; _maxRun = _maxRun max _run;
    private _bank = _p # 1 # 1;
    if (_prev isNotEqualTo []) then {_maxBankStep = _maxBankStep max abs (_bank - _prevBank);};
    _prevBank = _bank; _prev = _p # 1; _prevUp = _up;
    _pos = _pos vectorAdd (_d vectorMultiply (_speed * 0.05));
  };
  _results pushBack [_offset, _maxF2C, _maxL, _maxBankStep, _maxNose, _maxRun, _finalF2C, _finalL];
} forEach [0,45,90,135,180];
diag_log ["ROLL_RESULTS", _results];
{ _x params ["_o","_f","_l","_b","_n","_r"];
  [_b <= 4.5001, format ["bank rate limit 90 deg/s at %1 deg: %2", _o, _b]] call _assert;
  [_n <= 18.001, format ["nose rotation limit 360 deg/s at %1 deg: %2", _o, _n]] call _assert;
  [_r <= 10, format ["excess roll lasts at most 0.5 s at %1 deg: %2 writes", _o, _r]] call _assert;
} forEach _results;
{[(_results # _x # 2) <= 30.5, format ["no vertical pass: roll within bank cap %1", _results # _x]] call _assert;} forEach [0,1,2,3];
[(_results # 0 # 2) < 1, "straight dive stays wings level"] call _assert;
[(_results # 2 # 1) >= 40 && {(_results # 3 # 1) >= 40}, format ["F2C parallel transport roll reproduced: %1", _results]] call _assert;
''')
        self.assertIn('ROLL_RESULTS', out)

    def test_roll_guard_through_vertical_and_convergence(self):
        self.vm(['terminalPresentationUp'], self.ROLL + r'''
private _prev = []; private _prevUp = []; private _last = [];
for "_k" from 0 to 40 do {
  private _pitch = -70 - _k;
  private _d = [0, cos _pitch, sin _pitch];
  private _p = [_d,[0,0,0],20,_prev,0.05] call A3UE_fnc_fpv_terminalPresentationUp;
  [count _p == 2, format ["vertical finite %1", _k]] call _assert;
  private _up = _p # 0;
  if (_prevUp isNotEqualTo []) then {
    private _carried = vectorNormalized (_prevUp vectorDiff (_d vectorMultiply (_prevUp vectorDotProduct _d)));
    private _step = abs (((_carried vectorCrossProduct _up) vectorDotProduct _d) atan2 (_carried vectorDotProduct _up));
    [_step <= 18.001, format ["roll guard 360 deg/s at %1: %2", _k, _step]] call _assert;
  };
  _prev = _p # 1; _prevUp = _up; _last = [_d,_up];
};
[abs (_last call _roll) < 1, "converges back to level after the flip"] call _assert;
''')

    def test_bank_direction_invalid_inputs_and_fresh_start(self):
        self.vm(['terminalPresentationUp'], r'''
private _first = [[0,1,0],[0,0,-1],20,[],0.05] call A3UE_fnc_fpv_terminalPresentationUp;
[(_first # 0) vectorDistance [0,0,1] < 1e-6 && {(_first # 1 # 1) == 0},"fresh write is level"] call _assert;
private _p = _first;
for "_i" from 1 to 10 do {_p = [[0,1,0],[0,0,-1],20,_p # 1,0.05] call A3UE_fnc_fpv_terminalPresentationUp;};
[abs ((_p # 1 # 1) - 30) < 1e-6 && {abs ((_p # 0 # 0) - 0.5) < 1e-4},"right turn banks right, capped at 30"] call _assert;
private _gap = [[0,1,0],[0,0,1],20,_p # 1,10] call A3UE_fnc_fpv_terminalPresentationUp;
[abs ((_gap # 1 # 1) - 7.5) < 1e-6,"gap clamps dt to 0.25 s"] call _assert;
{[([_x # 0,_x # 1,_x # 2,_x # 3,_x # 4] call A3UE_fnc_fpv_terminalPresentationUp) isEqualTo [],format ["invalid %1",_forEachIndex]] call _assert;} forEach [
 [[0,0,0],[0,0,0],10,[],0],[[1,0,0],[0,0,0],-1,[],0],[[1,0,0],[0,0],10,[],0],[[1,0,0],[0,0,0],10,[],"x"]];
private _fresh = [[1,0,0],[0,0,0],10,[],0.05] call A3UE_fnc_fpv_terminalPresentationUp;
private _junk = [[1,0,0],[0,0,0],10,[[5,5],99,[0,0,0]],0.05] call A3UE_fnc_fpv_terminalPresentationUp;
[((_fresh # 0) isEqualTo (_junk # 0)) && {(_fresh # 0) vectorDistance [0,0,1] < 1e-6},"malformed previous is a level fresh start"] call _assert;
private _down = [[0,0,-1],[0,0,0],10,[],0.05] call A3UE_fnc_fpv_terminalPresentationUp;
[count _down == 2 && {abs ((_down # 0) vectorDotProduct [0,0,-1]) < 1e-6},"straight down has a defined up"] call _assert;
''')

    def test_writer_travel_identical_to_published_f2c(self):
        original = subprocess.check_output(
            ['git', 'show', f'{PUBLISHED_F2C}:addons/drones/functions/fpv/fn_fpv_runTerminalVector.sqf'], cwd=ROOT, text=True)
        self.assertIn('_uav setVectorDirAndUp [_blendedDir, vectorNormalized _up];', original)
        extra = 'FPV_originalWriter={' + adapt_helper('runTerminalVector', original) + '};\n'
        r = execute(self.ROLL + r'''
_uav setVariable ["A3UE_FPV_terminalImpactMode","DIRECT_HULL"];
_uav setVariable ["A3UE_FPV_lastImpactValid",true];_uav setVariable ["A3UE_FPV_lastImpactTargetNetId","target"];
_uav setVariable ["A3UE_FPV_lastImpactSurfaceType","vehicle"];_uav setVariable ["A3UE_FPV_impactAnchorObject",_target];
_uav setVariable ["A3UE_FPV_lastImpactPointASL",[250,0,2.4]];
_uav setVariable ["velocity",[0,10,0]];
private _run = {
  params ["_writer"];
  FPV_moves=[]; FPV_poses=[]; FPV_time=10; FPV_observed=20; FPV_frame=100;
  _uav setVariable ["A3UE_FPV_lastImpactTelemetryAt",FPV_time];
  {_uav setVariable [_x,[]];} forEach ["A3UE_FPV_trajectory","A3UE_FPV_terminalSteeringState",
    "A3UE_FPV_terminalPoseContext","A3UE_FPV_terminalPoseAttitude","A3UE_FPV_nativeControl"];
  {_uav setVariable [_x,0];} forEach ["A3UE_FPV_terminalSteeringSerial","A3UE_FPV_terminalPoseSerial"];
  _uav setVariable ["A3UE_FPV_trajectoryAttemptAt",-1];
  [_uav,_target,_profile,1,_identity] call A3UE_fnc_fpv_prepareTrajectory;
  private _states=[];
  for "_i" from 0 to 11 do {
    FPV_time=FPV_time+0.06; FPV_observed=FPV_observed+0.06; FPV_frame=FPV_frame+3;
    [[_uav,_target,_profile,1,_identity] call _writer,"writer admitted"] call _assert;
    _states pushBack +(_uav getVariable ["A3UE_FPV_terminalSteeringState",[]]);
  };
  [+FPV_moves,+FPV_poses,_states]
};
private _old=[FPV_originalWriter] call _run;
private _new=[A3UE_fnc_fpv_runTerminalVector] call _run;
[count (_old # 0) >= 10 && {(_old # 0) isEqualTo (_new # 0)},"identical commanded velocity"] call _assert;
[(_old # 2) isEqualTo (_new # 2),"identical logical steering state"] call _assert;
[count (_new # 1) >= 5 && {count (_old # 1) == count (_new # 1)},"same D1 pose cadence"] call _assert;
private _maxOld=0; private _maxNew=0;
{
  [(_x # 0) isEqualTo ((_old # 1) # _forEachIndex # 0),"identical pose direction"] call _assert;
  _maxNew=_maxNew max abs ([_x # 0,_x # 1] call _roll);
  _maxOld=_maxOld max abs ([(_old # 1) # _forEachIndex # 0,(_old # 1) # _forEachIndex # 1] call _roll);
} forEach (_new # 1);
diag_log ["WRITER_ROLL", _maxOld, _maxNew];
[_maxNew <= 30.5, format ["writer pose roll bounded: %1", _maxNew]] call _assert;
''', extra)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('COMMITMENT_TEST_OK', r.stdout, r.stdout + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout)

    # ---- FS-02 / FS-03 standoff geometry ------------------------------------------
    def test_launch_standoff_geometry(self):
        self.vm(['launchStandoff'], r'''
private _r = [[0,0,0],[10,0,35],[[2000,0,0]],createHashMap] call A3UE_fnc_fpv_launchStandoff;
[(_r # 1) == "DIRECT" && {(_r # 0) isEqualTo [10,0,35]} && {abs ((_r # 2) - 1990) < 0.01},"clear preferred point kept"] call _assert;
_r = [[0,0,0],[10,0,35],[[0,0,0]],createHashMap] call A3UE_fnc_fpv_launchStandoff;
[(_r # 1) == "STANDOFF" && {(_r # 2) >= 800} && {(_r # 2) <= 820},format ["threat on anchor %1",_r]] call _assert;
_r = [[0,0,0],[0,20,35],[[0,300,0]],createHashMap] call A3UE_fnc_fpv_launchStandoff;
[(_r # 1) == "STANDOFF" && {(_r # 0 # 1) < -400} && {(_r # 2) >= 800},format ["far side %1",_r]] call _assert;
_r = [[0,0,0],[0,0,35],[[0,400,0],[0,-400,0]],createHashMap] call A3UE_fnc_fpv_launchStandoff;
[(_r # 1) == "STANDOFF" && {((_r # 0) distance2D [0,400,0]) >= 800} && {((_r # 0) distance2D [0,-400,0]) >= 800},format ["between %1",_r]] call _assert;
private _ring = []; for "_b" from 0 to 330 step 30 do {_ring pushBack [500 * sin _b, 500 * cos _b, 0];};
_r = [[0,0,0],[0,0,35],_ring,createHashMap] call A3UE_fnc_fpv_launchStandoff;
[(_r # 1) == "BLOCKED" && {(_r # 0) isEqualTo []},"surrounded is blocked, never overhead"] call _assert;
FPV_water={true};
_r = [[0,0,0],[0,0,35],[[0,0,0]],createHashMap] call A3UE_fnc_fpv_launchStandoff;
[(_r # 1) == "BLOCKED","water candidates rejected"] call _assert;
FPV_water={false};
FPV_terrainIntersectASL={((_this # 1) # 0) < -300};
_r = [[0,0,0],[0,0,35],[[0,0,0]],createHashMap] call A3UE_fnc_fpv_launchStandoff;
[(_r # 1) == "STANDOFF" && {(_r # 0 # 0) < -300} && {(_r # 2) >= 800},format ["terrain-hidden candidate preferred %1",_r]] call _assert;
FPV_terrainIntersectASL={false};
missionNamespace setVariable ["A3UE_FPV_launchStandoff",500];
_r = [[0,0,0],[0,0,35],[[0,0,0]],createHashMap] call A3UE_fnc_fpv_launchStandoff;
[(_r # 2) >= 500 && {(_r # 2) < 520},"configured standoff"] call _assert;
missionNamespace setVariable ["A3UE_FPV_launchStandoff","bad"];
_r = [[0,0,0],[0,0,35],[[0,0,0]],createHashMap] call A3UE_fnc_fpv_launchStandoff;
[(_r # 2) >= 800 && {(_r # 2) < 820},"invalid config falls back to 800"] call _assert;
missionNamespace setVariable ["A3UE_FPV_launchStandoff",0];
_r = [[0,0,0],[0,0,35],[[0,0,0]],createHashMap] call A3UE_fnc_fpv_launchStandoff;
[(_r # 1) == "DIRECT","zero standoff disables (F2C behaviour)"] call _assert;
missionNamespace setVariable ["A3UE_FPV_launchStandoff",800];
_r = [[0,0,0],[0,0,35],[[0,0,0]],createHashMapFromArray [["probeOnly",true]]] call A3UE_fnc_fpv_launchStandoff;
[(_r # 1) == "NEAR" && {(_r # 0) isEqualTo []},"probe classifies only"] call _assert;
_r = [[],[0,0,35],[[0,0,0]],createHashMap] call A3UE_fnc_fpv_launchStandoff;
[(_r # 1) == "BLOCKED","invalid anchor"] call _assert;
_r = [[0,0,0],[0,0,35],[],createHashMap] call A3UE_fnc_fpv_launchStandoff;
[(_r # 1) == "DIRECT" && {(_r # 2) == -1},"no threats"] call _assert;
''')

    # ---- FS-04 session stock ------------------------------------------------------
    def test_site_stock_rolls_once_depletes_returns_and_refills(self):
        self.vm(['profileValue', 'userSetting', 'siteStock'], r'''
missionNamespace setVariable ["A3UE_FPV_siteFrequency", "ALWAYS"];
private _profile = createHashMapFromArray [["spawnChance",0.5],["stock",[3,3]]];
private _open = ["OPEN","Outpost_1",east,_profile] call A3UE_fnc_fpv_siteStock;
[_open isEqualTo [3,3,false,0],format ["fresh roll %1",_open]] call _assert;
[(["SPEND","Outpost_1",east,2] call A3UE_fnc_fpv_siteStock) == 1,"spend"] call _assert;
private _again = ["OPEN","Outpost_1",east,createHashMapFromArray [["stock",[1,1]]]] call A3UE_fnc_fpv_siteStock;
[(_again # 0) == 1 && {(_again # 1) == 3},"no re-roll on re-activation"] call _assert;
FPV_time = 100 + 899;
[((["OPEN","Outpost_1",east,_profile] call A3UE_fnc_fpv_siteStock) # 0) == 1,"no refill before 15 min"] call _assert;
FPV_time = 100 + 900;
[((["OPEN","Outpost_1",east,_profile] call A3UE_fnc_fpv_siteStock) # 0) == 2,"one drone at 15 min"] call _assert;
FPV_time = 100 + 1800;
[((["OPEN","Outpost_1",east,_profile] call A3UE_fnc_fpv_siteStock) # 0) == 3,"second drone at 30 min"] call _assert;
[((A3UE_FPV_siteStock get "Outpost_1") get "refillAt") == -1,"full stops the timer"] call _assert;
FPV_time = 100 + 5000;
[((["OPEN","Outpost_1",east,_profile] call A3UE_fnc_fpv_siteStock) # 0) == 3,"never above the rolled maximum"] call _assert;
[(["SPEND","Outpost_1",east,10] call A3UE_fnc_fpv_siteStock) == 0,"spend is bounded"] call _assert;
FPV_time = FPV_time + 1800;
[((["OPEN","Outpost_1",east,_profile] call A3UE_fnc_fpv_siteStock) # 0) == 2,"lazy catch-up, one per interval"] call _assert;
[(["RETURN","Outpost_1",east,5] call A3UE_fnc_fpv_siteStock) == 3,"returns capped at maximum"] call _assert;
private _inv = ["OPEN","Outpost_1",independent,createHashMapFromArray [["stock",[2,2]]]] call A3UE_fnc_fpv_siteStock;
[_inv isEqualTo [2,2,false,0],"a different holder rolls fresh"] call _assert;
["CLEAR","Outpost_1"] call A3UE_fnc_fpv_siteStock;
[!("Outpost_1" in A3UE_FPV_siteStock),"cleared"] call _assert;
[(["SPEND","nowhere",east,1] call A3UE_fnc_fpv_siteStock) == -1,"no record"] call _assert;
missionNamespace setVariable ["A3UE_FPV_siteFrequency", "NORMAL"];
private _skip = ["OPEN","Resource_1",east,createHashMapFromArray [["spawnChance",-1],["stock",[1,1]]]] call A3UE_fnc_fpv_siteStock;
[(_skip # 2) && {(_skip # 1) == 0},"failed spawn chance gives no stock"] call _assert;
_skip = ["OPEN","Resource_1",east,createHashMapFromArray [["spawnChance",1],["stock",[1,1]]]] call A3UE_fnc_fpv_siteStock;
[_skip # 2,"the failed roll is kept for the session"] call _assert;
missionNamespace setVariable ["A3UE_FPV_siteFrequency", "ALWAYS"];
missionNamespace setVariable ["A3UE_FPV_siteStockRefillSeconds", 300];
FPV_time = 0; ["OPEN","Factory_1",east,_profile] call A3UE_fnc_fpv_siteStock; ["SPEND","Factory_1",east,3] call A3UE_fnc_fpv_siteStock;
FPV_time = 300;
[((["OPEN","Factory_1",east,_profile] call A3UE_fnc_fpv_siteStock) # 0) == 1,"configured interval"] call _assert;
missionNamespace setVariable ["A3UE_FPV_siteStockRefillSeconds", 30];
FPV_time = 1000; ["OPEN","Factory_2",east,_profile] call A3UE_fnc_fpv_siteStock; ["SPEND","Factory_2",east,1] call A3UE_fnc_fpv_siteStock;
[((A3UE_FPV_siteStock get "Factory_2") get "refillAt") == 1900,"invalid interval falls back to 900 s"] call _assert;
''')

    SITE_STUBS = r'''
A3UE_fnc_fpv_resolveSiteType={_this # 1};
A3UE_fnc_fpv_selectFamilyForSite={"kvn"};
A3UE_FPV_catalog=createHashMapFromArray [["kvn",createHashMap]];
A3UE_FPV_doctrine=createHashMapFromArray [["Outpost",createHashMapFromArray [["spawnChance",1],["stock",[3,3]]]]];
A3UE_FPV_siteReady=true; A3UE_FPV_registry=createHashMap; A3UE_FPV_siteLifecycle=createHashMap;
missionNamespace setVariable ["A3UE_FPV_debug", true]; missionNamespace setVariable ["A3UE_FPV_siteFrequency", "ALWAYS"];
sidesX="VMUAV" createVehicle [0,0,0]; Occupants=east; Invaders=independent;
{sidesX setVariable [_x,east]; A3UE_FPV_siteLifecycle set [_x,createHashMapFromArray [["generation",1],["cleanupDrones",[]]]];} forEach ["Outpost_1","Outpost_2","Outpost_3"];
A3UE_fnc_fpv_standoffThreats={[]};
FPV_spawnPlan=[]; FPV_cleaned=[];
A3UE_fnc_fpv_managerSpawnDrone={
  params ["_m","_t","_p","_s","_f",["_placement",createHashMap]];
  private _next = if (FPV_spawnPlan isEqualTo []) then {"ok"} else {FPV_spawnPlan deleteAt 0};
  if (_next == "standoff") exitWith {_placement set ["mode","BLOCKED"]; _placement set ["reason","STANDOFF"]; _placement set ["nearestHostile",120]; objNull};
  _placement set ["mode",["DIRECT","STANDOFF"] select (_next == "displaced")]; _placement set ["nearestHostile",850];
  private _o="VMUAV" createVehicle [0,0,0]; _o setVariable ["A3UE_FPV_managed",true]; _o
};
A3UE_fnc_fpv_cleanupDrone={params ["_u"]; _u setVariable ["A3UE_FPV_managed",false]; FPV_cleaned pushBack _u; true};
'''

    def test_site_lifecycle_keeps_losses_and_refills(self):
        out = self.vm(['profileValue', 'userSetting', 'siteStock', 'managerDeployStock', 'managerEvaluateSite'], r'''
[["Outpost_1","Outpost",true] call A3UE_fnc_fpv_managerEvaluateSite,"activation 1"] call _assert;
private _entry = A3UE_FPV_registry get "Outpost_1";
[count (_entry get "drones") == 3 && {(_entry get "status") == "active"},"three spawned"] call _assert;
[((A3UE_FPV_siteStock get "Outpost_1") get "remaining") == 0,"spawned drones spend stock"] call _assert;
((_entry get "drones") # 0) setVariable ["alive",false];
((_entry get "drones") # 1) setVariable ["siteActive",false];
["Outpost_1","Outpost",false] call A3UE_fnc_fpv_managerEvaluateSite;
[((A3UE_FPV_siteStock get "Outpost_1") get "remaining") == 1,"only the intact drone returns"] call _assert;
[!("Outpost_1" in A3UE_FPV_registry) && {count FPV_cleaned == 3},"despawn still cleans every drone"] call _assert;
FPV_time = 200;
["Outpost_1","Outpost",true] call A3UE_fnc_fpv_managerEvaluateSite;
_entry = A3UE_FPV_registry get "Outpost_1";
[count (_entry get "drones") == 1,"no regeneration on re-activation"] call _assert;
((_entry get "drones") # 0) setVariable ["alive",false];
["Outpost_1","Outpost",false] call A3UE_fnc_fpv_managerEvaluateSite;
FPV_time = 300;
["Outpost_1","Outpost",true] call A3UE_fnc_fpv_managerEvaluateSite;
_entry = A3UE_FPV_registry get "Outpost_1";
[(_entry get "status") == "depleted" && {(_entry get "drones") isEqualTo []},"depleted site deploys nothing"] call _assert;
["Outpost_1","Outpost",false] call A3UE_fnc_fpv_managerEvaluateSite;
FPV_time = 1000;
["Outpost_1","Outpost",true] call A3UE_fnc_fpv_managerEvaluateSite;
_entry = A3UE_FPV_registry get "Outpost_1";
[count (_entry get "drones") == 1,"one drone refilled 15 min after the first loss"] call _assert;
(A3UE_FPV_siteLifecycle get "Outpost_1") set ["captured",true];
["Outpost_1","Outpost",false] call A3UE_fnc_fpv_managerEvaluateSite;
[!("Outpost_1" in A3UE_FPV_siteStock),"capture clears the stock"] call _assert;
''', self.SITE_STUBS)
        lines = [l for l in out.splitlines() if 'siteDeploy marker=Outpost_1' in l]
        self.assertEqual(len(lines), 4, out)
        self.assertIn('status=active', lines[0])
        self.assertIn('stock=0/3', lines[0])
        self.assertIn('nearestHostileM=850', lines[0])
        self.assertIn('status=depleted', lines[2])
        self.assertIn('requested=0', lines[2])

    def test_standoff_deferral_is_bounded_and_unspent_stock_stays(self):
        out = self.vm(['profileValue', 'userSetting', 'siteStock', 'managerDeployStock', 'managerEvaluateSite'], r'''
FPV_spawnPlan = ["ok","standoff","standoff"]; FPV_time = 5000;
["Outpost_2","Outpost",true] call A3UE_fnc_fpv_managerEvaluateSite;
private _e = A3UE_FPV_registry get "Outpost_2";
[count (_e get "drones") == 1 && {(_e get "deferred") == 2} && {(_e get "deferRetryAt") == 5020} && {(_e get "status") == "active"},"two deferred"] call _assert;
[((A3UE_FPV_siteStock get "Outpost_2") get "remaining") == 2,"deferred drones are not spent"] call _assert;
private _profile = A3UE_FPV_doctrine get "Outpost";
FPV_spawnPlan = ["standoff","standoff"]; FPV_time = 5020;
["Outpost_2","Outpost",_profile,east,"kvn",_e get "deferred",_e,"retry"] call A3UE_fnc_fpv_managerDeployStock;
[(_e get "deferRetries") == 1 && {(_e get "deferred") == 2} && {(_e get "deferRetryAt") == 5040},"retry 1 still blocked"] call _assert;
FPV_spawnPlan = ["displaced","standoff"]; FPV_time = 5040;
["Outpost_2","Outpost",_profile,east,"kvn",_e get "deferred",_e,"retry"] call A3UE_fnc_fpv_managerDeployStock;
[(_e get "deferRetries") == 2 && {count (_e get "drones") == 2} && {(_e get "deferred") == 1},"retry 2 spawns one"] call _assert;
FPV_spawnPlan = ["standoff"]; FPV_time = 5060;
["Outpost_2","Outpost",_profile,east,"kvn",_e get "deferred",_e,"retry"] call A3UE_fnc_fpv_managerDeployStock;
[(_e get "deferRetries") == 3 && {(_e get "deferred") == 0} && {(_e get "deferRetryAt") == -1},"gives up after three retries"] call _assert;
[((A3UE_FPV_siteStock get "Outpost_2") get "remaining") == 1,"unspent stock stays with the site"] call _assert;
FPV_spawnPlan = ["standoff","standoff","standoff"];
["Outpost_3","Outpost",true] call A3UE_fnc_fpv_managerEvaluateSite;
private _e3 = A3UE_FPV_registry get "Outpost_3";
[(_e3 get "status") == "deferred" && {(_e3 get "drones") isEqualTo []} && {(_e3 get "deferred") == 3},"fully blocked site waits, never overhead"] call _assert;
''', self.SITE_STUBS)
        retry = [l for l in out.splitlines() if 'siteDeploy marker=Outpost_2' in l and 'pass=retry' in l]
        self.assertEqual(len(retry), 3, out)
        self.assertRegex(retry[1], r'placement=\[\W*STANDOFF\W*\]')

    def test_queue_schedules_retry_and_clears_captured_stock(self):
        self.vm(['processSiteQueue'], r'''
A3UE_FPV_registrationComplete=true; serverInitDone=true; airportsX=[]; outposts=["Outpost_2"]; resourcesX=[];
spawner="VMUAV" createVehicle [0,0,0]; spawner setVariable ["Outpost_2",0];
sidesX="VMUAV" createVehicle [0,0,0]; sidesX setVariable ["Outpost_2",east]; Occupants=east; Invaders=independent;
A3UE_FPV_siteReady=true; A3UE_FPV_integrationHooksEnabled=false; A3UE_FPV_siteEpoch="ep";
FPV_markers set ["Outpost_2",[0,0,0]];
A3UE_FPV_siteLifecycle=createHashMapFromArray [["Outpost_2",createHashMapFromArray [["generation",1],["phase","active"],
  ["producer",2],["appliedGeneration",1],["appliedActive",true],["siteSide",east],["siteType","Outpost"],["cleanupDrones",[]]]]];
A3UE_FPV_siteTracked=createHashMapFromArray [["Outpost_2",true]]; A3UE_FPV_siteQueue=createHashMap;
A3UE_FPV_registry=createHashMapFromArray [["Outpost_2",createHashMapFromArray [["status","active"],["drones",[]],
  ["deferred",2],["deferRetryAt",5020],["siteType","Outpost"],["siteSide",east],["selectedFamily","kvn"]]]];
A3UE_FPV_doctrine=createHashMapFromArray [["Outpost",createHashMap]];
FPV_deploys=[]; FPV_stockCalls=[]; FPV_evaluations=[];
A3UE_fnc_fpv_managerDeployStock={FPV_deploys pushBack [_this # 0,_this # 5,_this # 7]; (_this # 6) set ["deferred",0]; 0};
A3UE_fnc_fpv_siteStock={FPV_stockCalls pushBack +_this; true};
A3UE_fnc_fpv_managerEvaluateSite={FPV_evaluations pushBack +_this; true};
FPV_time=5010;
call A3UE_fnc_fpv_processSiteQueue;
[FPV_deploys isEqualTo [],"no retry before deferRetryAt"] call _assert;
FPV_time=5020;
call A3UE_fnc_fpv_processSiteQueue;
[FPV_deploys isEqualTo [["Outpost_2",2,"retry"]],format ["one bounded retry %1",FPV_deploys]] call _assert;
call A3UE_fnc_fpv_processSiteQueue;
[count FPV_deploys == 1,"no retry once nothing is deferred"] call _assert;
sidesX setVariable ["Outpost_2",independent];
call A3UE_fnc_fpv_processSiteQueue;
call A3UE_fnc_fpv_processSiteQueue;
[(FPV_evaluations findIf {(_x # 2) isEqualTo false}) >= 0,"captured site despawns"] call _assert;
[(FPV_stockCalls findIf {(_x # 0) == "CLEAR" && {(_x # 1) == "Outpost_2"}}) >= 0,format ["capture clears stock %1",FPV_stockCalls]] call _assert;
''')

    # ---- FS-02 support origin -----------------------------------------------------
    ORIGIN_STUBS = r'''
A3UE_FPV_siteReady=true; A3UE_FPV_siteEpoch="ep";
sidesX="VMUAV" createVehicle [0,0,0]; spawner="VMUAV" createVehicle [0,0,0];
FPV_markers set ["OutA",[100,0,0]]; FPV_markers set ["OutB",[0,2500,0]];
{sidesX setVariable [_x,east]; spawner setVariable [_x,1];} forEach ["OutA","OutB"];
FPV_site={createHashMapFromArray [["phase","active"],["siteType","Outpost"],["siteSide",east],["generation",3],["cleanupDrones",[]]]};
A3UE_FPV_siteLifecycle=createHashMapFromArray [["OutA",call FPV_site],["OutB",call FPV_site]];
FPV_players=[]; A3UE_fnc_fpv_standoffThreats={+FPV_players};
FPV_controls=[]; FPV_samples=[];
A3UE_fnc_fpv_sampleRadioLink={FPV_samples pushBack +(_this # 0); FPV_controls pushBack +(_this # 1); createHashMapFromArray [["signal",1]]};
FPV_caps=createHashMapFromArray [["KVN_X",createHashMapFromArray [["maxSpeed",120],["nominalEnduranceDistance",20000]]],
  ["UA_X",createHashMapFromArray [["maxSpeed",120]]]];
A3UE_FPV_catalog=createHashMapFromArray [
  ["kvn",createHashMapFromArray [["signalModel","FIBER_VISUAL"],["classCapabilities",FPV_caps]]],
  ["fpv_ua",createHashMapFromArray [["signalModel","RADIO"],["classCapabilities",FPV_caps],["jammerClasses",[]],["retranslatorClass",""]]]];
FPV_role=createHashMapFromArray [["AT",createHashMapFromArray [["searchHeightAGL",35],["trackingSpeed",100]]]];
A3UE_FPV_doctrine=createHashMapFromArray [["Outpost",createHashMapFromArray [["behavior",createHashMapFromArray [
  ["profiles",createHashMapFromArray [["kvn",FPV_role],["fpv_ua",FPV_role]]]]]]]];
FPV_plan={params ["_family","_class"]; createHashMapFromArray [["familyId",_family],["uavClass",_class],["siteType","Outpost"],
  ["payloadRole","AT"],["activeRadius",350],["strikeDuration",600]]};
FPV_resolve={params ["_plan",["_context",createHashMap]]; [east,[0,0,0],_plan,_context,createHashMap] call A3UE_fnc_fpv_supportResolveOrigin};
'''

    def test_support_origin_skips_site_under_assault_and_displaces_launch(self):
        self.vm(['launchStandoff', 'supportCheckReach', 'supportResolveOrigin'], r'''
private _kvn = ["kvn","KVN_X"] call FPV_plan;
private _r = [_kvn] call FPV_resolve;
[(_r get "ok") && {(_r get "originMarker") == "OutB"} && {(_r get "launchMode") == "ORIGIN"}
  && {(_r get "launchPosATL") isEqualTo [0,2500,35]},format ["clear origin preferred over the site under assault %1",_r]] call _assert;
A3UE_FPV_siteLifecycle deleteAt "OutB";
_r = [_kvn] call FPV_resolve;
private _launch = _r get "launchPosATL";
[(_r get "ok") && {(_r get "originMarker") == "OutA"} && {(_r get "launchMode") == "STANDOFF"},format ["displaced %1",_r]] call _assert;
[(_launch distance2D [0,0,0]) >= 800 && {(_launch # 2) == 35},format ["launch at least 800 m out %1",_launch]] call _assert;
[(_r get "controlPosATL") isEqualTo [100,0,0.5] && {(_r get "fiberAnchorPos") isEqualTo [100,0,0.5]}
  && {(_r get "originPosATL") isEqualTo [100,0,0.5]},"control and fiber anchor stay at the base"] call _assert;
[abs (((_r get "reach") get "extraDistance") - (_launch distance2D [100,0,0])) < 0.01,"base-to-launch leg counted"] call _assert;
FPV_caps set ["KVN_X",createHashMapFromArray [["maxSpeed",120],["nominalEnduranceDistance",2400]]];
_r = [_kvn] call FPV_resolve;
[!(_r get "ok") && {(_r get "reason") == "ENDURANCE_BUDGET_EXCEEDED"},format ["KVN endurance includes the extra leg %1",_r]] call _assert;
FPV_caps set ["KVN_X",createHashMapFromArray [["maxSpeed",120],["nominalEnduranceDistance",20000]]];
FPV_water={true};
_r = [_kvn] call FPV_resolve;
[!(_r get "ok") && {(_r get "reason") == "NO_STANDOFF_LAUNCH"},format ["never pops in %1",_r]] call _assert;
FPV_water={false};
missionNamespace setVariable ["A3UE_FPV_launchStandoff",0];
_r = [_kvn] call FPV_resolve;
[(_r get "launchMode") == "ORIGIN" && {(_r get "launchPosATL") isEqualTo [100,0,35]},"standoff 0 restores F2C origin launch"] call _assert;
missionNamespace setVariable ["A3UE_FPV_launchStandoff",800];
private _ua = ["fpv_ua","UA_X"] call FPV_plan;
_r = [_ua] call FPV_resolve;
[(_r get "ok") && {(_r get "launchMode") == "STANDOFF"},format ["radio displaced %1",_r]] call _assert;
[(FPV_controls findIf {!(_x isEqualTo [100,0,0.5])}) < 0 && {count FPV_controls >= 6},"radio samples use the base control node"] call _assert;
[((FPV_samples # 0) distance2D (_r get "launchPosATL")) < 0.01,"radio path starts at the launch point"] call _assert;
''', self.ORIGIN_STUBS)

    def test_support_origin_players_and_target_area(self):
        self.vm(['launchStandoff', 'supportCheckReach', 'supportResolveOrigin'], r'''
private _kvn = ["kvn","KVN_X"] call FPV_plan;
A3UE_FPV_siteLifecycle deleteAt "OutA";
FPV_players = [[0,2300,0]];
private _r = [_kvn] call FPV_resolve;
private _launch = _r get "launchPosATL";
[(_r get "ok") && {(_r get "launchMode") == "STANDOFF"} && {(_launch distance2D [0,2300,0]) >= 800}
  && {(_launch distance2D [0,0,0]) >= 800},format ["hostile player near the origin %1",_r]] call _assert;
FPV_players = [];
FPV_areas set ["OutB",3000];
_r = [_kvn] call FPV_resolve;
[(_r get "ok") && {(_r get "launchMode") == "ORIGIN"} && {(_r get "launchPosATL") isEqualTo [0,2500,35]},
  format ["target inside a large area but centre clear %1",_r]] call _assert;
private _override = [_kvn,createHashMapFromArray [["originMarker","outb"]]] call FPV_resolve;
[(_override get "ok") && {(_override get "originSource") == "override"} && {(_override get "originMarker") == "OutB"},"override spelling kept"] call _assert;
''', self.ORIGIN_STUBS)


class F2CLSourceContracts(unittest.TestCase):
    def src(self, name):
        return (FPV / f'fn_fpv_{name}.sqf').read_text()

    def code(self, name):
        return re.sub(r'//[^\n]*', '', self.src(name))

    def test_functions_registered_and_present(self):
        config = (ROOT / 'addons/drones/config.cpp').read_text()
        for name in ['terminalPresentationUp', 'launchStandoff', 'standoffThreats', 'siteStock', 'managerDeployStock']:
            self.assertIn(f'class fpv_{name} {{}};', config)
            self.assertTrue((FPV / f'fn_fpv_{name}.sqf').is_file(), name)

    def test_presentation_is_pose_only_and_logical_basis_unchanged(self):
        s = self.src('runTerminalVector')
        block = s.split('if (_poseDue) then {', 1)[1].split('\n};', 1)[0]
        self.assertIn('call A3UE_fnc_fpv_terminalPresentationUp', block)
        self.assertIn('_uav setVectorDirAndUp [_blendedDir, _poseUp];', block)
        self.assertNotIn('call A3UE_fnc_fpv_terminalPresentationUp', s.split('if (_poseDue) then {', 1)[0])
        self.assertIn('_state set [4, _up];', s)
        self.assertIn('private _seedUp = if (abs (_seedDir # 2) < 0.95) then {[0,0,1]} else {[0,1,0]};', s)
        self.assertIn('private _desiredVelocity = if (_dt > 0) then {_blendedDir vectorMultiply _nextSpeedBudget}', s)
        published = subprocess.check_output(['git', 'show', f'{PUBLISHED_F2C}:addons/drones/functions/fpv/fn_fpv_stepTerminalSteering.sqf'],
                                            cwd=ROOT, text=True)
        self.assertEqual(published, self.src('stepTerminalSteering'))
        helper = self.code('terminalPresentationUp')
        self.assertNotRegex(helper, r'\b(getVariable|setVariable|vectorUp|vectorDir|velocity|getPos\w*|spawn|sleep|random|diag_log)\b')
        for constant in ['private _bankMax = 30;', 'private _bankRate = 90;', 'private _rollGuardRate = 360;']:
            self.assertIn(constant, helper)

    def test_fs05_lines_are_info_level_and_spawn_time_only(self):
        deploy = self.src('managerDeployStock')
        launch = self.src('supportLaunch')
        self.assertIn('diag_log format ["[A3UE_FPV] siteDeploy marker=%1', deploy)
        self.assertIn('diag_log format ["[A3UE_FPV] supportDeploy name=%1', launch)
        self.assertIn('diag_log format ["[A3UE_FPV] supportDeployFailed name=%1', launch)
        for text, marker in [(deploy, 'siteDeploy'), (launch, 'supportDeploy name'), (launch, 'supportDeployFailed')]:
            before = text.split(marker, 1)[0].rsplit('\n', 3)
            self.assertNotIn('A3UE_FPV_debug', ''.join(before[-3:]), marker)
        for name in ['runTerminalVector', 'runController', 'stepTerminalSteering', 'terminalPresentationUp', 'trajectorySteering']:
            self.assertNotIn('siteDeploy', self.src(name))
            self.assertNotIn('supportDeploy', self.src(name))
            self.assertNotIn('standoffThreats', self.src(name))

    def test_defaults_bounds_and_no_new_workers(self):
        self.assertIn('getVariable ["A3UE_FPV_launchStandoff", 800]', self.src('launchStandoff'))
        self.assertIn('_standoff = _standoff min 3000;', self.src('launchStandoff'))
        self.assertIn('getVariable ["A3UE_FPV_siteStockRefillSeconds", 900]', self.src('userSetting'))
        self.assertIn('["siteRefillSeconds"] call A3UE_fnc_fpv_userSetting', self.src('siteStock'))
        self.assertIn('forEach [0, 30, -30, 60, -60, 90, -90];', self.src('launchStandoff'))
        self.assertIn('_retries < 3', self.src('managerDeployStock'))
        self.assertIn('time + 20', self.src('managerDeployStock'))
        self.assertIn('_candidates resize ((count _candidates) min 8);', self.src('supportResolveOrigin'))
        for name in ['launchStandoff', 'standoffThreats', 'siteStock', 'managerDeployStock', 'terminalPresentationUp']:
            s = self.code(name)
            self.assertNotRegex(s, r'\b(spawn|sleep|execVM|waitUntil|EachFrame|addMissionEventHandler|remoteExec\w*|publicVariable)\b', name)
            self.assertNotIn(', true]', s.replace('["probeOnly", true]', ''), name)

    def test_site_and_support_wiring(self):
        evaluate = self.src('managerEvaluateSite')
        self.assertIn('["OPEN", _markerX, _siteSide, _profile] call A3UE_fnc_fpv_siteStock', evaluate)
        self.assertIn('["RETURN", _markerX', evaluate)
        self.assertIn('["CLEAR", _markerX] call A3UE_fnc_fpv_siteStock', evaluate)
        self.assertNotIn('random', self.code('managerEvaluateSite'))
        spawn = self.src('managerSpawnDrone')
        self.assertIn('call A3UE_fnc_fpv_launchStandoff', spawn)
        self.assertIn('_spec set ["controlPosATL", [_spawnCenter # 0, _spawnCenter # 1, _spawnHeight]];', spawn)
        self.assertIn('_spec set ["fiberAnchorPos", [_spawnCenter # 0, _spawnCenter # 1, 0.5]];', spawn)
        queue = self.src('processSiteQueue')
        self.assertIn('"retry"] call A3UE_fnc_fpv_managerDeployStock', queue)
        self.assertIn('["CLEAR", _markerX] call A3UE_fnc_fpv_siteStock', queue)
        origin = self.src('supportResolveOrigin')
        # The changed candidate loop is VM-executable (no continue); the AU carrier loop is untouched.
        self.assertNotIn('continue', origin.split('private _candidates = _planning getOrDefault', 1)[1])
        self.assertIn('"NO_STANDOFF_LAUNCH"', origin)
        launch = self.src('supportLaunch')
        self.assertIn('(_checkedOrigin get "originPosATL") isNotEqualTo (_origin get "originPosATL")', launch)


if __name__ == '__main__':
    unittest.main()
