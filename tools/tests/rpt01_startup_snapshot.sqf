// Read-only collector. Run BEFORE helpers, retries, debug changes or repairs.
// Copy to a disposable AU mission: ["BASELINE"] call compileScript ["scripts\rpt01_startup_snapshot.sqf"];
params [["_label", "BASELINE", [""]], ["_markers", ["airport", "airport_2", "Outpost_2", "Outpost_15", "resource_3"], [[]]]];

private _values = [];
{
    private _exists = !isNil {missionNamespace getVariable _x};
    _values pushBack [_x, _exists, missionNamespace getVariable [_x, "<ABSENT>"]];
} forEach [
    "A3UE_FPV_registrationComplete", "A3UE_FPV_registrationPending", "A3UE_FPV_siteEpoch",
    "A3UE_FPV_siteHooksInstalled", "A3UE_FPV_siteHooksPending", "A3UE_FPV_siteReady",
    "serverInitDone", "bis_fnc_init", "A3UE_FPV_debug", "A3UE_FPV_siteCampaignId",
    "A3UE_FPV_siteIngressRejected", "A3UE_FPV_siteLastRejection"
];
private _maps = ["A3UE_FPV_loadedMods", "A3UE_FPV_catalog", "A3UE_FPV_doctrine", "A3UE_FPV_siteLifecycle", "A3UE_FPV_siteTracked", "A3UE_FPV_siteQueue", "A3UE_FPV_registry"] apply {
    private _value = missionNamespace getVariable [_x, "<ABSENT>"];
    [_x, typeName _value, if (_value isEqualType createHashMap) then {keys _value} else {[]}]
};
private _scheduler = missionNamespace getVariable ["A3A_fnc_scheduler", 0];
private _binding = _scheduler isEqualType {} && {_scheduler isEqualTo A3UE_fnc_fpv_scheduleSite};
private _bindingInfo = ["schedulerMatches", _binding, "schedulerType", typeName _scheduler,
    "originalType", typeName (missionNamespace getVariable ["A3UE_FPV_originalScheduler", 0])];
private _adapter = missionNamespace getVariable ["A3UE_FPV_auAdapterReport", "<ABSENT>"];
private _adapterRows = if (_adapter isEqualType createHashMap) then {
    (_adapter getOrDefault ["rows", []]) apply {[_x get "function", _x get "state", _x get "bodyMatches"]}
} else {[]};
private _events = missionNamespace getVariable ["A3A_Events_EventRegistry", createHashMap];
private _listeners = [
    ["locationSpawned", "A3UE_FPV_locationSpawned"], ["AIVehInit", "A3UE_FPV_aivehInit"],
    ["markerChange", "A3UE_FPV_markerChange"]
] apply {
    _x params ["_event", "_id"];
    private _entries = _events getOrDefault [_event, createHashMap];
    private _callback = _entries getOrDefault [_id, "<ABSENT>"];
    private _expected = switch (_event) do {
        case "locationSpawned": {A3UE_fnc_fpv_onLocationSpawned};
        case "AIVehInit": {A3UE_fnc_fpv_onAIVehInit};
        default {A3UE_fnc_fpv_onMarkerChange};
    };
    [_event, keys _entries, _id, typeName _callback, _callback isEqualType {} && {_callback isEqualTo _expected}]
};
// One on-demand UAV enumeration also exposes owner-local bootstrap state on HCs.
private _managed = allUnitsUAV select {_x getVariable ["A3UE_FPV_managed", false]};
private _sites = _markers apply {
    private _markerX = _x;
    private _state = (missionNamespace getVariable ["A3UE_FPV_siteLifecycle", createHashMap]) getOrDefault [_markerX, createHashMap];
    private _entry = (missionNamespace getVariable ["A3UE_FPV_registry", createHashMap]) getOrDefault [_markerX, createHashMap];
    private _spawnState = if (isNil "spawner" || {isNull spawner}) then {-1} else {spawner getVariable [_markerX, -1]};
    private _side = if (isNil "sidesX" || {isNull sidesX}) then {sideUnknown} else {sidesX getVariable [_markerX, sideUnknown]};
    private _siteDrones = +(_entry getOrDefault ["drones", []]);
    {_siteDrones pushBackUnique _x;} forEach (_managed select {(_x getVariable ["A3UE_FPV_siteMarker", ""]) == _markerX});
    private _drones = _siteDrones apply {
        private _uav = _x;
        [netId _uav, typeOf _uav, owner _uav, local _uav, alive _uav, getPosATL _uav,
            ["controllerDone", scriptDone (_uav getVariable ["A3UE_FPV_controllerHandle", scriptNull])],
            ["A3UE_FPV_managed", "A3UE_FPV_lifecycleId", "A3UE_FPV_controllerIdentity", "A3UE_FPV_controllerGeneration", "A3UE_FPV_startedGeneration", "A3UE_FPV_controllerRunning", "A3UE_FPV_controllerHandle", "A3UE_FPV_lifecycleClaimFailure", "A3UE_FPV_bootstrapJipId", "A3UE_FPV_localityEH"] apply {
                [_x, _uav getVariable [_x, "<ABSENT>"]]
            }]
    };
    [_markerX, markerShape _markerX, _spawnState, _side, _state, _entry, _drones]
};
private _scripts = diag_activeSQFScripts select {
    private _text = toLower str _x;
    (_text find "fpv") >= 0 || {(_text find "a3ue") >= 0}
};
private _result = [_label, clientOwner, isServer, isRemoteExecuted, diag_tickTime, _values, _maps,
    _bindingInfo, ["adapter", typeName _adapter, _adapterRows],
    ["listeners", _listeners], ["sites", _sites], ["activeScripts", _scripts]];
// Split evidence into bounded rows; no scheduler body dump or giant combined line.
diag_log ["A3UE FPV RPT01 SNAPSHOT", "BEGIN", _label, clientOwner, isServer, isRemoteExecuted, diag_tickTime];
{diag_log ["A3UE FPV RPT01 VALUE", _label, _x];} forEach _values;
{diag_log ["A3UE FPV RPT01 MAP", _label, _x];} forEach _maps;
diag_log ["A3UE FPV RPT01 BINDING", _label, _bindingInfo];
diag_log ["A3UE FPV RPT01 ADAPTER", _label, typeName _adapter, _adapterRows];
// Record equality against the expected callback without dumping its full body.
{diag_log ["A3UE FPV RPT01 LISTENER", _label, _x];} forEach _listeners;
{
    _x params ["_markerX", "_shape", "_spawnState", "_side", "_state", "_entry", "_drones"];
    diag_log ["A3UE FPV RPT01 SITE", _label, _markerX, _shape, _spawnState, _side];
    diag_log ["A3UE FPV RPT01 STATE", _label, _markerX, _state];
    diag_log ["A3UE FPV RPT01 STOCK", _label, _markerX, _entry];
    {
        diag_log ["A3UE FPV RPT01 OBJECT", _label, _markerX, _x select [0, 7]];
        private _objectId = _x # 0;
        {diag_log ["A3UE FPV RPT01 OBJECT_FIELD", _label, _objectId, _x];} forEach (_x # 7);
    } forEach _drones;
} forEach _sites;
{diag_log ["A3UE FPV RPT01 SCRIPT", _label, _x];} forEach _scripts;
diag_log ["A3UE FPV RPT01 SNAPSHOT", "END", _label];
_result
