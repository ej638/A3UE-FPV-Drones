// 1.0.9 friendly FPV swarm (SW-1b): is the way clear? One GEOM ray (the shapes an airframe actually
// hits, terrain included), ignoring the drone, the target and anyone inside either. Used two ways
// since SW-1g (the dive gate's corridor and the dive's look-ahead are gone: EJ, "not picky"):
// - the roof over a target: one ray up (open targets are taken first);
// - the cruise's look-ahead: one ray along the next 2 s of the path (climb over it).
// One ray from "from" to "to" (SW-1g: SW-1b's three parallel corridor rays went with the gate).
// [uav, target, fromASL, toASL] -> [] when clear, else [hitASL, what]
params [["_uav", objNull], ["_target", objNull], ["_from", []], ["_to", []]];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {[]};
if !(_from isEqualType [] && {count _from == 3} && {_to isEqualType []} && {count _to == 3}) exitWith {[]};
if ((_from vectorDistance _to) < 0.5) exitWith {[]};
private _found = [];
private _hits = lineIntersectsSurfaces [_from, _to, _uav, _target, true, 4, "GEOM", "NONE"];
private _index = _hits findIf {
	private _object = _x param [3, objNull];
	if (isNull _object) then {_object = _x param [2, objNull];};
	isNull _object || {
		_object isNotEqualTo _uav && {_object isNotEqualTo _target}
		&& {(objectParent _object) isNotEqualTo _target} && {(objectParent _object) isNotEqualTo _uav}
		&& {_object isNotEqualTo (objectParent _target)}
	}
};
if (_index >= 0) then {
	private _hit = _hits # _index;
	private _object = _hit param [3, objNull];
	if (isNull _object) then {_object = _hit param [2, objNull];};
	private _what = if (isNull _object) then {"terrain"} else {typeOf _object};
	if (_what == "") then {_what = str _object;};
	_found = [+(_hit # 0), _what];
};
_found
