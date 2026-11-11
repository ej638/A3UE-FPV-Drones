// ["list"] call ...; ["cleanup", runId] execVM ... (server local scheduled).
params [["_action", "list"], ["_id", missionNamespace getVariable ["A3UE_FPV_QA_lastRun", ""]]];
if (isRemoteExecuted || {!isServer}) exitWith {diag_log "A3UE_FPV_QA control BLOCKED server Local Exec required";};
private _run = (missionNamespace getVariable ["A3UE_FPV_QA_runs", createHashMap]) getOrDefault [_id, createHashMap];
if (count _run == 0) exitWith {if (hasInterface) then {copyToClipboard "No retained QA run";}; diag_log ["A3UE_FPV_QA_CONTROL_BLOCKED", "No retained QA run"];};
if (_action == "list") exitWith {
	private _rows = (_run get "drones") apply {[netId _x, typeOf _x, alive _x, local _x, owner _x,
		_x getVariable ["A3UE_FPV_mode", ""], _x getVariable ["A3UE_FPV_controllerGeneration", -1],
		_x getVariable ["A3UE_FPV_lifecycleId", -1], crew _x,
		_x getVariable ["A3UE_FPV_controllerRunning", false], scriptDone (_x getVariable ["A3UE_FPV_controllerHandle", scriptNull]),
		_x getVariable ["A3UE_FPV_startedGeneration", -1], [_x] call A3UE_fnc_fpv_hasCurrentLifecycle,
		_x getVariable ["A3UE_FPV_controllerIdentity", []],
		_x getVariable ["A3UE_FPV_claimRetryGeneration", -2], scriptDone (_x getVariable ["A3UE_FPV_claimRetryHandle", scriptNull]),
		_x getVariable ["A3UE_FPV_lifecycleClaimFailure", ""],
		[_x] call A3UE_fnc_fpv_hasCurrentLifecycle
			&& {(_x getVariable ["A3UE_FPV_startedGeneration", -1]) == (_x getVariable ["A3UE_FPV_controllerGeneration", -2])}
			&& {_x getVariable ["A3UE_FPV_controllerRunning", false]}
			&& {!(scriptDone (_x getVariable ["A3UE_FPV_controllerHandle", scriptNull]))}]};
	diag_log ["A3UE_FPV_QA_LIST", _id, _run get "ids", _rows]; if (hasInterface) then {copyToClipboard str _rows;}; _rows
};
if (_action != "cleanup" || {!canSuspend}) exitWith {if (hasInterface) then {copyToClipboard "Use cleanup with scheduled execVM";}; diag_log ["A3UE_FPV_QA_CONTROL_BLOCKED", "Use cleanup with scheduled execVM"];};
// Cancel only this run's reversible diagnostic workers before retirement/export.
private _testDrones = _run get "drones";
if ((missionNamespace getVariable ["A3UE_FPV_QA_retryId", ""]) in (_run get "ids")) then {A3UE_FPV_QA_retryCancel = true;};
{if (!isNull _x && {_x getVariable ["A3UE_FPV_QA_linkInjection", false]}) then {_x setVariable ["A3UE_FPV_QA_linkCancel", true];};} forEach _testDrones;
private _injectionsRestored = {
	!((missionNamespace getVariable ["A3UE_FPV_QA_retryId", ""]) in (_run get "ids"))
		&& {(_testDrones findIf {!isNull _x && {_x getVariable ["A3UE_FPV_QA_linkInjection", false]}}) < 0}
};
private _restoreUntil = diag_tickTime + 2;
waitUntil {sleep 0.05; call _injectionsRestored || {diag_tickTime >= _restoreUntil}};
if !(call _injectionsRestored) exitWith {if (hasInterface) then {copyToClipboard "Cleanup pending: diagnostic worker restoration; retry before next case.";}; diag_log ["A3UE_FPV_QA_CLEANUP_PENDING", _id, "INJECTION_RESTORE"];};
private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState", createHashMap];
if (count _cap > 0 && {(_cap get "id") == _id} && {_cap get "active"}) then {
	["stop", "", [], 60, "cleanup"] call compileScript ["scripts\ua_dive\capture.sqf"];
};
// Production retirement closes only this run's lifetime and handles owner deletion/JIP.
{if (!isNull _x) then {[_x] call A3UE_fnc_fpv_cleanupDrone;};} forEach (_run get "drones");
private _until = diag_tickTime + 20;
waitUntil {sleep 0.1; ((_run get "drones") findIf {!isNull _x}) < 0 || {diag_tickTime >= _until}};
private _left = (_run get "drones") select {!isNull _x};
if (_left isNotEqualTo []) exitWith {if (hasInterface) then {copyToClipboard "Cleanup pending; release control, retry and retain logs. Do not launch next case.";}; diag_log ["A3UE_FPV_QA_CLEANUP_PENDING", _id, _left apply {netId _x}];};
// Only exact retained test crew/groups; don't touch global lifecycle/manager maps.
{if (!isNull _x && {local _x}) then {deleteVehicle _x;};} forEach (_run get "crew");
{if (!isNull _x && {local _x} && {units _x isEqualTo []}) then {deleteGroup _x;};} forEach (_run get "groups");
private _crewLeft = (_run get "crew") select {!isNull _x};
private _groupsLeft = (_run get "groups") select {!isNull _x};
if (_crewLeft isNotEqualTo [] || {_groupsLeft isNotEqualTo []}) exitWith {
	if (hasInterface) then {copyToClipboard "Cleanup pending: retained crew/groups still exist. Retain owner logs and retry before next case.";};
	diag_log ["A3UE_FPV_QA_CLEANUP_PENDING", _id, "CREW_OR_GROUPS", _crewLeft apply {[netId _x, owner _x, local _x]}, _groupsLeft];
};
deleteMarkerLocal (_run get "marker");
_run set ["cleaned", true];
diag_log ["A3UE_FPV_QA_CLEANUP", _id, (_run get "drones") apply {isNull _x}, (_run get "crew") apply {isNull _x}, (_run get "groups") apply {isNull _x}];
if (hasInterface) then {copyToClipboard "QA run retired. Wait for EXPORT_DONE before restarting capture; retain original IDs for evidence.";};
