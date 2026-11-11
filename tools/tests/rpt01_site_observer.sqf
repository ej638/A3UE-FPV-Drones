// Optional evidence-only listeners; install AFTER the untouched startup snapshot.
// Does not invoke FPV helpers, change rolls or synthesize events. Restart after testing.
if (isRemoteExecuted || {isNil "A3A_Events_fnc_addEventListener"}) exitWith {
    diag_log ["A3UE FPV RPT01 OBSERVER", "BLOCKED", "local AU event provider required"];
};
private _events = missionNamespace getVariable ["A3A_Events_EventRegistry", createHashMap];
if (isNil {(_events getOrDefault ["locationSpawned", createHashMap]) get "RPT01_validation_locationSpawned"}) then {
    ["locationSpawned", "RPT01_validation_locationSpawned", {
        private _context = if (isNil "_A3UE_FPV_siteWorkerContext") then {[]} else {+_A3UE_FPV_siteWorkerContext};
        diag_log ["A3UE FPV RPT01 NATURAL_EVENT", clientOwner, _this, "workerContext", _context];
    }] call A3A_Events_fnc_addEventListener;
};
if (isNil {(_events getOrDefault ["AIVehInit", createHashMap]) get "RPT01_validation_AIVehInit"}) then {
    ["AIVehInit", "RPT01_validation_AIVehInit", {
        params [["_uav", objNull, [objNull]]];
        if (!isNull _uav && {_uav getVariable ["A3UE_FPV_managed", false]}) then {
            diag_log ["A3UE FPV RPT01 NATURAL_OBJECT", clientOwner, netId _uav, typeOf _uav,
                owner _uav, _uav getVariable ["A3UE_FPV_siteMarker", ""],
                _uav getVariable ["A3UE_FPV_lifecycleId", -1]];
        };
    }] call A3A_Events_fnc_addEventListener;
};
diag_log ["A3UE FPV RPT01 OBSERVER", "INSTALLED", clientOwner];
