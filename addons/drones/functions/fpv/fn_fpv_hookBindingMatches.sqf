// Server-local admission; expected material is never evidence of effective identity.
params ["_functionName", "_path", ["_declaration", configNull], ["_sources", []]];
if (!isServer || {isRemoteExecuted}) exitWith {false};
if (!(_functionName isEqualType "") || {!(_path isEqualType "")}) exitWith {false};
private _effective = missionNamespace getVariable [_functionName, 0];
private _checkedKey = "A3UE_FPV_hookChecked_" + _functionName;
private _checked = localNamespace getVariable [_checkedKey, []];
// Retire old success before any partial/refused work. Revalidate provenance every time.
localNamespace setVariable [_checkedKey, nil];
if !(_effective isEqualType {}) exitWith {false};
private _prepared = [_functionName, _path, _declaration, _sources] call A3UE_fnc_fpv_bindingRepresentations;
_prepared params ["_reason", "_expected", "_context"];
if (_reason != "REVIEWED") exitWith {false};
private _actual = str _effective;
if (count _actual > 262144) exitWith {false};
private _matches = false;
if (!isFilePatchingEnabled && {count _checked == 2} && {(_checked # 0) isEqualTo _actual}
    && {(_checked # 1) isEqualTo _context}) then {
    _matches = true;
} else {
    _matches = (_expected findIf {_x isEqualTo _actual}) >= 0;
};
if (_matches && {!isFilePatchingEnabled}) then {
    localNamespace setVariable [_checkedKey, [_actual, _context]];
};
_matches
