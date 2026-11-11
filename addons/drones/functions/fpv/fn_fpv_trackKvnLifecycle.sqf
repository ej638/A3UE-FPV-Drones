params [["_uav", objNull, [objNull]], ["_initialIdentity", [], [[]]]];
if (isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}) exitWith {false};
if (isNull _uav || {!(_uav isKindOf "frtz_drone_kvn_base_F")}) exitWith {false};
if (canSuspend) exitWith {private _ok = false; isNil {_ok = _this call A3UE_fnc_fpv_trackKvnLifecycle;}; _ok};
if (_uav getVariable ["A3UE_FPV_managed", false]) exitWith {
    _uav setVariable ["A3UE_FPV_nativePromoted", true];
    private _retry = _uav getVariable ["A3UE_FPV_nativeClaimRetry", scriptNull];
    if !(scriptDone _retry) then {terminate _retry;};
    _uav setVariable ["A3UE_FPV_nativeClaimRetry", scriptNull];
    true
};
if (_uav getVariable ["A3UE_FPV_nativePromoted", false] || {_uav getVariable ["A3UE_FPV_cleanupPending", false]}) exitWith {false};
private _identity = _uav getVariable ["A3UE_FPV_controllerIdentity", []];
if (count _initialIdentity == 4 && {count _identity != 4}) then {
    _uav setVariable ["A3UE_FPV_controllerIdentity", _initialIdentity];
    _uav setVariable ["A3UE_FPV_lifecycleId", _initialIdentity # 0];
    _uav setVariable ["A3UE_FPV_lifecycleEpisode", _initialIdentity # 2];
};
if (isServer) then {[_uav] call A3UE_fnc_fpv_registerLifecycle;};
if ((_uav getVariable ["A3UE_FPV_nativeLocalEH", -1]) < 0) then {
    private _eh = _uav addEventHandler ["Local", {
        params ["_vehicle", "_local"];
        if (_vehicle getVariable ["A3UE_FPV_managed", false]) exitWith {};
        if (!_local) then {[_vehicle, "release", []] call A3UE_fnc_fpv_sendLifecycle;};
        _vehicle setVariable ["A3UE_FPV_nativeGeneration", 1 + (_vehicle getVariable ["A3UE_FPV_nativeGeneration", 0])];
        _vehicle setVariable ["A3UE_FPV_lifecycleTicket", []];
        _vehicle setVariable ["A3UE_FPV_lifecycleTicketIdentity", []];
        _vehicle setVariable ["A3UE_FPV_nativeClaimAttempts", 0];
        private _retry = _vehicle getVariable ["A3UE_FPV_nativeClaimRetry", scriptNull];
        if !(scriptDone _retry) then {terminate _retry;};
        _vehicle setVariable ["A3UE_FPV_nativeClaimRetry", scriptNull];
        if (_local) then {[_vehicle] spawn A3UE_fnc_fpv_trackKvnLifecycle;};
    }];
    _uav setVariable ["A3UE_FPV_nativeLocalEH", _eh];
};
if (local _uav && {!(_uav getVariable ["A3UE_FPV_managed", false])}) then {
    if (count (_uav getVariable ["A3UE_FPV_lifecycleTicket", []]) == 3) exitWith {true};
    private _generation = _uav getVariable ["A3UE_FPV_nativeGeneration", 0];
    _uav setVariable ["A3UE_FPV_nativeGeneration", _generation];
    private _identity = _uav getVariable ["A3UE_FPV_controllerIdentity", []];
        if (count _identity != 4 && {(_uav getVariable ["A3UE_FPV_lifecycleId", -1]) >= 0}) then {
            _identity = [_uav getVariable "A3UE_FPV_lifecycleId", clientOwner, _uav getVariable ["A3UE_FPV_lifecycleEpisode", 0], -1];
        };
    if (count _identity == 4) then {
        private _request = [_uav, _uav getVariable ["A3UE_FPV_lifecycleEpisode", _identity # 2], _generation];
        if (isServer) then {_request call A3UE_fnc_fpv_claimLifecycle;} else {_request remoteExecCall ["A3UE_fnc_fpv_claimLifecycle", 2];};
    };
    private _attempts = _uav getVariable ["A3UE_FPV_nativeClaimAttempts", 0];
    private _retry = _uav getVariable ["A3UE_FPV_nativeClaimRetry", scriptNull];
    if (_attempts < 5 && {scriptDone _retry} && {count (_uav getVariable ["A3UE_FPV_lifecycleTicket", []]) != 3}) then {
        _uav setVariable ["A3UE_FPV_nativeClaimAttempts", _attempts + 1];
        _uav setVariable ["A3UE_FPV_nativeClaimRetry", [_uav, _generation] spawn {
            params ["_vehicle", "_generation"];
            sleep 1;
            if (!isNull _vehicle && {local _vehicle} && {alive _vehicle}
                && {!(_vehicle getVariable ["A3UE_FPV_managed", false])}
                && {!(_vehicle getVariable ["A3UE_FPV_nativePromoted", false])}
                && {(_vehicle getVariable ["A3UE_FPV_nativeGeneration", -1]) == _generation}) then {
                _vehicle setVariable ["A3UE_FPV_nativeClaimRetry", scriptNull];
                [_vehicle] call A3UE_fnc_fpv_trackKvnLifecycle;
            };
        }];
    };
};
true
