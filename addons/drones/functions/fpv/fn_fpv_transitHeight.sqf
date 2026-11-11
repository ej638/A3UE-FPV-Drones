// F4-2 native-flight clearance. IDLE/SEARCHING/TRACKING/LOST_TARGET are flown by the AI with
// flyInHeight, which is height above the terrain and ignores trees (the 15 m tracking height
// flew through Virolahti forest). Returns the minimum flight height AGL: the canopy-clearing
// transit floor, raised for 6 s over a tall obstacle that a forward probe at the drone's own
// height finds within 4 s of flight (at most one probe per 0.5 s per drone, owner-local).
// [uav, settings (optional)] -> metres AGL; 0 when the attack run is off.
params [["_uav", objNull], ["_settings", []]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {0};
if (isNull _uav) exitWith {0};
if (_settings isEqualTo []) then {_settings = call A3UE_fnc_fpv_attackSettings;};
if !(_settings # 0) exitWith {0};
private _floor = _settings # 12;
if (!(_settings # 11) || {!local _uav}) exitWith {_floor};
private _now = time;
private _probe = _uav getVariable ["A3UE_FPV_transitProbe", []];
if !(_probe isEqualType [] && {count _probe == 3} && {(_probe findIf {!(_x isEqualType 0) || {!finite _x}}) < 0}) then {
	_probe = [-1, -1, 0];
};
_probe params ["_nextAt", "_raiseUntil", "_raiseTo"];
if (_now >= _nextAt || {_nextAt - _now > 0.5}) then {
	_nextAt = _now + 0.5;
	private _velocity = velocity _uav;
	private _flat = [_velocity # 0, _velocity # 1, 0];
	private _speed = vectorMagnitude _flat;
	if (_speed > 3) then {
		private _from = getPosASL _uav;
		private _look = ((_speed * 4) max 40) min 120;
		private _found = [_uav, objNull, _from, _from vectorAdd (_flat vectorMultiply (_look / _speed)), true, true] call A3UE_fnc_fpv_obstacleProbe;
		if (_found isNotEqualTo []) then {
			// Clear the obstacle's top by 12 m; the AI keeps following the terrain itself.
			_raiseTo = ((((_found # 1) - (_found # 3)) + 12) max 0) min 100;
			_raiseUntil = _now + 6;
		};
	};
	_uav setVariable ["A3UE_FPV_transitProbe", [_nextAt, _raiseUntil, _raiseTo]];
};
if (_now < _raiseUntil) then {_floor max _raiseTo} else {_floor}
