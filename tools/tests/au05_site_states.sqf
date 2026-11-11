// Server-local STRUCTURAL regression; not natural AU/HC/control/reload evidence.
// Disposable, fully ready AU mission: [] execVM "scripts\au05_site_states.sqf";
if (!isServer || {isRemoteExecuted} || {!(missionNamespace getVariable ["A3UE_FPV_siteReady", false])}) exitWith {
	diag_log "[A3UE FPV TEST AU-05] BLOCKED: run server-local after siteReady";
	false
};
isNil {
	private _candidates = outposts select {markerShape _x != "" && {spawner getVariable [_x, -1] == 2}
		&& {sidesX getVariable [_x, sideUnknown] in [Occupants, Invaders]}};
	if (_candidates isEqualTo []) exitWith {diag_log "[A3UE FPV TEST AU-05] BLOCKED: need inactive enemy outpost";};
	private _markerX = _candidates # 0;
	private _oldSide = sidesX getVariable _markerX;
	private _oldSpawn = spawner getVariable _markerX;
	private _names = ["A3UE_FPV_originalScheduler", "A3UE_FPV_siteEpoch", "A3UE_FPV_siteLifecycle", "A3UE_FPV_siteTracked",
		"A3UE_FPV_siteQueue", "A3UE_FPV_registry", "A3UE_FPV_siteMarkers", "A3UE_FPV_siteHCs", "A3UE_FPV_siteQueueCursor",
		"serverInitDone", "A3UE_FPV_siteIngressRejected", "A3UE_FPV_siteLastRejection"];
	private _saved = _names apply {missionNamespace getVariable [_x, nil]};
	private _oldManager = A3UE_fnc_fpv_managerEvaluateSite;
	private _oldControl = A3UE_fnc_fpv_isExternallyControlled;
	private _calls = [];
	private _status = "active";
	private _controlled = true;
	private _failures = 0;
	private _cases = 0;
	private _assert = {
		params ["_name", "_ok"];
		_cases = _cases + 1;
		if (!_ok) then {_failures = _failures + 1;};
		diag_log format ["[A3UE FPV TEST AU-05] STRUCTURAL case=%1 pass=%2", _name, _ok];
	};
	private _manager = {
		_calls pushBack +_this;
		if (_this # 2) then {
			A3UE_FPV_registry set [_this # 0, createHashMapFromArray [["status", _status], ["drones", []]]];
		} else {A3UE_FPV_registry deleteAt (_this # 0);};
		true
	};
	private _control = {_controlled};
	A3UE_fnc_fpv_managerEvaluateSite = _manager;
	A3UE_fnc_fpv_isExternallyControlled = _control;
	if (!(A3UE_fnc_fpv_managerEvaluateSite isEqualTo _manager) || {!(A3UE_fnc_fpv_isExternallyControlled isEqualTo _control)}) exitWith {
		A3UE_fnc_fpv_managerEvaluateSite = _oldManager;
		A3UE_fnc_fpv_isExternallyControlled = _oldControl;
		diag_log "[A3UE FPV TEST AU-05] BLOCKED: immutable fixture functions";
	};
	A3UE_FPV_originalScheduler = {true};
	A3UE_FPV_siteEpoch = "QA_AU05";
	A3UE_FPV_siteLifecycle = createHashMap;
	A3UE_FPV_siteTracked = createHashMap;
	A3UE_FPV_siteQueue = createHashMap;
	A3UE_FPV_registry = createHashMap;
	A3UE_FPV_siteMarkers = [_markerX];
	A3UE_FPV_siteHCs = (missionNamespace getVariable ["hcArray", []]) arrayIntersect ((entities "HeadlessClient_F") apply {owner _x});
	A3UE_FPV_siteHCs sort true;
	A3UE_FPV_siteQueueCursor = 0;
	spawner setVariable [_markerX, 0];
	serverInitDone = false;
	private _notReady = call A3UE_fnc_fpv_processSiteQueue;
	["readiness blocks deployment", !_notReady && {_calls isEqualTo []}] call _assert;
	serverInitDone = true;
	call A3UE_fnc_fpv_reconcileSites;
	call A3UE_fnc_fpv_processSiteQueue;
	call A3UE_fnc_fpv_reconcileSites;
	call A3UE_fnc_fpv_processSiteQueue;
	["missed active site reconciles exactly once", count _calls == 1 && {((A3UE_FPV_siteLifecycle get _markerX) get "appliedGeneration") == 1}] call _assert;
	private _schedule = {
		[[_markerX], "A3A_fnc_createAIOutposts"] call A3UE_fnc_fpv_scheduleSite;
		(A3UE_FPV_siteLifecycle get _markerX) get "generation"
	};
	private _intent = {
		params ["_generation"];
		[_markerX, "Outpost", true, A3UE_FPV_siteEpoch, _generation, 2] call A3UE_fnc_fpv_receiveSiteIntent
	};
	{
		_status = _x;
		private _g = call _schedule;
		[_g] call _intent;
		call A3UE_fnc_fpv_processSiteQueue;
		private _before = count _calls;
		call A3UE_fnc_fpv_reconcileSites;
		[_g] call _intent;
		call A3UE_fnc_fpv_processSiteQueue;
		[format ["%1 never rerolls or refills", _status], count _calls == _before
			&& {((A3UE_FPV_siteLifecycle get _markerX) get "status") == _status}] call _assert;
	} forEach ["skipped", "spawn_failed", "depleted"];
	_status = "active";
	private _g = call _schedule;
	[_g] call _intent;
	call A3UE_fnc_fpv_processSiteQueue;
	sidesX setVariable [_markerX, teamPlayer];
	private _captured = [_markerX, teamPlayer] call A3UE_fnc_fpv_onMarkerChange;
	call A3UE_fnc_fpv_processSiteQueue;
	["capture closes stock", _captured && {!(_markerX in A3UE_FPV_registry)}
		&& {((A3UE_FPV_siteLifecycle get _markerX) get "status") == "captured"}] call _assert;
	private _before = count _calls;
	sidesX setVariable [_markerX, _oldSide];
	[_markerX, _oldSide] call A3UE_fnc_fpv_onMarkerChange;
	call A3UE_fnc_fpv_reconcileSites;
	call A3UE_fnc_fpv_processSiteQueue;
	["recapture waits for a new AU activation", count _calls == _before] call _assert;
	private _next = call _schedule;
	[_next] call _intent;
	private _oldClose = [_markerX, "Outpost", false, A3UE_FPV_siteEpoch, _g, 2] call A3UE_fnc_fpv_receiveSiteIntent;
	call A3UE_fnc_fpv_processSiteQueue;
	["old teardown cannot close recaptured generation", !_oldClose && {((A3UE_FPV_siteLifecycle get _markerX) get "appliedGeneration") == _next}] call _assert;
	private _uav = createVehicle ["B_UAV_01_F", [0, 0, 100], [], 0, "NONE"];
	_uav enableSimulationGlobal false;
	private _state = A3UE_FPV_siteLifecycle get _markerX;
	_state set ["cleanupDrones", [_uav]];
	private _waiting = call _schedule;
	[_waiting] call _intent;
	_before = count _calls;
	call A3UE_fnc_fpv_processSiteQueue;
	["retained old asset blocks replacement stock", count _calls == _before + 1
		&& {((A3UE_FPV_siteLifecycle get _markerX) get "status") == "cleanup-pending"}] call _assert;
	private _held = [_uav, true] call A3UE_fnc_fpv_deleteLocal;
	["owner deletion checks control in same slice", !_held && {!isNull _uav}] call _assert;
	_controlled = false;
	private _deleted = [_uav, true] call A3UE_fnc_fpv_deleteLocal;
	call A3UE_fnc_fpv_processSiteQueue;
	["release permits retirement then one replacement", _deleted && {isNull _uav}
		&& {((A3UE_FPV_siteLifecycle get _markerX) get "appliedGeneration") == _waiting}] call _assert;
	private _plain = createVehicle ["B_UAV_01_F", [0, 0, 100], [], 0, "NONE"];
	_plain enableSimulationGlobal false;
	private _unmanaged = [_plain] call A3UE_fnc_fpv_isSiteDroneActive;
	_plain setVariable ["A3UE_FPV_siteEpoch", "QA_AU05"];
	["unmanaged unchanged; missing virtual pilot inhibits attack", _unmanaged && {!([_plain] call A3UE_fnc_fpv_isSiteDroneActive)}] call _assert;
	createVehicleCrew _plain;
	private _pilot = driver _plain;
	private _group = group _pilot;
	private _crewSide = side _group;
	sidesX setVariable [_markerX, _crewSide];
	_plain setVariable ["A3UE_FPV_siteMarker", _markerX];
	_plain setVariable ["A3UE_FPV_siteSide", _crewSide];
	private _viable = [_plain] call A3UE_fnc_fpv_isSiteDroneActive;
	_pilot setVariable ["surrendered", true];
	private _surrenderFlag = [_plain] call A3UE_fnc_fpv_isSiteDroneActive;
	_pilot setVariable ["surrendered", false];
	_pilot setCaptive true;
	private _bareCaptiveActive = [_plain] call A3UE_fnc_fpv_isSiteDroneActive;
	_pilot setCaptive false;
	sidesX setVariable [_markerX, ([east, west, independent] select {_x != _crewSide}) # 0];
	private _ownerChanged = [_plain] call A3UE_fnc_fpv_isSiteDroneActive;
	sidesX setVariable [_markerX, _crewSide];
	_pilot setDamage 1;
	["viable/bare-captive pilot positive (V01); surrendered/dead/captured inhibit attack", !isNull _pilot && {_viable} && {!_surrenderFlag} && {_bareCaptiveActive}
		&& {!_ownerChanged} && {!([_plain] call A3UE_fnc_fpv_isSiteDroneActive)}] call _assert;
	{_plain deleteVehicleCrew _x;} forEach crew _plain;
	deleteVehicle _plain;
	deleteGroup _group;
	if (!isNull _uav) then {deleteVehicle _uav;};
	spawner setVariable [_markerX, _oldSpawn];
	sidesX setVariable [_markerX, _oldSide];
	A3UE_fnc_fpv_managerEvaluateSite = _oldManager;
	A3UE_fnc_fpv_isExternallyControlled = _oldControl;
	{missionNamespace setVariable [_x, _saved # _forEachIndex];} forEach _names;
	diag_log format ["[A3UE FPV TEST AU-05] STRUCTURAL complete=%1 failures=%2; natural AU/HC/control/reload NOT RUN", _cases, _failures];
};
true
