// GENUINE AU acceptance collector: no replacement functions, synthetic origins,
// resource writes or forced locks. One paid request per isolated campaign run.
// See docs/audits/2026-10-09/RV01_Implementation.md for setup and evidence rules.
params ["_side", "_override", "_target", ["_expectSuccess", true], ["_pool", "attack"], ["_budget", 500]];
if (!isServer || {isRemoteExecuted} || {!canSuspend}
    || {!(missionNamespace getVariable ["A3UE_FPV_siteReady", false])}
    || {isNull _target} || {!alive _target} || {!(_side in [Occupants, Invaders])}
    || {!(_pool in ["attack", "defence"])}) exitWith {
    diag_log "[A3UE FPV TEST RV-01 AU] BLOCKED: scheduled server-local ready AU, live target, valid faction/pool required";
};
private _runId = format ["RV01_%1_%2", clientOwner, diag_tickTime];
private _context = createHashMapFromArray [["context", "MajorAttackSupport"],
    ["resourcePool", _pool], ["originMarker", _override], ["targetSide", side group _target]];
private _resourceVar = "A3A_resources" + (["Defence", "Attack"] select (_pool == "attack"))
    + (["Occ", "Inv"] select (_side == Invaders));
private _snapshot = {
    createHashMapFromArray [
        ["balance", missionNamespace getVariable [_resourceVar, -1]],
        ["allBalances", [A3A_resourcesAttackOcc, A3A_resourcesDefenceOcc, A3A_resourcesAttackInv, A3A_resourcesDefenceInv]],
        ["markers", allMapMarkers], ["vehicles", vehicles], ["units", allUnits],
        ["registry", str (missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap])],
        ["transient", +(missionNamespace getVariable ["A3UE_FPV_supportTransientMarkers", []])],
        ["supports", str A3A_activeSupports], ["strikes", str A3A_supportStrikes],
        ["last", str [missionNamespace getVariable ["A3UE_FPV_lastSupportPlan", createHashMap],
            missionNamespace getVariable ["A3UE_FPV_lastSupportContext", createHashMap],
            missionNamespace getVariable ["A3UE_FPV_lastSupportFailureReason", ""]]],
        ["count", A3A_supportCount], ["nextId", missionNamespace getVariable ["A3UE_FPV_nextSupportId", 0]]
    ]
};
private _chars = toArray (toLower _override);
{
    if (_forEachIndex mod 2 == 0 && {_x >= 97} && {_x <= 122}) then {_chars set [_forEachIndex, _x - 32];};
} forEach _chars;
private _spellings = [_override, toUpper _override, toLower _override, toString _chars];
private _log = {
    params ["_tag", "_data"];
    private _text = str _data;
    private _parts = ceil (count _text / 6000);
    for "_part" from 0 to (_parts - 1) do {
        diag_log format ["[A3UE FPV TEST RV-01 AU] run=%1 tag=%2 part=%3/%4 %5", _runId, _tag, _part + 1, _parts, _text select [_part * 6000, 6000]];
    };
};
["BEGIN", [productVersion, _side, _pool, _override, _expectSuccess, _budget, netId _target, getPosATL _target]] call _log;
private _originPlan = [_side, _target, _budget, _context, _pool, getPosATL _target] call A3UE_fnc_fpv_resolveSupportPackage;
private _queryBefore = call _snapshot;
private _queries = [];
private _origins = [];
{
    _context set ["originMarker", _x];
    // Each direct origin request and production planner call uses a fresh map.
    private _origin = createHashMap;
    if (_originPlan get "ok") then {
        _origin = [_side, getPosATL _target, _originPlan, _context, createHashMap] call A3UE_fnc_fpv_supportResolveOrigin;
    };
    _origins pushBack [_x, markerShape _x, markerPos _x, _origin];
    for "_i" from 1 to 10 do {
        private _q = [_side, _target, _budget, _context, _pool, getPosATL _target, true] call A3UE_fnc_fpv_resolveSupportPackage;
        private _weight = [_context, {[_target, _side, _budget, ["FPV"]] call A3A_fnc_SUP_FPVAvailable}] call A3UE_fnc_fpv_withSupportContext;
        _queries pushBack [_q, _weight];
    };
} forEach _spellings;
private _queryAfter = call _snapshot;
private _queryEqual = _queries findIf {_x isNotEqualTo (_queries # 0)} == -1;
["QUERY", [_queryEqual, _queryBefore isEqualTo _queryAfter, _queries, _origins, _queryBefore, _queryAfter]] call _log;
_context set ["originMarker", _override];
private _before = call _snapshot;
private _name = [_context, {
    ["FPV", _side, _pool, _budget, _target, getPosATL _target, 0, 0] call A3A_fnc_createSupport
}] call A3UE_fnc_fpv_withSupportContext;
private _after = call _snapshot;
private _entry = (missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap]) getOrDefault [_name, createHashMap];
private _delta = (_before get "balance") - (_after get "balance");
private _newVehicles = (_after get "vehicles") select {!(_x in (_before get "vehicles"))};
private _newUnits = (_after get "units") select {!(_x in (_before get "units"))};
private _newMarkers = (_after get "markers") select {!(_x in (_before get "markers"))};
private _observed = if (_expectSuccess) then {
    _name != "" && {(_entry getOrDefault ["status", ""]) == "active"}
        && {_delta == (_entry getOrDefault ["resourceCost", -1])} && {_delta > 0}
        && {(_entry getOrDefault ["drones", []]) isNotEqualTo []}
} else {
    _name == "" && {_delta == 0} && {_newVehicles isEqualTo []} && {_newUnits isEqualTo []} && {_newMarkers isEqualTo []}
        && {(_before get "supports") isEqualTo (_after get "supports")}
        && {(_before get "strikes") isEqualTo (_after get "strikes")}
        && {(_before get "transient") isEqualTo (_after get "transient")}
};
["AU_RETURN", [_observed, _name, _delta, _entry, _newVehicles, _newUnits, _newMarkers, _before, _after]] call _log;
// Check persistent marker/asset absence on declines after the transaction.
sleep 10;
private _late = call _snapshot;
["END", [_late, "REVIEW REQUIRED: count genuine AU debit log events, origin identity and query purity; unrelated activity is INCONCLUSIVE"]] call _log;
