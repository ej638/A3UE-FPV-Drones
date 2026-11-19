"""1.0.9 friendly FPV swarm, SW-1 (2026-11-17): server core; SW-1g (2026-11-18): the simple attack.
Shipped SQF in SQF-VM through the commitment harness (engine reads/effects substituted), plus
source contracts. These pin decisions for given clocks and positions: reservations, the run-in
gate, the lean dive's limits and fuse, break-offs, the brain's phases and the request's authority
and drone mix. They make no claim about Arma's AI flight, physics, frame times or the look of a
dive: that is the engine card's job."""
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from f2_commitment_vm import VM, FPV, ROOT, script, adapt_helper

SWARM = ['swarmSettings', 'swarmScan', 'swarmAssign', 'swarmSetTask', 'swarmDrop', 'swarmControl',
         'swarmTick', 'swarmDive', 'swarmPass', 'swarmRequest', 'swarmClear', 'swarmFly', 'swarmPose', 'swarmSafe',
         'swarmBrain']
ALL = SWARM + ['swarmNotify', 'swarmLock', 'swarmCall', 'swarmCallReply', 'swarmMenuMark']
# SW-2: the commander-menu wrappers (AU's SCRT_fnc_ui_* names, files in au_menu/).
MENU = ['ui_updateSupportMenu', 'ui_setSupportCostText', 'ui_manageSupportTabEventHandler', 'ui_launchSupport',
        'ui_clearSupport']
CFG = ('class CfgVehicles {class AllVehicles {};class Man: AllVehicles {}; class LandVehicle: AllVehicles {};'
       'class Air: AllVehicles {};class VMMan: Man {};class VMVehicle: LandVehicle {};class VMUAV: Air {};};')


def source(name):
    return (FPV / f'fn_fpv_{name}.sqf').read_text()


def code(name):
    return '\n'.join(line.split('//', 1)[0] for line in source(name).splitlines())


def must(s, old, new, name):
    assert old in s, (name, old)
    return s.replace(old, new)


def adapt(name, s):
    """VM stand-ins for engine commands SQF-VM lacks; every replaced text must exist."""
    if name == 'swarmScan':
        s = must(s, '_center nearEntities [["Man", "LandVehicle", "Ship"], _radius]', '([_center,_radius] call FPV_nearEntities)', name)
        # SW-1f: weapons and gunners are test object variables; BIS_fnc_itemType is a stub (STUBS).
        s = must(s, 'primaryWeapon _target', '(_target getVariable ["primaryWeapon", ""])', name)
        s = must(s, 'alive gunner _target', 'alive (_target getVariable ["gunner", objNull])', name)
        # SW-1h: an autonomous static (SAM, radar) is a test object flag.
        s = must(s, 'unitIsUAV _target', '(_target getVariable ["uav", false])', name)
        # SW-1l: patrol towers are test objects outside the entity list; the deck is an object variable.
        s = must(s, 'nearestObjects [_center, _settings getOrDefault ["stairTowers", []], _radius + 20]', '([_center, _radius + 20] call FPV_towersNear)', name)
        s = must(s, '(_x buildingPos 1)', '(_x getVariable ["buildingPos1", [0, 0, 0]])', name)
    if name == 'swarmAssign':
        s = must(s, '_order sort true;', '_order = _order call FPV_sort;', name)
        s = must(s, '_ranked sort true;', '_ranked = _ranked call FPV_sort;', name)
    if name in ('swarmTick', 'swarmDive', 'swarmAssign'):
        s = s.replace('aimPos _target', '(_target call FPV_aimPos)')
    if name == 'swarmTick':
        s = must(s, 'isServer', 'true', name)
        s = must(s, '_center getDir (getPosASL _uav)', '([_center, getPosASL _uav] call FPV_dirTo)', name)
        s, n = re.subn(r'_center getPos \[_ring, ([^\]]+)\]', r'([_center, _ring, \1] call FPV_relPos)', s)
        assert n == 2, n
        s, n = re.subn(r'_uav enableAI "ALL";.*?_uav setCombatMode "BLUE";', 'FPV_ai pushBack ["SETUP"];', s, flags=re.S)
        assert n == 1, n
        s = must(s, '_uav flyInHeight _height;\n\t_uav forceSpeed _speed;\n\t_uav doMove [_posATL # 0, _posATL # 1, _height];',
                 'FPV_ai pushBack ["MOVE", +_posATL, _height, _speed];', name)
    if name in ('swarmDive', 'swarmFly'):
        s = must(s, '_uav setVelocity _velocity;', 'FPV_moves pushBack +_velocity;', name)
    if name == 'swarmPose':
        s = must(s, '_uav setVectorDirAndUp [_nose, _up # 0];', 'FPV_poses pushBack [diag_frameNo, time, _nose, _up # 0, +_newPath];', name)
    if name == 'swarmSafe':
        # SW-1e: the VM has no entity lists, life states or side relations: test objects stand in.
        # SW-1f: 3D (the stand-in list is flat; the shipped distance check is kept).
        s = must(s, 'nearestObjects [_pos, ["Man", "LandVehicle", "Ship", "StaticWeapon", "Air"], _radius]', '([_pos, _radius] call FPV_nearEntities)', name)
        s = must(s, '(_side getFriend _group) >= 0.6', '(_group in FPV_friends)', name)
        s = must(s, 'typeOf _unit', '(_unit getVariable ["netId", ""])', name)
    if name == 'swarmBrain':
        # SW-1g: the launch schedule. Sleeping advances the test clock; the launch, the lock and HQ's
        # line are recorded; geometry by the stand-ins; no shuffle (the lanes go by launch order).
        s = must(s, 'if (!isServer ||', 'if (!true ||', name)
        s = must(s, '_center getDir _spawn', '([_center, _spawn] call FPV_dirTo)', name)
        s = must(s, '_spawn getDir _center', '([_spawn, _center] call FPV_dirTo)', name)
        s = must(s, '_center getPos [(_settings get "ring") + (_style # 3), _bearing + ((_index - ((_count - 1) / 2)) * 25)]',
                 '([_center, (_settings get "ring") + (_style # 3), _bearing + ((_index - ((_count - 1) / 2)) * 25)] call FPV_relPos)', name)
        s = must(s, '_spawn getPos [abs _lane, _bearing + ([90, -90] select (_lane < 0))]',
                 '([_spawn, abs _lane, _bearing + ([90, -90] select (_lane < 0))] call FPV_relPos)', name)
        s = must(s, 'surfaceIsWater _from && {!surfaceIsWater _spawn}', 'false', name)
        s = must(s, 'floor random (_i + 1)', '_i', name)
        s = must(s, 'selectRandom _pool', '(_pool # 0)', name)
        s = must(s, '_spec call A3UE_fnc_fpv_spawnManagedDrone', '(_spec call FPV_spawn)', name)
        s, n = re.subn(r'_uav addEventHandler \["(IncomingMissile|Killed)", \{.*?\n\t\t\t\}\];', '', s, flags=re.S)
        assert n == 2, n
        s = must(s, '[_uav] remoteExecCall ["A3UE_fnc_fpv_swarmLock", 0, _uav];', 'FPV_locks pushBack _uav;', name)
        s = must(s, '["STR_A3UE_FPV_SWARM_LAUNCHED", [_count]] remoteExecCall ["A3UE_fnc_fpv_swarmNotify", _record get "side"];',
                 'FPV_notes pushBack ["STR_A3UE_FPV_SWARM_LAUNCHED", [_count]];', name)
        s = must(s, 'typeOf _uav', '"VMUAV"', name)
        s = must(s, 'sleep (((_wake - time) max 0.05) min 1.5);', 'FPV_time = FPV_time + (((_wake - time) max 0.05) min 1.5);', name)
    if name == 'swarmControl':
        s = re.sub(r'_x checkAIFeature "(\w+)"', 'true', s)
        s = re.sub(r'(\(_x # 0\)|_unit) (enableAI|disableAI) "(\w+)";', r'FPV_ai pushBack ["\2","\3"];', s)
        s = re.sub(r'_uav forceSpeed ([^;]+);', r'FPV_ai pushBack ["SPEED",\1];', s)
    if name == 'swarmPass':
        s = must(s, 'allPlayers select', 'FPV_players select', name)
        s = must(s, '(_x distance2D _pos)', '((_x call FPV_getPosASL) distance2D _pos)', name)
        s = must(s, '{deleteMarker _x;} forEach (_record get "markers");', 'FPV_deleted append (_record get "markers");', name)
        s, n = re.subn(r'\[("STR_A3UE_FPV_SWARM_\w+"), (\[[^\]]*\])\] remoteExecCall \["A3UE_fnc_fpv_swarmNotify", _record get "side"\];',
                       r'FPV_notes pushBack [\1, \2];', s)
        assert n == 2, n
    if name in ('swarmRequest', 'swarmCall'):
        # SW-2: the menu call's pass for swarmRequest (the VM has no localNamespace).
        s = s.replace('localNamespace', 'missionNamespace')
    if name == 'swarmCall':
        s = must(s, 'if (!isServer ||', 'if (!true ||', name)
        s = must(s, '!isPlayer _requester', '!(_requester getVariable ["isPlayer", false])', name)
        s = must(s, '[_ok, _why, _token] remoteExecCall ["A3UE_fnc_fpv_swarmCallReply", _sender];',
                 'FPV_replies pushBack [_ok, _why, _token, _sender];', name)
        s = must(s, 'publicVariable "supportPoints";', 'FPV_published pushBack "supportPoints";', name)
        s = must(s, '[0, -_money] spawn A3A_fnc_resourcesFIA;', 'FPV_money pushBack (-_money);', name)
    if name == 'swarmRequest':
        s = must(s, 'if (!isServer ||', 'if (!true ||', name)
        s = must(s, 'worldSize', '10000', name)
        s = s.replace('worldSize', '10000')
        s = must(s, 'getMarkerPos _x', '(FPV_markers getOrDefault [_x, [0, 0, 0]])', name)
        s = must(s, '_center getDir _home', '([_center, _home] call FPV_dirTo)', name)
        # SW-1j: a caller on the centre: behind his back (his facing is a test object variable).
        s = must(s, '_center getPos [100, (getDir _requester) + 180]', '([_center, 100, (_requester getVariable ["dir", 0]) + 180] call FPV_relPos)', name)
        s = must(s, '_center getPos [_launchDistance, _bearing]', '([_center, _launchDistance, _bearing] call FPV_relPos)', name)
        s = must(s, '_center getPos [(_settings get "spawnMax") + 300, _bearing]', '([_center, (_settings get "spawnMax") + 300, _bearing] call FPV_relPos)', name)
        s, n = re.subn(r'createMarker \[_area, _center\];.*?setMarkerText \(localize "STR_A3UE_FPV_SWARM_MARKER"\);',
                       'private _label = format ["A3UE_FPV_%1_label", _id]; FPV_madeMarkers append [_area, _label];', s, flags=re.S)
        assert n == 1, n
        s = must(s, '[_id, _roles, _families] spawn A3UE_fnc_fpv_swarmBrain;', 'FPV_brain = [_id, _roles, _families];', name)
    return adapt_helper(name, s)


def load(name):
    return f'A3UE_fnc_fpv_{name}={{{adapt(name, source(name))}}};\n'


STUBS = r'''
FPV_sort={private _a=+_this; for "_i" from 1 to ((count _a)-1) do {private _k=_a # _i; private _j=_i-1;
 while {_j >= 0 && {((_a # _j) # 0) > (_k # 0)}} do {_a set [_j+1,_a # _j]; _j=_j-1;}; _a set [_j+1,_k];}; _a};
FPV_aimPos={(_this call FPV_getPosASL) vectorAdd [0,0,1]};
FPV_itemTypes=createHashMap;BIS_fnc_itemType={["Weapon",[FPV_itemTypes,[_this # 0,"AssaultRifle"]] call FPV_getOrDefault]};
FPV_relPos={params ["_p","_d","_h"];[(_p # 0)+_d*(sin _h),(_p # 1)+_d*(cos _h),0]};
FPV_dirTo={params ["_a","_b"];private _d=((_b # 0)-(_a # 0)) atan2 ((_b # 1)-(_a # 1));if (_d < 0) then {_d=_d+360};_d};
FPV_ai=[];FPV_notes=[];FPV_retired=[];FPV_strikes=[];FPV_commit=true;FPV_players=[];FPV_deleted=[];FPV_madeMarkers=[];
FPV_markers=createHashMap;FPV_brain=[];FPV_collision="CLEARANCE";FPV_locks=[];
FPV_towerList=[];FPV_towersNear={params ["_c","_r"];FPV_towerList select {((_x getVariable ["position",[0,0,0]]) distance2D _c) <= _r}};
A3UE_fnc_fpv_applyTargetability={true};
// SW-1d: the ground under the swarm's own cruise (sea level unless a test raises it).
FPV_groundRule={0};FPV_getTerrainHeightASL={_this call FPV_groundRule};
// SW-1b: the shipped ray helper is kept as FPV_clearReal (its own test); the others get a stand-in
// that records each call ([uav, target, from, to]) and answers "blocked" while FPV_blocked, else
// whatever FPV_clearRule says. SW-1g: only the roof check and the cruise's look-ahead ask.
FPV_clearReal=A3UE_fnc_fpv_swarmClear;FPV_clearCalls=[];FPV_clearRule={[]};
A3UE_fnc_fpv_swarmClear={FPV_clearCalls pushBack +_this;if (FPV_blocked) then {[[0,0,0],"VMWall"]} else {_this call FPV_clearRule}};
// SW-1e: the swarm's friendly check; the shipped one is kept as FPV_safeReal (its own test).
FPV_safeReal=A3UE_fnc_fpv_swarmSafe;FPV_friends=[];
A3UE_fnc_fpv_swarmSafe={if (FPV_targetSafe) then {""} else {"VMFriend/GUER/free"}};
A3UE_fnc_fpv_cleanupDrone={FPV_retired pushBack (_this # 0);(_this # 0) setVariable ["A3UE_FPV_managed",false];true};
A3UE_fnc_fpv_detonateCompat={FPV_strikes pushBack [_this # 2,_this # 4];
 if (FPV_commit) then {(_this # 0) setVariable ["A3UE_FPV_detonating",true];};FPV_commit};
private _swarmDrone={params ["_id","_pos","_role","_task"];private _d=["VMUAV",_id] call _make;
 {_d setVariable [_x # 0,_x # 1];} forEach [["A3UE_FPV_managed",true],["A3UE_FPV_controllerRunning",true],["A3UE_FPV_netId",_id],
  ["A3UE_FPV_controllerIdentity",[1,2,1,1]],["A3UE_FPV_controllerGeneration",1],["A3UE_FPV_swarmId","swarm1"],
  ["A3UE_FPV_swarmTask",_task],["A3UE_FPV_payloadRole",_role],["A3UE_FPV_vendorId","armafpv"],["position",_pos],
  ["side",independent],["velocity",[-15,0,0]]];_d};
private _enemy={params ["_id","_class","_pos",["_kinds",[]]];private _o=[_class,_id] call _make;
 _o setVariable ["position",_pos];_o setVariable ["side",west];_o setVariable ["velocity",[0,0,0]];
 if (_class=="VMVehicle") then {private _c="VMMan" createVehicle [0,0,0];_c setVariable ["side",west];_c setVariable ["netId",_id+"c"];
  _o setVariable ["crew",[_c]];_o setVariable ["commander",_c];};
 if (_kinds isNotEqualTo []) then {_o setVariable ["kinds",(_o getVariable ["kinds",[]])+_kinds];};_o};
private _newRecord={params [["_drones",[]],["_phase","ON_STATION"]];
 private _r=createHashMapFromArray [["id","swarm1"],["center",[1000,1000,0]],["side",independent],["hidden",createHashMap],
  ["drones",_drones],["nextGoAt",0],["strikes",0],["breaks",0],["drops",0],["returned",0],["divePerf",[0,0,0]],
  ["phase",_phase],["createdAt",FPV_time],["arrivedAt",FPV_time],["lastTargetAt",FPV_time],["leaveAt",-1],["leaveReason",""],
  ["markers",["mA","mB"]],["exit",[1000,2800,0]],["launched",count _drones],["size",count _drones]];
 missionNamespace setVariable ["A3UE_FPV_swarms",createHashMapFromArray [["swarm1",_r]]];
 missionNamespace setVariable ["A3UE_FPV_swarmActive","swarm1"];_r};
private _settings={missionNamespace setVariable ["A3UE_FPV_swarmSettingsCache",[]];call A3UE_fnc_fpv_swarmSettings};
private _tick={params ["_d","_state"];[_d,_state,[1,2,1,1],1] call A3UE_fnc_fpv_swarmTick};
// One frame of flight: the next tick, then the drone moves by the velocity it was given.
private _fly={params ["_d","_state",["_dt",0.02]];FPV_time=FPV_time+_dt;FPV_frame=FPV_frame+1;FPV_observed=FPV_observed+_dt;
 private _n=count FPV_moves;private _r=[_d,_state] call _tick;
 if (count FPV_moves > _n) then {private _v=FPV_moves select ((count FPV_moves)-1);_d setVariable ["velocity",_v];
  _d setVariable ["position",(_d getVariable "position") vectorAdd (_v vectorMultiply _dt)];};_r};
'''


def run(body, timeout=180):
    # SW-2: the swarm size is a CBA setting read through userSetting.
    extra = ''.join(load(n) for n in SWARM + ['swarmCall', 'userSetting']) + STUBS
    text = script(body, extra)
    with tempfile.TemporaryDirectory(prefix='fpv-swarm-') as d:
        p = Path(d) / 'test.sqf'
        p.write_text(text)
        c = Path(d) / 'config.cpp'
        c.write_text(CFG)
        return subprocess.run([VM, '-a', '--suppress-welcome', '--no-execute-print', '--no-work-print',
                               '-m', '5000000', '--input-config', str(c), '-i', str(p)],
                              capture_output=True, text=True, timeout=timeout)


@unittest.skipUnless(VM and Path(VM).is_file(), 'FPV_SQFVM offline interpreter not configured')
class SwarmSQF(unittest.TestCase):
    def sqf(self, body):
        r = run(body)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('COMMITMENT_TEST_OK', r.stdout, r.stdout[-6000:] + r.stderr)
        self.assertNotIn('[ERR]', r.stdout, r.stdout[-6000:])
        return r.stdout

    def test_settings_defaults_and_clamps(self):
        self.sqf(r'''
private _s=call _settings;
[(_s get "size")==7 && {(_s get "maxAT")==4} && {(_s get "radius")==300} && {(_s get "idleS")==60}
 && {(_s get "stationS")==360} && {(_s get "spacing")==15} && {(_s get "safety")==15},"defaults (EJ: seven; SW-1j spacing 15; SW-1g a minute idle; SW-1i four AT)"] call _assert;
[(_s get "diveAngle")==40 && {(_s get "diveFacing")==30} && {(_s get "stagger")==0.6} && {(_s get "maxTries")==2} && {(_s get "triesS")==600}
 && {(_s get "launchGap")==1.5} && {(_s get "trailS")==14} && {(_s get "tapGap")==3},"SW-1g/1h/1i: the simple gate, the tries, the launch groups, the tap gap"] call _assert;
// SW-1i (SW1h: SAMs shot down 17 drones from 1058-1276 m; Arma's MIM-145 and S-750 do not fire inside 1000 m).
[(_s get "spawnMin")==600 && {(_s get "spawnMax")==750},"launch 600-750 m out"] call _assert;
// SW-1j (EJ after SW1i: "spawn behind the commander and fly over his head").
[(_s get "behindM")==200,"launch 200 m behind the caller"] call _assert;
[(_s get "tapRadius")==25,"SW-1j: dives at neighbours within 25 m a tap gap apart"] call _assert;
[(_s get "stairM")==6 && {"Cargo_Patrol_base_F" in (_s get "stairTowers")} && {"Land_Cargo_Patrol_V3_ruins_F" in (_s get "stairTowers")},"SW-1l: patrol tower stairs"] call _assert;
[(_s get "lastS")==10,"SW-1m: the stairs men are the last resort after 10 s with nothing else"] call _assert;
// SW-1g (EJ after SW1f: "not picky about obstacles"): the corridor, commit, passes and look-ahead are gone.
{[!(_x in _s),"gone: "+_x] call _assert;} forEach ["clearance","blockedGate","lookAheadS","passLead","passTurn","passRotate",
 "passDrop","passLow","passGiveUp","passEntry","patienceS","visMin","forceAngle","coverWaitS","diveGate","passBeyond","passAhead","laneFar","laneNear","maxStrikes"];
[(_s get "ring")==120 && {(_s get "loiterSpeed")==18} && {(_s get "runInS")==75}
 && {(_s get "pushRate")==30} && {(_s get "pushRamp")==150} && {(_s get "pushAccel")==3}
 && {count (_s get "styleHeights")==8} && {count (_s get "styleLanes")==8}
 && {count (_s get "styleSpeeds")==8} && {count (_s get "styleRings")==8},"ring, push-over, style"] call _assert;
[(_s get "runSpeed")==22 && {(_s get "runTurn")==75} && {(_s get "climb")==6} && {(_s get "floorAGL")==25}
 && {(_s get "returnM")==150} && {(_s get "arriveM")==40},"SW-1d: the swarm's own cruise"] call _assert;
[(_s get "turnAccel")==120 && {(_s get "latAccel")==15} && {(_s get "brakeTurn")==60} && {(_s get "turnSpeed")==12} && {(_s get "diveBank")==12},"SW-1f: turns, dive bank"] call _assert;
[((_s get "speeds") get "armafpv") isEqualTo [34,32],"dive table"] call _assert;
missionNamespace setVariable ["A3UE_FPV_swarmSize",12];missionNamespace setVariable ["A3UE_FPV_swarmMaxAT","lots"];
missionNamespace setVariable ["A3UE_FPV_swarmRadius",5];
_s=call _settings;
[(_s get "size")==8 && {(_s get "maxAT")==4} && {(_s get "radius")==100},"clamped and defaulted"] call _assert;
missionNamespace setVariable ["A3UE_FPV_swarmSize",1.4];
[((call _settings) get "size")==3,"at least three"] call _assert;
''')

    def test_scan_classes_hidden_area_and_sides(self):
        out = self.sqf(r'''
private _rec=[] call _newRecord;
["m1","VMMan",[1010,1000,0]] call _enemy;
["t1","VMVehicle",[1100,1000,0],["Tank"]] call _enemy;
["s1","VMVehicle",[1000,1150,0],["StaticWeapon"]] call _enemy;
["c1","VMVehicle",[1000,900,0]] call _enemy;
["far","VMMan",[1400,1000,0]] call _enemy;
private _own=["own","VMMan",[1005,1000,0]] call _enemy;_own setVariable ["side",independent];
private _hid=["hid","VMMan",[1020,1000,0]] call _enemy;(_rec get "hidden") set ["hid",FPV_time+5];
private _dead=["dead","VMMan",[1030,1000,0]] call _enemy;_dead setVariable ["alive",false];
private _empty=["empty","VMVehicle",[1040,1000,0]] call _enemy;_empty setVariable ["crew",[]];_empty setVariable ["commander",objNull];
// SW-1f (EJ after SW1e: "manned machine guns"): a machine gunner, an armed vehicle with its gunner.
private _m1=FPV_objects select {(_x getVariable ["netId",""])=="m1"};(_m1 # 0) setVariable ["primaryWeapon","VM_Rifle"];
private _mg=["mg1","VMMan",[1015,1000,0]] call _enemy;_mg setVariable ["primaryWeapon","VM_MMG"];FPV_itemTypes set ["VM_MMG","MachineGun"];
private _gunner="VMMan" createVehicle [0,0,0];_gunner setVariable ["side",west];
private _g1=["g1","VMVehicle",[1000,950,0]] call _enemy;_g1 setVariable ["gunner",_gunner];
// SW-1h (EJ after SW1g: AP hits on the SAM and radar did nothing): an autonomous static is a SYSTEM.
private _sam=["sam","VMVehicle",[1050,1050,0],["StaticWeapon"]] call _enemy;_sam setVariable ["uav",true];
// SW-1m (EJ after SW1l: the seaport's gunboat "was the most deadly threat" and was never targeted):
// boats are seen; a gunboat with its gunner is an armed vehicle, a crewed boat without one a vehicle.
private _boatGunner="VMMan" createVehicle [0,0,0];_boatGunner setVariable ["side",west];
private _gb=["gb","VMVehicle",[1100,1100,0],["Ship"]] call _enemy;_gb setVariable ["gunner",_boatGunner];
["rhib","VMVehicle",[1100,900,0],["Ship"]] call _enemy;
private _c=[_rec,call _settings] call A3UE_fnc_fpv_swarmScan;
private _seen=_c apply {[(_x # 0) getVariable "netId",_x # 1]};
diag_log str _seen;
[count _c==9,"nine legal targets"] call _assert;
{[_x in _seen,str _x] call _assert;} forEach [["m1","MAN"],["mg1","MG"],["t1","ARMOR"],["s1","STATIC"],["g1","GUN"],["c1","VEHICLE"],["sam","SYSTEM"],
 ["gb","GUN"],["rhib","VEHICLE"]];
[(_c findIf {_x # 3}) < 0,"no last resort among them"] call _assert;
// A dead gunner: just a vehicle. The weapon type is looked up once per class.
_gunner setVariable ["alive",false];FPV_itemTypes set ["VM_MMG","AssaultRifle"];
_c=[_rec,call _settings] call A3UE_fnc_fpv_swarmScan;_seen=_c apply {[(_x # 0) getVariable "netId",_x # 1]};
[["g1","VEHICLE"] in _seen && {["mg1","MG"] in _seen},"remembered weapon type; a dead gunner: "+str _seen] call _assert;
FPV_time=FPV_time+6;
[count ([_rec,call _settings] call A3UE_fnc_fpv_swarmScan)==10,"a hidden target comes back"] call _assert;
// SW-1l (EJ after SW1k: "the guy on the stairs always survives ... not the regular infantry standing on
// the stairs"): a patrol tower (deck 4.6 m) and a ruin, found once per swarm. SW-1m (EJ after SW1l):
// the men on the stairs are passed on as the last resort (swarmAssign); on the deck, on the ground
// beside it, off the ground away from it, the gun: ordinary targets.
{deleteVehicle _x;} forEach FPV_objects;FPV_objects=[];
_rec=[] call _newRecord;
private _tower="VMVehicle" createVehicle [0,0,0];_tower setVariable ["position",[1100,1000,0]];_tower setVariable ["buildingPos1",[1100,1001,4.6]];
private _ruin="VMVehicle" createVehicle [0,0,0];_ruin setVariable ["position",[900,1000,0]];
FPV_towerList=[_tower,_ruin];
["stair","VMMan",[1103,1000,2.5]] call _enemy;
["deck","VMMan",[1100,1001,4.6]] call _enemy;
["foot","VMMan",[1104,1000,0]] call _enemy;
["wall","VMMan",[1150,1000,2.5]] call _enemy;
["gun","VMVehicle",[1100,1002,4.6],["StaticWeapon"]] call _enemy;
["rstair","VMMan",[902,1000,3]] call _enemy;
_c=[_rec,call _settings] call A3UE_fnc_fpv_swarmScan;_seen=_c apply {[(_x # 0) getVariable "netId",_x # 3]};
diag_log str _seen;
[count _c==6 && {["stair",true] in _seen} && {["rstair",true] in _seen},"men on the stairs: the last resort: "+str _seen] call _assert;
{[[_x,false] in _seen,"an ordinary target: "+_x+" "+str _seen] call _assert;} forEach ["deck","foot","wall","gun"];
FPV_towerList=[];
_c=[_rec,call _settings] call A3UE_fnc_fpv_swarmScan;_seen=_c apply {[(_x # 0) getVariable "netId",_x # 3]};
[["stair",true] in _seen,"the towers are remembered for the swarm"] call _assert;
''')
        self.assertRegex(out, r'swarm id=swarm1 event=TOWERS count=2 deckM=\[4\.6,1000\]')
        self.assertRegex(out, r'event=STAIRS target=stair class=MAN atlM=2\.5')
        self.assertRegex(out, r'event=STAIRS target=rstair class=MAN atlM=3')
        self.assertEqual(len(re.findall(r'event=STAIRS target=stair ', out)), 1, 'once per man')

    def test_one_target_per_drone_spacing_roles_and_stagger(self):
        out = self.sqf(r'''
private _d1=["d1",[1200,1000,70],"AP","LOITER"] call _swarmDrone;
private _d2=["d2",[1000,1200,70],"AP","LOITER"] call _swarmDrone;
private _d3=["d3",[800,1000,70],"AP","LOITER"] call _swarmDrone;
private _rec=[[_d1,_d2,_d3]] call _newRecord;
["a","VMMan",[1000,1000,0]] call _enemy;
["b","VMMan",[1005,1000,0]] call _enemy;
["c","VMMan",[1060,1000,0]] call _enemy;
["t","VMVehicle",[1100,1000,0],["Tank"]] call _enemy;
private _s=call _settings;
private _n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
private _targets=[_d1,_d2,_d3] apply {_x getVariable ["A3UE_FPV_targetNetId",""]};
diag_log str _targets;
[_n==2,format ["two reservations, got %1",_n]] call _assert;
[!("t" in _targets),"anti-personnel never takes armour"] call _assert;
[!("a" in _targets && {"b" in _targets}),"5 m apart: one warhead, one drone"] call _assert;
["c" in _targets,"the spaced target is taken"] call _assert;
private _idle=[_d1,_d2,_d3] select {(_x getVariable "A3UE_FPV_swarmTask")=="LOITER"};
[count _idle==1,"the third drone waits (nothing left for it)"] call _assert;
private _go=([_d1,_d2,_d3] - _idle) apply {_x getVariable "A3UE_FPV_swarmGoAt"};
_go sort true;
[abs ((_go # 1)-(_go # 0)-0.6) < 0.001,str _go] call _assert;
[([_d1,_d2,_d3] - _idle) findIf {(_x getVariable "A3UE_FPV_mode")!="TRACKING"} < 0,"attacking drones show TRACKING"] call _assert;
// An anti-tank drone takes the armour first.
private _d4=["d4",[1000,800,70],"AT","LOITER"] call _swarmDrone;(_rec get "drones") pushBack _d4;
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[(_d4 getVariable "A3UE_FPV_targetNetId")=="t","anti-tank prefers armour"] call _assert;
// Nothing held is reserved twice; a free drone 800 m out is not used yet.
private _d5=["d5",[1800,1000,70],"AP","INBOUND"] call _swarmDrone;(_rec get "drones") pushBack _d5;
["e","VMMan",[950,1000,0]] call _enemy;
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[(_d5 getVariable ["A3UE_FPV_targetNetId",""])=="","beyond engage range"] call _assert;
private _all=([_d1,_d2,_d3,_d4] apply {_x getVariable ["A3UE_FPV_targetNetId",""]}) select {_x != ""};
[count _all==count (_all arrayIntersect _all),"no target held twice: "+str _all] call _assert;
// SW-1j (EJ after SW1j: "theres still 2-3 left that were kind of close"): spacing 15, so two men 18 m
// apart are both taken (their dives go in a tap gap apart, swarmTick).
{deleteVehicle _x;} forEach FPV_objects;FPV_objects=[];
private _e1=["e1",[1200,1000,70],"AP","LOITER"] call _swarmDrone;
private _e2=["e2",[1200,1010,70],"AP","LOITER"] call _swarmDrone;
_rec=[[_e1,_e2]] call _newRecord;
["p","VMMan",[1000,1000,0]] call _enemy;["q","VMMan",[1000,1018,0]] call _enemy;
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[_n==2,format ["18 m apart: both taken, got %1",_n]] call _assert;
''')
        self.assertRegex(out, r'swarm id=swarm1 event=RESERVE drone=d\d role=AP target=\w class=MAN')

    def test_machine_guns_first_and_a_roofed_static_at_once(self):
        out = self.sqf(r'''
// SW-1f (EJ after SW1e: "increase target priority for manned machine guns ... then infantry"): an
// anti-personnel drone takes the static gun, even under a roof, before a machine gunner, and him
// before a rifleman; an anti-tank drone takes an armed vehicle before an unarmed one.
private _d1=["d1",[1000,1100,70],"AP","LOITER"] call _swarmDrone;
private _rec=[[_d1]] call _newRecord;
private _a=["a","VMMan",[1000,1040,0]] call _enemy;
private _b=["b","VMMan",[1060,1000,0]] call _enemy;_b setVariable ["primaryWeapon","VM_LMG"];FPV_itemTypes set ["VM_LMG","MachineGun"];
private _st=["st","VMVehicle",[940,1000,0],["StaticWeapon"]] call _enemy;
FPV_clearRule={if ((((_this # 1) getVariable "netId")=="st") && {((_this # 3) # 2) > ((_this # 2) # 2)}) then {[[0,0,0],"VMRoof"]} else {[]}};
private _s=call _settings;
private _n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[_n==1 && {(_d1 getVariable "A3UE_FPV_targetNetId")=="st"},"the static gun under a roof, at once: "+(_d1 getVariable ["A3UE_FPV_targetNetId",""])] call _assert;
private _d2=["d2",[1000,1100,70],"AP","LOITER"] call _swarmDrone;(_rec get "drones") pushBack _d2;
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[(_d2 getVariable "A3UE_FPV_targetNetId")=="b","then the machine gunner, farther than the rifleman"] call _assert;
private _d3=["d3",[1000,1100,70],"AP","LOITER"] call _swarmDrone;(_rec get "drones") pushBack _d3;
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[(_d3 getVariable "A3UE_FPV_targetNetId")=="a","then the rifleman"] call _assert;
// Anti-tank: the armed car before the truck nearer to it.
private _gunner="VMMan" createVehicle [0,0,0];_gunner setVariable ["side",west];
private _g=["g","VMVehicle",[1100,1250,0]] call _enemy;_g setVariable ["gunner",_gunner];
private _t=["t","VMVehicle",[1050,1200,0]] call _enemy;
private _d4=["d4",[1000,1200,70],"AT","LOITER"] call _swarmDrone;(_rec get "drones") pushBack _d4;
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[(_d4 getVariable "A3UE_FPV_targetNetId")=="g","anti-tank: the armed vehicle first"] call _assert;
''')
        self.assertRegex(out, r'event=RESERVE drone=d1 role=AP target=st class=STATIC distM=\d+ goInS=\S+ covered=1')
        self.assertRegex(out, r'event=RESERVE drone=d2 role=AP target=b class=MG distM=\d+ goInS=\S+ covered=0')
        self.assertRegex(out, r'event=RESERVE drone=d4 role=AT target=g class=GUN')

    def test_systems_are_anti_tank_work_and_anti_tank_drones_stay_on_armour(self):
        out = self.sqf(r'''
// SW-1h (EJ after SW1g): "there was an AA launcher and radar. I saw multiple drone strikes on these and
// they remained functional ... If they were AP, they shouldn't be going for those ... I think AT can go
// for those". SW-1i (EJ after SW1h): "the AT drones can keep going for the high value targets until
// they are no longer a valid target" (an APC took six AT drones before it went).
private _ap=["ap",[1000,1300,70],"AP","LOITER"] call _swarmDrone;
private _rec=[[_ap]] call _newRecord;
private _sam=["sam","VMVehicle",[1000,1050,0],["StaticWeapon"]] call _enemy;_sam setVariable ["uav",true];
private _s=call _settings;
private _n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[_n==0 && {(_ap getVariable ["A3UE_FPV_targetNetId",""])==""},"anti-personnel never takes a SAM or radar"] call _assert;
// Anti-tank drones choose first (SW1h swarm 7: both took men with the APC in the circle): an
// anti-personnel drone nearer the centre does not get the man beside the APC first and block it.
private _apc=["apc","VMVehicle",[1100,1000,0],["Wheeled_APC_F"]] call _enemy;
["near","VMMan",[1110,1000,0]] call _enemy;
private _ap2=["ap2",[1100,1050,70],"AP","LOITER"] call _swarmDrone;
private _at1=["at1",[1100,1300,70],"AT","LOITER"] call _swarmDrone;private _at2=["at2",[1100,1310,70],"AT","LOITER"] call _swarmDrone;
private _at3=["at3",[1100,1320,70],"AT","LOITER"] call _swarmDrone;
(_rec get "drones") append [_ap2,_at1,_at2,_at3];
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
private _t=[_at1,_at2,_at3] apply {_x getVariable ["A3UE_FPV_targetNetId",""]};
[_t isEqualTo ["apc","apc","apc"],"all three anti-tank drones on the APC, before the SAM: "+str _t] call _assert;
private _go=[_at1,_at2,_at3] apply {_x getVariable "A3UE_FPV_swarmGoAt"};
[abs ((_go # 1)-(_go # 0)-0.6) < 0.001 && {abs ((_go # 2)-(_go # 1)-0.6) < 0.001},"in turn: "+str _go] call _assert;
[(_ap2 getVariable ["A3UE_FPV_targetNetId",""])=="","10 m from the APC under attack: not taken"] call _assert;
// The APC gone: they take what is left (the SAM).
_apc setVariable ["alive",false];
{_x setVariable ["A3UE_FPV_swarmTask","LOITER"];_x setVariable ["A3UE_FPV_targetNetId",""];} forEach [_at1,_at2,_at3];
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[(_at1 getVariable ["A3UE_FPV_targetNetId",""])=="sam","then the SAM: "+(_at1 getVariable ["A3UE_FPV_targetNetId",""])] call _assert;
// A friendly break in the dive gives the try back.
private _d=["d1",[1080,800,70],"AP","ATTACK"] call _swarmDrone;(_rec get "drones") pushBack _d;
["m","VMMan",[1000,800,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];
private _state=createHashMap;
[_d,_state] call _tick;
[(((missionNamespace getVariable "A3UE_FPV_swarmTries") get "m") # 0)==1,"one try"] call _assert;
FPV_targetSafe=false;FPV_time=FPV_time+1.1;[_d,_state] call _fly;
[(((missionNamespace getVariable "A3UE_FPV_swarmTries") get "m") # 0)==0,"called off for a friendly: not a try"] call _assert;
''')
        self.assertRegex(out, r'event=RESERVE drone=at1 role=AT target=apc class=ARMOR distM=\d+ goInS=\S+ covered=0 heavy=2')
        self.assertRegex(out, r'event=RESERVE drone=at2 role=AT target=apc class=ARMOR')
        self.assertRegex(out, r'event=RESERVE drone=at3 role=AT target=apc class=ARMOR')
        self.assertRegex(out, r'event=RESERVE drone=at1 role=AT target=sam class=SYSTEM distM=\d+ goInS=\S+ covered=0 heavy=1')
        self.assertRegex(out, r'event=WAIT free=1 candidates=1 unsafe=0 triedOut=0 classes=SYSTEM:1 why=(?!\w)')
        self.assertRegex(out, r'event=BREAK drone=d1 target=m reason=FRIENDLY_NEAR')

    def test_reservation_checks_friendlies_roof_order_and_strike_cap(self):
        out = self.sqf(r'''
private _d1=["d1",[1200,1000,70],"AP","INBOUND"] call _swarmDrone;_d1 setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];
private _rec=[[_d1]] call _newRecord;
["a","VMMan",[1000,1000,0]] call _enemy;
private _s=call _settings;
FPV_targetSafe=false;
private _n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[_n==0 && {([(_rec get "hidden"),["a",0]] call FPV_getOrDefault) > FPV_time},"friendlies near: no reservation, hidden"] call _assert;
[FPV_clearCalls isEqualTo [],"no ray for a target that is not safe"] call _assert;
// SW-1g (EJ after SW1f: "not picky about obstacles"): under a roof and nothing else there: taken at
// once, even by a drone still flying in (SW-1c made it circle 15 s first, and only on the ring).
FPV_targetSafe=true;(_rec get "hidden") deleteAt "a";FPV_blocked=true;
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[_n==1 && {(_d1 getVariable "A3UE_FPV_targetNetId")=="a"},"under a roof: taken at once"] call _assert;
private _c=FPV_clearCalls # 0;
[(_c # 2) isEqualTo [1000,1000,1] && {(_c # 3) isEqualTo [1000,1000,31]} && {count _c==4},"one ray 30 m straight up: "+str _c] call _assert;
// An open target still goes first, even one that ranks lower by distance; the roof answer is remembered.
private _d2=["d2",[1200,1100,70],"AP","LOITER"] call _swarmDrone;
(_rec get "drones") pushBack _d2;
["b","VMMan",[1000,1100,0]] call _enemy;["c","VMMan",[1150,850,0]] call _enemy;
FPV_blocked=false;
FPV_clearRule={if ((((_this # 1) getVariable "netId") in ["b"]) && {((_this # 3) # 2) > ((_this # 2) # 2)}) then {[[0,0,0],"VMRoof"]} else {[]}};
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[(_d2 getVariable "A3UE_FPV_targetNetId")=="c","the open one first: "+str (_d2 getVariable "A3UE_FPV_targetNetId")] call _assert;
// SW-1h: a man or a static dived at twice and still there (in a house, in a tower) is left alone for
// ten minutes by every swarm; an expired count does not; a vehicle never is.
private _d3=["d3",[1000,1300,70],"AP","LOITER"] call _swarmDrone;(_rec get "drones") pushBack _d3;
{_x setVariable ["A3UE_FPV_swarmTask","LOITER"];_x setVariable ["A3UE_FPV_targetNetId",""];} forEach [_d1,_d2];
missionNamespace setVariable ["A3UE_FPV_swarmTries",createHashMapFromArray [["b",[2,FPV_time+600]],["a",[1,FPV_time+600]],["c",[2,FPV_time+600]]]];
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
private _t=[_d1,_d2,_d3] apply {_x getVariable ["A3UE_FPV_targetNetId",""]};
[_n==1 && {"a" in _t} && {!("b" in _t)} && {!("c" in _t)},"tried twice: left alone; once: still taken: "+str _t] call _assert;
{_x setVariable ["A3UE_FPV_swarmTask","LOITER"];_x setVariable ["A3UE_FPV_targetNetId",""];} forEach [_d1,_d2,_d3];
(missionNamespace getVariable "A3UE_FPV_swarmTries") set ["a",[2,FPV_time+600]];
(missionNamespace getVariable "A3UE_FPV_swarmTries") set ["c",[2,FPV_time-1]];
private _v=["v","VMVehicle",[1150,1250,0]] call _enemy;
(missionNamespace getVariable "A3UE_FPV_swarmTries") set ["v",[5,FPV_time+600]];
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
_t=[_d1,_d2,_d3] apply {_x getVariable ["A3UE_FPV_targetNetId",""]};
[_n==2 && {"c" in _t} && {"v" in _t} && {!("a" in _t)} && {!("b" in _t)},"expired: taken again; a vehicle is never left alone: "+str _t] call _assert;
{_x setVariable ["A3UE_FPV_swarmTask","LOITER"];_x setVariable ["A3UE_FPV_targetNetId",""];} forEach [_d1,_d2,_d3];
_v setVariable ["alive",false];(missionNamespace getVariable "A3UE_FPV_swarmTries") set ["c",[2,FPV_time+600]];
_rec set ["waitAt",0];
_n=[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign;
[_n==0,"nothing left worth a drone"] call _assert;
''')
        self.assertRegex(out, r'event=WAIT free=1 candidates=1 unsafe=1 triedOut=0 classes=MAN:1 why=VMFriend/GUER/free')
        self.assertRegex(out, r'event=RESERVE drone=d1 role=AP target=a class=MAN distM=\d+ goInS=\S+ covered=1')
        self.assertRegex(out, r'event=RESERVE drone=d2 role=AP target=c class=MAN distM=\d+ goInS=\S+ covered=0')
        self.assertRegex(out, r'event=WAIT free=3 candidates=3 unsafe=0 triedOut=3 classes=MAN:3 why=(?!\w)')

    def test_stairs_men_are_the_last_resort(self):
        out = self.sqf(r'''
// SW-1m (EJ after SW1l: two men at a caved-in tower "kept shooting at me" while the drones orbited;
// "if there are really no other targets after a short time, a drone will pick and dive on one of the
// seen but obstructed targets"): a man on the stairs is taken only after 10 s with nothing else.
private _d1=["d1",[1200,1000,70],"AP","LOITER"] call _swarmDrone;
private _d2=["d2",[1000,1200,70],"AP","LOITER"] call _swarmDrone;
private _rec=[[_d1,_d2]] call _newRecord;
private _ruin="VMVehicle" createVehicle [0,0,0];_ruin setVariable ["position",[900,1000,0]];
FPV_towerList=[_ruin];
["s","VMMan",[902,1000,3]] call _enemy;
private _real=["r","VMMan",[1100,1000,0]] call _enemy;
private _s=call _settings;
private _pass={_rec set ["waitAt",0];[_rec,[_rec,_s] call A3UE_fnc_fpv_swarmScan,_s] call A3UE_fnc_fpv_swarmAssign};
private _free={{_x setVariable ["A3UE_FPV_swarmTask","LOITER"];_x setVariable ["A3UE_FPV_targetNetId",""];} forEach [_d1,_d2]};
private _taken={[_d1,_d2] apply {_x getVariable ["A3UE_FPV_targetNetId",""]}};
private _n=call _pass;
[_n==1 && {"r" in (call _taken)} && {!("s" in (call _taken))},"the real target first; the man on the stairs waits: "+str (call _taken)] call _assert;
// The real target is gone: the last resort opens 10 s later, not before.
_real setVariable ["alive",false];call _free;
FPV_time=FPV_time+1;
[(call _pass)==0,"nothing else, just now: wait"] call _assert;
FPV_time=FPV_time+6;
[(call _pass)==0,"6 s: still wait"] call _assert;
// Another target turns up: it is taken, and the wait starts again once it is gone.
private _late=["late","VMMan",[1000,1100,0]] call _enemy;
FPV_time=FPV_time+2;
_n=call _pass;
[_n==1 && {"late" in (call _taken)},"a new real target is taken: "+str (call _taken)] call _assert;
_late setVariable ["alive",false];call _free;
FPV_time=FPV_time+2;
[(call _pass)==0,"the wait starts again"] call _assert;
FPV_time=FPV_time+9.9;
[(call _pass)==0,"9.9 s: still wait"] call _assert;
FPV_time=FPV_time+0.2;
_n=call _pass;
[_n==1 && {"s" in (call _taken)},"10 s with nothing else: the man on the stairs: "+str (call _taken)] call _assert;
// Still at most two dives at him (SW-1h), then left alone.
call _free;
missionNamespace setVariable ["A3UE_FPV_swarmTries",createHashMapFromArray [["s",[2,FPV_time+600]]]];
[(call _pass)==0,"tried twice: left alone"] call _assert;
''')
        self.assertRegex(out, r'event=STAIRS target=s class=MAN atlM=3')
        self.assertRegex(out, r'event=RESERVE drone=d\d role=AP target=r class=MAN distM=\d+ goInS=\S+ covered=0 heavy=0 last=0')
        self.assertRegex(out, r'event=WAIT free=2 candidates=1 unsafe=0 triedOut=0 classes=MAN:1 why= stairs=1 lastInS=10')
        self.assertRegex(out, r'event=WAIT free=2 candidates=1 unsafe=0 triedOut=0 classes=MAN:1 why= stairs=1 lastInS=4')
        self.assertRegex(out, r'event=RESERVE drone=d\d role=AP target=s class=MAN distM=\d+ goInS=\S+ covered=0 heavy=0 last=1')
        self.assertRegex(out, r'event=WAIT free=2 candidates=1 unsafe=0 triedOut=1 classes=MAN:1 why= stairs=1 lastInS=0')

    def test_clear_ray_and_what_blocks(self):
        self.sqf(r'''
private _d=["d1",[1080,1000,70],"AP","ATTACK"] call _swarmDrone;
private _m=["m","VMMan",[1000,1000,0]] call _enemy;
FPV_rays=[];FPV_rayHits=[];
FPV_lineIntersectsSurfaces={FPV_rays pushBack [_this # 0,_this # 1,_this # 2,_this # 3,_this # 6];FPV_rayHits};
// SW-1g: one ray (the roof check, the cruise's look-ahead); the corridor went with the gate.
private _r=[_d,_m,[1000,1000,1],[1000,1000,31]] call FPV_clearReal;
[_r isEqualTo [] && {count FPV_rays==1},"clear: one ray"] call _assert;
[((FPV_rays # 0) # 0) isEqualTo [1000,1000,1] && {((FPV_rays # 0) # 1) isEqualTo [1000,1000,31]}
 && {((FPV_rays # 0) # 2) isEqualTo _d} && {((FPV_rays # 0) # 3) isEqualTo _m} && {((FPV_rays # 0) # 4)=="GEOM"},"GEOM, the drone and target ignored"] call _assert;
FPV_rays=[];
[([_d,_m,[1000,1000,1],[1000,1000,1.2]] call FPV_clearReal) isEqualTo [] && {FPV_rays isEqualTo []},"too short to ask"] call _assert;
// The target, anyone in it and the drone never block; anything else does, the ground included.
private _gunner="VMMan" createVehicle [0,0,0];_gunner setVariable ["parent",_m];
FPV_rayHits=[[[1,1,1],[0,0,1],_m,objNull],[[2,2,2],[0,0,1],_gunner,objNull],[[3,3,3],[0,0,1],_d,objNull]];
_r=[_d,_m,[1080,1000,70],[1000,1000,1]] call FPV_clearReal;
[_r isEqualTo [],"target, crew and drone ignored: "+str _r] call _assert;
private _wall="VMVehicle" createVehicle [0,0,0];
FPV_rayHits=[[[1,1,1],[0,0,1],_m,objNull],[[4,4,4],[0,0,1],_wall,objNull]];
_r=[_d,_m,[1080,1000,70],[1000,1000,1]] call FPV_clearReal;
// (Arma names it by typeOf, or the terrain object's own name; SQF-VM has no class names, so the name.)
[(_r # 0) isEqualTo [4,4,4] && {(_r # 1) != ""} && {(_r # 1) != "terrain"},"a wall blocks: "+str _r] call _assert;
FPV_rayHits=[[[5,5,5],[0,0,1],objNull,objNull]];
_r=[_d,_m,[1080,1000,70],[1000,1000,1]] call FPV_clearReal;
[(_r # 1)=="terrain","the ground blocks"] call _assert;
''')

    def test_run_in_waits_for_its_turn_then_dives_at_the_gate(self):
        out = self.sqf(r'''
private _d=["d1",[1250,1000,70],"AP","ATTACK"] call _swarmDrone;
private _rec=[[_d]] call _newRecord;
["m","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];
_d setVariable ["A3UE_FPV_swarmGoAt",FPV_time+1];
private _state=createHashMap;
private _toAim={FPV_clearCalls select {((_x # 3) vectorDistance [1000,1000,1]) < 0.01}};
// 250 m out at 70 m: 15.6 degrees, not yet. The swarm flies the run-in itself (SW-1d): no AI orders.
private _r=[_d,_state] call _tick;
[_r isEqualTo [0.02,true],str _r] call _assert;
[count (_d getVariable ["A3UE_FPV_nativeControl",[]])==3 && {(FPV_ai select {(_x # 0)=="MOVE"}) isEqualTo []},"the swarm holds the airframe; no AI order"] call _assert;
FPV_time=FPV_time+0.02;[_d,_state] call _tick;
private _v=FPV_moves select ((count FPV_moves)-1);
[(_v # 0) < -14 && {abs (_v # 1) < 0.01},"flying straight at it: "+str _v] call _assert;
// 80 m out: 41 degrees below, but not its turn yet.
_d setVariable ["position",[1080,1000,70]];
FPV_time=FPV_time+0.02;_r=[_d,_state] call _tick;
[(_d getVariable "A3UE_FPV_swarmTask")=="ATTACK","waits for its stagger"] call _assert;
// Its turn, but 120 m out: 30 degrees (SW1: 18). It flies on.
FPV_time=FPV_time+1.1;
_d setVariable ["position",[1120,1000,70]];
_r=[_d,_state] call _tick;
[(_d getVariable "A3UE_FPV_swarmTask")=="ATTACK","not steep enough yet"] call _assert;
// SW-1g (EJ after SW1f: "not picky about obstacles"): at the gate it dives, whatever is in the way.
FPV_blocked=true;
_d setVariable ["position",[1080,1000,70]];
FPV_time=FPV_time+0.02;_r=[_d,_state] call _tick;
[_r isEqualTo [0.02,true] && {(_d getVariable "A3UE_FPV_swarmTask")=="DIVE"},"dives with cover on the line: "+str _r] call _assert;
[(call _toAim) isEqualTo [],"no corridor or sight check to the aim point"] call _assert;
[(_d getVariable "A3UE_FPV_mode")=="TERMINAL_VECTOR","dive shows TERMINAL_VECTOR"] call _assert;
[count (_d getVariable ["A3UE_FPV_nativeControl",[]])==3,"the dive holds the airframe"] call _assert;
[count (_d getVariable "A3UE_FPV_swarmDive")==12,"the dive record"] call _assert;
// Friendlies by the target at the gate: no dive, the target hidden 20 s, the AI back on the ring.
// (SW-1j: 40 m from the man just dived at, beyond "tapRadius", so no tap gap holds it first.)
private _d2=["d2",[1000,1120,70],"AP","ATTACK"] call _swarmDrone;_d2 setVariable ["velocity",[0,-15,0]];(_rec get "drones") pushBack _d2;
["m2","VMMan",[1000,1040,0]] call _enemy;
_d2 setVariable ["A3UE_FPV_targetNetId","m2"];_d2 setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];
private _state2=createHashMap;FPV_targetSafe=false;
[_d2,_state2] call _tick;
[(_d2 getVariable "A3UE_FPV_swarmTask")=="LOITER" && {([(_rec get "hidden"),["m2",0]] call FPV_getOrDefault) >= FPV_time+19.9},"friendlies by the target: no dive"] call _assert;
[_d2,_state2] call _tick;
[(_d2 getVariable ["A3UE_FPV_nativeControl",[]]) isEqualTo [] && {(FPV_ai select {(_x # 0)=="MOVE"}) isNotEqualTo []},"back on the ring, the AI flies it"] call _assert;
''')
        self.assertRegex(out, r'(?m)event=DIVE drone=d1 target=m distM=80 aboveM=69 angle=41 again=0 try=1 tapS=-1$')
        self.assertNotRegex(out, r'GATE_BLOCKED|UNSEEN')
        self.assertRegex(out, r'event=DROP drone=d2 target=m2 reason=FRIENDLY_NEAR hideS=20 why=VMFriend/GUER/free')

    def test_target_behind_is_turned_round_to_never_looped(self):
        out = self.sqf(r'''
// SW-1g: the gate wants the target ahead (within diveFacing of the way the drone flies). Steep below
// but behind it, the drone turns round level first (braking, SW-1f) and only then dives.
private _d=["d1",[1030,1000,70],"AP","ATTACK"] call _swarmDrone;_d setVariable ["velocity",[18,0,0]];
private _rec=[[_d]] call _newRecord;
["m","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];_d setVariable ["A3UE_FPV_swarmTargetClass","MAN"];
private _state=createHashMap;
[_d,_state] call _tick;
[(_d getVariable "A3UE_FPV_swarmTask")=="ATTACK","66 degrees below but behind: no dive yet"] call _assert;
private _n=0;
while {(_d getVariable "A3UE_FPV_swarmTask")=="ATTACK" && {_n < 600}} do {[_d,_state] call _fly;_n=_n+1;};
private _fv=FPV_moves select ((count FPV_moves)-1);
private _p=_d getVariable "position";
private _to=vectorNormalized ([1000,1000,0] vectorDiff [_p # 0,_p # 1,0]);
private _ahead=(vectorNormalized [_fv # 0,_fv # 1,0]) vectorDotProduct _to;
diag_log format ["behind n=%1 pos=%2 v=%3 ahead=%4",_n,_p,_fv,_ahead];
[(_d getVariable "A3UE_FPV_swarmTask")=="DIVE","then dives"] call _assert;
[_ahead >= (cos 30)-0.05,"facing the target when it dives: "+str _ahead] call _assert;
[(_n*0.02) < 8,"round and down in "+str (_n*0.02)+" s"] call _assert;
private _k=0;while {(_d getVariable "A3UE_FPV_swarmTask")=="DIVE" && {!(_d getVariable ["A3UE_FPV_detonating",false])} && {_k < 900}} do {[_d,_state] call _fly;_k=_k+1;};
[count FPV_strikes==1,"and strikes: "+str FPV_strikes] call _assert;
''')
        self.assertRegex(out, r'(?m)event=STRIKE drone=d1 role=AP target=m class=MAN reason=\w+ diveS=\S+ speed=\d+$')

    def test_dives_at_one_target_go_in_a_tap_gap_apart(self):
        out = self.sqf(r'''
// SW-1i (EJ after SW1h: "If we call in 4 AT drones and the vehicle blows up after 1 or 2, the rest can
// just go for other targets"): a second drone at the gate of the same target holds, slowed, until
// "tapGap" s after the first dive started, then dives.
private _d1=["d1",[1080,1000,70],"AT","ATTACK"] call _swarmDrone;
private _d2=["d2",[1000,1080,70],"AT","ATTACK"] call _swarmDrone;_d2 setVariable ["velocity",[0,-15,0]];
private _rec=[[_d1,_d2]] call _newRecord;
["apc","VMVehicle",[1000,1000,0],["Tank"]] call _enemy;
{_x setVariable ["A3UE_FPV_targetNetId","apc"];_x setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];_x setVariable ["A3UE_FPV_swarmTargetClass","ARMOR"];} forEach [_d1,_d2];
private _s1=createHashMap;private _s2=createHashMap;
[_d1,_s1] call _tick;
private _t0=FPV_time;
[(_d1 getVariable "A3UE_FPV_swarmTask")=="DIVE","the first dives at the gate"] call _assert;
private _n=0;
while {_n < 50} do {[_d2,_s2] call _fly;_n=_n+1;};
private _v=FPV_moves select ((count FPV_moves)-1);
[(_d2 getVariable "A3UE_FPV_swarmTask")=="ATTACK","the second holds at the gate"] call _assert;
[(vectorMagnitude _v) <= 12.5,"and slows: "+str (vectorMagnitude _v)] call _assert;
// SW-1j (spacing 15): a man 20 m from the APC waits the gap too, so the APC's blast has gone off
// before the drone on him dives; a man 40 m off is dived at once.
["m1","VMMan",[1000,1020,0]] call _enemy;["m2","VMMan",[1000,1040,0]] call _enemy;
private _d3=["d3",[1080,1020,70],"AP","ATTACK"] call _swarmDrone;
private _d4=["d4",[1080,1040,70],"AP","ATTACK"] call _swarmDrone;
{(_x # 0) setVariable ["A3UE_FPV_targetNetId",_x # 1];(_x # 0) setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];(_x # 0) setVariable ["A3UE_FPV_swarmTargetClass","MAN"];
 (_rec get "drones") pushBack (_x # 0);} forEach [[_d3,"m1"],[_d4,"m2"]];
private _s3=createHashMap;private _s4=createHashMap;
[_d3,_s3] call _tick;[_d4,_s4] call _tick;
[(_d3 getVariable "A3UE_FPV_swarmTask")=="ATTACK","20 m from the APC: holds"] call _assert;
[(_d4 getVariable "A3UE_FPV_swarmTask")=="DIVE","40 m off: dives at once"] call _assert;
FPV_time=_t0+3.05;
[_d2,_s2] call _tick;
[(_d2 getVariable "A3UE_FPV_swarmTask")=="DIVE","then dives, the gap gone"] call _assert;
[_d3,_s3] call _tick;
[(_d3 getVariable "A3UE_FPV_swarmTask")=="ATTACK","the man beside it waits for the second APC dive too"] call _assert;
FPV_time=_t0+6.1;
[_d3,_s3] call _tick;
[(_d3 getVariable "A3UE_FPV_swarmTask")=="DIVE","then dives"] call _assert;
''')
        self.assertRegex(out, r'(?m)event=DIVE drone=d1 target=apc .* try=1 tapS=-1$')
        self.assertRegex(out, r'(?m)event=DIVE drone=d2 target=apc .* try=2 tapS=3\.\d$')
        self.assertRegex(out, r'(?m)event=DIVE drone=d4 target=m2 .* try=1 tapS=-1$')
        self.assertRegex(out, r'(?m)event=DIVE drone=d3 target=m1 .* try=1 tapS=3\.\d$')

    def test_track_line_with_perf_log(self):
        out = self.sqf(r'''
private _d=["d1",[1100,1000,70],"AP","ATTACK"] call _swarmDrone;
private _rec=[[_d]] call _newRecord;
["m","VMMan",[1000,1000,0]] call _enemy;_d setVariable ["A3UE_FPV_targetNetId","m"];
private _pass={[_rec,call _settings] call A3UE_fnc_fpv_swarmPass};
call _pass;
missionNamespace setVariable ["A3UE_FPV_perfLog",true];
call _pass;FPV_time=FPV_time+1;call _pass;
FPV_time=FPV_time+5;call _pass;
''')
        self.assertEqual(len(re.findall(r'event=TRACK', out)), 2, out[-3000:])
        self.assertRegex(out, r'event=TRACK phase=ON_STATION drones=\[\["+d1"+,"+ATTACK"+,100,100,15,70\]\]')

    def test_lean_dive_limits_and_hit(self):
        out = self.sqf(r'''
private _d=["d1",[1080,1000,70],"AP","ATTACK"] call _swarmDrone;
private _rec=[[_d]] call _newRecord;
private _m=["m","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];
_d setVariable ["A3UE_FPV_swarmTargetClass","MAN"];
private _state=createHashMap;
[_d,_state] call _tick;
private _steps=0;
while {(_d getVariable "A3UE_FPV_swarmTask")=="DIVE" && {!(_d getVariable ["A3UE_FPV_detonating",false])} && {_steps < 900}} do {
 [_d,_state] call _fly;_steps=_steps+1;};
diag_log format ["steps=%1 strikes=%2 moves=%3 poses=%4",_steps,FPV_strikes,count FPV_moves,count FPV_poses];
[count FPV_strikes==1,"one strike"] call _assert;
[((FPV_strikes # 0) # 0) in ["DIRECT_CONTACT","PREDICTED_IMPACT"],str FPV_strikes] call _assert;
[(_rec get "strikes")==1,"counted"] call _assert;
[(_d getVariable "A3UE_FPV_terminalImpactMode")=="DIRECT_BODY" && {_d getVariable "A3UE_FPV_lastImpactValid"},"impact point handed to the strike"] call _assert;
// Limits: turn at most 150 deg/s, speed change at most 14 m/s2, never above the family's 34 m/s.
private _worstTurn=0;private _worstAccel=0;private _top=0;
for "_i" from 1 to ((count FPV_moves)-1) do {
 private _a=FPV_moves # (_i-1);private _b=FPV_moves # _i;
 private _turn=acos ((((vectorNormalized _a) vectorDotProduct (vectorNormalized _b)) min 1) max -1);
 _worstTurn=_worstTurn max _turn;_worstAccel=_worstAccel max abs ((vectorMagnitude _b)-(vectorMagnitude _a));_top=_top max (vectorMagnitude _b);};
diag_log format ["turn=%1 accel=%2 top=%3",_worstTurn,_worstAccel,_top];
[_worstTurn <= 3.0001,"turn per 0.02 s step"] call _assert;
[_worstAccel <= 0.2801,"speed change per step"] call _assert;
[_top <= 34.0001 && {_top > 33},"dive speed reached, not exceeded"] call _assert;
// Attitude at the D1 cadence: at least 3 frames and 0.05 s apart.
private _cadence=true;
for "_i" from 1 to ((count FPV_poses)-1) do {
 if (((FPV_poses # _i) # 0)-((FPV_poses # (_i-1)) # 0) < 3 || {((FPV_poses # _i) # 1)-((FPV_poses # (_i-1)) # 1) < 0.0499}) then {_cadence=false;};};
[_cadence && {count FPV_poses > 10} && {count FPV_poses < count FPV_moves},"pose cadence"] call _assert;
''')
        self.assertRegex(out, r'event=STRIKE drone=d1 role=AP target=m class=MAN reason=(DIRECT_CONTACT|PREDICTED_IMPACT)')

    def test_lean_dive_leads_a_moving_target(self):
        self.sqf(r'''
private _d=["d1",[1080,1000,70],"AT","ATTACK"] call _swarmDrone;
private _rec=[[_d]] call _newRecord;
private _v=["v","VMVehicle",[1000,1000,0]] call _enemy;_v setVariable ["velocity",[0,8,0]];
_d setVariable ["A3UE_FPV_targetNetId","v"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];
_d setVariable ["A3UE_FPV_swarmTargetClass","VEHICLE"];
private _state=createHashMap;
[_d,_state] call _tick;
private _steps=0;
while {(_d getVariable "A3UE_FPV_swarmTask")=="DIVE" && {!(_d getVariable ["A3UE_FPV_detonating",false])} && {_steps < 900}} do {
 _v setVariable ["position",(_v getVariable "position") vectorAdd [0,0.16,0]];[_d,_state] call _fly;_steps=_steps+1;};
[count FPV_strikes==1,"hit a vehicle doing 29 km/h: "+str FPV_strikes] call _assert;
[(_d getVariable "A3UE_FPV_terminalImpactMode")=="DIRECT_HULL","vehicle impact mode"] call _assert;
[vectorMagnitude (FPV_moves select ((count FPV_moves)-1)) <= 32.0001,"anti-tank dive speed"] call _assert;
''')

    def test_any_contact_on_the_way(self):
        self.sqf(r'''
private _d=["d1",[1080,1000,70],"AP","ATTACK"] call _swarmDrone;
private _rec=[[_d]] call _newRecord;
["m","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];
private _state=createHashMap;
[_d,_state] call _tick;
[_d,_state] call _fly;
FPV_collision="OBJECT";
[_d,_state] call _fly;
[(FPV_strikes # 0 # 0)=="SURFACE_CONTACT","a tree or wall on the way fires the fuse"] call _assert;
[(_d getVariable "A3UE_FPV_lastSurfaceContactASL") isEqualTo [50,0,30],"at the contact point"] call _assert;
[!(_d getVariable "A3UE_FPV_lastImpactValid"),"not a target impact"] call _assert;
// A refused commit releases the fence and the dive goes on.
FPV_commit=false;FPV_strikes=[];
_d setVariable ["A3UE_FPV_detonating",false];[_d,"DIVE"] call A3UE_fnc_fpv_swarmSetTask;
private _r=[_d,_state] call _fly;
[count FPV_strikes==1 && {_r isEqualTo [0.02,true]},"refused: still diving"] call _assert;
[(_d getVariable ["A3UE_FPV_contactFence",[]]) isEqualTo [],"fence released"] call _assert;
''')

    def test_break_off_pulls_up_and_returns_to_the_swarm(self):
        out = self.sqf(r'''
private _d=["d1",[1080,1000,70],"AP","ATTACK"] call _swarmDrone;
private _rec=[[_d]] call _newRecord;
private _m=["m","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];
private _state=createHashMap;
[_d,_state] call _tick;
for "_i" from 1 to 40 do {[_d,_state] call _fly;};
private _revision=_d getVariable ["A3UE_FPV_targetRevision",0];
_m setVariable ["alive",false];
[_d,_state] call _fly;
private _climb=false;
for "_i" from 1 to 30 do {[_d,_state] call _fly;if (((FPV_moves select ((count FPV_moves)-1)) # 2) > 0) then {_climb=true;};};
[_climb,"pulls up"] call _assert;
for "_i" from 1 to 40 do {[_d,_state] call _fly;};
[(_d getVariable "A3UE_FPV_swarmTask")=="LOITER","back to the swarm"] call _assert;
[(_d getVariable "A3UE_FPV_targetNetId")=="" && {(_d getVariable "A3UE_FPV_targetRevision")==_revision+1},"target given back"] call _assert;
[(_d getVariable ["A3UE_FPV_nativeControl",[]]) isEqualTo [] && {!(_d getVariable "A3UE_FPV_terminalSteeringActive")},"AI given back"] call _assert;
[count FPV_strikes==0 && {(_rec get "breaks")==1},"no strike, one break"] call _assert;
''')
        self.assertRegex(out, r'event=BREAK drone=d1 target=m reason=TARGET_GONE')

    def test_a_miss_breaks_off(self):
        out = self.sqf(r'''
private _d=["d1",[1080,1000,70],"AP","ATTACK"] call _swarmDrone;
private _rec=[[_d]] call _newRecord;
private _m=["m","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];
private _state=createHashMap;
[_d,_state] call _tick;
private _moved=false;private _steps=0;
while {(_d getVariable "A3UE_FPV_swarmTask")=="DIVE" && {count FPV_strikes==0} && {_steps < 900}} do {
 if (!_moved && {((_d getVariable "position") vectorDistance [1000,1000,1]) < 14}) then {
  _moved=true;private _v=FPV_moves select ((count FPV_moves)-1);
  _m setVariable ["position",(_d getVariable "position") vectorDiff ((vectorNormalized _v) vectorMultiply 26)];};
 [_d,_state] call _fly;_steps=_steps+1;};
[count FPV_strikes==0,"no strike"] call _assert;
[(_d getVariable "A3UE_FPV_swarmTask")=="ATTACK" && {(_d getVariable "A3UE_FPV_targetNetId")=="m"} && {(_d getVariable "A3UE_FPV_swarmRetries")==1},
 "a miss with the target still there: it comes back for it once"] call _assert;
[(_rec get "reattacks")==1 && {count (_d getVariable ["A3UE_FPV_nativeControl",[]])==3},"counted; the swarm flies the new run-in (SW-1d)"] call _assert;
''')
        self.assertRegex(out, r'event=BREAK drone=d1 target=m reason=MISSED')
        self.assertRegex(out, r'event=AGAIN drone=d1 target=m after=MISSED')

    def test_cover_in_the_dive_takes_the_blast_no_look_ahead(self):
        out = self.sqf(r'''
// SW-1g (EJ after SW1f: "not picky about obstacles"): no look-ahead ray in the dive and no BLOCKED
// pull-up and return; cover on the line takes the blast through the any-contact fuse.
private _d=["d1",[1080,1000,70],"AP","ATTACK"] call _swarmDrone;
private _rec=[[_d]] call _newRecord;
private _m=["m","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];_d setVariable ["A3UE_FPV_swarmRetries",0];
_d setVariable ["A3UE_FPV_swarmTargetClass","MAN"];
private _state=createHashMap;
FPV_blocked=true;
[_d,_state] call _tick;
[(_d getVariable "A3UE_FPV_swarmTask")=="DIVE","dives"] call _assert;
private _calls=count FPV_clearCalls;
for "_i" from 1 to 40 do {[_d,_state] call _fly;};
[count FPV_clearCalls==_calls && {(_rec get "breaks")==0},"no look-ahead, no break: "+str [count FPV_clearCalls-_calls,_rec get "breaks"]] call _assert;
[(_d getVariable "A3UE_FPV_swarmTask")=="DIVE","still diving"] call _assert;
FPV_collision="OBJECT";
[_d,_state] call _fly;
[(FPV_strikes # 0 # 0)=="SURFACE_CONTACT","the wall on the way takes the blast"] call _assert;
[(((missionNamespace getVariable "A3UE_FPV_swarmTries") get "m") # 0)==1,"the dive counted as a try at the target"] call _assert;
''')
        self.assertNotRegex(out, r'reason=BLOCKED|event=AGAIN')
        self.assertRegex(out, r'(?m)event=STRIKE drone=d1 role=AP target=m class=MAN reason=SURFACE_CONTACT diveS=\S+ speed=\d+$')

    def test_external_control_writes_nothing_and_drops_the_dive(self):
        self.sqf(r'''
private _d=["d1",[1080,1000,70],"AP","ATTACK"] call _swarmDrone;
private _rec=[[_d]] call _newRecord;
["m","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];
private _state=createHashMap;
[_d,_state] call _tick;
_d setVariable ["controlled",true];
private _moves=count FPV_moves;private _ai=count FPV_ai;private _sent=FPV_sent;
private _r=[_d,_state] call _fly;
[_r isEqualTo [0.5,false] && {count FPV_moves==_moves} && {count FPV_ai==_ai},"no writes under control"] call _assert;
[FPV_sent==_sent+1 && {_d getVariable "A3UE_FPV_reportedControl"},"control reported to the lifecycle once"] call _assert;
[_d,_state] call _fly;
[FPV_sent==_sent+1,"only on change"] call _assert;
[(_d getVariable "A3UE_FPV_swarmTask")=="LOITER","dive dropped"] call _assert;
[count (_d getVariable ["A3UE_FPV_nativeControl",[]])==3,"AI not touched while controlled"] call _assert;
_d setVariable ["controlled",false];
[_d,_state] call _fly;
[(_d getVariable ["A3UE_FPV_nativeControl",[]]) isEqualTo [],"restored after release"] call _assert;
''')

    def test_brain_phases_idle_leave_retire_done(self):
        out = self.sqf(r'''
private _d=["d1",[1700,1000,70],"AP","INBOUND"] call _swarmDrone;
private _rec=[[_d],"INBOUND"] call _newRecord;
private _pass={[_rec,call _settings] call A3UE_fnc_fpv_swarmPass};
[(call _pass)=="INBOUND","700 m out: still inbound"] call _assert;
_d setVariable ["position",[1500,1000,70]];
[(call _pass)=="ON_STATION" && {FPV_notes isEqualTo [["STR_A3UE_FPV_SWARM_ON_STATION",[]]]},"on station"] call _assert;
FPV_time=FPV_time+59;
[(call _pass)=="ON_STATION","quiet for 59 s"] call _assert;
FPV_time=FPV_time+2;
[(call _pass)=="LEAVING" && {(_rec get "leaveReason")=="IDLE"},"leaves after a minute without a dive (SW-1g)"] call _assert;
[(_d getVariable "A3UE_FPV_swarmTask")=="LEAVE","turned for home"] call _assert;
private _p="VMMan" createVehicle [0,0,0];_p setVariable ["position",[1500,1100,0]];FPV_players=[_p];
call _pass;
[FPV_retired isEqualTo [],"a player is near: not yet"] call _assert;
_p setVariable ["position",[3000,1000,0]];
call _pass;
[FPV_retired isEqualTo [_d] && {(_rec get "returned")==1},"retired once 1 km from every player"] call _assert;
[(call _pass)=="DONE","no drones: done"] call _assert;
[FPV_deleted isEqualTo ["mA","mB"] && {count (missionNamespace getVariable "A3UE_FPV_swarms")==0}
 && {(missionNamespace getVariable "A3UE_FPV_swarmActive")==""},"closed and cleaned"] call _assert;
''')
        self.assertRegex(out, r'event=DONE reason=IDLE launched=1 strikes=0 returned=1 lost=0')

    def test_brain_dives_keep_it_on_station_until_the_time_limit(self):
        self.sqf(r'''
private _d=["d1",[1200,1000,70],"AP","ATTACK"] call _swarmDrone;
private _rec=[[_d]] call _newRecord;
private _pass={[_rec,call _settings] call A3UE_fnc_fpv_swarmPass};
FPV_time=FPV_time+50;
[(call _pass)=="ON_STATION","50 s in, no dive yet"] call _assert;
_rec set ["lastDiveAt",FPV_time];FPV_time=FPV_time+55;
[(call _pass)=="ON_STATION","55 s after a dive"] call _assert;
FPV_time=FPV_time+6;
[(call _pass)=="LEAVING" && {(_rec get "leaveReason")=="IDLE"},"61 s after the last dive: idle, a run-in under way or not (SW-1e)"] call _assert;
[(_d getVariable "A3UE_FPV_swarmTask")=="LEAVE" && {(_d getVariable ["A3UE_FPV_targetNetId",""])==""},"the run-in is dropped"] call _assert;
// Dives keep it on station, but never past 6 minutes (and never leaving mid-dive).
private _e=["e1",[1200,1000,70],"AP","ATTACK"] call _swarmDrone;
_rec=[[_e]] call _newRecord;
{FPV_time=FPV_time+50;_rec set ["lastDiveAt",FPV_time];[(call _pass)=="ON_STATION","diving every 50 s: "+str _x] call _assert;} forEach [1,2,3,4,5,6];
[_e,"DIVE"] call A3UE_fnc_fpv_swarmSetTask;FPV_time=FPV_time+70;
[(call _pass)=="ON_STATION","never leaves during a dive"] call _assert;
[_e,"ATTACK"] call A3UE_fnc_fpv_swarmSetTask;
[(call _pass)=="LEAVING" && {(_rec get "leaveReason") in ["TIME","IDLE"]},"after 6 minutes"] call _assert;
''')

    def test_brain_assigns_free_drones_on_arrival(self):
        self.sqf(r'''
private _d1=["d1",[1500,1000,70],"AP","INBOUND"] call _swarmDrone;
private _d2=["d2",[1500,1050,70],"AP","INBOUND"] call _swarmDrone;
private _rec=[[_d1,_d2],"INBOUND"] call _newRecord;
["a","VMMan",[1000,1000,0]] call _enemy;["b","VMMan",[1000,1100,0]] call _enemy;
[(_rec call {[_this,call _settings] call A3UE_fnc_fpv_swarmPass})=="ON_STATION","arrived"] call _assert;
[_rec,call _settings] call A3UE_fnc_fpv_swarmPass;
private _t=[_d1,_d2] apply {_x getVariable ["A3UE_FPV_targetNetId",""]};
[("a" in _t) && {"b" in _t},"two drones, two targets, at once: "+str _t] call _assert;
''')

    def test_request_authority_one_at_a_time_and_mix(self):
        out = self.sqf(r'''
missionNamespace setVariable ["A3UE_FPV_catalog",createHashMapFromArray [["armafpv",createHashMapFromArray [["classesBySide",
 createHashMapFromArray [["independent",createHashMapFromArray [["AT",["I_Crocus_AT"]],["AP",["I_Crocus_AP"]]]]]]]]]];
missionNamespace setVariable ["A3UE_FPV_swarmActive",""];
FPV_markers=createHashMapFromArray [["Synd_HQ",[1000,3000,0]]];
FPV_remote=true;FPV_sender=3;
[([[1000,1000,0]] call A3UE_fnc_fpv_swarmRequest) isEqualTo [false,"AUTHORITY"],"client callers refused (SW-1)"] call _assert;
FPV_remote=false;FPV_sender=2;
// A claim whose swarm is gone (its script failed) does not block a call.
missionNamespace setVariable ["A3UE_FPV_swarmActive","swarm9"];
[([[1000,-5,0]] call A3UE_fnc_fpv_swarmRequest) isEqualTo [false,"POSITION"],"off the map"] call _assert;
["c1","VMVehicle",[1000,1050,0]] call _enemy;["c2","VMVehicle",[1050,1000,0]] call _enemy;
["t1","VMVehicle",[950,1000,0],["Tank"]] call _enemy;["m1","VMMan",[1000,980,0]] call _enemy;
private _r=[[1000,1000,0],5] call A3UE_fnc_fpv_swarmRequest;
[_r isEqualTo [true,"swarm1"],str _r] call _assert;
private _roles=FPV_brain # 1;
[count _roles==5 && {({_x=="AT"} count _roles)==4},"three vehicles, one armour: four anti-tank (EJ's cap after SW1h), one anti-personnel: "+str _roles] call _assert;
private _rec=(missionNamespace getVariable "A3UE_FPV_swarms") get "swarm1";
[((_rec get "spawn") vectorDistance [1000,1750,0]) < 0.01,"launched 750 m out towards HQ (SW-1i: inside a SAM's 1000 m): "+str (_rec get "spawn")] call _assert;
[FPV_madeMarkers isEqualTo ["A3UE_FPV_swarm1_area","A3UE_FPV_swarm1_label"],"area marker"] call _assert;
[([[1000,1000,0]] call A3UE_fnc_fpv_swarmRequest) isEqualTo [false,"SWARM_ACTIVE"],"one swarm at a time"] call _assert;
// Nothing on wheels or tracks: all anti-personnel. Size clamped; HQ 300 m away: launch 600 m out.
missionNamespace setVariable ["A3UE_FPV_swarmActive",""];FPV_markers=createHashMapFromArray [["Synd_HQ",[5000,5300,0]]];
_r=[[5000,5000,0],12] call A3UE_fnc_fpv_swarmRequest;
_roles=FPV_brain # 1;
[count _roles==8 && {({_x=="AT"} count _roles)==0},"eight, all anti-personnel: "+str _roles] call _assert;
_rec=(missionNamespace getVariable "A3UE_FPV_swarms") get (_r # 1);
[((_rec get "spawn") vectorDistance [5000,5600,0]) < 0.01,"at least 600 m out"] call _assert;
missionNamespace setVariable ["A3UE_FPV_swarmActive",""];
_r=[[5000,5000,0],1] call A3UE_fnc_fpv_swarmRequest;
[count (FPV_brain # 1)==3,"at least three"] call _assert;
missionNamespace setVariable ["A3UE_FPV_swarmActive",""];
// SW-1j (EJ after SW1i: "they should get all 4 now ... its taking up to 6 drones to take 1 out"; SW-1i
// counted armour three times): armour in the circle sends all four; a truck, an armed car or a SAM one
// each (the SAM and radar went at one AT hit); at most four.
{
 _x params ["_list","_want","_why"];
 {deleteVehicle _x;} forEach FPV_objects;FPV_objects=[];
 missionNamespace setVariable ["A3UE_FPV_swarmActive",""];
 {
  private _o=[format ["h%1",_forEachIndex],"VMVehicle",[5050,5000+(_forEachIndex*40),0],_x] call _enemy;
  if ("StaticWeapon" in _x) then {_o setVariable ["uav",true];};
 } forEach _list;
 [[5000,5000,0]] call A3UE_fnc_fpv_swarmRequest;
 [({_x=="AT"} count (FPV_brain # 1))==_want,_why+": "+str (FPV_brain # 1)] call _assert;
} forEach [[[["Tank"]],4,"one APC: all four anti-tank"],[[[]],1,"one truck: one"],[[["StaticWeapon"]],1,"a SAM alone: one"],
 [[["StaticWeapon"],["StaticWeapon"]],2,"a SAM and a radar: two"],[[["Tank"],[]],4,"an APC and a truck: four"],
 [[["Tank"],["Tank"]],4,"two APCs: four, the cap"],[[[],[],[],[],[]],4,"five trucks: four, the cap"],
 [[["Ship"]],1,"SW-1m (EJ after SW1l: the seaport's gunboat): a boat: one"]];
// SW-1j (EJ after SW1i: "the drones spawn behind the commander and fly over his head on the way to the
// target"): on the line from the centre through the caller, 200 m behind him, 600-750 m out; without
// a live caller, on HQ's side as before; with one on the centre (SW1j: 30 m), behind his back.
{deleteVehicle _x;} forEach FPV_objects;FPV_objects=[];
FPV_markers=createHashMapFromArray [["Synd_HQ",[5000,8000,0]]];
private _caller=["VMMan","caller"] call _make;_caller setVariable ["dir",90];
{
 _x params ["_at","_want","_why"];
 missionNamespace setVariable ["A3UE_FPV_swarmActive",""];
 _caller setVariable ["position",_at];
 private _r=[[5000,5000,0],-1,_caller] call A3UE_fnc_fpv_swarmRequest;
 private _rec=(missionNamespace getVariable "A3UE_FPV_swarms") get (_r # 1);
 [((_rec get "spawn") vectorDistance _want) < 0.01,_why+": "+str (_rec get "spawn")] call _assert;
} forEach [[[5000,4600,0],[5000,4400,0],"caller 400 m south: 600 m out, 200 m behind him"],
 [[5450,5000,0],[5650,5000,0],"caller 450 m east: 650 m out"],
 [[5000,4300,0],[5000,4250,0],"caller 700 m south: 750 m out at most (SW-1i, the SAMs)"],
 [[5020,5020,0],[4400,5000,0],"caller on the centre, facing east: behind his back, west"]];
_caller setVariable ["alive",false];_caller setVariable ["position",[5000,4600,0]];
missionNamespace setVariable ["A3UE_FPV_swarmActive",""];
_r=[[5000,5000,0],-1,_caller] call A3UE_fnc_fpv_swarmRequest;
_rec=(missionNamespace getVariable "A3UE_FPV_swarms") get (_r # 1);
[((_rec get "spawn") vectorDistance [5000,5750,0]) < 0.01,"a dead caller: HQ's side: "+str (_rec get "spawn")] call _assert;
missionNamespace setVariable ["A3UE_FPV_swarmActive",""];
missionNamespace setVariable ["A3UE_FPV_catalog",createHashMapFromArray [["kvn",createHashMapFromArray [["classesBySide",createHashMap]]]]];
[([[5000,5000,0]] call A3UE_fnc_fpv_swarmRequest) isEqualTo [false,"NO_DRONE_PACK"],"no rebel-side drones"] call _assert;
''')
        self.assertRegex(out, r'event=CALLED center=\[1000,1000,0\] size=5 at=4 vehiclesSeen=3 armor=1 launchM=750 bearing=0 from=HOME callerM=-1 families=')
        self.assertRegex(out, r'event=CALLED center=\[5000,5000,0\] size=7 at=0 vehiclesSeen=0 armor=0 launchM=600 bearing=180 from=CALLER callerM=400 ')
        self.assertRegex(out, r'event=CALLED center=\[5000,5000,0\] size=7 at=0 vehiclesSeen=0 armor=0 launchM=650 bearing=90 from=CALLER callerM=450 ')
        self.assertRegex(out, r'launchM=750 bearing=180 from=CALLER callerM=700 ')
        self.assertRegex(out, r'launchM=600 bearing=270 from=FACING callerM=28 ')
        self.assertRegex(out, r'launchM=750 bearing=0 from=HOME callerM=-1 ')

    def test_menu_call_checks_the_commander_and_charges_once(self):
        # SW-2 (EJ, 17 November: commander only, 1 support point + 500, no airport; design §4.4: the
        # commander's machine only asks, the server checks and charges).
        out = self.sqf(r'''
missionNamespace setVariable ["A3UE_FPV_catalog",createHashMapFromArray [["armafpv",createHashMapFromArray [["classesBySide",
 createHashMapFromArray [["independent",createHashMapFromArray [["AT",["I_Crocus_AT"]],["AP",["I_Crocus_AP"]]]]]]]]]];
missionNamespace setVariable ["A3UE_FPV_swarmActive",""];
FPV_markers=createHashMapFromArray [["Synd_HQ",[1000,3000,0]]];
FPV_replies=[];FPV_published=[];FPV_money=[];
server="VMVehicle" createVehicle [0,0,0];server setVariable ["resourcesFIA",1000];
supportPoints=2;supportCooldown=false;A3A_fnc_hasRadio={true};
private _boss=["VMMan","boss"] call _make;_boss setVariable ["isPlayer",true];_boss setVariable ["owner",3];
_boss setVariable ["position",[1000,700,0]];theBoss=_boss;
private _other=["VMMan","other"] call _make;_other setVariable ["isPlayer",true];_other setVariable ["owner",4];
FPV_remote=true;
private _call={params ["_who","_token","_from"];FPV_sender=_from;FPV_replies=[];
 [[1000,1000,0],_who,_token] call A3UE_fnc_fpv_swarmCall;FPV_replies # 0};
[([_other,1,4] call _call) isEqualTo [false,"NOT_COMMANDER",1,4],"another player"] call _assert;
[([_boss,2,4] call _call) isEqualTo [false,"NOT_COMMANDER",2,4],"another machine naming the commander"] call _assert;
_boss setVariable ["isPlayer",false];
[([_boss,3,3] call _call) isEqualTo [false,"NOT_COMMANDER",3,3],"an AI commander"] call _assert;
_boss setVariable ["isPlayer",true];
supportCooldown=true;[([_boss,4,3] call _call) # 1 == "COOLDOWN","AU's cooldown"] call _assert;supportCooldown=false;
supportPoints=0;[([_boss,5,3] call _call) # 1 == "NO_POINTS","no support point"] call _assert;supportPoints=2;
server setVariable ["resourcesFIA",499];[([_boss,6,3] call _call) # 1 == "NO_MONEY","499 money"] call _assert;
server setVariable ["resourcesFIA",1000];
A3A_fnc_hasRadio={false};[([_boss,7,3] call _call) # 1 == "NO_RADIO","no radio"] call _assert;A3A_fnc_hasRadio={true};
missionNamespace setVariable ["A3UE_FPV_swarmEnabled",false];
[([_boss,8,3] call _call) # 1 == "DISABLED","switched off"] call _assert;
missionNamespace setVariable ["A3UE_FPV_swarmEnabled",true];
[supportPoints==2 && {FPV_money isEqualTo []} && {FPV_published isEqualTo []} && {FPV_brain isEqualTo []},"nothing charged or called on a refusal"] call _assert;
// The call: the commander's own machine; charged once; launched behind him (300 m south: 600 m out).
missionNamespace setVariable ["A3UE_FPV_swarmSize",5];missionNamespace setVariable ["A3UE_FPV_swarmSettingsCache",[]];
private _r=[_boss,9,3] call _call;
[_r isEqualTo [true,"swarm1",9,3],str _r] call _assert;
[supportPoints==1 && {FPV_money isEqualTo [-500]} && {FPV_published isEqualTo ["supportPoints"]},"1 point and 500 money"] call _assert;
[count (FPV_brain # 1)==5,"the size setting: "+str (FPV_brain # 1)] call _assert;
private _rec=(missionNamespace getVariable "A3UE_FPV_swarms") get "swarm1";
[((_rec get "spawn") vectorDistance [1000,400,0]) < 0.01,"over the commander's head: "+str (_rec get "spawn")] call _assert;
// One at a time, and a refused call costs nothing.
_r=[_boss,10,3] call _call;
[_r isEqualTo [false,"SWARM_ACTIVE",10,3] && {supportPoints==1} && {FPV_money isEqualTo [-500]},"one swarm at a time: "+str _r] call _assert;
// swarmRequest itself still refuses that machine: only swarmCall's checked call gets through.
missionNamespace setVariable ["A3UE_FPV_swarmActive",""];
[([[1000,1000,0],-1,_boss] call A3UE_fnc_fpv_swarmRequest) isEqualTo [false,"AUTHORITY"],"a client calling swarmRequest"] call _assert;
[!(missionNamespace getVariable ["A3UE_FPV_swarmCallTrusted",false]),"the pass is closed again"] call _assert;
''')
        self.assertRegex(out, r'event=MENU_CALL ok=false why=NOT_COMMANDER sender=4 commander=3 points=2 money=1000')
        self.assertRegex(out, r'event=MENU_CALL ok=true why=swarm1 sender=3 commander=3 points=1 money=1000')
        self.assertRegex(out, r'event=CALLED center=\[1000,1000,0\] size=5 at=0 vehiclesSeen=0 armor=0 launchM=600 bearing=180 from=CALLER callerM=300 ')

    def test_loiter_and_leave_are_ai_and_a_wanderer_is_flown_back(self):
        out = self.sqf(r'''
private _d=["d1",[1000,1100,70],"AP","LOITER"] call _swarmDrone;
private _rec=[[_d]] call _newRecord;
private _state=createHashMap;
[_d,_state] call _tick;
private _moves={FPV_ai select {(_x # 0)=="MOVE"}};
private _loiter=(call _moves) # 0;
[((_loiter # 1) distance2D [1000,1000,0]) > 119 && {((_loiter # 1) distance2D [1000,1000,0]) < 121} && {(_loiter # 3)==18},"loiter on the 120 m ring over the zone"] call _assert;
[(FPV_ai select {(_x # 0)=="SETUP"}) isNotEqualTo [] && {(_d getVariable ["A3UE_FPV_nativeControl",[]]) isEqualTo []},"the AI flies it: careless, hold fire, once per task"] call _assert;
FPV_time=FPV_time+0.5;[_d,_state] call _tick;
[count (call _moves)==1,"no new order while it still holds"] call _assert;
// SW1c: the AI took a loitering drone 600-800 m out for a minute. 430 m outside the ring: flown back.
_d setVariable ["position",[1000,1550,70]];
private _r=[_d,_state] call _tick;
[(_d getVariable "A3UE_FPV_swarmTask")=="INBOUND" && {((_d getVariable "A3UE_FPV_swarmArrive") distance2D [1000,1120,0]) < 0.01},"to the nearest point of the ring"] call _assert;
FPV_time=FPV_time+0.05;_r=[_d,_state] call _tick;
[_r isEqualTo [0.02,true] && {count (_d getVariable ["A3UE_FPV_nativeControl",[]])==3} && {count (call _moves)==1},"by the swarm, not by an AI order"] call _assert;
[(_rec get "returns")==1,"counted"] call _assert;
[_d,"LEAVE"] call A3UE_fnc_fpv_swarmSetTask;[_d,_state] call _tick;
[(_d getVariable ["A3UE_FPV_nativeControl",[]]) isEqualTo [],"the AI flies it out"] call _assert;
private _leave=(call _moves) select ((count (call _moves))-1);
[(_leave # 1) isEqualTo [1000,2800,0] && {(_leave # 2)==80},"leave: to the exit, higher"] call _assert;
[(_d getVariable "A3UE_FPV_mode")=="SEARCHING","shown as searching"] call _assert;
''')
        self.assertRegex(out, r'event=RETURN drone=d1 outM=430')

    def test_cruise_in_turns_climbs_poses_and_hands_over_at_the_ring(self):
        self.sqf(r'''
private _d=["d1",[1000,2500,60],"AP","INBOUND"] call _swarmDrone;
_d setVariable ["velocity",[15,0,0]];
private _rec=[[_d],"INBOUND"] call _newRecord;
_d setVariable ["A3UE_FPV_swarmArrive",[1000,1200,0]];
private _state=createHashMap;
private _r=[_d,_state] call _tick;
[_r isEqualTo [0.02,true] && {count (_d getVariable ["A3UE_FPV_nativeControl",[]])==3},"the swarm flies it in (SW-1d)"] call _assert;
[(FPV_ai select {(_x # 0)=="MOVE"}) isEqualTo [],"no AI order"] call _assert;
for "_i" from 1 to 400 do {[_d,_state] call _fly;};
// Level turns at most 75 deg/s, 14 m/s2 to 22 m/s, at most 6 m/s up or down.
private _worstTurn=0;private _worstAccel=0;private _top=0;private _worstClimb=0;
for "_i" from 1 to ((count FPV_moves)-1) do {
 private _a=FPV_moves # (_i-1);private _b=FPV_moves # _i;
 private _fa=[_a # 0,_a # 1,0];private _fb=[_b # 0,_b # 1,0];
 _worstTurn=_worstTurn max (acos ((((vectorNormalized _fa) vectorDotProduct (vectorNormalized _fb)) min 1) max -1));
 _worstAccel=_worstAccel max abs ((vectorMagnitude _fb)-(vectorMagnitude _fa));
 _top=_top max (vectorMagnitude _fb);_worstClimb=_worstClimb max abs (_b # 2);};
diag_log format ["cruise turn=%1 accel=%2 top=%3 climb=%4 pos=%5",_worstTurn,_worstAccel,_top,_worstClimb,_d getVariable "position"];
[_worstTurn <= 1.501,"turn per 0.02 s step: "+str _worstTurn] call _assert;
[_worstAccel <= 0.2801 && {_top <= 22.0001} && {_top > 21.9},"speed: "+str [_worstAccel,_top]] call _assert;
[_worstClimb <= 6.0001,"climb rate: "+str _worstClimb] call _assert;
private _p=_d getVariable "position";
[(_p # 1) < 2400 && {abs ((_p # 0)-1000) < 60},"turned south for its ring point: "+str _p] call _assert;
[abs ((_p # 2)-70) < 1,"70 m over the ground there: "+str _p] call _assert;
// Attitude at the D1 cadence, the nose down a little in level flight as a quad's is.
private _cadence=true;
for "_i" from 1 to ((count FPV_poses)-1) do {
 if (((FPV_poses # _i) # 0)-((FPV_poses # (_i-1)) # 0) < 3 || {((FPV_poses # _i) # 1)-((FPV_poses # (_i-1)) # 1) < 0.0499}) then {_cadence=false;};};
private _last=FPV_poses select ((count FPV_poses)-1);
[_cadence && {count FPV_poses > 20} && {count FPV_poses < count FPV_moves},"pose cadence"] call _assert;
[((_last # 2) # 2) < -0.25 && {((_last # 2) # 2) > -0.4} && {abs (((_last # 4) # 2)) < 0.05},"nose about 18 degrees down, path level: "+str _last] call _assert;
// High ground ahead keeps it 25 m over it; something in the path (a mast): hard up.
FPV_groundRule={if (((_this # 1) < 2330) && {(_this # 1) > 2000}) then {80} else {0}};
for "_i" from 1 to 300 do {[_d,_state] call _fly;};
[((_d getVariable "position") # 2) > 90,"climbs for the hill: "+str (_d getVariable "position")] call _assert;
FPV_groundRule={0};
FPV_clearRule={[[0,0,0],"Land_Mast"]};
for "_i" from 1 to 60 do {[_d,_state] call _fly;};
[((FPV_moves select ((count FPV_moves)-1)) # 2) > 6.1,"climbs harder than the 6 m/s cruise rate"] call _assert;
FPV_clearRule={[]};
// At its point of the ring: the AI takes over the loiter.
_d setVariable ["position",[1000,1230,70]];
FPV_time=FPV_time+0.02;[_d,_state] call _tick;
[(_d getVariable "A3UE_FPV_swarmTask")=="LOITER","arrived"] call _assert;
[_d,_state] call _tick;
[(_d getVariable ["A3UE_FPV_nativeControl",[]]) isEqualTo [] && {(FPV_ai select {(_x # 0)=="MOVE"}) isNotEqualTo []},"the AI flies the ring"] call _assert;
''')

    def test_run_in_from_close_turns_back_over_the_target_and_dives(self):
        out = self.sqf(r'''
// SW1c: a loitering drone took a target 70-150 m away while heading away from it; the AI flew on
// 400-700 m and took a minute to come back. The swarm turns it round (SW-1g: until the target is
// ahead) and dives.
private _d=["d1",[1100,1000,70],"AP","ATTACK"] call _swarmDrone;
_d setVariable ["velocity",[6,0,0]];
private _rec=[[_d]] call _newRecord;
["m","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];_d setVariable ["A3UE_FPV_swarmGoAt",FPV_time];
_d setVariable ["A3UE_FPV_swarmTargetClass","MAN"];
private _state=createHashMap;
private _far=0;private _n=0;private _t0=FPV_time;
while {(_d getVariable "A3UE_FPV_swarmTask")=="ATTACK" && {_n < 400}} do {
 [_d,_state,0.05] call _fly;_n=_n+1;
 _far=_far max ((_d getVariable "position") distance2D [1000,1000,0]);};
diag_log format ["closeRun far=%1 s=%2",_far,FPV_time-_t0];
[(_d getVariable "A3UE_FPV_swarmTask")=="DIVE","dives"] call _assert;
[(FPV_time-_t0) < 8,"within 8 s: "+str (FPV_time-_t0)] call _assert;
[_far < 140,"never far from its target: "+str _far] call _assert;
''')
        self.assertRegex(out, r'(?m)event=DIVE drone=d1 target=m distM=\d+ aboveM=\d+ angle=(4\d|[5-8]\d) again=0 try=1 tapS=-1$')

    def test_a_target_steeply_below_dives_whichever_way_the_drone_faces(self):
        out = self.sqf(r'''
// SW-2b (session SW2): the last-resort drone took a man at a ruin from 8 m off and 70 m up, then circled
// him 6-12 m out at 12 m/s for 46 s (a point inside its turning circle never came within 30 degrees of
// its heading) until the swarm left. Steeply below: the short push-over, whichever way it faces.
private _d=["d1",[1008,1000,70],"AP","ATTACK"] call _swarmDrone;
_d setVariable ["velocity",[0,12,0]];
private _rec=[[_d]] call _newRecord;
["m","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];_d setVariable ["A3UE_FPV_swarmGoAt",FPV_time];
_d setVariable ["A3UE_FPV_swarmTargetClass","MAN"];
private _state=createHashMap;private _n=0;private _t0=FPV_time;
while {(_d getVariable "A3UE_FPV_swarmTask")=="ATTACK" && {_n < 200}} do {[_d,_state,0.05] call _fly;_n=_n+1;};
[(_d getVariable "A3UE_FPV_swarmTask")=="DIVE","dives: "+(_d getVariable "A3UE_FPV_swarmTask")] call _assert;
[(FPV_time-_t0) < 0.2,"at once: "+str (FPV_time-_t0)] call _assert;
_n=0;
while {(_d getVariable "A3UE_FPV_swarmTask")=="DIVE" && {!(_d getVariable ["A3UE_FPV_detonating",false])} && {_n < 900}} do {[_d,_state] call _fly;_n=_n+1;};
diag_log format ["overhead steps=%1 strikes=%2 pos=%3",_n,FPV_strikes,_d getVariable "position"];
[count FPV_strikes==1,"and hits him: "+str FPV_strikes] call _assert;
// Not steeply below: 50 degrees down and off to the side, it still turns to face him first.
{deleteVehicle _x;} forEach FPV_objects;FPV_objects=[];FPV_strikes=[];
_d=["d2",[1059,1000,70],"AP","ATTACK"] call _swarmDrone;
_d setVariable ["velocity",[0,12,0]];
_rec=[[_d]] call _newRecord;
["m2","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m2"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];_d setVariable ["A3UE_FPV_swarmGoAt",FPV_time];
_d setVariable ["A3UE_FPV_swarmTargetClass","MAN"];
_state=createHashMap;
[_d,_state,0.05] call _fly;
[(_d getVariable "A3UE_FPV_swarmTask")=="ATTACK","50 degrees down, side on: turns first"] call _assert;
// Nearly overhead but behind it (77 degrees down, flying away): turns round first, never a loop (SW-1g).
{deleteVehicle _x;} forEach FPV_objects;FPV_objects=[];
_d=["d3",[1015,1000,70],"AP","ATTACK"] call _swarmDrone;
_d setVariable ["velocity",[12,0,0]];
_rec=[[_d]] call _newRecord;
["m3","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m3"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];_d setVariable ["A3UE_FPV_swarmGoAt",FPV_time];
_d setVariable ["A3UE_FPV_swarmTargetClass","MAN"];
_state=createHashMap;
[_d,_state,0.05] call _fly;
[(_d getVariable "A3UE_FPV_swarmTask")=="ATTACK","overhead but behind: turns first"] call _assert;
// The settings.
private _s=call _settings;
[(_s get "overheadAngle")==65 && {(_s get "overheadFacing")==120},"SW-2b: 65 degrees down, within 120 of the heading"] call _assert;
''')
        self.assertRegex(out, r'event=DIVE drone=d1 target=m distM=8 aboveM=69 angle=8\d again=0 try=1 tapS=-1')
        self.assertRegex(out, r'event=STRIKE drone=d1 role=AP target=m class=MAN reason=(DIRECT_CONTACT|PREDICTED_IMPACT)')

    def test_approach_from_launch_lanes_is_straight_and_spread(self):
        self.sqf(r'''
// SW-1f (EJ after SW1e: "a crazy twist together"; SW-1e swerved each drone out into its lane and back):
// two drones launched 70 m apart in their lanes fly straight lines to their own targets, each at its own
// height and speed, and never swerve.
private _a=["a1",[965,1600,70],"AP","ATTACK"] call _swarmDrone;private _b=["b1",[1035,1600,70],"AP","ATTACK"] call _swarmDrone;
{_x setVariable ["velocity",[0,-15,0]];} forEach [_a,_b];
_a setVariable ["A3UE_FPV_swarmStyle",[20,-35,1.1,0,1]];_b setVariable ["A3UE_FPV_swarmStyle",[0,35,0.9,0,-1]];
private _rec=[[_a,_b]] call _newRecord;
["ta","VMMan",[990,1000,0]] call _enemy;["tb","VMMan",[1010,1000,0]] call _enemy;
_a setVariable ["A3UE_FPV_targetNetId","ta"];_b setVariable ["A3UE_FPV_targetNetId","tb"];
// No dive yet (their turn never comes): just the flight in.
{_x setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];_x setVariable ["A3UE_FPV_swarmGoAt",FPV_time+1000];} forEach [_a,_b];
private _sa=createHashMap;private _sb=createHashMap;
private _off={params ["_p","_from","_to"];private _d=vectorNormalized ([_to # 0,_to # 1,0] vectorDiff [_from # 0,_from # 1,0]);
 abs ((((_p # 0)-(_from # 0))*(_d # 1))-(((_p # 1)-(_from # 1))*(_d # 0)))};
private _step={FPV_time=FPV_time+0.1;FPV_frame=FPV_frame+3;FPV_observed=FPV_observed+0.1;
 {_x params ["_d","_s"];private _n=count FPV_moves;[_d,_s] call _tick;
  if (count FPV_moves > _n) then {private _v=FPV_moves select ((count FPV_moves)-1);_d setVariable ["velocity",_v];
   _d setVariable ["position",(_d getVariable "position") vectorAdd (_v vectorMultiply 0.1)];};} forEach [[_a,_sa],[_b,_sb]];};
private _gap=1e9;private _n=0;private _pa=[];private _pb=[];private _lead=0;private _wa=0;private _wb=0;
while {(_pa isEqualTo [] || {_pb isEqualTo []}) && {_n < 400}} do {
 call _step;_n=_n+1;
 _wa=_wa max ([_a getVariable "position",[965,1600],[990,1000]] call _off);
 _wb=_wb max ([_b getVariable "position",[1035,1600],[1010,1000]] call _off);
 if (_pa isEqualTo [] && {((_a getVariable "position") # 1) <= 1110}) then {_pa=+(_a getVariable "position");_lead=((_b getVariable "position") # 1)-(_pa # 1);};
 if (_pb isEqualTo [] && {((_b getVariable "position") # 1) <= 1110}) then {_pb=+(_b getVariable "position");};
 if (((_a getVariable "position") # 1) > 1300) then {_gap=_gap min ((_a getVariable "position") distance2D (_b getVariable "position"));};};
diag_log format ["lanes gap=%1 a=%2 b=%3 lead=%4 offA=%5 offB=%6",_gap,_pa,_pb,_lead,_wa,_wb];
[_gap >= 40,"apart on the way in: "+str _gap] call _assert;
[_wa < 3 && {_wb < 3},"straight lines from the launch lanes, no swerve: "+str [_wa,_wb]] call _assert;
[((_pa # 2)-(_pb # 2)) > 12,"its own height: "+str [_pa # 2,_pb # 2]] call _assert;
[_lead > 15,"its own speed: the faster one ahead by "+str _lead] call _assert;
''')

    def test_launch_lead_group_then_trailing_third(self):
        out = self.sqf(r'''
// SW-1g (EJ after SW1f: "fly in staggered, and spread out ... some trailing further behind"): seven
// drones, five in the lead group 1.5 s apart, the last two 14 s after the first. The brain runs while
// they wait (the lead attacks at once), and the swarm is never closed with a launch still to come.
private _rec=[[],"INBOUND"] call _newRecord;_rec set ["spawn",[1000,1600,0]];_rec set ["marker","mA"];_rec set ["launched",0];
FPV_spawned=[];
FPV_spawn={private _d=["VMUAV",format ["u%1",count FPV_spawned]] call _make;
 _d setVariable ["position",_this get "spawnPosATL"];FPV_spawned pushBack [FPV_time,_d,+(_this get "spawnPosATL")];_d};
FPV_passes=[];
A3UE_fnc_fpv_swarmPass={params ["_record"];private _launching=[_record,["launching",false]] call FPV_getOrDefault;
 FPV_passes pushBack [FPV_time,count (_record get "drones"),_launching];
 if ((_record get "drones") isEqualTo [] && {!_launching}) then {_record set ["phase","DONE"];};
 if (FPV_time > 40) then {_record set ["phase","DONE"];};_record get "phase"};
private _t0=FPV_time;
["swarm1",["AT","AP","AP","AP","AP","AP","AP"],createHashMapFromArray [["AT",["kvn"]],["AP",["armafpv"]]]] call A3UE_fnc_fpv_swarmBrain;
private _at=FPV_spawned apply {(_x # 0)-_t0};
diag_log format ["launch at=%1 passes=%2",_at,FPV_passes select [0,6]];
private _want=[0,1.5,3,4.5,6,14,15.5];
[count _at==7,"seven launched: "+str _at] call _assert;
{[abs ((_at # _forEachIndex)-_x) < 0.06,format ["drone %1 at %2 s, wanted %3",_forEachIndex,_at # _forEachIndex,_x]] call _assert;} forEach _want;
[(_rec get "launched")==7 && {count FPV_locks==7},"counted and locked"] call _assert;
[(FPV_notes select {(_x # 0)=="STR_A3UE_FPV_SWARM_LAUNCHED"}) isEqualTo [["STR_A3UE_FPV_SWARM_LAUNCHED",[7]]],"HQ once, the whole swarm"] call _assert;
// Passes every 1.5 s from the start, while the trailing group still waits.
private _early=FPV_passes select {((_x # 0)-_t0) < 14};
[count _early >= 9 && {(_early findIf {!(_x # 2)}) < 0},"the brain runs during the launches: "+str count _early] call _assert;
// Each in its own lane beside the launch point, a straight line in (SW-1f).
private _lanes=FPV_spawned apply {round (((_x # 2) # 0)-1000)};
[(_lanes # 0)==0 && {(_lanes # 1)==-35} && {(_lanes # 2)==35} && {(_lanes # 6)==105},"lanes: "+str _lanes] call _assert;
// A swarm that leaves before the trailing group is due never launches it.
FPV_spawned=[];FPV_passes=[];FPV_time=FPV_time+100;
_rec=[[],"INBOUND"] call _newRecord;_rec set ["spawn",[1000,1600,0]];_rec set ["marker","mA"];_rec set ["launched",0];
A3UE_fnc_fpv_swarmPass={params ["_record"];FPV_passes pushBack FPV_time;
 if (count (_record get "drones") >= 2 && {(_record get "phase")!="LEAVING"}) then {_record set ["phase","LEAVING"];};
 if ((_record get "phase")=="LEAVING" && {!(_record get "launching")}) then {_record set ["phase","DONE"];};_record get "phase"};
["swarm1",["AP","AP","AP","AP","AP","AP"],createHashMapFromArray [["AP",["armafpv"]]]] call A3UE_fnc_fpv_swarmBrain;
[count FPV_spawned < 6 && {(_rec get "phase")=="DONE"},"leaving: the rest never launch: "+str count FPV_spawned] call _assert;
''')

    def test_turns_build_brake_and_ease_out(self):
        self.sqf(r'''
// SW-1f (EJ after SW1e: a drone "did an abrupt turn and came back"; SW-1e swung round at 75 deg/s at
// full speed from a standing start): a reversal builds its turn rate, brakes into it, stays under
// latAccel sideways and eases out onto the new heading.
private _d=["d1",[1000,1000,70],"AP","INBOUND"] call _swarmDrone;
_d setVariable ["velocity",[22,0,0]];
private _rec=[[_d],"INBOUND"] call _newRecord;
_d setVariable ["A3UE_FPV_swarmArrive",[200,1000,0]];
private _state=createHashMap;
[_d,_state] call _tick;
private _m0=count FPV_moves;
for "_i" from 1 to 400 do {[_d,_state] call _fly;};
private _hdg={params ["_v"];(_v # 0) atan2 (_v # 1)};
private _rates=[];private _worstLat=0;private _slowest=1e9;private _doneAt=-1;
for "_i" from (_m0+1) to ((count FPV_moves)-1) do {
 private _a=FPV_moves # (_i-1);private _b=FPV_moves # _i;
 private _dh=([_b] call _hdg)-([_a] call _hdg);if (_dh > 180) then {_dh=_dh-360};if (_dh < -180) then {_dh=_dh+360};
 private _rate=abs (_dh/0.02);_rates pushBack _rate;
 private _v=vectorMagnitude [_b # 0,_b # 1,0];
 _worstLat=_worstLat max (_v*(_rate/57.2958));_slowest=_slowest min _v;
 if (_doneAt < 0 && {abs (([_b] call _hdg)+90) < 3}) then {_doneAt=(_i-_m0)*0.02;};};
private _onset=(_rates select [0,5]);
diag_log format ["turn onset=%1 lat=%2 slowest=%3 doneAt=%4 maxRate=%5",_onset,_worstLat,_slowest,_doneAt,selectMax _rates];
[(_onset # 0) < 6 && {(_onset # 4) <= 15},"the turn builds (120 deg/s2; SW-1e: 75 deg/s at once): "+str _onset] call _assert;
[_worstLat <= 15.9,"at most 15 m/s2 sideways: "+str _worstLat] call _assert;
[_slowest <= 12.5,"brakes into the turn: "+str _slowest] call _assert;
[_doneAt > 2.4 && {_doneAt < 6},"round in "+str _doneAt+" s (SW-1e: 2.4 s at full speed)"] call _assert;
// Eased out: no overshoot past the new heading, and back to its speed.
private _last=FPV_moves select ((count FPV_moves)-1);
[abs (([_last] call _hdg)+90) < 2 && {(vectorMagnitude _last) > 21.5},"west at speed: "+str _last] call _assert;
''')

    def test_loiter_style_height_ring_and_direction(self):
        self.sqf(r'''
private _d=["d1",[1000,1100,70],"AP","LOITER"] call _swarmDrone;
_d setVariable ["A3UE_FPV_swarmStyle",[20,0,1,40,-1]];
private _rec=[[_d]] call _newRecord;
private _state=createHashMap;
[_d,_state] call _tick;
private _loiter=(FPV_ai select {(_x # 0)=="MOVE"}) # 0;
[abs (((_loiter # 1) distance2D [1000,1000,0])-160) < 1 && {(_loiter # 2)==90},"its own ring (160 m) and height (90 m): "+str _loiter] call _assert;
[((_loiter # 1) # 0) < 1000,"the other way round: "+str _loiter] call _assert;
// Bad style values fall back to the plain ring.
_d setVariable ["A3UE_FPV_swarmStyle",[20,"x",1,40,-1]];FPV_time=FPV_time+6;[_d,_state] call _tick;
_loiter=(FPV_ai select {(_x # 0)=="MOVE"}) select ((count (FPV_ai select {(_x # 0)=="MOVE"}))-1);
[abs (((_loiter # 1) distance2D [1000,1000,0])-120) < 1 && {(_loiter # 2)==70},"defaults: "+str _loiter] call _assert;
''')

    def test_push_over_is_gentle_and_continuous(self):
        self.sqf(r'''
// SW-1e (EJ after SW1d: "goes from steadily approaching immediately into a fast dive … almost snaps
// to the dive position"): the nose goes over gently from the cruise pose and the speed builds.
private _d=["d1",[1300,1000,70],"AP","ATTACK"] call _swarmDrone;
_d setVariable ["velocity",[-22,0,0]];
private _rec=[[_d]] call _newRecord;
["m","VMMan",[1000,1000,0]] call _enemy;
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];_d setVariable ["A3UE_FPV_swarmTargetClass","MAN"];
private _state=createHashMap;
private _n=0;
while {(_d getVariable "A3UE_FPV_swarmTask")=="ATTACK" && {_n < 1000}} do {[_d,_state] call _fly;_n=_n+1;};
[(_d getVariable "A3UE_FPV_swarmTask")=="DIVE","dives"] call _assert;
private _poseAt=count FPV_poses;private _moveAt=count FPV_moves;
while {(_d getVariable "A3UE_FPV_swarmTask")=="DIVE" && {!(_d getVariable ["A3UE_FPV_detonating",false])} && {_n < 2000}} do {[_d,_state] call _fly;_n=_n+1;};
[count FPV_strikes==1,"strikes: "+str FPV_strikes] call _assert;
private _pitch={params ["_v"];asin ((((_v # 2)/(vectorMagnitude _v)) max -1) min 1)};
private _v0=FPV_moves # (_moveAt-1);private _v15=FPV_moves # (_moveAt+14);private _v50=FPV_moves # (_moveAt+49);
private _over=([_v0] call _pitch)-([_v15] call _pitch);
diag_log format ["push over=%1 v0=%2 v15=%3 v50=%4",_over,_v0,_v15,_v50];
[_over > 5 && {_over <= 17.5},"a gentle start: "+str _over+" degrees in 0.3 s"] call _assert;
[((vectorMagnitude _v15)-(vectorMagnitude _v0)) < 2,"the speed builds: "+str [vectorMagnitude _v0,vectorMagnitude _v15]] call _assert;
[([_v50] call _pitch) < -30,"diving after a second: "+str ([_v50] call _pitch)] call _assert;
// The nose: no jump from the cruise into the dive (SW1d jumped from 18 degrees down to level).
private _nose={params ["_p"];asin ((((_p # 2) # 2) max -1) min 1)};
private _jump=0;
for "_i" from (_poseAt max 1) to ((_poseAt+8) min ((count FPV_poses)-1)) do {
 _jump=_jump max abs (([FPV_poses # _i] call _nose)-([FPV_poses # (_i-1)] call _nose));};
diag_log format ["push jump=%1 cruise=%2 first=%3",_jump,[FPV_poses # (_poseAt-1)] call _nose,[FPV_poses # _poseAt] call _nose];
[_jump < 8,"no snap: largest nose step "+str _jump] call _assert;
''')

    def test_dive_at_a_walking_man_banks_gently(self):
        self.sqf(r'''
// SW-1f (EJ after SW1e: "a crazy twist together when they started diving"): leading a man who walks
// across its line, SW-1e rolled 26 degrees and back in 0.75 s while its nose went over. At most 12 now.
private _d=["d1",[1000,1300,70],"AP","ATTACK"] call _swarmDrone;
_d setVariable ["velocity",[0,-22,0]];
private _rec=[[_d]] call _newRecord;
private _m=["m","VMMan",[1000,1000,0]] call _enemy;_m setVariable ["velocity",[3,0,0]];
_d setVariable ["A3UE_FPV_targetNetId","m"];_d setVariable ["A3UE_FPV_swarmTaskAt",FPV_time];_d setVariable ["A3UE_FPV_swarmTargetClass","MAN"];
private _state=createHashMap;private _n=0;private _p0=-1;
while {!(_d getVariable ["A3UE_FPV_detonating",false]) && {_n < 3000}} do {
 [_d,_state] call _fly;_n=_n+1;_m setVariable ["position",(_m getVariable "position") vectorAdd [0.06,0,0]];
 if (_p0 < 0 && {(_d getVariable "A3UE_FPV_swarmTask")=="DIVE"}) then {_p0=count FPV_poses;};};
[count FPV_strikes==1 && {_p0 > 0},"dived and struck: "+str FPV_strikes] call _assert;
private _bank={params ["_p"];_p params ["_f","_t","_nose","_up"];
 private _h=vectorNormalized [_nose # 0,_nose # 1,0];private _right=[_h # 1,-(_h # 0),0];
 private _lvl=vectorNormalized (_right vectorCrossProduct _nose);(_up vectorDotProduct _right) atan2 (_up vectorDotProduct _lvl)};
private _worst=0;
for "_i" from _p0 to ((count FPV_poses)-1) do {_worst=_worst max abs ([FPV_poses # _i] call _bank);};
diag_log format ["dive bank worst=%1 poses=%2",_worst,(count FPV_poses)-_p0];
[_worst <= 12.01,"bank in the dive at most 12 degrees: "+str _worst] call _assert;
''')

    def test_safety_no_enemy_protects_and_spent_drones_never_count(self):
        self.sqf(r'''
private _rec=[[]] call _newRecord;
private _m=["m","VMMan",[1000,1000,0]] call _enemy;
// AU makes a wounded enemy captive while a player is near (fn_unconsciousAAF): no protection.
private _w=["w","VMMan",[1005,1000,0]] call _enemy;_w setVariable ["captive",true];_w setVariable ["lifeState","INCAPACITATED"];
[([independent,_m,15] call FPV_safeReal)=="","a wounded enemy protects nobody"] call _assert;
_w setVariable ["lifeState","HEALTHY"];_w setVariable ["incapacitated",true];
[([independent,_m,15] call FPV_safeReal)=="","nor with AU's own flag"] call _assert;
// SW-1f (EJ after SW1e: "surrendered enemies should not shield active enemies"): nor a surrendered
// one (captive, on his feet, in his own side's group); nor a free enemy.
_w setVariable ["incapacitated",false];
private _r=[independent,_m,15] call FPV_safeReal;
[_r=="","a surrendered man protects nobody: "+_r] call _assert;
_w setVariable ["captive",false];
[([independent,_m,15] call FPV_safeReal)=="","a free enemy: none"] call _assert;
// SW-1f: a spent drone parked 1000 m over its strike with its crew alive (SW1e: three dives broken by
// it). Measured in 3D it is far away; flagged as struck or being removed it never counts at all.
private _g=["g","VMVehicle",[1003,1000,1000]] call _enemy;((_g getVariable "crew") # 0) setVariable ["side",independent];
[([independent,_m,15] call FPV_safeReal)=="","1000 m overhead: 3D"] call _assert;
_g setVariable ["position",[1003,1000,5]];
[([independent,_m,15] call FPV_safeReal)=="gc/GUER/free","the same crew beside him: "+([independent,_m,15] call FPV_safeReal)] call _assert;
_g setVariable ["A3UE_FPV_detonationCommitted",true];
[([independent,_m,15] call FPV_safeReal)=="","a spent drone never counts"] call _assert;
_g setVariable ["A3UE_FPV_detonationCommitted",false];_g setVariable ["A3UE_FPV_cleanupPending",true];
[([independent,_m,15] call FPV_safeReal)=="","nor one being removed"] call _assert;
_g setVariable ["position",[3000,3000,0]];
// Civilians and our own side do, inside the ring only; a managed drone never counts.
private _c=["c","VMMan",[1010,1000,0]] call _enemy;_c setVariable ["side",civilian];
_r=[independent,_m,15] call FPV_safeReal;
[_r=="c/CIV/free","a civilian: "+_r] call _assert;
_c setVariable ["position",[1020,1000,0]];
[([independent,_m,15] call FPV_safeReal)=="","20 m away"] call _assert;
private _o=["o","VMMan",[995,1000,0]] call _enemy;_o setVariable ["side",independent];
_r=[independent,_m,15] call FPV_safeReal;
[_r=="o/GUER/free","our own man: "+_r] call _assert;
_o setVariable ["A3UE_FPV_managed",true];
[([independent,_m,15] call FPV_safeReal)=="","a managed drone never counts"] call _assert;
// A friendly side; a vehicle's crew.
_o setVariable ["A3UE_FPV_managed",false];_o setVariable ["side",east];FPV_friends=[east];
[([independent,_m,15] call FPV_safeReal)!="","a friendly side"] call _assert;
FPV_friends=[];_o setVariable ["side",west];
private _v=["v","VMVehicle",[1008,1000,0]] call _enemy;((_v getVariable "crew") # 0) setVariable ["side",independent];
[([independent,_m,15] call FPV_safeReal)!="","our crew in a vehicle"] call _assert;
[([independent,objNull,15] call FPV_safeReal)=="NO_TARGET","no target"] call _assert;
''')


class SwarmContracts(unittest.TestCase):
    def test_every_function_is_registered(self):
        config = (ROOT / 'addons/drones/config.cpp').read_text()
        for name in ALL:
            self.assertIn(f'class fpv_{name} {{}};', config, name)
            self.assertTrue((FPV / f'fn_fpv_{name}.sqf').is_file(), name)

    def test_nothing_a_tick_or_pass_reaches_suspends(self):
        for name in ['swarmTick', 'swarmDive', 'swarmPass', 'swarmAssign', 'swarmScan', 'swarmSetTask',
                     'swarmDrop', 'swarmControl', 'swarmSettings', 'swarmRequest', 'swarmFly', 'swarmPose', 'swarmSafe']:
            body = code(name)
            self.assertNotRegex(body, r'\b(sleep|waitUntil|uiSleep)\b', name)
        # The brain is the only scheduled swarm script and runs each pass in one slice.
        self.assertIn('isNil {[_record, call A3UE_fnc_fpv_swarmSettings] call A3UE_fnc_fpv_swarmPass;};', code('swarmBrain'))

    def test_controller_branch_is_narrow(self):
        rc = code('runController')
        self.assertIn('private _swarmTick = _running && {(_uav getVariable ["A3UE_FPV_swarmId", ""]) isNotEqualTo ""};', rc)
        self.assertIn('[_uav, _state, _controllerIdentity, _generation] call A3UE_fnc_fpv_swarmTick', rc)
        self.assertIn('if (_running && {!_swarmTick}) then {', rc)
        self.assertEqual(rc.count('A3UE_fnc_fpv_swarmTick'), 1)

    def test_spawn_variables_are_prefixed_and_before_bootstrap(self):
        spawn = code('spawnManagedDrone')
        self.assertIn('(_name select [0, 9]) isEqualTo "A3UE_FPV_"', spawn)
        self.assertLess(spawn.index('_spec getOrDefault ["uavVars", []]'), spawn.index('A3UE_fnc_fpv_bootstrapLocal'))

    def test_authority_and_client_fences(self):
        fence = 'if (!isServer || {isRemoteExecutedJIP} || {isRemoteExecuted && {remoteExecutedOwner != 2}}) exitWith {'
        # SW-2: the commander's call, checked and charged by swarmCall, is the one remote caller let through.
        self.assertIn('if (!isServer || {isRemoteExecutedJIP} || {isRemoteExecuted && {remoteExecutedOwner != 2}\n'
                      '\t&& {!(localNamespace getVariable ["A3UE_FPV_swarmCallTrusted", false])}}) exitWith {[false, "AUTHORITY"]};',
                      code('swarmRequest'))
        call = code('swarmCall')
        self.assertIn('if (!isServer || {isRemoteExecutedJIP}) exitWith {};', call)
        self.assertLess(call.index('localNamespace setVariable ["A3UE_FPV_swarmCallTrusted", true];'),
                        call.index('call A3UE_fnc_fpv_swarmRequest;'))
        self.assertLess(call.index('call A3UE_fnc_fpv_swarmRequest;'),
                        call.index('localNamespace setVariable ["A3UE_FPV_swarmCallTrusted", false];'))
        self.assertNotIn('missionNamespace setVariable ["A3UE_FPV_swarmCallTrusted"', call)
        self.assertNotRegex(call, r'\b(sleep|waitUntil|uiSleep)\b')
        self.assertIn('remoteExecutedOwner != 2', code('swarmCallReply'))
        self.assertIn(fence + '};', code('swarmBrain'))
        for name in ['swarmNotify', 'swarmLock']:
            self.assertIn('remoteExecutedOwner != 2', code(name), name)
        self.assertIn('[_uav] remoteExecCall ["A3UE_fnc_fpv_swarmLock", 0, _uav];', code('swarmBrain'))
        self.assertIn('player disableUAVConnectability [_uav, true];', code('swarmLock'))

    def test_strike_uses_the_managed_commit_and_fence(self):
        dive = code('swarmDive')
        self.assertIn('[_uav, "SET"] call A3UE_fnc_fpv_contactFence;', dive)
        self.assertIn('call A3UE_fnc_fpv_detonateCompat;', dive)
        self.assertIn('[_uav, "RELEASE"] call A3UE_fnc_fpv_contactFence;', dive)
        self.assertNotIn('createVehicle', dive)
        self.assertNotIn('triggerAmmo', dive)
        # One pose writer for the cruise and the dive (SW-1e), at the D1 cadence.
        self.assertIn('if (_dt <= 0 || {(_now - _poseAt) < 0.05} || {(diag_frameNo - _poseFrame) < 3}) exitWith', code('swarmPose'))
        self.assertIn('[_poseAt, _poseFrame, _attitude], _settings get "diveBank"] call A3UE_fnc_fpv_swarmPose;', code('swarmDive'))
        for name in ['swarmDive', 'swarmFly']:
            self.assertIn('call A3UE_fnc_fpv_swarmPose;', code(name), name)
            self.assertNotIn('setVectorDirAndUp', code(name), name)
        # SW-1f: each drone launches in its own lane; the run-in has no lane swerve any more.
        brain = code('swarmBrain')
        self.assertIn('private _from = _spawn getPos [abs _lane, _bearing + ([90, -90] select (_lane < 0))];', brain)
        self.assertIn('["spawnPosATL", [_from # 0, _from # 1, _settings get "spawnHeight"]]', brain)
        self.assertIn('if (surfaceIsWater _from && {!surfaceIsWater _spawn}) then {_from = +_spawn;};', brain)
        self.assertNotIn('laneFar', code('swarmTick'))
        self.assertNotIn('_lane', code('swarmTick'))
        # The swarm's own friendly check everywhere (no enemy protects anyone).
        for name in ['swarmTick', 'swarmDive', 'swarmAssign']:
            self.assertIn('call A3UE_fnc_fpv_swarmSafe;', code(name), name)
            self.assertNotIn('supportPassesSafetyRing', code(name), name)

    def test_the_attack_is_simple(self):
        # SW-1g (EJ after SW1f: the passes and picky target checks made the flight "crazy"; "pick a
        # target, not picky about obstacles, and go for them"): no corridor, sight check, passes or
        # commit at the gate, no look-ahead or BLOCKED return in the dive, and the roof only orders targets.
        tick, dive, assign = code('swarmTick'), code('swarmDive'), code('swarmAssign')
        for word in ['checkVisibility', 'GATE_BLOCKED', 'UNSEEN', 'swarmRun', 'passDir', 'forced', 'swarmClear']:
            self.assertNotIn(word, tick, word)
        for word in ['swarmClear', 'BLOCKED', 'lookAheadS', '_forced', '_aheadAt']:
            self.assertNotIn(word, dive, word)
        self.assertNotIn('coverWaitS', assign)
        self.assertIn('&& {!([_id, _class] call _triedOut)}', assign)
        # SW-1i: anti-tank drones stay on armour (no cap of two); dives at one target a tap gap apart.
        self.assertNotIn('_holders < 2', assign)
        self.assertIn('{!_tapHeld}', tick)
        self.assertNotIn('struck', code('swarmRequest'))
        self.assertIn('if (isNull _choice && {!isNull _fallback}) then {', assign)
        self.assertIn('_record getOrDefault ["launching", false]', code('swarmPass'))

    def test_strings_exist(self):
        table = (ROOT / 'addons/drones/stringtable.xml').read_text()
        keys = set(re.findall(r'"(STR_A3UE_FPV_SWARM_\w+)"', ''.join(code(n) for n in ALL)))
        keys |= set(re.findall(r'"(STR_A3UE_FPV_SWARM_\w+)"', ''.join((FPV / 'au_menu' / f'fn_{w}.sqf').read_text() for w in MENU)))
        self.assertGreaterEqual(len(keys), 11)
        for key in sorted(keys | {f'STR_A3UE_FPV_SWARM_{k}' for k in ['LAUNCHED', 'ON_STATION', 'LEAVING', 'MARKER']}):
            self.assertIn(f'<Key ID="{key}">', table, key)

    def test_menu_wrappers_run_au_first_and_add_only_the_swarm(self):
        # SW-2 (EJ, 17 November: "like an AU bombing run"; design §2): AU's Supports tab gets an "FPV drone
        # swarm" entry. Each wrapper runs AU's own copy of the function it replaces; only the swarm's type
        # gets our code, and the commander's machine only asks: the server checks and charges.
        config = (ROOT / 'addons/drones/config.cpp').read_text()
        self.assertIn('requiredAddons[] = {"A3A_core", "A3A_scrt", "A3_Weapons_F_Tank"};', config)
        scrt = config.split('    class SCRT {', 1)[1]
        stock = code('getStockAUFunction')
        self.assertIn('format ["\\x\\A3A\\addons\\scrt\\UI\\fn_%1.sqf", _name]', stock)
        for name in MENU:
            path = FPV / 'au_menu' / f'fn_{name}.sqf'
            text = path.read_text()
            body = '\n'.join(line.split('//', 1)[0] for line in text.splitlines())
            self.assertIn(f'file = "\\fpv_ai_drones\\functions\\fpv\\au_menu\\fn_{name}.sqf";', scrt, name)
            self.assertEqual(len(re.findall(r'\bclass\s+' + name + r'\s*\{', config)), 1, name)
            self.assertIn(f'case "{name}"', stock, name)
            self.assertIn(f'(["{name}"] call A3UE_fnc_fpv_getStockAUFunction)', body, name)
            # Named in the header, so au_compat_check fingerprints AU's copy (drift shows as REVIEW).
            self.assertIn(f'SCRT_fnc_{name}', text, name)
            self.assertNotRegex(body, r'\bsupportPoints\s*=|A3A_fnc_resourcesFIA', name)
            # Session SW2: AU's menu functions return nothing; handing that on was an undefined-variable error.
            self.assertNotIn('_result', body, name)
        launch = '\n'.join(line.split('//', 1)[0] for line in (FPV / 'au_menu' / 'fn_ui_launchSupport.sqf').read_text().splitlines())
        # Every other type: AU's copy and nothing else.
        self.assertTrue(launch.lstrip().startswith('if (isNil "supportType" || {supportType isNotEqualTo "A3UE_FPV_SWARM"}) exitWith {\n'
                                                   '\t_this call (["ui_launchSupport"] call A3UE_fnc_fpv_getStockAUFunction)\n};'))
        self.assertIn('remoteExecCall ["A3UE_fnc_fpv_swarmCall", 2];', launch)
        self.assertLess(launch.index('remoteExecCall ["A3UE_fnc_fpv_swarmCall", 2];'), launch.index('supportCooldown = true;'))
        manage = (FPV / 'au_menu' / 'fn_ui_manageSupportTabEventHandler.sqf').read_text()
        self.assertLess(manage.index('["A3UE_FPV_swarmMap", "onMapSingleClick"] call BIS_fnc_removeStackedEventHandler;'),
                        manage.index('(["ui_manageSupportTabEventHandler"] call A3UE_fnc_fpv_getStockAUFunction)'))
        self.assertIn('[_pos] spawn A3UE_fnc_fpv_swarmMenuMark;', manage)
        self.assertIn('deleteMarkerLocal "A3UE_FPV_swarmCircle";', (FPV / 'au_menu' / 'fn_ui_clearSupport.sqf').read_text())
        # One type id everywhere.
        for text in [launch, manage, code('swarmMenuMark'), (FPV / 'au_menu' / 'fn_ui_updateSupportMenu.sqf').read_text(),
                     (FPV / 'au_menu' / 'fn_ui_setSupportCostText.sqf').read_text()]:
            self.assertIn('"A3UE_FPV_SWARM"', text)
        self.assertIn('if (_key == "STR_A3UE_FPV_SWARM_ON_STATION") then {A3UE_FPV_swarmArrivedAt = time;};', code('swarmNotify'))


if __name__ == '__main__':
    unittest.main()
