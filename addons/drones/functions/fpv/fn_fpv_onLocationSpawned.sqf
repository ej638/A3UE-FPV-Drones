params [["_markerX", "", [""]], ["_locationType", "", [""]], ["_isSpawning", false, [true]]];

// Latch the server-issued identity in the AU worker's private scope. Reading a
// shared marker variable here could label an old worker's teardown as a new one.
// AU raises this event for every location (towns, roadblocks, HQ). Only a drone site type
// outside a worker is worth a line; the rest are expected and log with debug only (1.0.6).
if (isNil "_A3UE_FPV_siteWorkerContext") exitWith {
	if (_locationType in ["Airport", "Outpost", "Resource", "Milbase"] || {missionNamespace getVariable ["A3UE_FPV_debug", false]}) then {
		diag_log format ["[A3UE_FPV] siteEvent skipped marker=%1 machine=%2 reason=workerContext", _markerX, clientOwner];
	};
	false
};
_A3UE_FPV_siteWorkerContext params ["_workerMarker", "_eventType", "_siteType", "_epoch", "_generation"];
if (_markerX != _workerMarker || {_locationType != _eventType}) exitWith {
	diag_log format ["[A3UE_FPV] siteEvent skipped marker=%1 machine=%2 reason=workerMismatch", _markerX, clientOwner];
	false
};

private _producer = [clientOwner, 2] select isServer;
private _intent = [_markerX, _siteType, _isSpawning, _epoch, _generation, _producer];
if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {
	diag_log format ["[A3UE_FPV] siteEvent machine=%1 intent=%2", clientOwner, _intent];
};
if (isServer) exitWith {_intent call A3UE_fnc_fpv_receiveSiteIntent};
// 1.0.6: a headless client no longer sends the intent. The engine delivers HC-origin
// remoteExecCall to the server as not remote with owner 0 (measured on 1.0.5), so the
// server could only refuse it. The server's own spawner check in processSiteQueue
// promotes HC-run sites after the grace period and closes them when they despawn.
false
