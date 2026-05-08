params [["_uav", objNull]];

if (isNull _uav) exitWith {false};

private _applyCompatState = {
	params ["_uav"];

	if (isNull _uav) exitWith {false};
	if (!local _uav) exitWith {false};

	_uav enableAI "ALL";
	_uav setVariable ["DB_jammer_customUavBehavior", true, true];
	_uav setVariable ["A3UE_FPV_linkState", "OK", true];

	switch (_uav getVariable ["A3UE_FPV_vendorId", ""]) do {
		case "armafpv": {
			_uav setVariable ["DB_fpv_isDetonating", false, true];
			_uav setVariable ["DB_fpv_isUAVsignalLost", false, true];
		};

		case "fpv_ua": {
			_uav setVariable ["UA_fpv_isUAVsignalLost", false, true];
		};

		case "kvn": {
			_uav setCaptive false;
			_uav setVariable ["kvn_fiber_path", [], false];
			_uav setVariable ["kvn_fiber_length", 0, false];
			_uav setVariable ["kvn_fiber_length_count", 0, false];
			_uav setVariable ["kvn_lastSync", time, false];
		};
	};

	true
};

private _result = [_uav] call _applyCompatState;

if (local _uav && {!(_uav getVariable ["A3UE_FPV_compatNormalizeQueued", false])}) then {
	_uav setVariable ["A3UE_FPV_compatNormalizeQueued", true];

	[_uav, _applyCompatState] spawn {
		params ["_uav", "_applyCompatState"];

		sleep 1.25;
		[_uav] call _applyCompatState;

		if (!isNull _uav) then {
			_uav setVariable ["A3UE_FPV_compatNormalizeQueued", false];
		};
	};
};

_result