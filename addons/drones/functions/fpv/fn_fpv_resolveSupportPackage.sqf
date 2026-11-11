params [
    ["_side", sideUnknown],
    ["_target", objNull],
    ["_maxSpend", 0],
    ["_contextInput", createHashMap],
    ["_resPool", ""],
    ["_targPos", []],
    ["_queryOnly", false]
];

private _doctrine = missionNamespace getVariable ["A3UE_FPV_doctrine", createHashMap];

private _contextMap = [_resPool, _contextInput] call A3UE_fnc_fpv_getSupportContext;
private _contextKey = _contextMap getOrDefault ["context", "ReactiveSupport"];

private _makeFailure = {
    params ["_failure", ["_extra", createHashMap]];

    private _result = createHashMapFromArray [
        ["ok", false],
        ["failure", _failure],
        ["context", _contextKey]
    ];

    if (_extra isEqualType createHashMap) then {
        {
            _result set [_x, _y];
        } forEach _extra;
    };

    _result
};

// AU maxDefenceSpend supplies a ceiling, never an unlimited-budget sentinel.
// The same contract applies to explicit createSupport calls.
if !(_maxSpend isEqualType 0 && {finite _maxSpend} && {_maxSpend > 0}) exitWith {
    ["NO_BUDGET"] call _makeFailure
};
// Startup builds the doctrine/catalog. Queries must not initialize shared state.
if (count _doctrine == 0) exitWith {["NO_CONTEXT_DOCTRINE"] call _makeFailure};

private _targetSide = _contextMap getOrDefault ["targetSide", sideUnknown];
private _hostileSides = [_side, _targetSide] call A3UE_fnc_fpv_getHostileSides;
if (_hostileSides isEqualTo []) exitWith {
    ["NO_HOSTILE_TARGET_SIDE"] call _makeFailure
};
if (_target isEqualType objNull && {!isNull _target} && {isNull ([_target, _hostileSides] call A3UE_fnc_fpv_filterTarget)}) exitWith {
    ["TARGET_INELIGIBLE"] call _makeFailure
};

private _weightedPick = {
    params ["_entries"];

    if (_entries isEqualTo []) exitWith {""};

    private _totalWeight = 0;
    {
        _totalWeight = _totalWeight + ((_x param [1, 0]) max 0);
    } forEach _entries;

    if (_totalWeight <= 0) exitWith {(_entries select 0) param [0, ""]};

    private _selected = (_entries select ((count _entries) - 1)) param [0, ""];
    private _roll = random _totalWeight;
    {
        _roll = _roll - ((_x param [1, 0]) max 0);
        if (_roll <= 0) exitWith {
            _selected = _x param [0, _selected];
        };
    } forEach _entries;

    _selected
};

private _contextEntry = _doctrine getOrDefault [_contextKey, createHashMap];
if (count _contextEntry == 0) exitWith {
    ["NO_CONTEXT_DOCTRINE"] call _makeFailure
};

private _candidateSideKeys = switch (_side) do {
    case east: { ["east"] };
    case west: { ["west"] };
    case independent: { ["independent"] };
    default { [] };
};
if (_candidateSideKeys isEqualTo []) exitWith {
    ["INVALID_SIDE"] call _makeFailure
};

private _supportData = _contextEntry getOrDefault ["support", createHashMap];
private _classPools = _contextEntry getOrDefault ["classPools", createHashMap];
private _roleWeights = _contextEntry getOrDefault ["roleWeights", createHashMap];
private _familyWeights = _contextEntry getOrDefault ["familyWeights", createHashMap];
private _vehicleResourceCosts = missionNamespace getVariable ["A3A_vehicleResourceCosts", createHashMap];
if !(_vehicleResourceCosts isEqualType createHashMap) then {
    _vehicleResourceCosts = createHashMap;
};

private _fallbackClassCosts = createHashMapFromArray [
    ["armafpv", 75],
    ["fpv_ua", 65],
    ["kvn", 95]
];

private _costOverhead = _supportData getOrDefault ["costOverhead", 20];
private _minDroneCount = (_supportData getOrDefault ["droneCountMin", 1]) max 1;
private _maxDroneCount = (_supportData getOrDefault ["droneCountMax", _minDroneCount]) max _minDroneCount;
private _pairTier = _supportData getOrDefault ["pairTier", 99];
private _warTier = missionNamespace getVariable ["tierWar", 1];
private _minWarTier = _supportData getOrDefault ["minWarTier", 3];

if !(_minWarTier isEqualType 0) then {
    _minWarTier = 3;
};

if (_warTier < _minWarTier) exitWith {
    ["WAR_TIER_TOO_LOW", createHashMapFromArray [["warTier", _warTier], ["minWarTier", _minWarTier]]] call _makeFailure
};

private _resolveBaseCost = {
    params ["_familyId", "_uavClass"];

    private _baseCost = _vehicleResourceCosts getOrDefault [_uavClass, -1];
    if !(_baseCost isEqualType 0) then {
        _baseCost = -1;
    };
    if (_baseCost < 0) then {
        _baseCost = _fallbackClassCosts getOrDefault [_familyId, 80];
    };

    _baseCost
};

private _roleHasClassPool = {
    params ["_familyId", "_roleId"];

    private _hasPool = false;
    {
        private _sidePools = _classPools getOrDefault [_x, createHashMap];
        private _familyPools = _sidePools getOrDefault [_familyId, createHashMap];
        private _rolePool = _familyPools getOrDefault [_roleId, []];
        if (_rolePool isNotEqualTo []) exitWith {
            _hasPool = true;
        };
    } forEach _candidateSideKeys;

    _hasPool
};

private _targetClass = "none";
if (_target isEqualType objNull && {!isNull _target}) then {
    _targetClass = switch (true) do {
        case (_target isKindOf "Air"): {"air"};
        case (_target isKindOf "Tank"): {"vehicle"};
        case (_target isKindOf "Wheeled_APC_F"): {"vehicle"};
        case (_target isKindOf "Car"): {"vehicle"};
        case (_target isKindOf "Ship"): {"vehicle"};
        case (_target isKindOf "StaticWeapon"): {"static"};
        case (_target isKindOf "Man"): {"infantry"};
        case (_target isKindOf "LandVehicle"): {"vehicle"};
        default {"unknown"};
    };
};

if (_targetClass isEqualTo "air") exitWith {
    ["AIR_TARGET_UNSUPPORTED"] call _makeFailure
};

private _weightedRoles = [];
{
    private _roleId = _x;
    private _weight = _roleWeights getOrDefault [_roleId, 0];
    // Target preferences may adjust permitted roles, never enable a disabled one.
    if (_weight <= 0) then { continue };

    switch (_targetClass) do {
        case "vehicle": {
            if (_roleId isEqualTo "AT") then { _weight = _weight + 35; };
            if (_roleId isEqualTo "AP") then { _weight = _weight + 10; };
            if (_roleId isEqualTo "RECON") then { _weight = (_weight - 5) max 0; };
        };
        case "infantry": {
            if (_roleId isEqualTo "AP") then { _weight = _weight + 35; };
            if (_roleId isEqualTo "RECON") then { _weight = _weight + 5; };
        };
        case "static": {
            if (_roleId isEqualTo "AP") then { _weight = _weight + 25; };
            if (_roleId isEqualTo "AT") then { _weight = _weight + 10; };
        };
    };

    if (_weight <= 0) then { continue };

    private _roleHasFamily = false;
    {
        if ((_familyWeights getOrDefault [_x, 0]) > 0 && {[_x, _roleId] call _roleHasClassPool}) exitWith {
            _roleHasFamily = true;
        };
    } forEach ["armafpv", "fpv_ua", "kvn"];

    if (_roleHasFamily) then {
        _weightedRoles pushBack [_roleId, _weight];
    };
} forEach ["AT", "AP", "RECON"];

if (_weightedRoles isEqualTo []) exitWith {
    ["NO_VALID_ROLE_FOR_TARGET", createHashMapFromArray [["targetClass", _targetClass]]] call _makeFailure
};

// Establish feasible origin/class/role combinations before drawing any plan.
if !(_targPos isEqualType [] && {count _targPos >= 2}) then {
    if (_target isEqualType objNull && {!isNull _target}) then {_targPos = getPosATL _target;};
};
if !(_targPos isEqualType [] && {count _targPos >= 2}) exitWith {["INVALID_TARGET_POSITION"] call _makeFailure};
// Object engagements use their actual position; position-only requests defer
// safety until a seed is selected. Scan once before bounded class/origin work.
if (!isNull _target && {!([_side, _target, _targPos, _supportData] call A3UE_fnc_fpv_supportPassesSafetyRing)}) exitWith {
    ["UNSAFE_ENGAGEMENT"] call _makeFailure
};
private _siteType = _contextKey;
private _profileId = _contextEntry getOrDefault ["profileId", format ["support_%1_default", toLower _contextKey]];
private _resourcePool = _contextMap getOrDefault ["resourcePool", _supportData getOrDefault ["resourcePool", "defence"]];
private _candidates = [];
private _planning = createHashMap;
private _lowestEstimatedCost = -1;
private _reachFailure = "NO_VALID_CLASS_FOR_ROLE";
{
    private _payloadRole = _x # 0;
    {
        private _familyId = _x;
        private _familyWeight = _familyWeights getOrDefault [_familyId, 0];
        if (_familyWeight <= 0) then {continue;};
        private _sidePools = _classPools getOrDefault [_candidateSideKeys # 0, createHashMap];
        private _entries = (_sidePools getOrDefault [_familyId, createHashMap]) getOrDefault [_payloadRole, []];
        {
            _x params ["_uavClass", "_classWeight"];
            if (_classWeight <= 0 || {!isClass (configFile >> "CfgVehicles" >> _uavClass)}) then {continue;};
            private _baseCost = [_familyId, _uavClass] call _resolveBaseCost;
            private _droneCount = _minDroneCount;
            private _estimatedCost = (_baseCost * _droneCount) + _costOverhead;
            if (_maxDroneCount > _minDroneCount && {_warTier >= _pairTier}) then {
                private _expandedCost = (_baseCost * _maxDroneCount) + _costOverhead;
                if (_expandedCost <= _maxSpend) then {
                    _droneCount = _maxDroneCount; _estimatedCost = _expandedCost;
                };
            };
            if (_lowestEstimatedCost < 0 || {_estimatedCost < _lowestEstimatedCost}) then {_lowestEstimatedCost = _estimatedCost;};
            if (_estimatedCost > _maxSpend) then {continue;};
            private _candidate = createHashMapFromArray [
                ["ok", true], ["context", _contextKey],
                ["contextSource", _contextMap getOrDefault ["contextSource", "default"]],
                ["resourcePool", _resourcePool], ["targetSide", _targetSide],
                ["originMarker", _contextMap getOrDefault ["originMarker", ""]],
                ["siteType", _siteType], ["profileId", _profileId],
                ["templateSiteType", _supportData getOrDefault ["templateSiteType", ""]],
                ["familyId", _familyId], ["payloadRole", _payloadRole], ["uavClass", _uavClass],
                ["droneCount", _droneCount], ["estimatedCost", _estimatedCost], ["costOverhead", _costOverhead],
                ["selectorWeight", _supportData getOrDefault ["selectorWeight", 0.35]],
                ["activeRadius", _supportData getOrDefault ["activeRadius", 350]],
                ["strikeDuration", _supportData getOrDefault ["strikeDuration", 300]],
                ["safetyRadius", _supportData getOrDefault ["safetyRadius", 40]],
                ["minWarTier", _minWarTier], ["targetClass", _targetClass], ["classWeight", _classWeight]
            ];
            private _origin = [_side, _targPos, _candidate, _contextMap, _planning] call A3UE_fnc_fpv_supportResolveOrigin;
            if !(_origin get "ok") then {_reachFailure = _origin get "reason"; continue;};
            _candidate set ["origin", _origin];
            _candidate set ["originMarker", _origin get "originMarker"];
            _candidates pushBack _candidate;
        } forEach _entries;
    } forEach ["armafpv", "fpv_ua", "kvn"];
} forEach _weightedRoles;
if (_candidates isEqualTo []) exitWith {
    if (_lowestEstimatedCost > _maxSpend) exitWith {
        ["BUDGET_TOO_LOW", createHashMapFromArray [["estimatedCost", _lowestEstimatedCost], ["maxSpend", _maxSpend]]] call _makeFailure
    };
    [_reachFailure] call _makeFailure
};
// Both routes use the same candidate set. Availability performs no random draw,
// retains no plan and cannot overwrite the last successfully launched support.
if (_queryOnly) exitWith {
    createHashMapFromArray [["ok", true], ["context", _contextKey],
        ["selectorWeight", _supportData getOrDefault ["selectorWeight", 0.35]],
        ["candidateCount", count _candidates]]
};
private _feasibleRoles = _weightedRoles select {
    private _role = _x # 0;
    _candidates findIf {(_x get "payloadRole") == _role} > -1
};
private _payloadRole = [_feasibleRoles] call _weightedPick;
private _roleCandidates = _candidates select {(_x get "payloadRole") == _payloadRole};
private _feasibleFamilies = [];
{
    private _family = _x;
    if (_roleCandidates findIf {(_x get "familyId") == _family} > -1) then {
        _feasibleFamilies pushBack [_family, _familyWeights get _family];
    };
} forEach ["armafpv", "fpv_ua", "kvn"];
private _familyId = [_feasibleFamilies] call _weightedPick;
private _familyCandidates = _roleCandidates select {(_x get "familyId") == _familyId};
private _uavClass = [_familyCandidates apply {[_x get "uavClass", _x get "classWeight"]}] call _weightedPick;
private _result = _familyCandidates # (_familyCandidates findIf {(_x get "uavClass") == _uavClass});
_result deleteAt "classWeight";
_result
