params ["_uav", "_key", "_value", ["_interval", 0.5]];

if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};

private _publish = false;
// Keep the owner check and per-key deadline update in one unscheduled slice.
isNil {
	if (!isNull _uav && {local _uav}) then {
		private _clock = _uav getVariable ["A3UE_FPV_telemetryNextAt", createHashMap];
		private _now = time;
		_publish = _now >= (_clock getOrDefault [_key, -1]);
		_uav setVariable [_key, _value, _publish];
		if (_publish) then {
			_clock set [_key, _now + _interval];
			_uav setVariable ["A3UE_FPV_telemetryNextAt", _clock];
		};
	};
};

_publish
