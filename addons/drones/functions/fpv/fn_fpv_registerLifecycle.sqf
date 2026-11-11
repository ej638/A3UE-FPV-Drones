params [["_uav", objNull, [objNull]], ["_managed", false, [true]], ["_support", "", [""]], ["_site", "", [""]], ["_rival", "", [""]]];
if !(call A3UE_fnc_fpv_lifecycleAccess) exitWith {-1};
if (canSuspend) exitWith {private _id = -1; isNil {_id = _this call A3UE_fnc_fpv_registerLifecycle;}; _id};
if (isNull _uav || {netId _uav == ""} || {count _support > 128} || {count _site > 128} || {count _rival > 128}) exitWith {-1};
if (!_managed && {!(_uav isKindOf "frtz_drone_kvn_base_F")}) exitWith {-1};
if (isNil "A3UE_FPV_lifecycles") then {A3UE_FPV_lifecycles = createHashMap; A3UE_FPV_lifecycleIndex = createHashMap; A3UE_FPV_lifecycleCapability = createHashMapFromArray [["server", true]];};
call A3UE_fnc_fpv_pruneLifecycle;
private _netId = netId _uav;
private _oldId = A3UE_FPV_lifecycleIndex getOrDefault [_netId, -1];
private _old = A3UE_FPV_lifecycles getOrDefault [str _oldId, createHashMap];
if (count _old > 0 && {(_old get "object") isEqualTo _uav} && {(_old get "phase") == "live"}) exitWith {
    if (_managed) then {
        if !(_old get "managed") then {
            // Revoke an in-flight native challenge and its reporting authority.
            // The owner will claim a generation above its native generation.
            private _challenge = _old getOrDefault ["challenge", []];
            private _floor = if ((_old get "owner") == owner _uav) then {_old get "generation"} else {-1};
            if (count _challenge == 4 && {(_challenge # 0) == owner _uav}) then {_floor = _floor max (_challenge # 1);};
            _old set ["managedGenerationFloor", _floor + 1];
            _old set ["managedGenerationOwner", owner _uav];
            _old deleteAt "challenge";
            _old set ["released", true];
            _uav setVariable ["A3UE_FPV_signalIdentity", [], true];
            _uav setVariable ["A3UE_FPV_crocusSignalSnapshot", [], true];
        };
        _old set ["managed", true]; _old set ["support", _support]; _old set ["site", _site]; _old set ["rival", _rival];
    };
    _oldId
};
if (count A3UE_FPV_lifecycleIndex >= 512) exitWith {-1};
private _id = 1 + (missionNamespace getVariable ["A3UE_FPV_nextLifecycleId", 0]);
if (_id > 10000000) exitWith {-1};
missionNamespace setVariable ["A3UE_FPV_nextLifecycleId", _id];
private _record = createHashMapFromArray [
    ["id", _id], ["netId", _netId], ["object", _uav], ["managed", _managed],
    ["support", _support], ["site", _site], ["rival", _rival], ["phase", "live"],
    ["owner", owner _uav], ["episode", 0], ["generation", -1], ["token", ""],
    ["sequences", createHashMap], ["path", []], ["archived", false], ["fiber", _uav isKindOf "frtz_drone_kvn_base_F"],
    ["signalSince", serverTime], ["autonomous", true]
];
A3UE_FPV_lifecycles set [str _id, _record];
A3UE_FPV_lifecycleIndex set [_netId, _id];
_uav setVariable ["A3UE_FPV_lifecycleIdServer", _id];
_uav setVariable ["A3UE_FPV_lifecycleId", _id, true];
_uav setVariable ["A3UE_FPV_lifecycleEpisode", 0, true];
_uav setVariable ["A3UE_FPV_controllerIdentity", [_id, owner _uav, 0, -1], true];
_uav setVariable ["A3UE_FPV_signalIdentity", [_id, owner _uav, 0, -1, 0], true];
_uav addEventHandler ["Deleted", {
    params ["_vehicle"];
    private _id = _vehicle getVariable ["A3UE_FPV_lifecycleIdServer", -1];
    // F4-2b evidence: UA's native hit handler detonates and deletes the airframe, so a managed
    // UA lost that way (tree, shot down, a nearby drone's blast) never reaches MPKilled.
    if (_vehicle getVariable ["UA_FPV_Detonated", false]) then {
        [_vehicle, objNull, objNull, _id, "UA_HIT"] call A3UE_fnc_fpv_logDroneLoss;
    };
    // F5: a managed spawn's own crew and groups are swept once its airframe is gone.
    private _crewGroups = _vehicle getVariable ["A3UE_FPV_crewGroups", []];
    if (isServer && {_crewGroups isNotEqualTo []}) then {
        private _crew = +(_vehicle getVariable ["A3UE_FPV_crewUnits", []]);
        {_crew pushBackUnique _x;} forEach (crew _vehicle);
        [_crew, +_crewGroups, netId _vehicle] spawn A3UE_fnc_fpv_sweepCrew;
    };
    private _A3UE_FPV_lifecycleAuthorized = missionNamespace getVariable ["A3UE_FPV_lifecycleCapability", createHashMap];
    [_id, "delete"] call A3UE_fnc_fpv_endLifecycle;
}];
_uav addMPEventHandler ["MPKilled", {
    params ["_vehicle", ["_killer", objNull], ["_instigator", objNull]];
    if (!isServer) exitWith {};
    private _id = (missionNamespace getVariable ["A3UE_FPV_lifecycleIndex", createHashMap]) getOrDefault [netId _vehicle, -1];
    // F4-2 evidence: a loss outside the strike commit (tree, wall, shot down) logs one line.
    [_vehicle, _killer, _instigator, _id] call A3UE_fnc_fpv_logDroneLoss;
    private _A3UE_FPV_lifecycleAuthorized = missionNamespace getVariable ["A3UE_FPV_lifecycleCapability", createHashMap];
    [_id, "kill"] call A3UE_fnc_fpv_endLifecycle;
}];
// Supply identity in the targeted message as well: object state and RPC arrival
// order need not agree on a newly created remote native owner.
if (!_managed && {!local _uav}) then {[_uav, [_id, owner _uav, 0, -1]] remoteExecCall ["A3UE_fnc_fpv_trackKvnLifecycle", owner _uav];};
_id
