// QA extraction: docs\experiments\crocus-at-policy-20261026\commands\08-target-cleanup.sqf; scheduled local caller.

if (!isServer || {isRemoteExecuted} || {!canSuspend}) exitWith {};
private _run = (missionNamespace getVariable ["A3UE_FPV_QA_runs", createHashMap])
    getOrDefault [missionNamespace getVariable ["A3UE_POLICY_run", ""], createHashMap];
if (((missionNamespace getVariable ["A3UE_POLICY_run", ""]) != "" && {count _run == 0})
    || {(count _run > 0 && {!(_run getOrDefault ["cleaned", false])})}
    || {(missionNamespace getVariable ["A3UE_FPV_QA_captureState", createHashMap]) getOrDefault ["active", false]}) exitWith {
    diag_log "POLICY target cleanup blocked: retire the drone run first";
};
private _vehicle = missionNamespace getVariable ["A3UE_POLICY_target", objNull];
private _crew = missionNamespace getVariable ["A3UE_POLICY_crew", []];
private _groups = missionNamespace getVariable ["A3UE_POLICY_groups", []];
private _expectedCrew = missionNamespace getVariable ["A3UE_POLICY_crewIds", []];
if (count _crew != count _expectedCrew || {count _crew > 2} || {count _groups > 2}
    || {!isNull _vehicle && {netId _vehicle != (missionNamespace getVariable ["A3UE_POLICY_targetId", ""])
        || {typeOf _vehicle != "I_MRAP_03_F"} || {!local _vehicle}}}) exitWith {
    diag_log "POLICY target cleanup blocked: saved identity/locality mismatch";
};
if ((_crew findIf {!isNull _x && {!(netId _x in _expectedCrew)
    || {isPlayer _x} || {!local _x}
    || {!isNull (objectParent _x) && {objectParent _x != _vehicle}}}}) >= 0
    || {!isNull _vehicle && {(crew _vehicle) findIf {!(_x in _crew)} >= 0}}
    || {(_groups findIf {!isNull _x && {!local _x
        || {(units _x) findIf {!(_x in _crew)} >= 0}}}) >= 0}) exitWith {
    diag_log "POLICY target cleanup blocked: changed crew/group ownership; retain state";
};
diag_log ["CROCUS_RCA_CADENCE_TARGET_RETIRE", "BEFORE", netId _vehicle,
    alive _vehicle, damage _vehicle,
    _crew apply {[netId _x, alive _x, damage _x]}];
{if (!isNull _x) then {deleteVehicle _x;};} forEach _crew;
if (!isNull _vehicle) then {deleteVehicle _vehicle;};
private _gone = {
    isNull _vehicle && {(_crew findIf {!isNull _x}) < 0}
        && {(_groups findIf {!isNull _x}) < 0}
};
private _until = diag_tickTime + 3;
waitUntil {
    sleep 0.05;
    {
        if (!isNull _x && {local _x} && {units _x isEqualTo []}) then {
            deleteGroup _x;
        };
    } forEach _groups;
    call _gone || {diag_tickTime >= _until}
};
private _complete = call _gone;
if (_complete) then {
    {missionNamespace setVariable [_x, nil];} forEach [
        "A3UE_POLICY_target", "A3UE_POLICY_crew", "A3UE_POLICY_groups"
    ];
};
private _result = [
    ["vehicleGone", isNull _vehicle],
    ["crewGone", _crew apply {isNull _x}],
    ["groupsGone", _groups apply {isNull _x}],
    ["referencesCleared", _complete]
];
{diag_log ["CROCUS_RCA_CADENCE_TARGET_RETIRE", _forEachIndex, _x];} forEach _result;
diag_log str _result;
