// Server-local STRUCTURAL fixture, not natural scheduling/HC/flight evidence.
// Copy to a disposable mission's scripts/; Server Exec:
// [] spawn {[] execVM "scripts\au01_site_lifecycle.sqf"};
if (!isServer || {isRemoteExecuted}) exitWith {false};
if (isNil "spawner" || {isNil "sidesX"} || {isNil "A3UE_FPV_siteLifecycle"}) exitWith {
	diag_log "[A3UE FPV TEST AU-01] BLOCKED: campaign/site hooks not ready";
	false
};

// No scheduled AU worker or queue can interleave with this small fixture.
isNil {
	private _markerX = (missionNamespace getVariable ["outposts", []]) select {
		markerShape _x != "" && {spawner getVariable [_x, -1] == 2}
			&& {(sidesX getVariable [_x, sideUnknown]) in [Occupants, Invaders]}
	};
	if (_markerX isEqualTo []) exitWith {
		diag_log "[A3UE FPV TEST AU-01] BLOCKED: need an inactive enemy outpost";
	};
	_markerX = _markerX # 0;
	private _oldSpawn = spawner getVariable _markerX;
	private _names = ["A3UE_FPV_originalScheduler", "A3UE_FPV_siteEpoch", "A3UE_FPV_siteLifecycle",
		"A3UE_FPV_siteTracked", "A3UE_FPV_siteQueue", "A3UE_FPV_registry", "A3UE_FPV_siteIngressRejected", "A3UE_FPV_siteLastRejection"];
	private _saved = _names apply {missionNamespace getVariable [_x, nil]};
	private _oldManager = A3UE_fnc_fpv_managerEvaluateSite;
	private _calls = [];
	private _dispatches = [];
	private _failures = 0;
	private _assert = {
		params ["_case", "_ok"];
		if (!_ok) then {_failures = _failures + 1;};
		diag_log format ["[A3UE FPV TEST AU-01] STRUCTURAL case=%1 pass=%2", _case, _ok];
	};
	private _fixtureScheduler = {_dispatches pushBack +_this; 7};
	A3UE_FPV_originalScheduler = _fixtureScheduler;
	A3UE_FPV_siteEpoch = "QA_AU01";
	A3UE_FPV_siteLifecycle = createHashMap;
	A3UE_FPV_siteTracked = createHashMap;
	A3UE_FPV_siteQueue = createHashMap;
	A3UE_FPV_registry = createHashMap;
	private _fixtureManager = {
		_calls pushBack +_this;
		if (_this # 2) then {
			A3UE_FPV_registry set [_this # 0, createHashMapFromArray [["status", "fixture"], ["drones", []]]];
		} else {A3UE_FPV_registry deleteAt (_this # 0);};
		true
	};
	A3UE_fnc_fpv_managerEvaluateSite = _fixtureManager;
	if (!(A3UE_fnc_fpv_managerEvaluateSite isEqualTo _fixtureManager)
		|| {!(A3UE_FPV_originalScheduler isEqualTo _fixtureScheduler)}) exitWith {
		A3UE_fnc_fpv_managerEvaluateSite = _oldManager;
		{missionNamespace setVariable [_x, _saved # _forEachIndex];} forEach _names;
		diag_log "[A3UE FPV TEST AU-01] BLOCKED: immutable fixture functions";
	};
	private _schedule = {
		spawner setVariable [_markerX, 0];
		[[_markerX], "A3A_fnc_createAIOutposts"] call A3UE_fnc_fpv_scheduleSite;
		(A3UE_FPV_siteLifecycle get _markerX) get "generation"
	};
	private _intent = {
		params ["_generation", "_active"];
		[_markerX, "Outpost", _active, A3UE_FPV_siteEpoch, _generation, 2] call A3UE_fnc_fpv_receiveSiteIntent
	};
	private _g1 = call _schedule;
	call A3UE_fnc_fpv_processSiteQueue;
	["pending does not spawn; wrapped dispatch", _calls isEqualTo [] && {((_dispatches # 0) # 1) == "A3UE_fnc_fpv_runSiteWorker"}
		&& {(((_dispatches # 0) # 0) # 0) isEqualTo [_markerX]}] call _assert;
	private _A3UE_FPV_siteWorkerContext = +(((_dispatches # 0) # 0) # 2);
	private _first = [_markerX, "Outpost", true] call A3UE_fnc_fpv_onLocationSpawned;
	private _duplicate = [_g1, true] call _intent;
	call A3UE_fnc_fpv_processSiteQueue;
	["duplicate activation rolls once", _first && {!_duplicate} && {count _calls == 1}] call _assert;
	private _g2 = call _schedule;
	spawner setVariable [_markerX, 2];
	private _earlyClose = [_g2, false] call _intent;
	spawner setVariable [_markerX, 0];
	private _lateStart = [_g2, true] call _intent;
	call A3UE_fnc_fpv_processSiteQueue;
	["close before activation stays closed; old stock retires", _earlyClose && {!_lateStart} && {count _calls == 2}
		&& {A3UE_FPV_registry getOrDefault [_markerX, createHashMap] isEqualTo createHashMap}] call _assert;
	private _g3 = call _schedule;
	[_g3, true] call _intent;
	call A3UE_fnc_fpv_processSiteQueue;
	private _oldClose = [_markerX, "Outpost", false] call A3UE_fnc_fpv_onLocationSpawned;
	private _oldStart = [_g2, true] call _intent;
	private _wrongEpoch = [_markerX, "Outpost", false, "OLD_EPOCH", _g3, 2] call A3UE_fnc_fpv_receiveSiteIntent;
	private _wrongType = [_markerX, "Airport", true, A3UE_FPV_siteEpoch, _g3, 2] call A3UE_fnc_fpv_receiveSiteIntent;
	private _fabricated = ["QA_FABRICATED", "Outpost", true, A3UE_FPV_siteEpoch, _g3, 2] call A3UE_fnc_fpv_receiveSiteIntent;
	private _codePayload = [_markerX, "Outpost", {}, A3UE_FPV_siteEpoch, _g3, 2] call A3UE_fnc_fpv_receiveSiteIntent;
	call A3UE_fnc_fpv_processSiteQueue;
	["stale/fabricated/malformed intents preserve new stock", !(_oldClose || {_oldStart} || {_wrongEpoch} || {_wrongType} || {_fabricated} || {_codePayload})
		&& {count _calls == 3} && {((A3UE_FPV_registry get _markerX) get "siteGeneration") == _g3}] call _assert;
	private _g4 = call _schedule;
	[_g4, true] call _intent;
	call A3UE_fnc_fpv_processSiteQueue;
	["new generation cleans old before spawning", count _calls == 5 && {!((_calls # 3) # 2)} && {(_calls # 4) # 2}] call _assert;
	spawner setVariable [_markerX, 2];
	call A3UE_fnc_fpv_processSiteQueue;
	call A3UE_fnc_fpv_processSiteQueue;
	["missing deactivation reconciles once", count _calls == 6 && {!( _markerX in A3UE_FPV_siteTracked)}] call _assert;
	private _g5 = call _schedule;
	[_g5, true] call _intent;
	call A3UE_fnc_fpv_processSiteQueue;
	// Manufacture only the disconnection state, not an authenticated HC report.
	(A3UE_FPV_siteLifecycle get _markerX) set ["producer", 100000000];
	call A3UE_fnc_fpv_processSiteQueue;
	["disconnected producer retires registry", count _calls == 8 && {!( _markerX in A3UE_FPV_registry)}
		&& {((A3UE_FPV_siteLifecycle get _markerX) get "closeReason") == "hcDisconnected"}] call _assert;
	private _plain = [["QA_PLAIN", 42], "QA_NON_SITE"];
	private _result = _plain call A3UE_fnc_fpv_scheduleSite;
	["unrelated scheduler arguments/return preserved", _result == 7 && {(_dispatches # ((count _dispatches) - 1)) isEqualTo _plain}] call _assert;
	spawner setVariable [_markerX, _oldSpawn];
	A3UE_fnc_fpv_managerEvaluateSite = _oldManager;
	{missionNamespace setVariable [_x, _saved # _forEachIndex];} forEach _names;
	diag_log format ["[A3UE FPV TEST AU-01] STRUCTURAL complete=8 failures=%1; no HC/natural/flight evidence", _failures];
};
true
