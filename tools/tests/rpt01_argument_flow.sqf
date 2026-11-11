// Actual packaged functions; no replacement functions, map resets or startup rescue.
// Run AFTER preserving normal startup/site evidence, on the server with Local Exec.
// [] call compileScript ["scripts\rpt01_argument_flow.sqf"];
if (!isServer || {isRemoteExecuted} || {!(isClass (missionConfigFile >> "A3A"))}) exitWith {
    diag_log ["A3UE FPV RPT01 ARG", "BLOCKED", "trusted server-local AU context required"];
};
if (!(missionNamespace getVariable ["A3UE_FPV_registrationComplete", false])
    || {!(missionNamespace getVariable ["A3UE_FPV_siteReady", false])}
    || {isNil "A3UE_FPV_siteEpoch"} || {isNil "A3UE_FPV_auAdapterReport"}
    || {A3A_fnc_scheduler isNotEqualTo A3UE_fnc_fpv_scheduleSite}) exitWith {
    diag_log ["A3UE FPV RPT01 ARG", "BLOCKED", "automatic startup incomplete; preserve evidence, restart, do not retry registrar"];
};
private _failures = [];
// BEGIN/END delimit the actual helper's diagnostic. Check the log count in the RPT.
{
    _x params ["_label", "_parentArgs", "_invoke", "_expectedLogs"];
    diag_log ["A3UE FPV RPT01 ARG", "BEGIN", _label, "expectedAdapterLogs", _expectedLogs];
    private _report = _parentArgs call _invoke;
    private _returned = !isNil "_report" && {_report isEqualType createHashMap}
        && {count (_report getOrDefault ["rows", []]) == 6};
    if (!_returned) then {_failures pushBack _label;};
    diag_log ["A3UE FPV RPT01 ARG", "END", _label, "reportReturned", _returned];
} forEach [
    ["EXPLICIT_TRUE", ["postInit", false], {[true] call A3UE_fnc_fpv_reportAUAdapter}, 1],
    ["EXPLICIT_FALSE", ["postInit", true], {[false] call A3UE_fnc_fpv_reportAUAdapter}, 0],
    ["DEFAULT_FROM_NONEMPTY_PARENT", [false, "parent"], {[] call A3UE_fnc_fpv_reportAUAdapter}, 1],
    ["INHERITED_POSTINIT", ["postInit", false], {call A3UE_fnc_fpv_reportAUAdapter}, 1],
    ["INHERITED_POSTINIT_JIP", ["postInit", true], {call A3UE_fnc_fpv_reportAUAdapter}, 1],
    ["MALFORMED_LOG", [123], {call A3UE_fnc_fpv_reportAUAdapter}, 1],
    ["SCALAR_CONTEXT", "postInit", {call A3UE_fnc_fpv_reportAUAdapter}, 1]
];

private _epoch = A3UE_FPV_siteEpoch;
private _report = A3UE_FPV_auAdapterReport;
private _maps = [A3UE_FPV_siteLifecycle, A3UE_FPV_siteTracked, A3UE_FPV_siteQueue, A3UE_FPV_registry];
private _events = missionNamespace getVariable ["A3A_Events_EventRegistry", createHashMap];
// Unscheduled comparison prevents normal queue work changing the stock snapshot.
isNil {
    private _before = str [_maps, _events];
    ["postInit", false] call A3UE_fnc_addFPVEventListeners;
    [] call A3UE_fnc_addFPVEventListeners;
    private _same = _epoch isEqualTo A3UE_FPV_siteEpoch
        && {_report isEqualRef A3UE_FPV_auAdapterReport}
        && {_before isEqualTo str [[A3UE_FPV_siteLifecycle, A3UE_FPV_siteTracked, A3UE_FPV_siteQueue, A3UE_FPV_registry], _events]}
        && {_maps # 0 isEqualRef A3UE_FPV_siteLifecycle}
        && {_maps # 1 isEqualRef A3UE_FPV_siteTracked}
        && {_maps # 2 isEqualRef A3UE_FPV_siteQueue}
        && {_maps # 3 isEqualRef A3UE_FPV_registry}
        && {_events isEqualRef (missionNamespace getVariable ["A3A_Events_EventRegistry", createHashMap])}
        && {A3UE_FPV_registrationComplete} && {A3UE_FPV_siteReady}
        && {A3A_fnc_scheduler isEqualTo A3UE_fnc_fpv_scheduleSite};
    if (!_same) then {_failures pushBack "REPEAT_MUTATED_REGISTRATION_OR_STOCK";};
    diag_log ["A3UE FPV RPT01 ARG", "REPEAT_UNCHANGED", _same, "epoch", A3UE_FPV_siteEpoch];
};
diag_log ["A3UE FPV RPT01 ARG", "RETURN_AND_REPEAT_CHECKS", _failures,
    "logging and duplicate-worker assertions require RPT/snapshot review; fresh automatic startup requires separate launch evidence"];
_failures
