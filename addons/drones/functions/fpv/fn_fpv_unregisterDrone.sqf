params [["_uav", objNull], ["_uavNetId", ""], ["_reason", ""], ["_id", -1]];
if !(call A3UE_fnc_fpv_lifecycleAccess) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
if (canSuspend) exitWith {private _ok = false; isNil {_ok = _this call A3UE_fnc_fpv_unregisterDrone;}; _ok};
if (_uavNetId == "" && {!isNull _uav}) then {_uavNetId = netId _uav;};
if (_id < 0) then {_id = (missionNamespace getVariable ["A3UE_FPV_lifecycleIndex", createHashMap]) getOrDefault [_uavNetId, -1];};
private _record = (missionNamespace getVariable ["A3UE_FPV_lifecycles", createHashMap]) getOrDefault [str _id, createHashMap];
if (count _record == 0 || {_uavNetId != (_record get "netId")}) exitWith {false};
if ((_record get "phase") == "live") exitWith {
    [_id, if (_reason in ["deleted", "mpkilled"]) then {["kill", "delete"] select (_reason == "deleted")} else {"retire"}] call A3UE_fnc_fpv_endLifecycle
};
private _supportStatus = ["finished", "failed"] select ((_record get "outcome") in ["kill", "delete"]);
private _changed = [_record get "support", _supportStatus, _reason, _uavNetId] call A3UE_fnc_fpv_supportFinalize;
private _registry = missionNamespace getVariable ["A3UE_FPV_registry", createHashMap];
private _site = _record get "site";
private _entry = _registry getOrDefault [_site, createHashMap];
if (count _entry > 0) then {
    private _drones = _entry getOrDefault ["drones", []];
    private _remaining = _drones select {!(_x isEqualTo (_record get "object"))};
    if (count _remaining != count _drones) then {
        _entry set ["drones", _remaining];
        _entry set ["lastCleanup", serverTime]; _entry set ["lastCleanupReason", _reason]; _entry set ["lastCleanupNetId", _uavNetId];
        if ((_entry getOrDefault ["status", ""]) == "active" && {_remaining isEqualTo []}) then {_entry set ["status", "depleted"];};
        _changed = true;
    };
};
_changed
