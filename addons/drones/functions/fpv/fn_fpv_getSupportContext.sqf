params [
    ["_resPool", ""],
    ["_contextOverride", createHashMap]
];

private _validContexts = [
    "ReactiveSupport",
    "CounterAttackSupport",
    "MajorAttackSupport",
    "HQAttackSupport",
    "PunishmentSupport"
];
private _defaultContext = "ReactiveSupport";
private _defaultPoolByContext = createHashMapFromArray [
    ["ReactiveSupport", "defence"],
    ["CounterAttackSupport", "defence"],
    ["MajorAttackSupport", "attack"],
    ["HQAttackSupport", "attack"],
    ["PunishmentSupport", "attack"]
];

private _fallbackContext = switch (_resPool) do {
    case "attack": {"MajorAttackSupport"};
    case "defence": {"ReactiveSupport"};
    default {_defaultContext};
};

private _normalizeContext = {
    params [
        ["_candidate", createHashMap],
        ["_fallbackContextKey", _defaultContext],
        ["_contextSource", "default"]
    ];

    if !(_candidate isEqualType createHashMap) then {
        _candidate = createHashMap;
    };

    private _contextKey = _candidate getOrDefault ["context", _fallbackContextKey];
    if !(_contextKey in _validContexts) then {
        _contextKey = _fallbackContextKey;
    };

    private _originMarker = _candidate getOrDefault ["originMarker", ""];
    if !(_originMarker isEqualType "") then {
        _originMarker = "";
    };

    private _resourcePool = _candidate getOrDefault ["resourcePool", ""];
    if !(_resourcePool in ["attack", "defence"]) then {
        _resourcePool = _defaultPoolByContext getOrDefault [_contextKey, _defaultPoolByContext getOrDefault [_fallbackContextKey, "defence"]];
    };

    private _targetSide = _candidate getOrDefault ["targetSide", sideUnknown];
    if !(_targetSide isEqualType sideUnknown) then {
        _targetSide = sideEmpty;
    };

    createHashMapFromArray [
        ["context", _contextKey],
        ["originMarker", _originMarker],
        ["resourcePool", _resourcePool],
        ["targetSide", _targetSide],
        ["contextSource", _contextSource]
    ]
};

if (_contextOverride isEqualType createHashMap && {count _contextOverride > 0}) exitWith {
    [_contextOverride, _fallbackContext, "argument"] call _normalizeContext
};

private _context = if (isNil "_A3UE_FPV_callContext") then {
    missionNamespace getVariable ["A3UE_FPV_supportContext", createHashMap]
} else {
    _A3UE_FPV_callContext
};
if (_context isEqualType createHashMap && {count _context > 0}) exitWith {
    [_context, _fallbackContext, "wrapper"] call _normalizeContext
};

[createHashMapFromArray [["context", _fallbackContext]], _fallbackContext, ["default", "pool"] select (_resPool in ["attack", "defence"])] call _normalizeContext
