// Evidence line for a managed drone destroyed outside the strike commit path: a tree or wall
// strike, shot down, a launch collision, or another drone's blast. Server only, from MPKilled
// (via=KILLED), KVN's native detonate-and-delete hit handler (via=KVN_HIT) or the deletion that
// follows UA's native hit detonation (via=UA_HIT, no killer known), while the
// lifecycle is still live (a committed strike has already closed it, so it is never logged twice).
// Cost per loss: two 12 m nearest-object queries and one RPT line; nothing per frame.
// [uav, killer, instigator, lifecycleId, via] -> true when logged
params [["_uav", objNull], ["_killer", objNull], ["_instigator", objNull], ["_id", -1], ["_via", "KILLED"]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};
if !(_via isEqualType "") then {_via = "KILLED";};
if (!isServer || {isNull _uav} || {!(_id isEqualType 0)} || {_id < 0}) exitWith {false};
private _record = (missionNamespace getVariable ["A3UE_FPV_lifecycles", createHashMap]) getOrDefault [str _id, createHashMap];
if (!(_record isEqualType createHashMap) || {count _record == 0} || {(_record getOrDefault ["phase", ""]) != "live"}
	|| {!(_record getOrDefault ["managed", false])}) exitWith {false};
// A lethal KVN hit can raise both its hit handler and MPKilled: one line per drone.
if (_uav getVariable ["A3UE_FPV_lossLogged", false]) exitWith {false};
_uav setVariable ["A3UE_FPV_lossLogged", true];
private _pos = getPosASL _uav;
private _terrainZ = getTerrainHeightASL [_pos # 0, _pos # 1];
private _near = ASLToAGL _pos;
private _describe = {
	params ["_object"];
	if (isNull _object) exitWith {"none"};
	private _box = boundingBoxReal _object;
	private _name = (getModelInfo _object) param [0, ""];
	if (_name == "") then {_name = typeOf _object;};
	format ["%1@%2m/h%3m", _name, (round ((_object distance2D _uav) * 10)) / 10,
		(round ((((_box # 1) # 2) - ((_box # 0) # 2)) * 10)) / 10]
};
private _who = {
	params ["_unit"];
	if (isNull _unit) exitWith {"none"};
	if (_unit isEqualTo _uav || {_unit in (crew _uav)}) exitWith {"self"};
	typeOf _unit
};
private _terrainObject = (nearestTerrainObjects [_near, [], 12, true, true]) param [0, objNull];
private _missionObject = ((nearestObjects [_near, ["Static"], 12, true]) select {_x isNotEqualTo _uav}) param [0, objNull];
diag_log format ["[A3UE_FPV] droneLost id=%1 lifecycle=%2 mode=%3 site=%4 support=%5 target=%6 killer=%7 instigator=%8 pos=%9 aglM=%10 speed=%11 terrainObject=%12 missionObject=%13 via=%14",
	netId _uav, _id, _uav getVariable ["A3UE_FPV_mode", ""], _record getOrDefault ["site", ""], _record getOrDefault ["support", ""],
	_uav getVariable ["A3UE_FPV_targetNetId", ""], [_killer] call _who, [_instigator] call _who,
	_pos apply {round _x}, (round (((_pos # 2) - _terrainZ) * 10)) / 10, (round ((vectorMagnitude (velocity _uav)) * 10)) / 10,
	[_terrainObject] call _describe, [_missionObject] call _describe, _via];
true
