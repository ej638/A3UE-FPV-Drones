// Read-only exact-roster observer. Arm while every controller is ready/live.
// [label, drones, retainedCrew, retainedGroups, supportName] via QA dispatcher.
// No pruning, cleanup, resource changes, clipboard, world scans or frame hooks.
params [
    ["_label", "", [""]], ["_drones", [], [[]]],
    ["_crew", [], [[]]], ["_groups", [], [[]]], ["_support", "", [""]]
];
if (!isServer || {isRemoteExecuted} || {!canSuspend} || {_label == ""}
    || {count _drones < 1} || {count _drones > 4} || {count _crew > 16} || {count _groups > 16}
    || {_drones findIf {isNull _x || {!alive _x} || {!local _x}
        || {!([_x] call A3UE_fnc_fpv_hasCurrentLifecycle)}
        || {scriptDone (_x getVariable ["A3UE_FPV_controllerHandle", scriptNull])}} >= 0}) exitWith {
    diag_log ["PACKET_B_RETENTION", _label, "BLOCKED_NOT_LIVE_READY_HOST_ROSTER"];
};
private _ids = _drones apply {netId _x};
private _lives = _drones apply {_x getVariable ["A3UE_FPV_lifecycleId", -1]};
// Keep exact script handles before object deletion erases object variables.
private _handles = _drones apply {
    private _uav = _x;
    ["A3UE_FPV_controllerHandle", "A3UE_FPV_fiberTrailHandle", "A3UE_FPV_claimRetryHandle"]
        apply {_uav getVariable [_x, scriptNull]}
};
private _entry = (missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap]) getOrDefault [_support, createHashMap];
private _identity = _entry getOrDefault ["preparationId", -1];
private _marker = _entry getOrDefault ["searchMarker", ""];
private _sample = {
    params ["_phase"];
    private _records = missionNamespace getVariable ["A3UE_FPV_lifecycles", createHashMap];
    private _current = (missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap]) getOrDefault [_support, createHashMap];
    diag_log ["PACKET_B_RETENTION", _label, _phase, serverTime, "ROSTER", _ids,
        _drones apply {isNull _x}, _crew apply {isNull _x}, _groups apply {isNull _x},
        _handles apply {_x apply {scriptDone _x}}];
    {
        private _r = _records getOrDefault [str _x, createHashMap];
        diag_log ["PACKET_B_RETENTION", _label, _phase, "LIFETIME", _x,
            ["phase", "outcome", "closedAt", "lateUntil"] apply {_r getOrDefault [_x, "ABSENT"]},
            isNull (_r getOrDefault ["object", objNull])];
    } forEach _lives;
    diag_log ["PACKET_B_RETENTION", _label, _phase, "SUPPORT", _support,
        _current getOrDefault ["preparationId", -1], _identity,
        _current getOrDefault ["status", "ABSENT"], _current getOrDefault ["finishedAt", -1],
        markerShape _marker, _marker in (missionNamespace getVariable ["A3UE_FPV_supportTransientMarkers", []]),
        count _records, count (missionNamespace getVariable ["A3UE_FPV_lifecycleIndex", createHashMap]),
        count (missionNamespace getVariable ["A3UE_FPV_deadFibers", []])];
};
["ARMED"] call _sample;
private _closeDeadline = serverTime + 420;
private _closedAt = -1;
waitUntil {
    sleep 1;
    private _records = missionNamespace getVariable ["A3UE_FPV_lifecycles", createHashMap];
    private _closed = _lives apply {(_records getOrDefault [str _x, createHashMap]) getOrDefault ["closedAt", -1]};
    if (_closed findIf {_x < 0} < 0) then {_closedAt = selectMax _closed;};
    _closedAt >= 0 || {serverTime >= _closeDeadline}
};
if (_closedAt < 0) exitWith {["TIMEOUT_NO_COMPLETE_CLOSURE"] call _sample;};
private _finishedAt = _entry getOrDefault ["finishedAt", -1];
if (_support != "" && {_finishedAt < 0}) exitWith {["BLOCKED_SUPPORT_NOT_SETTLED"] call _sample;};
sleep ((_closedAt + 10 - serverTime) max 0);
["CLOSED_PLUS_10"] call _sample;
private _until = (_closedAt max _finishedAt) + 610;
while {serverTime < _until} do {sleep ((_until - serverTime) min 30);};
["RETENTION_PLUS_610"] call _sample;
diag_log ["PACKET_B_RETENTION", _label, "END", _lives,
    "Closed lifecycle/archive entries prune on next legitimate event; idle presence alone is not a leak. No manual pruning performed."];
