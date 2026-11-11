// Server-local STRUCTURAL fixture. Synthetic capability/geometry/eligibility
// spies verify production planning and launch rejection, never actual AU debit.
// Disposable ready campaign: [] execVM "scripts\sup02_support_reach.sqf";
if (!isServer || {isRemoteExecuted} || {!(missionNamespace getVariable ["A3UE_FPV_siteReady", false])}) exitWith {
    diag_log "[A3UE FPV TEST SUP-02] BLOCKED: server-local after siteReady";
};
isNil {
    private _side = west;
    private _hostiles = [_side] call A3UE_fnc_fpv_getHostileSides;
    if (_hostiles isEqualTo [] || {!isClass (configFile >> "CfgVehicles" >> "B_UAV_01_F")}
        || {!isClass (configFile >> "CfgVehicles" >> "O_UAV_01_F")}) exitWith {
        diag_log "[A3UE FPV TEST SUP-02] BLOCKED: need west hostile combat side and vanilla UAV configs";
    };
    private _functions = ["A3A_fnc_availableBasesAir", "A3A_fnc_availableBasesLand",
        "A3UE_fnc_fpv_sampleRadioLink", "A3UE_fnc_fpv_spawnManagedDrone", "A3UE_fnc_fpv_supportCreateMarker"];
    if (_functions findIf {isFinal (missionNamespace getVariable [_x, {}])} >= 0) exitWith {
        diag_log "[A3UE FPV TEST SUP-02] BLOCKED: immutable spy bindings; use disposable recompile-enabled mission";
    };
    private _names = _functions + ["A3UE_FPV_catalog", "A3UE_FPV_doctrine", "airportsX", "tierWar",
        "A3UE_FPV_siteLifecycle", "A3UE_FPV_siteEpoch", "A3UE_FPV_siteReady",
        "A3UE_FPV_supportRegistry", "A3UE_FPV_supportTransientMarkers", "A3A_activeSupports", "A3A_supportStrikes",
        "A3A_supportMarkerCount", "A3UE_FPV_lastSupportPlan", "A3UE_FPV_lastSupportContext",
        "A3UE_FPV_lastSupportFailureReason", "A3UE_FPV_supportContext", "FPV_MaxFlightDistance", "kvn_showFiber",
        "A3A_vehicleResourceCosts", "A3UE_FPV_nextSupportId"];
    private _saved = _names apply {[_x, !isNil _x, missionNamespace getVariable [_x, 0]]};
    private _restore = {
        {_x params ["_name", "_present", "_value"]; missionNamespace setVariable [_name, if (_present) then {_value} else {nil}];} forEach _saved;
    };
    private _prefix = format ["A3UE_QA_SUP02_%1_", diag_tickTime];
    private _near = _prefix + "near";
    private _far = _prefix + "far";
    private _resource = _prefix + "resource";
    private _carrier = _prefix + "carrier";
    private _markers = [_near, _far, _resource, _carrier];
    {
        createMarkerLocal [_x, [4000 - (_forEachIndex * 1000), 5000, 0]];
        _x setMarkerShapeLocal "ICON";
        sidesX setVariable [_x, _side];
        spawner setVariable [_x, 0];
    } forEach _markers;
    private _targetPos = [5000, 5000, 0];
    private _airOrigins = [_near, _far];
    private _landOrigins = [];
    private _airCalls = 0;
    private _landCalls = 0;
    private _signal = 0.8;
    private _deniedMarker = "";
    private _samples = 0;
    private _spawns = 0;
    private _markerMutation = "";
    private _createdMarkers = [];
    private _seenOrigin = "";
    private _originalMarker = A3UE_fnc_fpv_supportCreateMarker;
    private _airSpy = {_airCalls = _airCalls + 1; [_airOrigins, _airOrigins apply {1}]};
    private _landSpy = {_landCalls = _landCalls + 1; [_landOrigins, _landOrigins apply {1}]};
    private _radioSpy = {
        params ["_position", "_control"];
        _samples = _samples + 1;
        private _value = _signal;
        if (_deniedMarker != "" && {_control distance2D markerPos _deniedMarker < 1}) then {_value = 0;};
        createHashMapFromArray [["signal", _value]]
    };
    private _spawnSpy = {_spawns = _spawns + 1; objNull};
    private _markerSpy = {
        _seenOrigin = (_this # 3) get "originMarker";
        private _marker = _this call _originalMarker;
        _createdMarkers pushBack _marker;
        switch (_markerMutation) do {
            case "capture": {sidesX setVariable [_resource, _hostiles # 0];};
            case "generation": {(A3UE_FPV_siteLifecycle get _resource) set ["generation", 2];};
            case "epoch": {A3UE_FPV_siteEpoch = "QA_SUP02_CHANGED";};
            case "position": {_resource setMarkerPosLocal [2050, 5000, 0];};
            case "contract": {(A3UE_FPV_siteLifecycle get _resource) set ["phase", "closed"]; _landOrigins = [_resource];};
            case "retirement": {(A3UE_FPV_siteLifecycle get _resource) set ["cleanupDrones", [objNull]];};
            case "link": {_signal = 0.2;};
        };
        _marker
    };
    A3A_fnc_availableBasesAir = _airSpy;
    A3A_fnc_availableBasesLand = _landSpy;
    A3UE_fnc_fpv_sampleRadioLink = _radioSpy;
    A3UE_fnc_fpv_spawnManagedDrone = _spawnSpy;
    A3UE_fnc_fpv_supportCreateMarker = _markerSpy;
    if (A3A_fnc_availableBasesAir isNotEqualTo _airSpy || {A3A_fnc_availableBasesLand isNotEqualTo _landSpy}
        || {A3UE_fnc_fpv_sampleRadioLink isNotEqualTo _radioSpy} || {A3UE_fnc_fpv_spawnManagedDrone isNotEqualTo _spawnSpy}
        || {A3UE_fnc_fpv_supportCreateMarker isNotEqualTo _markerSpy}) exitWith {
        call _restore;
        {deleteMarkerLocal _x; sidesX setVariable [_x, nil]; spawner setVariable [_x, nil];} forEach _markers;
        diag_log "[A3UE FPV TEST SUP-02] BLOCKED: spy assignment failed";
    };
    private _fast = "B_UAV_01_F";
    private _slow = "O_UAV_01_F";
    private _caps = createHashMapFromArray [
        [_fast, createHashMapFromArray [["maxSpeed", 200], ["nominalEnduranceDistance", 25000]]],
        [_slow, createHashMapFromArray [["maxSpeed", 1], ["nominalEnduranceDistance", 15000]]]
    ];
    A3UE_FPV_catalog = createHashMapFromArray [
        ["armafpv", createHashMapFromArray [["signalModel", "RADIO"], ["classCapabilities", _caps]]],
        ["kvn", createHashMapFromArray [["signalModel", "FIBER_VISUAL"], ["classCapabilities", _caps]]]
    ];
    private _profile = createHashMapFromArray [["trackingSpeed", 150], ["searchHeightAGL", 30], ["trackingHeightASL", 10]];
    private _roles = createHashMapFromArray [["AT", _profile], ["AP", _profile]];
    private _entry = createHashMapFromArray [
        ["behavior", createHashMapFromArray [["profiles", createHashMapFromArray [["armafpv", _roles], ["kvn", _roles]]]]],
        ["roleWeights", createHashMapFromArray [["AT", 1], ["AP", 100]]],
        ["familyWeights", createHashMapFromArray [["armafpv", 1], ["kvn", 0]]],
        ["classPools", createHashMapFromArray [["west", createHashMapFromArray [
            ["armafpv", createHashMapFromArray [["AT", [[_fast, 1], [_slow, 100]]], ["AP", [[_slow, 100]]]]]
        ]]]],
        ["support", createHashMapFromArray [["strikeDuration", 600], ["activeRadius", 100], ["minWarTier", 3], ["safetyRadius", 0]]]
    ];
    A3UE_FPV_doctrine = createHashMapFromArray [["MajorAttackSupport", _entry]];
    airportsX = [_near, _far]; tierWar = 5; FPV_MaxFlightDistance = 4000;
    A3UE_FPV_siteLifecycle = createHashMap; A3UE_FPV_siteEpoch = "QA_SUP02"; A3UE_FPV_siteReady = true;
    A3UE_FPV_supportRegistry = createHashMap; A3UE_FPV_supportTransientMarkers = [];
    A3A_activeSupports = []; A3A_supportStrikes = []; A3A_vehicleResourceCosts = createHashMap;
    A3UE_FPV_supportContext = createHashMap;
    private _context = createHashMapFromArray [["context", "MajorAttackSupport"], ["targetSide", _hostiles # 0]];
    private _plan = createHashMapFromArray [["familyId", "armafpv"], ["uavClass", _fast], ["payloadRole", "AT"],
        ["siteType", "MajorAttackSupport"], ["strikeDuration", 600], ["activeRadius", 100]];
    private _failures = 0;
    private _cases = 0;
    private _assert = {
        params ["_name", "_ok"];
        _cases = _cases + 1;
        if (!_ok) then {_failures = _failures + 1;};
        diag_log format ["[A3UE FPV TEST SUP-02] STRUCTURAL case=%1 pass=%2", _name, _ok];
    };
    private _reach = {[_targetPos, _plan, markerPos _near, createHashMap] call A3UE_fnc_fpv_supportCheckReach};
    // RV-01 uses the installed origin resolver, never an origin spy. Each
    // spelling/query is an independent request with a fresh planning snapshot.
    private _group = createGroup [_hostiles # 0, true];
    private _target = _group createUnit ["B_Soldier_F", _targetPos, [], 0, "NONE"];
    _target enableSimulationGlobal false;
    private _spellings = {
        params ["_marker"];
        private _chars = toArray (toLower _marker);
        {
            if (_forEachIndex mod 2 == 0 && {_x >= 97} && {_x <= 122}) then {_chars set [_forEachIndex, _x - 32];};
        } forEach _chars;
        [_marker, toUpper _marker, toLower _marker, toString _chars]
    };
    private _identity = {
        params ["_origin"];
        ["originMarker", "originPosATL", "controlPosATL", "fiberAnchorPos", "launchPosATL",
            "launchDir", "originSource", "originContract", "originEpoch", "originGeneration"] apply {_origin get _x}
    };
    private _queryState = {
        str [A3UE_FPV_supportRegistry, A3UE_FPV_supportTransientMarkers, A3A_activeSupports, A3A_supportStrikes,
            missionNamespace getVariable ["A3UE_FPV_lastSupportPlan", createHashMap],
            missionNamespace getVariable ["A3UE_FPV_lastSupportContext", createHashMap],
            missionNamespace getVariable ["A3UE_FPV_lastSupportFailureReason", ""],
            missionNamespace getVariable ["A3UE_FPV_nextSupportId", 0],
            missionNamespace getVariable ["A3A_supportMarkerCount", 0],
            missionNamespace getVariable ["A3A_resourcesAttackOcc", 0],
            missionNamespace getVariable ["A3A_resourcesDefenceOcc", 0],
            missionNamespace getVariable ["A3A_resourcesAttackInv", 0],
            missionNamespace getVariable ["A3A_resourcesDefenceInv", 0], allMapMarkers, vehicles, allUnits, _spawns]
    };
    private _caseVariants = {
        params ["_marker", "_contract", "_epoch", "_generation", ["_label", ""]];
        if (_label == "") then {_label = _contract;};
        private _ctx = createHashMapFromArray [["context", "MajorAttackSupport"], ["originMarker", _marker], ["targetSide", _hostiles # 0]];
        private _base = [_side, _targetPos, _plan, _ctx, createHashMap] call A3UE_fnc_fpv_supportResolveOrigin;
        [format ["%1 canonical control", _label], (_base get "ok") && {(_base get "originMarker") isEqualTo _marker}
            && {(_base get "originContract") == _contract} && {(_base get "originEpoch") isEqualTo _epoch}
            && {(_base get "originGeneration") == _generation}] call _assert;
        private _baseQuery = [_side, _target, 500, _ctx, "attack", _targetPos, true] call A3UE_fnc_fpv_resolveSupportPackage;
        {
            _ctx set ["originMarker", _x];
            private _r = [_side, _targetPos, _plan, _ctx, createHashMap] call A3UE_fnc_fpv_supportResolveOrigin;
            [format ["%1 spelling %2 identity", _label, _forEachIndex], (_r get "ok")
                && {([_r] call _identity) isEqualTo ([_base] call _identity)}] call _assert;
            private _before = call _queryState;
            private _q = [_side, _target, 500, _ctx, "attack", _targetPos, true] call A3UE_fnc_fpv_resolveSupportPackage;
            private _weight = [_ctx, {[_target, _side, 500, ["FPV"]] call A3A_fnc_SUP_FPVAvailable}] call A3UE_fnc_fpv_withSupportContext;
            [format ["%1 spelling %2 query equivalent and read-only", _label, _forEachIndex], (_q get "ok")
                && {_q isEqualTo _baseQuery} && {_weight == (_q get "selectorWeight")}
                && {(call _queryState) isEqualTo _before}] call _assert;
            private _p = [_side, _target, 500, _ctx, "attack", _targetPos] call A3UE_fnc_fpv_resolveSupportPackage;
            [format ["%1 spelling %2 plan canonical", _label, _forEachIndex], (_p get "ok")
                && {(_p get "originMarker") isEqualTo _marker}
                && {([_p get "origin"] call _identity) isEqualTo ([_base] call _identity)}] call _assert;
        } forEach ([_marker] call _spellings);
        private _shared = createHashMap;
        [_side, _targetPos, _plan, _ctx, _shared] call A3UE_fnc_fpv_supportResolveOrigin;
        private _calls = [_airCalls, _landCalls];
        private _otherPlan = createHashMap;
        {_otherPlan set [_x, _y];} forEach _plan;
        _otherPlan set ["payloadRole", "AP"]; _otherPlan set ["uavClass", _slow];
        [_side, _targetPos, _otherPlan, _ctx, _shared] call A3UE_fnc_fpv_supportResolveOrigin;
        [format ["%1 normalization reused within request", _label], [_airCalls, _landCalls] isEqualTo _calls
            && {(_shared get "resolvedOriginMarker") isEqualTo _marker}] call _assert;
    };
    [_near, "AU_AIR", -1, -1] call _caseVariants;
    ["radio reachable", (call _reach) get "ok"] call _assert;
    _signal = 0.25;
    ["signal margin boundary denied", !((call _reach) get "ok")] call _assert;
    _signal = 0.2501;
    ["signal above margin admitted", (call _reach) get "ok"] call _assert;
    _signal = 0.8;
    private _cache = createHashMap;
    [_targetPos, _plan, markerPos _near, _cache] call A3UE_fnc_fpv_supportCheckReach;
    private _beforeSamples = _samples;
    [_targetPos, _plan, markerPos _near, _cache] call A3UE_fnc_fpv_supportCheckReach;
    ["request-local geometry reused", _samples == _beforeSamples] call _assert;
    _plan set ["strikeDuration", 30];
    private _r = call _reach;
    ["short lifetime rejected before geometry", !(_r get "ok") && {_samples == _beforeSamples}] call _assert;
    _plan set ["strikeDuration", 5000];
    _r = [[20000, 5000, 0], _plan, markerPos _near, createHashMap] call A3UE_fnc_fpv_supportCheckReach;
    ["impossible radio envelope skips geometry", !(_r get "ok") && {_samples == _beforeSamples}] call _assert;
    _plan set ["strikeDuration", 600];
    _plan set ["uavClass", _slow];
    ["class speed affects lifetime", !((call _reach) get "ok")] call _assert;
    _plan set ["uavClass", "A3UE_QA_missing_capability"];
    _r = call _reach;
    ["missing capability fails closed", !(_r get "ok") && {(_r get "reason") == "NO_REACH_CAPABILITY"}] call _assert;
    _plan set ["uavClass", _fast];
    (A3UE_FPV_catalog get "armafpv") set ["signalModel", "UNSUPPORTED_FIBER"];
    _r = call _reach;
    ["unsupported fiber model denied", !(_r get "ok") && {(_r get "reason") == "NO_REACH_CAPABILITY"}] call _assert;
    (A3UE_FPV_catalog get "armafpv") set ["signalModel", "RADIO"];
    _plan set ["uavClass", _fast]; _plan set ["familyId", "kvn"];
    _r = call _reach;
    ["KVN endurance bypasses radio", (_r get "ok") && {_samples == _beforeSamples}] call _assert;
    kvn_showFiber = false;
    ["KVN drawing disabled retains endurance check", (call _reach) get "ok"] call _assert;
    (_caps get _fast) set ["nominalEnduranceDistance", 1000];
    _r = call _reach;
    ["KVN endurance exhausted", !(_r get "ok") && {(_r get "reason") == "ENDURANCE_BUDGET_EXCEEDED"}] call _assert;
    (_caps get _fast) set ["nominalEnduranceDistance", 25000];
    _plan set ["familyId", "armafpv"];
    _r = [_targetPos, _plan, markerPos _near, createHashMapFromArray [["sampleCount", 96]]] call A3UE_fnc_fpv_supportCheckReach;
    ["geometry budget fails closed", !(_r get "ok") && {(_r get "reason") == "REACH_CHECK_LIMIT"}] call _assert;
    _deniedMarker = _near;
    _r = [_side, _targetPos, _plan, _context] call A3UE_fnc_fpv_supportResolveOrigin;
    ["closest invalid farther valid", (_r get "ok") && {(_r get "originMarker") == _far}] call _assert;
    _deniedMarker = "";
    private _explicit = createHashMapFromArray [["originMarker", _near]];
    sidesX setVariable [_near, _hostiles # 0];
    _r = [_side, _targetPos, _plan, _explicit] call A3UE_fnc_fpv_supportResolveOrigin;
    ["explicit wrong side denied", !(_r get "ok") && {(_r get "reason") == "ORIGIN_INELIGIBLE"}] call _assert;
    sidesX setVariable [_near, _side]; _airOrigins = [_carrier];
    _r = [_side, _targetPos, _plan, _context] call A3UE_fnc_fpv_supportResolveOrigin;
    ["carrier-only denied", !(_r get "ok") && {(_r get "reason") == "CARRIER_ONLY_ORIGIN"}] call _assert;
    private _active = {
        sidesX setVariable [_resource, _side]; spawner setVariable [_resource, 0];
        _resource setMarkerPosLocal [2000, 5000, 0]; A3UE_FPV_siteEpoch = "QA_SUP02";
        A3UE_FPV_siteLifecycle = createHashMapFromArray [[_resource, createHashMapFromArray [
            ["phase", "active"], ["siteType", "Resource"], ["siteSide", _side], ["generation", 1]
        ]]];
    };
    call _active; _airOrigins = [];
    {
        (A3UE_FPV_siteLifecycle get _resource) set ["siteType", _x];
        [_resource, "ACTIVE_SITE", "QA_SUP02", 1, "ACTIVE_SITE " + _x] call _caseVariants;
    } forEach ["Airport", "Outpost", "Resource"];
    _r = [_side, _targetPos, _plan, _context] call A3UE_fnc_fpv_supportResolveOrigin;
    ["active Resource origin generation", (_r get "ok") && {(_r get "originContract") == "ACTIVE_SITE"} && {(_r get "originGeneration") == 1}] call _assert;
    spawner setVariable [_resource, 2];
    _r = [_side, _targetPos, _plan, _context] call A3UE_fnc_fpv_supportResolveOrigin;
    ["inactive lifecycle site denied", !(_r get "ok")] call _assert;
    spawner setVariable [_resource, 0]; (A3UE_FPV_siteLifecycle get _resource) set ["phase", "closed"];
    _explicit set ["originMarker", _resource];
    _r = [_side, _targetPos, _plan, _explicit] call A3UE_fnc_fpv_supportResolveOrigin;
    ["arbitrary explicit marker denied", !(_r get "ok")] call _assert;
    _landOrigins = [_resource];
    [_resource, "AU_LAND", -1, -1] call _caseVariants;
    _r = [_side, _targetPos, _plan, _explicit] call A3UE_fnc_fpv_supportResolveOrigin;
    ["explicit AU land eligibility retained", (_r get "ok") && {(_r get "originContract") == "AU_LAND"}] call _assert;
    _landOrigins = []; call _active;
    {
        private _bad = createHashMapFromArray [["originMarker", _x]];
        _r = [_side, _targetPos, _plan, _bad, createHashMap] call A3UE_fnc_fpv_supportResolveOrigin;
        [format ["strict invalid spelling %1", _x], !(_r get "ok")] call _assert;
    } forEach [toUpper (_prefix + "missing"), toLower (_prefix + "missing"), toUpper _carrier, toLower _carrier];
    _explicit set ["originMarker", toUpper _resource];
    {
        call _active;
        switch (_x) do {
            case "side": {sidesX setVariable [_resource, _hostiles # 0];};
            case "capture": {(A3UE_FPV_siteLifecycle get _resource) set ["captured", true];};
            case "retirement": {(A3UE_FPV_siteLifecycle get _resource) set ["cleanupDrones", [objNull]];};
            case "phase": {(A3UE_FPV_siteLifecycle get _resource) set ["phase", "closed"];};
            case "spawner": {spawner setVariable [_resource, 2];};
            case "siteType": {(A3UE_FPV_siteLifecycle get _resource) set ["siteType", "Town"];};
            case "siteSide": {(A3UE_FPV_siteLifecycle get _resource) set ["siteSide", _hostiles # 0];};
        };
        _r = [_side, _targetPos, _plan, _explicit, createHashMap] call A3UE_fnc_fpv_supportResolveOrigin;
        [format ["noncanonical %1 denied", _x], !(_r get "ok") && {(_r get "reason") == "ORIGIN_INELIGIBLE"}] call _assert;
    } forEach ["side", "capture", "retirement", "phase", "spawner", "siteType", "siteSide"];
    call _active;
    _airOrigins = [_near]; _deniedMarker = _resource;
    _r = [_side, _targetPos, _plan, _explicit, createHashMap] call A3UE_fnc_fpv_supportResolveOrigin;
    ["noncanonical unreachable explicit never substitutes reachable airport", !(_r get "ok")] call _assert;
    _deniedMarker = ""; _airOrigins = [];
    private _allPlansValid = true;
    for "_i" from 1 to 20 do {
        _r = [_side, objNull, 500, _context, "attack", _targetPos] call A3UE_fnc_fpv_resolveSupportPackage;
        if (!(_r get "ok") || {(_r get "uavClass") != _fast} || {(_r get "payloadRole") != "AT"}) then {_allPlansValid = false;};
    };
    ["high-weight infeasible role and class never selected", _allPlansValid] call _assert;
    _r = [_side, objNull, 1, _context, "attack", _targetPos] call A3UE_fnc_fpv_resolveSupportPackage;
    ["unaffordable tuples rejected before launch", !(_r get "ok") && {(_r get "failure") == "BUDGET_TOO_LOW"} && {_spawns == 0}] call _assert;
    _signal = 0.2;
    _r = [_side, objNull, 500, _context, "attack", _targetPos] call A3UE_fnc_fpv_resolveSupportPackage;
    ["no feasible tuple explicit failure", !(_r get "ok") && {A3UE_FPV_supportTransientMarkers isEqualTo []} && {_spawns == 0}] call _assert;
    _signal = 0.8;
    {
        _markerMutation = _x; call _active; _landOrigins = []; _seenOrigin = "";
        _context set ["originMarker", toUpper _resource];
        private _name = _prefix + _x;
        private _cost = [_context, {[_name, _side, "attack", 500, objNull, _targetPos, 0, 0] call A3A_fnc_SUP_FPV}] call A3UE_fnc_fpv_withSupportContext;
        [format ["launch %1 revalidation returns -1 without spawning", _x], _cost == -1 && {_spawns == 0}] call _assert;
        [format ["launch %1 creation context canonical", _x], _seenOrigin isEqualTo _resource] call _assert;
        [format ["launch %1 cleans marker and AU business state", _x], A3UE_FPV_supportTransientMarkers isEqualTo []
            && {A3A_activeSupports isEqualTo []} && {A3A_supportStrikes isEqualTo []}
            && {_createdMarkers findIf {markerShape _x != ""} == -1}] call _assert;
        _signal = 0.8;
    } forEach ["capture", "generation", "epoch", "position", "contract", "retirement", "link"];
    {if (markerShape _x != "") then {deleteMarker _x;};} forEach _createdMarkers;
    {deleteMarkerLocal _x; sidesX setVariable [_x, nil]; spawner setVariable [_x, nil];} forEach _markers;
    deleteVehicle _target; deleteGroup _group;
    call _restore;
    diag_log format ["[A3UE FPV TEST SUP-02] END result=%1 cases=%2 failures=%3; STRUCTURAL ONLY; restart disposable mission", ["PASS", "FAIL"] select (_failures > 0), _cases, _failures];
};
