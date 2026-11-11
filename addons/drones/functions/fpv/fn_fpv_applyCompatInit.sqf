params [["_uav", objNull]];

if (isRemoteExecutedJIP || {isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}}) exitWith {false};

if (isNull _uav) exitWith {false};
if !(_uav getVariable ["A3UE_FPV_managed", false]) exitWith {false};

private _applyCompatState = {
	params ["_uav", "_generation"];

	// Also guards live identity, locality, retirement, direct control and site viability.
	if !([_uav, _generation] call A3UE_fnc_fpv_applyTargetability) exitWith {false};
    // A delayed compatibility retry must not re-enable the managed movement writer.
    if ((_uav getVariable ["A3UE_FPV_nativeControl",[]]) isEqualTo []) then {_uav enableAI "ALL";};
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
            // Missing/invalid initial state only. Adoption reconciles caches once
            // per claim; repeat/delayed normalization must preserve live bends.
            private _path = _uav getVariable ["kvn_fiber_path", []];
            if !([_path, true] call A3UE_fnc_fpv_validFiberPath) then {
                _uav setVariable ["kvn_fiber_path", []];
                _uav setVariable ["kvn_fiber_length", 0];
                _uav setVariable ["kvn_fiber_length_count", 0];
            };
		};
	};
	true
};

private _result = false;
isNil {
	private _generation = _uav getVariable ["A3UE_FPV_controllerGeneration", 0];
	_result = [_uav, _generation] call _applyCompatState;
	if (alive _uav && {local _uav} && {_uav getVariable ["A3UE_FPV_managed", false]}
		&& {netId _uav == (_uav getVariable ["A3UE_FPV_netId", ""])}
		&& {!(_uav getVariable ["A3UE_FPV_compatNormalizeQueued", false])
			|| {(_uav getVariable ["A3UE_FPV_compatNormalizeGeneration", -1]) != _generation}}) then {
		_uav setVariable ["A3UE_FPV_compatNormalizeQueued", true];
		_uav setVariable ["A3UE_FPV_compatNormalizeGeneration", _generation];
		[_uav, _generation, _applyCompatState] spawn {
			params ["_uav", "_generation", "_applyCompatState"];
			sleep 1.25;
			isNil {
				[_uav, _generation] call _applyCompatState;
				// An old ownership episode cannot clear a newer episode's queued retry.
				if (!isNull _uav && {(_uav getVariable ["A3UE_FPV_compatNormalizeGeneration", -1]) == _generation}) then {
					_uav setVariable ["A3UE_FPV_compatNormalizeQueued", false];
				};
			};
		};
	};
};

_result
