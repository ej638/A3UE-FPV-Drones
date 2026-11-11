params ["_uav", "_stage", "_id", "_owner", "_episode", "_generation", "_token", "_path"];
if (isRemoteExecutedJIP || {isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}}) exitWith {false};
if (canSuspend) exitWith {private _ok = false; isNil {_ok = _this call A3UE_fnc_fpv_acceptLifecycle;}; _ok};
if (isNull _uav || {!local _uav} || {!alive _uav} || {_owner != clientOwner}
    || {_uav getVariable ["A3UE_FPV_cleanupPending", false]}) exitWith {false};
private _managed = _uav getVariable ["A3UE_FPV_managed", false];
if (!_managed && {_uav getVariable ["A3UE_FPV_nativePromoted", false]}) exitWith {false};
private _localGeneration = _uav getVariable [["A3UE_FPV_nativeGeneration", "A3UE_FPV_controllerGeneration"] select _managed, -1];
if (_localGeneration != _generation) exitWith {false};
private _knownId = _uav getVariable ["A3UE_FPV_lifecycleId", -1];
if (_knownId >= 0 && {_knownId != _id}) exitWith {false};
private _accepted = _uav getVariable ["A3UE_FPV_lifecycleTicketIdentity", []];
private _knownEpisode = _uav getVariable ["A3UE_FPV_lifecycleEpisode", 0];
if (count _accepted == 4) then {_knownEpisode = _knownEpisode max (_accepted # 2);};
private _published = _uav getVariable ["A3UE_FPV_controllerIdentity", []];
if (count _published == 4 && {(_published # 0) == _id}) then {_knownEpisode = _knownEpisode max (_published # 2);};
if (_episode < _knownEpisode) exitWith {false};
if (_stage == "retry") exitWith {
    // A base-episode correction is not an accepted ticket. Keep request spacing.
    _uav setVariable ["A3UE_FPV_lifecycleId", _id];
    _uav setVariable ["A3UE_FPV_lifecycleEpisode", _episode];
    if (_managed) then {[_uav] call A3UE_fnc_fpv_bootstrapLocal;} else {[_uav] call A3UE_fnc_fpv_trackKvnLifecycle;};
    true
};
if (_stage == "challenge") exitWith {
    private _request = [_id, _episode, 0, "claim", _token, []];
    if (isServer) then {_request call A3UE_fnc_fpv_reportLifecycle;} else {_request remoteExecCall ["A3UE_fnc_fpv_reportLifecycle", 2];};
    true
};
if (_stage != "ready") exitWith {false};
private _oldTicket = _uav getVariable ["A3UE_FPV_lifecycleTicket", []];
private _identity = [_id, _owner, _episode, _generation];
private _duplicate = _accepted isEqualTo _identity && {_oldTicket isEqualTo [_id, _episode, _token]};
if (_token == "") exitWith {false};
if (_accepted isEqualTo _identity && {!_duplicate}) exitWith {false};
// Private owner ticket is deliberately never broadcast. Replicated identity
// and a bounded canonical path travel in this same authenticated reply.
if (!_duplicate) then {
    _uav setVariable ["A3UE_FPV_lifecycleTicket", [_id, _episode, _token]];
    _uav setVariable ["A3UE_FPV_lifecycleTicketIdentity", _identity];
    _uav setVariable ["A3UE_FPV_reportSequences", createHashMap];
};
_uav setVariable ["A3UE_FPV_controllerIdentity", _identity];
_uav setVariable ["A3UE_FPV_lifecycleId", _id];
_uav setVariable ["A3UE_FPV_lifecycleEpisode", _episode];
if (_managed) then {
    if (!_duplicate && {(_uav getVariable ["A3UE_FPV_vendorId", ""]) == "kvn"}) then {[_uav, _path, _generation] call A3UE_fnc_fpv_adoptFiberPath;};
    [_uav, _generation] call A3UE_fnc_fpv_bootstrapLocal;
};
true
