// Packet A: bounded READ evidence or explicit NEGATIVE production regression; no callbacks/installers.
// Use [[], "scripts\ua_dive\bindings.sqf"] call A3UE_FPV_QA_dispatch after context qualification.
params [["_mode", "READ"]];
if !(_mode in ["READ", "NEGATIVE"]) exitWith {copyToClipboard "Packet A unknown mode";};
if (!isServer || {!hasInterface} || {isRemoteExecuted} || {!canSuspend}) exitWith {
    diag_log ["A3UE_FPV_QA_BINDINGS_BLOCKED", clientOwner, isServer, hasInterface, isRemoteExecuted, canSuspend];
    if (hasInterface) then {copyToClipboard "Packet A BLOCKED; retain tagged RPT context";};
};
if (isNil "BIS_fnc_functionMeta" || {!(isClass (missionConfigFile >> "A3A"))}
    || {!(missionNamespace getVariable ["serverInitDone", false])}) exitWith {
    diag_log ["A3UE_FPV_QA_BINDINGS_BLOCKED", "Functions Library/AU mission not ready"];
    copyToClipboard "Packet A BLOCKED: Functions Library/AU mission not ready";
};
private _started = diag_tickTime;
private _run = format ["PACKET-A:%1:%2", clientOwner, diag_frameNo];
private _records = 0;
// Every serialized record <= 900 chars even with escaping. No full code dumps.
private _emit = {
    params ["_kind", "_identity", "_value"];
    private _text = str ["A3UE_FPV_QA_BINDINGS", _run, _kind, _identity, _value];
    _text = (_text splitString (toString [10, 13])) joinString " ";
    if (count _text > 800) then {
        _text = (_text select [0, 720]) + format [" <TRUNCATED originalChars=%1>", count _text];
    };
    diag_log _text;
    _records = _records + 1;
};
private _clip = {
    params ["_value", ["_limit", 140]];
    private _text = if (_value isEqualType "") then {_value} else {str _value};
    if (count _text > _limit) then {(_text select [0, _limit]) + format ["<omitted %1 chars>", count _text - _limit]} else {_text};
};
// Observation controls only; production regression is separate below.
private _compare = {params ["_expected", "_actual"]; [_expected isEqualTo _actual]};
private _difference = {
    params ["_expected", "_actual", "_identity", "_alignment"];
    private _commonLimit = (count _expected) min (count _actual);
    if ((count _expected max count _actual) > 262144) exitWith {
        ["DIFF_UNAVAILABLE", _identity, [_alignment, "representation exceeds 262144-char search bound"]] call _emit;
    };
    // Binary prefix search: <= 19 native substring comparisons, no per-character walk/hash.
    private _low = 0;
    private _high = _commonLimit;
    for "_step" from 0 to 18 do {
        if (_low < _high) then {
            private _mid = floor ((_low + _high + 1) / 2);
            if ((_expected select [0, _mid]) isEqualTo (_actual select [0, _mid])) then {_low = _mid;} else {_high = _mid - 1;};
        };
    };
    private _offset = 0 max (_low - 32);
    ["DIFF", _identity, [_alignment, "commonPrefix/index", _low, "equal", _expected isEqualTo _actual,
        "windowStart", _offset, "expected", _expected select [_offset, 96], "effective", _actual select [_offset, 96]]] call _emit;
    // Numeric windows survive RPT newline flattening. Reuse the bounded offset.
    private _codeOffset = 0 max (_low - 4);
    ["DIFF_CODES", _identity, [_alignment, "firstDiff", _low, "lengths E/A", count _expected, count _actual,
        "windowStart", _codeOffset, "codes E/A", toArray (_expected select [_codeOffset, 12]),
        toArray (_actual select [_codeOffset, 12])]] call _emit;
    ["EDGES", _identity, [_alignment, "prefix E/A", _expected select [0, 96], _actual select [0, 96],
        "suffix E/A", _expected select [0 max (count _expected - 96)], _actual select [0 max (count _actual - 96)]]] call _emit;
};
// Isolated compiler control: generated context versus literal CR/LF/TAB/#line.
// Calls return only a fixture string; no production function is executed.
private _literal = toString [65, 13, 10, 35, 108, 105, 110, 101, 32, 67, 9, 66];
private _generatedContext = toString [13, 10] + format ["%1line 1 ""Packet A isolated compiler control""", "#"] + toString [13, 10];
private _fixture = compile (_generatedContext + str _literal + ";");
private _fixtureCopy = call compile str _fixture;
private _literalPreserved = (call _fixture) isEqualTo _literal && {(call _fixtureCopy) isEqualTo _literal};
["BEGIN", "host", [clientOwner, isServer, hasInterface, isRemoteExecuted, canSuspend,
    "version", productVersion, "AU", getText (configFile >> "CfgPatches" >> "A3A_core" >> "versionStr")]] call _emit;
["CONTEXT_CONTROL", "isolated literal", ["direct/copy complete", str _fixture isEqualTo str _fixtureCopy,
    "literal preserved", _literalPreserved, "literal codes", toArray _literal]] call _emit;
// Read the installed library's setting. Absent settings are not evidence of mode zero.
private _debug = uiNamespace getVariable ["bis_fnc_initFunctions_debugMode", "UNAVAILABLE"];
private _engineDebug = false;
#ifdef __A3_DEBUG__
_engineDebug = true;
#endif
["DEBUG", "library", ["uiNamespace bis_fnc_initFunctions_debugMode", _debug,
    "CfgFunctions debug", if (isNumber (missionConfigFile >> "CfgFunctions" >> "debug")) then {getNumber (missionConfigFile >> "CfgFunctions" >> "debug")} else {"UNAVAILABLE"},
    "__A3_DEBUG__ at helper preprocessing", _engineDebug]] call _emit;
private _specs = [
    ["A3A_fnc_SUP_FPV", "A3A", "A3UEFPVSupport", "SUP_FPV", "au_support\fn_SUP_FPV.sqf"],
    ["A3A_fnc_SUP_FPVAvailable", "A3A", "A3UEFPVSupport", "SUP_FPVAvailable", "au_support\fn_SUP_FPVAvailable.sqf"],
    ["A3UE_fnc_fpv_rivalsSelectAndExecuteEvent", "A3UE", "FPV", "fpv_rivalsSelectAndExecuteEvent", "fn_fpv_rivalsSelectAndExecuteEvent.sqf"],
    ["A3UE_fnc_fpv_rivalsUavFlyby", "A3UE", "FPV", "fpv_rivalsUavFlyby", "fn_fpv_rivalsUavFlyby.sqf"],
    ["A3A_fnc_singleAttack", "A3A", "CREATE", "singleAttack", "au_overrides\fn_singleAttack.sqf"],
    ["A3A_fnc_wavedAttack", "A3A", "CREATE", "wavedAttack", "au_overrides\fn_wavedAttack.sqf"],
    ["A3A_fnc_attackHQ", "A3A", "CREATE", "attackHQ", "au_overrides\fn_attackHQ.sqf"],
    ["A3A_fnc_invaderPunish", "A3A", "CREATE", "invaderPunish", "au_overrides\fn_invaderPunish.sqf"],
    ["A3A_fnc_showInterceptedSetupCall", "A3A", "Supports", "showInterceptedSetupCall", "au_overrides\fn_showInterceptedSetupCall.sqf"],
    ["A3A_fnc_showInterceptedSupportCall", "A3A", "Supports", "showInterceptedSupportCall", "au_overrides\fn_showInterceptedSupportCall.sqf"],
    ["SCRT_fnc_rivals_selectAndExecuteEvent", "SCRT", "Rivals", "rivals_selectAndExecuteEvent", ""],
    ["SCRT_fnc_rivals_encounter_uavFlyby", "SCRT", "Rivals", "rivals_encounter_uavFlyby", ""]
];
private _compared = 0;
{
    _x params ["_name", "_tag", "_category", "_leaf", "_relative"];
    private _path = if (_tag == "SCRT") then {"\x\A3A\addons\scrt\Rivals\fn_" + _leaf + ".sqf"} else {"\fpv_ai_drones\functions\fpv\" + _relative};
    private _cfg = configFile >> "CfgFunctions" >> _tag >> _category >> _leaf;
    private _effective = missionNamespace getVariable [_name, 0];
    private _effectiveRole = "LIVE";
    if (_tag == "SCRT") then {
        private _claim = missionNamespace getVariable ["A3UE_FPV_rivalsHookClaim", createHashMap];
        private _wrapper = missionNamespace getVariable [["A3UE_fnc_fpv_rivalsSelectAndExecuteEvent", "A3UE_fnc_fpv_rivalsUavFlyby"] select (_leaf == "rivals_encounter_uavFlyby"), 0];
        if (count _claim > 0 && {_effective isEqualTo _wrapper} && {!(_claim getOrDefault ["released", false])}) then {
            _effective = (_claim getOrDefault ["originals", []]) param [parseNumber (_leaf == "rivals_encounter_uavFlyby"), 0];
            _effectiveRole = "CAPTURED_ORIGINAL (live owned wrapper; not a live predicate positive)";
        };
    };
    private _codeAvailable = _effective isEqualType {};
    private _meta = _name call BIS_fnc_functionMeta;
    if (isNil "_meta") then {_meta = [];};
    ["IDENTITY", _name, ["expected", _path, "declaration", str _cfg, "code", _codeAvailable,
        "final", if (_codeAvailable) then {isFinal _effective} else {"UNAVAILABLE"}]] call _emit;
    // All nine metadata fields, individually bounded; no lifecycle state or tokens.
    ["META_PATH", _name, ["available", count _meta >= 9 && {(_meta param [0, ""]) != ""},
        "path", [_meta param [0, "UNAVAILABLE"], 180] call _clip]] call _emit;
    ["META_FLAGS", _name, [_meta param [1, "UNAVAILABLE"], _meta param [2, "UNAVAILABLE"],
        _meta param [3, "UNAVAILABLE"], _meta param [4, "UNAVAILABLE"], _meta param [5, "UNAVAILABLE"],
        "extension/headerType/preInit/postInit/recompile"]] call _emit;
    ["META_NAMES", _name, [(_meta select [6, 3]) apply {[_x, 100] call _clip}, "tag/category/name"]] call _emit;
    private _sources = configSourceAddonList _cfg;
    private _allowed = if (_tag == "A3A" && {_category in ["CREATE", "Supports"]}) then {["a3a_core", "fpv_ai_drones"]} else {if (_tag == "SCRT") then {["a3a_scrt"]} else {["fpv_ai_drones"]}};
    ["PROVENANCE", _name, ["configPath", [getText (_cfg >> "file"), 180] call _clip,
        "sourceCount", count _sources, "first8", (_sources select [0, 8]) apply {[_x, 48] call _clip},
        "foreign", (_sources findIf {!(toLower _x in _allowed)}) >= 0]] call _emit;
    {
        private _parent = _x;
        private _parentSources = configSourceAddonList _parent;
        ["PARENT_PROVENANCE", _name, [[str _parent, 180] call _clip,
            "sources/count/first8", count _parentSources, (_parentSources select [0, 8]) apply {[_x, 40] call _clip},
            "excessOmitted", count _parentSources > 8]] call _emit;
    } forEach [configFile >> "CfgFunctions" >> _tag >> _category, configFile >> "CfgFunctions" >> _tag];
    private _declarations = 0;
    {
        private _root = _x;
        {
            private _declaration = _x >> _leaf;
            if (isClass _declaration) then {
                _declarations = _declarations + 1;
                // Bound output even for a foreign preset with many declarations.
                if (_declarations <= 8) then {
                    ["DECL", _name, [[str _declaration, 180] call _clip, [getText (_declaration >> "file"), 180] call _clip,
                        "headerType", if (isNumber (_declaration >> "headerType")) then {getNumber (_declaration >> "headerType")} else {"UNSET (library default)"},
                        "sourceCount", count (configSourceAddonList _declaration),
                        "first4", ((configSourceAddonList _declaration) select [0, 4]) apply {[_x, 32] call _clip}]] call _emit;
                };
            };
        } forEach ("true" configClasses _root);
    } forEach [configFile >> "CfgFunctions" >> _tag, missionConfigFile >> "CfgFunctions" >> _tag, campaignConfigFile >> "CfgFunctions" >> _tag];
    ["DECL_COUNT", _name, [_declarations, "records max8; excess explicitly omitted"]] call _emit;
    private _fileAvailable = fileExists _path;
    if (_fileAvailable && {_codeAvailable}) then {
        private _prepared = [_name, _path, _cfg, _allowed] call A3UE_fnc_fpv_bindingRepresentations;
        _prepared params ["_reason", "_expectedForms"];
        private _actual = str _effective;
        private _form = _expectedForms findIf {_x isEqualTo _actual};
        private _production = [_name, _path, _cfg, _allowed] call A3UE_fnc_fpv_hookBindingMatches;
        ["FULL_BODY", _name, [_reason, "role", _effectiveRole, "completeEqual/formIndex", _form >= 0, _form,
            "expectedLengths", _expectedForms apply {count _x}, "effectiveLength", count _actual,
            "liveProductionPredicate", _production, "filePatching", isFilePatchingEnabled]] call _emit;
        if (_reason != "REVIEWED") then {
            ["COMPARE_UNAVAILABLE", _name, [_reason, "no body equality inferred"]] call _emit;
        } else {
            if (_form < 0) then {
                // One bounded mismatch per reviewed form, retaining the complete equality result.
                {[_x, _actual, _name, format ["full form %1", _forEachIndex]] call _difference;} forEach _expectedForms;
            };
        };
        if (_reason == "REVIEWED") then {_compared = _compared + 1;};
    } else {
        ["COMPARE_UNAVAILABLE", _name, ["fileExists", _fileAvailable, "effectiveCode", _codeAvailable,
            "no negative comparison inferred"]] call _emit;
    };
} forEach _specs;
// Isolated local Code specimens only: never executed or bound into live namespaces.
private _controlSource = "params ['_value']; _value + 41001";
private _controlExpected = str compile _controlSource;
private _controlsPassed = _literalPreserved;
{
    _x params ["_label", "_source", "_wanted"];
    private _result = [_controlExpected, str compile _source] call _compare;
    private _pass = _result isEqualTo _wanted;
    _controlsPassed = _controlsPassed && _pass;
    ["CONTROL", _label, ["whole equality", _result, "wanted", _wanted, "PASS", _pass,
        "isolated local code; production predicate not invoked"]] call _emit;
} forEach [
    ["KNOWN_GOOD", _controlSource, [true]],
    ["CHANGED", "params ['_value']; _value + 41002", [false]],
    ["FOREIGN", "params ['_value']; reverse _value; _value", [false]]
];
// No positive is manufactured: the untouched live callback must qualify first.
// Negative replacements are synchronous and restored only while still fixture-owned.
if (_mode == "NEGATIVE") then {
    isNil {
        private _name = "A3A_fnc_SUP_FPVAvailable";
        private _path = "\fpv_ai_drones\functions\fpv\au_support\fn_SUP_FPVAvailable.sqf";
        private _cfg = configFile >> "CfgFunctions" >> "A3A" >> "A3UEFPVSupport" >> "SUP_FPVAvailable";
        private _args = [_name, _path, _cfg, ["fpv_ai_drones"]];
        private _original = missionNamespace getVariable [_name, 0];
        private _baseline = _args call A3UE_fnc_fpv_hookBindingMatches;
        ["PRODUCTION", "UNTOUCHED_BASELINE", [_baseline, "required true before negative replacements"]] call _emit;
        if (!_baseline || {!(_original isEqualType {})} || {isFinal _original}) exitWith {
            ["PRODUCTION_BLOCKED", _name, "baseline false or immutable; no mutation performed"] call _emit;
        };
        private _foreign = [_name, _path, _cfg, ["packet_a_foreign"]] call A3UE_fnc_fpv_hookBindingMatches;
        private _wrongDecl = [_name, _path, configFile >> "CfgFunctions" >> "A3UE" >> "FPV" >> "fpv_rivalsUavFlyby", ["fpv_ai_drones"]] call A3UE_fnc_fpv_hookBindingMatches;
        ["PRODUCTION", "FOREIGN_PROVIDER_AND_DECLARATION", [!_foreign, !_wrongDecl, "required both true (refused)"]] call _emit;
        private _text = str _original;
        private _changed = compile ((_text select [1, count _text - 2]) + "; private _packetAChanged = true;");
        private _unknown = compileScript [_path, false, "private _packetAUnknownHeader = true;"];
        private _restoreFailed = false;
        {
            if (_restoreFailed) exitWith {};
            _x params ["_label", "_replacement"];
            // Warm success against original first, then require its invalidation.
            private _warm = _args call A3UE_fnc_fpv_hookBindingMatches;
            missionNamespace setVariable [_name, _replacement];
            private _rejected = !(_args call A3UE_fnc_fpv_hookBindingMatches);
            private _cleared = isNil {localNamespace getVariable ("A3UE_FPV_hookChecked_" + _name)};
            private _owned = (missionNamespace getVariable [_name, -1]) isEqualTo _replacement;
            if (_owned) then {missionNamespace setVariable [_name, _original];};
            _restoreFailed = !_owned;
            ["PRODUCTION", _label, ["warm/rejected/cacheCleared/restoredOwned", _warm, _rejected, _cleared, _owned]] call _emit;
        } forEach [["CHANGED_BODY_SAME_METADATA", _changed], ["UNKNOWN_HEADER_FULL_SOURCE", _unknown], ["UNAVAILABLE_BINDING", 0]];
        ["PRODUCTION", "RESTORED_ORIGINAL", [_args call A3UE_fnc_fpv_hookBindingMatches,
            (missionNamespace getVariable [_name, 0]) isEqualTo _original, "restart disposable mission before route tests"]] call _emit;
    };
};
// Exercise real reporter emission once; retain complete payloads in the RPT.
private _report = [true] call A3UE_fnc_fpv_reportAUAdapter;
private _rows = _report getOrDefault ["rows", []];
["REPORT", "six adapters", [count _rows, _rows apply {[_x get "function", _x get "state", _x get "bodyMatches"]},
    "one SUMMARY and six indexed ROW payloads must be reviewed in native RPT"]] call _emit;
["END", "host", ["functions", count _specs, "compared", _compared, "unavailable", count _specs - _compared,
    "controlsPassed", _controlsPassed, "recordsIncludingEnd", _records + 1, "elapsedSeconds", diag_tickTime - _started,
    "mode", _mode, "full-body results require engine review; no callback or installer invoked"]] call _emit;
copyToClipboard format ["Packet A END: %1/12 compared; controls=%2; run=%3; retain full RPT", _compared, _controlsPassed, _run];
