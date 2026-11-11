// F5-1b site-queue diagnostics (read-only). One compact snapshot of the server's site-queue
// worker: heartbeat, last pass result, stage breadcrumbs, the worker's script entry, queue and
// tracked markers and the worker's preflight inputs. Used by the site monitor's RPT lines and the
// engine card's readback. Server only; never an RPC entry point; changes no state.
// [] -> ["SITEQ", beatAgeS, passes, lastResult, resultAgeS, stage, spawnStage, lastTxn,
//        workerDone, workerScripts, queue, tracked, preflight, siteReady, time]
if (!isServer || {isRemoteExecuted && {remoteExecutedOwner != 2}}) exitWith {[]};
private _now = diag_tickTime;
private _age = {
	params [["_tick", -1]];
	if !(_tick isEqualType 0) exitWith {-1};
	if (_tick < 0) exitWith {-1};
	(round ((_now - _tick) * 10)) / 10
};
// Stage rows are [label, marker, tick, extra...]: report the tick as an age.
private _stageRow = {
	params [["_row", []]];
	if !(_row isEqualType []) exitWith {[]};
	if (count _row < 3) exitWith {+_row};
	private _copy = +_row;
	_copy set [2, [_row # 2] call _age];
	_copy
};
private _beat = missionNamespace getVariable ["A3UE_FPV_siteBeat", []];
if !(_beat isEqualType []) then {_beat = [];};
private _result = missionNamespace getVariable ["A3UE_FPV_siteLastResult", []];
if !(_result isEqualType []) then {_result = [];};
private _worker = missionNamespace getVariable ["A3UE_FPV_siteWorker", scriptNull];
private _workerDone = if (_worker isEqualType scriptNull) then {
	if (isNull _worker) then {"none"} else {scriptDone _worker}
} else {"none"};
// Name, file, running and current line of the worker if the scheduler still holds it.
private _scripts = diag_activeSQFScripts select {(_x # 0) isEqualTo "A3UE_FPV_siteWorker"};
private _queue = missionNamespace getVariable ["A3UE_FPV_siteQueue", createHashMap];
private _tracked = missionNamespace getVariable ["A3UE_FPV_siteTracked", createHashMap];
private _queueKeys = if (_queue isEqualType createHashMap) then {keys _queue} else {"invalid"};
private _trackedKeys = if (_tracked isEqualType createHashMap) then {keys _tracked} else {"invalid"};
// The worker's preflight inputs, in processSiteQueue's order.
private _preflight = [
	missionNamespace getVariable ["A3UE_FPV_registrationComplete", false],
	missionNamespace getVariable ["serverInitDone", false],
	!isNil "spawner" && {!isNull spawner},
	!isNil "sidesX" && {!isNull sidesX},
	!isNil "Occupants" && {Occupants in [east, west, independent]},
	!isNil "Invaders" && {Invaders in [east, west, independent]},
	!isNil "airportsX" && {!isNil "outposts"} && {!isNil "resourcesX"}
];
[
	"SITEQ",
	[_beat param [0, -1]] call _age, _beat param [1, -1],
	_result param [0, "none"], [_result param [1, -1]] call _age,
	[missionNamespace getVariable ["A3UE_FPV_siteStage", []]] call _stageRow,
	[missionNamespace getVariable ["A3UE_FPV_spawnStage", []]] call _stageRow,
	[missionNamespace getVariable ["A3UE_FPV_siteLastTxn", []]] call _stageRow,
	_workerDone, _scripts, _queueKeys, _trackedKeys, _preflight,
	missionNamespace getVariable ["A3UE_FPV_siteReady", false],
	round time
]
