// F4-1 TRACKING waypoint for the engagement's approach profile. Native AI still flies it
// through applyGuidance: HIGH_DIVE holds a high approach for a steep dive; FLANK first
// detours to a side bearing on a ring around the target, then turns in. DIRECT and every
// disabled case return the intercept unchanged.
// [uav, target, controllerIdentity, intercept ASL] -> waypoint ASL
params [["_uav", objNull], ["_target", objNull], ["_controllerIdentity", []], ["_intercept", []]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {_intercept};
if (!(_intercept isEqualType []) || {count _intercept < 3}) exitWith {_intercept};
private _record = [_uav, _target, _controllerIdentity, true] call A3UE_fnc_fpv_attackEngagement;
if (_record isEqualTo []) exitWith {_intercept};
private _targetPos = getPosASL _target;
private _result = _intercept;
if ((_record # 1) == "HIGH_DIVE") then {
	_result = +_intercept;
	_result set [2, (_intercept # 2) max ((_targetPos # 2) + ((_record # 2) # 0))];
};
if ((_record # 1) == "FLANK" && {(_record # 3) == "LEG"}) then {
	(_record # 2) params ["_side", "_angle", "_radius"];
	private _bearing = (_record # 4) + _side * _angle;
	private _waypoint = [(_targetPos # 0) + _radius * (sin _bearing), (_targetPos # 1) + _radius * (cos _bearing), _intercept # 2];
	private _uavPos = getPosASL _uav;
	private _relative = _uavPos vectorDiff _targetPos;
	private _current = (_relative # 0) atan2 (_relative # 1);
	private _offBearing = abs ((((((_current - _bearing) mod 360) + 540) mod 360)) - 180);
	if (_offBearing <= 15 || {(_uavPos distance2D _waypoint) <= 60} || {time - (_record # 5) > 25}) then {
		// Side reached (or bounded timeout): turn in on the ordinary intercept.
		if (local _uav && {(_uav getVariable ["A3UE_FPV_controllerIdentity", []]) isEqualTo _controllerIdentity}) then {
			private _updated = +_record;
			_updated set [3, "IN"];
			_uav setVariable ["A3UE_FPV_attackEngagement", _updated];
		};
	} else {
		_result = _waypoint;
	};
};
_result
