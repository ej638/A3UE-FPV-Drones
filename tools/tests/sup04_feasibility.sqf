// STRUCTURAL contract fixture: production planner/availability, synthetic origins/costs.
// Server-local disposable, recompile-enabled AU mission only; restart afterward.
// Actual AU selection/debit, vendor flight and concurrent routes need the session card.
if (!isServer || {isRemoteExecuted} || {!(missionNamespace getVariable ["A3UE_FPV_siteReady", false])}) exitWith {
    diag_log "[A3UE FPV TEST SUP-04] BLOCKED: server-local ready disposable campaign";
};
private _spies = ["A3UE_fnc_fpv_supportResolveOrigin", "A3UE_fnc_fpv_supportCreateMarker", "A3UE_fnc_fpv_spawnManagedDrone"];
if (_spies findIf {isFinal (missionNamespace getVariable [_x, {}])} >= 0) exitWith {
    diag_log "[A3UE FPV TEST SUP-04] BLOCKED: immutable spies";
};
private _side = Occupants;
private _hostiles = [_side] call A3UE_fnc_fpv_getHostileSides;
if (_hostiles isEqualTo []) exitWith {diag_log "[A3UE FPV TEST SUP-04] BLOCKED: no hostile combat side";};
private _names = _spies + ["A3UE_FPV_doctrine", "A3A_vehicleResourceCosts", "tierWar",
    "A3UE_FPV_lastSupportFailureReason", "A3UE_FPV_lastSupportPlan", "A3UE_FPV_lastSupportContext",
    "A3UE_FPV_supportContext", "A3UE_FPV_supportTransientMarkers", "A3UE_FPV_supportRegistry",
    "A3UE_FPV_nextSupportId", "A3A_activeSupports", "A3A_supportStrikes"];
private _saved = _names apply {[_x, !isNil _x, missionNamespace getVariable [_x, 0]]};
private _group = createGroup [_hostiles # 0, true];
private _pos = [50000, 50000, 0];
private _target = _group createUnit ["B_Soldier_F", _pos, [], 0, "NONE"];
_target enableSimulationGlobal false;
private _cases = 0;
private _failures = 0;
private _assert = {
    params ["_case", "_ok"];
    _cases = _cases + 1;
    if (!_ok) then {_failures = _failures + 1;};
    diag_log format ["[A3UE FPV TEST SUP-04] STRUCTURAL case=%1 pass=%2", _case, _ok];
};
// No scheduler interleaving while production functions use these local spies.
isNil {
    private _originValid = true;
    private _markers = 0;
    private _blockAtMarker = false;
    private _lateFriendly = objNull;
    private _lateGroup = grpNull;
    private _spawns = 0;
    private _originSpy = {
        params ["_side", "_pos", "_plan", "_ctx"];
        if (!_originValid) exitWith {createHashMapFromArray [["ok", false], ["reason", "ORIGIN_INELIGIBLE"]]};
        createHashMapFromArray [["ok", true], ["originMarker", _ctx getOrDefault ["originMarker", "QA_DEFAULT"]],
            ["originPosATL", _pos], ["controlPosATL", _pos], ["fiberAnchorPos", _pos],
            ["launchPosATL", _pos vectorAdd [0, 0, 35]], ["launchDir", 0],
            ["originContract", "QA"], ["originEpoch", 1], ["originGeneration", 1], ["reach", createHashMap]]
    };
    private _markerSpy = {
        params ["_name", "_pos", "_side"];
        _markers = _markers + 1;
        if (!_blockAtMarker) exitWith {""};
        _lateGroup = createGroup [_side, true];
        _lateFriendly = _lateGroup createUnit ["B_Soldier_F", _pos vectorAdd [3, 0, 0], [], 0, "NONE"];
        _lateFriendly enableSimulationGlobal false;
        private _marker = createMarker [_name + "_search", _pos];
        _marker setMarkerShape "ICON";
        _marker
    };
    private _spawnSpy = {_spawns = _spawns + 1; objNull};
    A3UE_fnc_fpv_supportResolveOrigin = _originSpy;
    A3UE_fnc_fpv_supportCreateMarker = _markerSpy;
    A3UE_fnc_fpv_spawnManagedDrone = _spawnSpy;
    if (A3UE_fnc_fpv_supportResolveOrigin isNotEqualTo _originSpy
        || {A3UE_fnc_fpv_supportCreateMarker isNotEqualTo _markerSpy}
        || {A3UE_fnc_fpv_spawnManagedDrone isNotEqualTo _spawnSpy}) exitWith {
        diag_log "[A3UE FPV TEST SUP-04] BLOCKED: spy assignment failed";
    };
    private _sideKey = switch (_side) do {case east: {"east"}; case west: {"west"}; default {"independent"};};
    private _cheap = "B_UAV_01_F";
    private _expensive = "O_UAV_01_F";
    private _roles = createHashMapFromArray [["AT", 0], ["AP", 10], ["RECON", 0]];
    private _families = createHashMapFromArray [["armafpv", 10], ["fpv_ua", 0], ["kvn", 0]];
    private _pools = createHashMapFromArray [["AP", [[_expensive, 100], [_cheap, 1]]],
        ["AT", [[_cheap, 1]]], ["RECON", [[_cheap, 1]]]];
    private _support = createHashMapFromArray [["selectorWeight", 0.35], ["costOverhead", 20],
        ["droneCountMin", 1], ["droneCountMax", 2], ["pairTier", 7], ["minWarTier", 3], ["safetyRadius", 40]];
    private _entry = createHashMapFromArray [["roleWeights", _roles], ["familyWeights", _families],
        ["support", _support], ["classPools", createHashMapFromArray [[_sideKey,
            createHashMapFromArray [["armafpv", _pools]]]]]];
    A3UE_FPV_doctrine = createHashMapFromArray [["ReactiveSupport", _entry], ["MajorAttackSupport", _entry]];
    A3A_vehicleResourceCosts = createHashMapFromArray [[_cheap, 30], [_expensive, 300]];
    tierWar = 7;
    A3UE_FPV_supportContext = createHashMap;
    A3UE_FPV_lastSupportFailureReason = "QA_CREATED_REASON";
    private _lastPlan = createHashMapFromArray [["QA_CREATED_PLAN", true]];
    private _lastContext = createHashMapFromArray [["QA_CREATED_CONTEXT", true]];
    A3UE_FPV_lastSupportPlan = _lastPlan;
    A3UE_FPV_lastSupportContext = _lastContext;
    private _ctx = createHashMapFromArray [["context", "ReactiveSupport"], ["originMarker", "QA_A"]];
    private _query = {[_side, _target, _this # 0, _ctx, "defence", _pos, true] call A3UE_fnc_fpv_resolveSupportPackage};
    private _commit = {[_side, _target, _this # 0, _ctx, "defence", _pos] call A3UE_fnc_fpv_resolveSupportPackage};
    private _r = [50] call _query;
    ["mixed costs affordable candidate", (_r get "ok") && {(_r get "candidateCount") == 1}] call _assert;
    ["query has no chosen plan", !("uavClass" in _r) && {!("origin" in _r)}] call _assert;
    private _stable = true;
    for "_i" from 1 to 40 do {
        if (([50] call _query) isNotEqualTo _r) then {_stable = false;};
        if (([_target, _side, 50, ["FPV"]] call A3A_fnc_SUP_FPVAvailable) != 0.35) then {_stable = false;};
    };
    ["identical snapshot availability", _stable] call _assert;
    private _legal = true;
    for "_i" from 1 to 40 do {
        private _p = [50] call _commit;
        if (!(_p get "ok") || {(_p get "uavClass") != _cheap} || {(_p get "estimatedCost") > 50}) then {_legal = false;};
    };
    ["commit selects affordable class", _legal] call _assert;
    ["exact minimum budget", ([50] call _commit) get "estimatedCost" == 50] call _assert;
    ["below minimum budget", ([49] call _query) get "failure" == "BUDGET_TOO_LOW"] call _assert;
    ["zero budget", ([0] call _query) get "failure" == "NO_BUDGET"] call _assert;
    ["negative budget", ([-1] call _commit) get "failure" == "NO_BUDGET"] call _assert;
    ["invalid budget", (["unlimited"] call _query) get "failure" == "NO_BUDGET"] call _assert;
    ["expanded package fits", ([80] call _commit) get "droneCount" == 2] call _assert;
    ["single when pair unaffordable", ([79] call _commit) get "droneCount" == 1] call _assert;
    _roles set ["AP", 0];
    ["zero roles not revived by infantry bonus", !(([500] call _query) get "ok")] call _assert;
    _roles set ["AP", 10];
    _families set ["armafpv", 0];
    ["role with no weighted family", !(([500] call _query) get "ok")] call _assert;
    _families set ["armafpv", 10];
    _pools set ["AP", [[_cheap, 0], [_expensive, 1]]];
    ["zero class weight excluded", !(([50] call _query) get "ok")] call _assert;
    _pools set ["AP", [[_cheap, 1]]];
    _roles set ["AT", 10];
    _pools set ["AT", [[_expensive, 100]]];
    ["infeasible role cannot hide feasible role", ([50] call _query) get "ok"] call _assert;
    _roles set ["AT", 0];
    _originValid = false;
    ["no reachable origin", ([50] call _query) get "failure" == "ORIGIN_INELIGIBLE"] call _assert;
    ["unavailable maps to zero", ([_target, _side, 50, ["FPV"]] call A3A_fnc_SUP_FPVAvailable) == 0] call _assert;
    _originValid = true;
    private _b = createHashMapFromArray [["context", "MajorAttackSupport"], ["originMarker", "QA_B"], ["resourcePool", "attack"]];
    private _plans = [_ctx, {
        private _a = [50] call _commit;
        private _bp = [_b, {[_side, _target, 50, createHashMap, "attack", _pos] call A3UE_fnc_fpv_resolveSupportPackage;}] call A3UE_fnc_fpv_withSupportContext;
        private _again = [_side, _target, 50, createHashMap, "defence", _pos] call A3UE_fnc_fpv_resolveSupportPackage;
        [_a, _bp, _again]
    }] call A3UE_fnc_fpv_withSupportContext;
    ["request contexts and plans remain separate", ((_plans # 0) get "originMarker") == "QA_A"
        && {((_plans # 1) get "originMarker") == "QA_B"}
        && {((_plans # 1) get "context") == "MajorAttackSupport"}
        && {((_plans # 2) get "originMarker") == "QA_A"}] call _assert;
    ["wrapper does not store a global plan", count A3UE_FPV_supportContext == 0] call _assert;
    ["positive query before invalidation", ([50] call _query) get "ok"] call _assert;
    _originValid = false;
    private _cost = ["QA_SUP04", _side, "defence", 50, _target, _pos, 0, 0] call A3A_fnc_SUP_FPV;
    ["creation rejects changed origin before marker", _cost == -1 && {_markers == 0}] call _assert;
    _originValid = true;
    _blockAtMarker = true;
    A3UE_FPV_supportRegistry = createHashMap;
    A3UE_FPV_supportTransientMarkers = [];
    A3A_activeSupports = []; A3A_supportStrikes = [];
    private _name = format ["A3UE_QA_SUP04_%1", diag_tickTime];
    _cost = [_name, _side, "defence", 50, _target, _pos, 0, 0] call A3A_fnc_SUP_FPV;
    ["creation rechecks safety after marker", _cost == -1 && {_spawns == 0}
        && {A3UE_FPV_lastSupportFailureReason == "UNSAFE_ENGAGEMENT"}
        && {markerShape (_name + "_search") == ""}] call _assert;
    deleteVehicle _lateFriendly;
    deleteGroup _lateGroup;
    deleteMarker (_name + "_search");
    // Restore sentinel to distinguish subsequent query failures from creation failure.
    A3UE_FPV_lastSupportFailureReason = "QA_CREATED_REASON";
    _originValid = true;
    private _friendlyGroup = createGroup [_side, true];
    private _friendly = _friendlyGroup createUnit ["B_Soldier_F", _pos vectorAdd [3, 0, 0], [], 0, "NONE"];
    _friendly enableSimulationGlobal false;
    ["production safety blocks query", ([50] call _query) get "failure" == "UNSAFE_ENGAGEMENT"] call _assert;
    ["production safety blocks commit", !(([50] call _commit) get "ok")] call _assert;
    deleteVehicle _friendly;
    deleteGroup _friendlyGroup;
    A3UE_FPV_doctrine = createHashMap;
    ["query cannot initialize doctrine", !(([50] call _query) get "ok") && {count A3UE_FPV_doctrine == 0}] call _assert;
    ["query preserves last-created diagnostics", A3UE_FPV_lastSupportFailureReason == "QA_CREATED_REASON"
        && {A3UE_FPV_lastSupportPlan isEqualRef _lastPlan}
        && {A3UE_FPV_lastSupportContext isEqualRef _lastContext}] call _assert;
};
deleteVehicle _target;
deleteGroup _group;
{_x params ["_name", "_present", "_value"]; missionNamespace setVariable [_name, if (_present) then {_value} else {nil}];} forEach _saved;
diag_log format ["[A3UE FPV TEST SUP-04] END qualified=%1 failures=%2 restored=true", _cases, _failures];
