// Copy to the disposable AU mission, then Local Exec on EACH machine:
// [] call compileScript ["au04_adapter.sqf"];
// Structural binding/conflict evidence only; no attack-route qualification.
private _names = ["singleAttack", "wavedAttack", "attackHQ", "invaderPunish", "showInterceptedSetupCall", "showInterceptedSupportCall"];
private _before = _names apply {str (missionNamespace getVariable ["A3A_fnc_" + _x, 0])};
private _report = call A3UE_fnc_fpv_reportAUAdapter;
private _rows = _report getOrDefault ["rows", []];
private _failures = [];
private _blocked = [];
if (count _rows != 6) then {_failures pushBack "SIX_BINDINGS_REQUIRED";};
{
    if ((_x getOrDefault ["state", ""]) isNotEqualTo "ACTIVE" || {!(_x getOrDefault ["bodyMatches", false])}) then {
        _failures pushBack ["BASELINE_BINDING", _x];
    };
} forEach _rows;
if !(_report getOrDefault ["versionReviewed", false]) then {_blocked pushBack "UNREVIEWED_AU_VERSION";};
if (_failures isNotEqualTo [] || {_blocked isNotEqualTo []}) exitWith {
    private _result = createHashMapFromArray [
        ["test", "AU04_BINDINGS"], ["machine", clientOwner], ["report", _report],
        ["failures", _failures], ["blocked", _blocked],
        ["status", ["BLOCKED", "FAIL"] select (_failures isNotEqualTo [])]
    ];
    diag_log ["A3UE FPV TEST AU04", _result];
    _result
};

// Return-only helper caches stock code; unknown names cannot select a file.
private _first = ["showInterceptedSetupCall"] call A3UE_fnc_fpv_getStockAUFunction;
private _second = ["showInterceptedSetupCall"] call A3UE_fnc_fpv_getStockAUFunction;
if (str _first isNotEqualTo str _second || {count str _first < 16}) then {_failures pushBack "STOCK_CACHE";};
if (str (["foreign"] call A3UE_fnc_fpv_getStockAUFunction) isNotEqualTo str {}) then {_failures pushBack "STOCK_ALLOWLIST";};

// Metadata remains unchanged, so only checking the config/file is insufficient.
// Restore only our sentinel, never a concurrently replaced foreign provider.
private _functionName = "A3A_fnc_showInterceptedSetupCall";
private _original = missionNamespace getVariable [_functionName, {}];
if (isFinal _original) then {
    _blocked pushBack "IMMUTABLE_BINDING_CONFLICT_CASE";
} else {
    private _foreign = {diag_log "AU04 foreign sentinel";};
    missionNamespace setVariable [_functionName, _foreign];
    private _conflict = call A3UE_fnc_fpv_reportAUAdapter;
    private _again = call A3UE_fnc_fpv_reportAUAdapter;
    private _row = (_again get "rows") select {(_x get "function") isEqualTo _functionName};
    if (count _row != 1 || {((_row # 0) get "state") isNotEqualTo "CONFLICT"}) then {
        _failures pushBack ["FOREIGN_NOT_REPORTED", _conflict, _again];
    };
    if (str (missionNamespace getVariable _functionName) isEqualTo str _foreign) then {
        missionNamespace setVariable [_functionName, _original];
    } else {
        _failures pushBack "FOREIGN_BINDING_OVERWRITTEN_OR_CONCURRENT_CHANGE";
    };
};

private _after = _names apply {str (missionNamespace getVariable ["A3A_fnc_" + _x, 0])};
if (_before isNotEqualTo _after) then {_failures pushBack "RESTORATION_FAILED_RESTART_NOW";};
private _restored = call A3UE_fnc_fpv_reportAUAdapter;
private _result = createHashMapFromArray [
    ["test", "AU04_BINDINGS"], ["machine", clientOwner],
    ["failures", _failures], ["blocked", _blocked], ["report", _restored],
    ["status", if (_failures isNotEqualTo []) then {"FAIL"} else {if (_blocked isNotEqualTo []) then {"BLOCKED"} else {"PASS"}}]
];
diag_log ["A3UE FPV TEST AU04", _result];
_result
