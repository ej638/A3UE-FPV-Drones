// F4-2 dive start on a clear line: a pilot does not push over into trees, buildings or a crest
// between the drone and the target. One ray from the drone to 8 m short of the target (the
// target's own surroundings stay with the cover rules), cached per target for 0.25 s.
// [uav, target] -> true when the line is clear
params [["_uav", objNull], ["_target", objNull]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {true};
if (isNull _uav || {isNull _target}) exitWith {true};
private _now = time;
private _cache = _uav getVariable ["A3UE_FPV_attackClearLine", []];
if (_cache isEqualType [] && {count _cache == 3} && {(_cache # 0) isEqualTo (netId _target)}
	&& {_now >= (_cache # 1)} && {_now - (_cache # 1) < 0.25}) exitWith {_cache # 2};
private _from = getPosASL _uav;
private _to = (getPosASL _target) vectorAdd [0, 0, [1.0, 1.15] select (_target isKindOf "Man")];
private _delta = _to vectorDiff _from;
private _length = vectorMagnitude _delta;
private _clear = true;
if (_length > 12) then {
	_clear = ([_uav, _target, _from, _from vectorAdd (_delta vectorMultiply ((_length - 8) / _length)), false, false]
		call A3UE_fnc_fpv_obstacleProbe) isEqualTo [];
};
if (local _uav) then {_uav setVariable ["A3UE_FPV_attackClearLine", [netId _target, _now, _clear]];};
_clear
