params [["_id", -1, [0]], ["_event", "", [""]]];
if !(call A3UE_fnc_fpv_lifecycleAccess) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
if (canSuspend) exitWith {private _ok = false; isNil {_ok = _this call A3UE_fnc_fpv_endLifecycle;}; _ok};
if !(_event in ["kill", "delete", "retire", "detonate"]) exitWith {false};
private _record = (missionNamespace getVariable ["A3UE_FPV_lifecycles", createHashMap]) getOrDefault [str _id, createHashMap];
if (count _record == 0) exitWith {false};
if ((_record get "phase") != "live") exitWith {
    // Retirement settles membership immediately. Physical deletion is the
    // eligible archive event; a controlled airframe left alive never archives.
    private _geometry = _record getOrDefault ["retiredGeometry", []];
    if (_event != "delete" || {(_record get "outcome") != "retire"} || {count _geometry != 2}
        || {serverTime > (_record get "lateUntil")}) exitWith {false};
    _record set ["outcome", "delete"];
    [_geometry # 0, _geometry # 1, str _id] call A3UE_fnc_fpv_archiveFiber;
    _record deleteAt "retiredGeometry";
    _record set ["object", objNull];
    true
};
private _uav = _record get "object";
_record set ["phase", "closed"];
_record set ["closedAt", serverTime];
_record set ["lateUntil", serverTime + 5];
_record set ["outcome", _event];
_record deleteAt "challenge";
private _index = missionNamespace getVariable ["A3UE_FPV_lifecycleIndex", createHashMap];
if ((_index getOrDefault [_record get "netId", -1]) == _id) then {_index deleteAt (_record get "netId");};
private _A3UE_FPV_lifecycleAuthorized = A3UE_FPV_lifecycleCapability;
if (_record get "managed") then {
    private _reason = switch (_event) do {case "kill": {"mpkilled"}; case "delete": {"deleted"}; case "detonate": {"detonate"}; default {"cleanup"};};
    [_uav, _record get "netId", _reason, _id] call A3UE_fnc_fpv_unregisterDrone;
};
if (!isNull _uav) then {
    _uav setVariable ["A3UE_FPV_controllerIdentity", [], true];
    _uav setVariable ["A3UE_FPV_signalIdentity", [], true];
    _uav setVariable ["A3UE_FPV_crocusSignalSnapshot", [], true];
};
if (_event == "retire" && {_record get "fiber"}) then {
    _record set ["retiredGeometry", [(_record get "path") apply {+_x}, missionNamespace getVariable ["kvn_fiberTTL", 20]]];
};
// Retirement is not an eligible fiber destruction. Actual kill/delete/commit is.
if (_record get "fiber" && {_event != "retire"}) then {
    private _geometry = _record getOrDefault ["pendingGeometry", []];
    if (count _geometry == 0) then {
        private _path = if (_record get "managed") then {_record get "path"} else {if (isNull _uav) then {[]} else {_uav getVariable ["kvn_fiber_path", []]}};
        _geometry = [_path, missionNamespace getVariable ["kvn_fiberTTL", 20]];
    };
    [_geometry # 0, _geometry # 1, str _id] call A3UE_fnc_fpv_archiveFiber;
};
_record deleteAt "pendingGeometry";
_record set ["path", []];
if (_event != "retire") then {_record set ["object", objNull];};
call A3UE_fnc_fpv_pruneLifecycle;
true
