// Read-only, machine-local startup/on-demand diagnostics. Never repairs bindings.
// Unary call can inherit an unrelated _this (including Functions Library postInit).
// Normalize before the Boolean condition; typed params would also report bad input.
private _args = if (!isNil "_this" && {_this isEqualType []}) then {_this} else {[]};
_args params [["_log", true]];
if !(_log isEqualType true) then {_log = true;};

if !(isClass (missionConfigFile >> "A3A")) exitWith {createHashMap};

private _au = [] call A3UE_fnc_fpv_auReviewedVersion;
private _version = _au # 0;
private _rows = [];
{
    _x params ["_name", "_category"];
    private _functionName = "A3A_fnc_" + _name;
    private _expectedPath = format ["\fpv_ai_drones\functions\fpv\au_overrides\fn_%1.sqf", _name];
    private _functionConfig = configFile >> "CfgFunctions" >> "A3A" >> _category >> _name;
    private _configPath = getText (_functionConfig >> "file");
    // Retain provenance when an earlier exact-category provider was overwritten
    // during config merge. The reviewed base and this addon are the only owners.
    private _configSources = configSourceAddonList _functionConfig;
    private _foreignSources = _configSources select {!(toLower _x in ["a3a_core", "fpv_ai_drones"])};
    private _meta = _functionName call BIS_fnc_functionMeta;
    if (isNil "_meta" || {!(_meta isEqualType [])}) then {_meta = [];};
    private _effectivePath = _meta param [0, "", [""]];
    private _effective = missionNamespace getVariable [_functionName, 0];

    // Same complete library-context rule as guarded production admission.
    private _prepared = [_functionName, _expectedPath, _functionConfig, ["a3a_core", "fpv_ai_drones"]]
        call A3UE_fnc_fpv_bindingRepresentations;
    _prepared params ["_representationReason", "_expectedBodies"];
    private _effectiveBody = if (_effective isEqualType {}) then {str _effective} else {""};
    private _bodyMatches = _representationReason == "REVIEWED" && {count _effectiveBody <= 262144}
        && {(_expectedBodies findIf {_x isEqualTo _effectiveBody}) >= 0};

    private _declarations = [];
    {
        private _tag = _x;
        {
            private _root = _x;
            {
                private _declaration = _x >> _name;
                if (isClass _declaration) then {
                    _declarations pushBack [str _root, configName _x, getText (_declaration >> "file"), configSourceAddonList _declaration];
                };
            } forEach ("true" configClasses _root);
        } forEach [configFile >> "CfgFunctions" >> _tag, missionConfigFile >> "CfgFunctions" >> _tag];
    } forEach ["A3A"];

    private _state = "ACTIVE";
    if !(_effective isEqualType {}) then {_state = "MISSING";};
    if (_state isEqualTo "ACTIVE" && {
        toLower _configPath isNotEqualTo toLower _expectedPath
        || {toLower _effectivePath isNotEqualTo toLower _expectedPath}
        || {!_bodyMatches}
        || {count _declarations != 1}
        || {_foreignSources isNotEqualTo []}
    }) then {_state = "CONFLICT";};

    _rows pushBack createHashMapFromArray [
        ["function", _functionName], ["category", _category], ["state", _state],
        ["configPath", _configPath], ["effectivePath", _effectivePath],
        ["bodyMatches", _bodyMatches], ["representationReason", _representationReason], ["declarations", _declarations],
        ["configSources", _configSources], ["foreignSources", _foreignSources]
    ];
} forEach [
    ["singleAttack", "CREATE"], ["wavedAttack", "CREATE"],
    ["attackHQ", "CREATE"], ["invaderPunish", "CREATE"],
    ["showInterceptedSetupCall", "Supports"], ["showInterceptedSupportCall", "Supports"]
];

private _report = createHashMapFromArray [
    ["reviewedVersion", (_au # 1) joinString ", "], ["loadedVersion", _version],
    ["versionReviewed", _au # 2], ["machineOwner", clientOwner],
    ["server", isServer], ["rows", _rows],
    ["stockDelegation", "Loaded AU source; FPV-capable singleAttack remains server-coordinated"],
    ["scope", "Six config adapters only; support registry and Rivals readiness require AU-06"]
];
missionNamespace setVariable ["A3UE_FPV_auAdapterReport", _report];
if (_log) then {
    // Startup/on-demand transport only. Keep the complete report above in memory.
    // Cap after serialization as paths/provider names can contain quotes or newlines.
    private _emit = {
        // Callers pass a flat record; serialize that complete argument array.
        private _text = str _this;
        _text = (_text splitString (toString [10, 13])) joinString " ";
        if (count _text > 760) then {
            _text = (_text select [0, 700]) + format [" <TRUNCATED originalChars=%1; full details in A3UE_FPV_auAdapterReport>", count _text];
        };
        diag_log _text;
    };
    ["A3UE FPV AU adapter SUMMARY", _version select [0, 48], "versionChars/max48", count _version, _report get "versionReviewed",
        clientOwner, isServer, count _rows, "six config adapters; full details in A3UE_FPV_auAdapterReport"] call _emit;
    // Informational only: nothing switches off on an AU release that is not on the list.
    if !(_report get "versionReviewed") then {
        ["A3UE FPV AU version NOTICE", _version select [0, 48], "not in the reviewed list", _report get "reviewedVersion",
            "all FPV features stay on; report problems with this RPT"] call _emit;
    };
    {
        ["A3UE FPV AU adapter ROW", _forEachIndex + 1, _x get "function", _x get "state",
            _x get "bodyMatches", "config/effective", (_x get "configPath") select [0, 120],
            (_x get "effectivePath") select [0, 120], "pathsTruncated",
            count (_x get "configPath") > 120 || {count (_x get "effectivePath") > 120}, "declarations/sources/foreign counts",
            count (_x get "declarations"), count (_x get "configSources"), count (_x get "foreignSources"),
            "paths max120; provenance details omitted; full report in memory"] call _emit;
    } forEach _rows;
};
_report
