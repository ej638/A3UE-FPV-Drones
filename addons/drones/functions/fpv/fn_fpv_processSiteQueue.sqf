// Called only by the registrar's server-local worker, never as an HC RPC.
if (!isServer || {isRemoteExecuted}) exitWith {false};
// Function compilation is earlier than campaign/template/marker readiness.
if (!(missionNamespace getVariable ["A3UE_FPV_registrationComplete", false])
	|| {!(missionNamespace getVariable ["serverInitDone", false])}
	|| {isNil "spawner"} || {isNull spawner} || {isNil "sidesX"} || {isNull sidesX}
	|| {isNil "Occupants"} || {isNil "Invaders"}
	|| {!(Occupants in [east, west, independent])} || {!(Invaders in [east, west, independent])}
	|| {isNil "airportsX"} || {isNil "outposts"} || {isNil "resourcesX"}) exitWith {false};
private _states = A3UE_FPV_siteLifecycle;
private _tracked = A3UE_FPV_siteTracked;
private _queue = A3UE_FPV_siteQueue;
private _registered = missionNamespace getVariable ["hcArray", []];
if !(_registered isEqualType []) then {_registered = [];};
private _liveHCs = (entities "HeadlessClient_F") apply {owner _x};
private _hcs = _registered arrayIntersect _liveHCs;
_hcs sort true;
private _firstReady = !(missionNamespace getVariable ["A3UE_FPV_siteReady", false]);
if (_firstReady) then {
	private _markers = [];
	{_markers append (missionNamespace getVariable [_x, []]);} forEach ["airportsX", "outposts", "resourcesX", "milbases", "seaports", "factories"];
	missionNamespace setVariable ["A3UE_FPV_siteMarkers", _markers arrayIntersect _markers];
	missionNamespace setVariable ["A3UE_FPV_siteCampaignId", +(missionNamespace getVariable ["A3A_saveTarget", []])];
	missionNamespace setVariable ["A3UE_FPV_siteReady", true];
	diag_log format ["[A3UE_FPV] siteReady epoch=%1 campaign=%2 markers=%3", A3UE_FPV_siteEpoch, A3UE_FPV_siteCampaignId, count A3UE_FPV_siteMarkers];
};
private _membershipChanged = !(_hcs isEqualTo (missionNamespace getVariable ["A3UE_FPV_siteHCs", []]));
if (_firstReady || {_membershipChanged}) then {
	missionNamespace setVariable ["A3UE_FPV_siteHCs", +_hcs];
	call A3UE_fnc_fpv_reconcileSites;
};

// AU has no support-registry rebuild event. Reuse this worker at low cadence;
// no per-frame comparisons, extra waiter, RPC or automatic conflict takeover.
if (missionNamespace getVariable ["A3UE_FPV_integrationHooksEnabled", true]
	&& {_firstReady || {_membershipChanged} || {diag_tickTime >= (missionNamespace getVariable ["A3UE_FPV_hookCheckAt", 0])}}) then {
	missionNamespace setVariable ["A3UE_FPV_hookCheckAt", diag_tickTime + 30];
	missionNamespace setVariable ["A3UE_FPV_siteStage", ["hooks", "", diag_tickTime]];
	["INSTALL"] call A3UE_fnc_fpv_reportIntegrationHooks;
};

// Check only tracked sites at the existing 1 s cadence. No per-flight world scan.
// F5-1b: stage breadcrumbs (server-local, read by A3UE_fnc_fpv_siteQueueProbe).
missionNamespace setVariable ["A3UE_FPV_siteStage", ["scan", "", diag_tickTime]];
{
	private _markerX = _x;
	isNil {
		private _state = _states get _markerX;
		private _producer = _state get "producer";
		private _inactive = markerShape _markerX == "" || {!((spawner getVariable [_markerX, -1]) in [0, 1])};
		private _disconnected = _producer > 2 && {!(_producer in _hcs)};
		private _siteSide = _state getOrDefault ["siteSide", sideUnknown];
		private _captured = _siteSide != sideUnknown && {sidesX getVariable [_markerX, sideUnknown] != _siteSide};
		if (_inactive || {_disconnected} || {_captured}) then {
			_state set ["phase", "closed"];
			_state set ["captured", _captured || {_state getOrDefault ["captured", false]}];
			_state set ["closeReason", if (_captured) then {"captured"} else {["inactive", "hcDisconnected"] select _disconnected}];
			_queue set [_markerX, true];
		};
		// A lost HC event must not strand a server-scheduled site forever. AU owns
		// spawner on the server (0/1 active); never infer activation from RPC data.
		// Keep closed/applied generations as tombstones and let cleanup drain below.
		if ((_state get "phase") == "pending" && {_producer == -1}
			&& {(_state getOrDefault ["epoch", ""]) == A3UE_FPV_siteEpoch}
			&& {time >= ((_state getOrDefault ["scheduledAt", 1e10]) + 5)}
			&& {(_state get "generation") > (_state get "appliedGeneration")}
			&& {!(_state getOrDefault ["captured", false])}
			&& {_siteSide in [Occupants, Invaders]} && {_siteSide != sideUnknown}
			&& {sidesX getVariable [_markerX, sideUnknown] == _siteSide}) then {
			_state set ["phase", "active"];
			_state set ["recovered", true];
			_queue set [_markerX, true];
			diag_log format ["[A3UE_FPV] siteRecover marker=%1 generation=%2 epoch=%3 reason=serverSpawner age=%4",
				_markerX, _state get "generation", A3UE_FPV_siteEpoch, time - (_state get "scheduledAt")];
		};
		private _entry = A3UE_FPV_registry getOrDefault [_markerX, createHashMap];
		// Retire dead/surrendered/side-changed pilots rather than running human surrender.
		{
			if (!isNull _x && {!([_x] call A3UE_fnc_fpv_isSiteDroneActive)}) then {
				private _pending = _state getOrDefault ["cleanupDrones", []];
				_pending pushBackUnique _x;
				_state set ["cleanupDrones", _pending];
				[_x, true] call A3UE_fnc_fpv_cleanupDrone;
			};
		} forEach (_entry getOrDefault ["drones", []]);
		if ((_state getOrDefault ["cleanupDrones", []]) isNotEqualTo []) then {_queue set [_markerX, true];};
		if ((_state get "phase") == "active" && {(_state get "appliedGeneration") == (_state get "generation")}) then {
			_state set ["status", _entry getOrDefault ["status", "skipped"]];
			// FS-03: drones held back by the launch standoff retry on this queue.
			if ((_entry getOrDefault ["deferred", 0]) > 0 && {time >= (_entry getOrDefault ["deferRetryAt", 1e10])}) then {
				_queue set [_markerX, true];
			};
		};
	};
} forEach (keys _tracked);

// One site transaction per pass, rotating so controlled retirement cannot starve
// other sites. Safe-position creation remains the expensive existing operation.
private _queued = keys _queue;
if (_queued isEqualTo []) exitWith {true};
_queued sort true;
private _cursor = missionNamespace getVariable ["A3UE_FPV_siteQueueCursor", 0];
private _markerX = _queued # (_cursor mod (count _queued));
missionNamespace setVariable ["A3UE_FPV_siteQueueCursor", (_cursor + 1) mod (count _queued)];
missionNamespace setVariable ["A3UE_FPV_siteStage", ["pick", _markerX, diag_tickTime]];
isNil {
	_queue deleteAt _markerX;
	private _state = _states get _markerX;
	private _generation = _state get "generation";
	private _phase = _state get "phase";
	private _siteType = _state get "siteType";
	missionNamespace setVariable ["A3UE_FPV_siteLastTxn", ["txn", _markerX, diag_tickTime, _phase, _generation, _state get "appliedGeneration"]];
	missionNamespace setVariable ["A3UE_FPV_siteStage", ["txn", _markerX, diag_tickTime]];
	if (missionNamespace getVariable ["A3UE_FPV_debug", false] && {(_state getOrDefault ["status", ""]) != "cleanup-pending"}) then {
		diag_log format ["[A3UE_FPV] siteTxn marker=%1 generation=%2 phase=%3 applied=%4 queued=%5", _markerX, _generation, _phase, _state get "appliedGeneration", count _queued];
	};
	if ((_state get "appliedActive") && {_phase != "active" || {(_state get "appliedGeneration") != _generation}}) then {
		missionNamespace setVariable ["A3UE_FPV_siteStage", ["retire", _markerX, diag_tickTime]];
		[_markerX, _siteType, false] call A3UE_fnc_fpv_managerEvaluateSite;
		_state set ["appliedActive", false];
	};
	private _pending = (_state getOrDefault ["cleanupDrones", []]) select {!isNull _x};
	_state set ["cleanupDrones", _pending];
	if (_pending isNotEqualTo []) exitWith {
		missionNamespace setVariable ["A3UE_FPV_siteStage", ["cleanupPending", _markerX, diag_tickTime]];
		_state set ["status", "cleanup-pending"];
		_queue set [_markerX, true];
	};
	if (_phase == "active" && {(_state get "appliedGeneration") != _generation}) then {
		// Claim skipped/failed/unsupported stock too: no same-generation retry.
		_state set ["appliedGeneration", _generation];
		_state set ["appliedActive", true];
		missionNamespace setVariable ["A3UE_FPV_siteStage", ["evaluate", _markerX, diag_tickTime]];
		[_markerX, _siteType, true] call A3UE_fnc_fpv_managerEvaluateSite;
		private _entry = A3UE_FPV_registry getOrDefault [_markerX, createHashMap];
		_state set ["status", _entry getOrDefault ["status", "skipped"]];
		_state set ["rollReason", if (count _entry == 0) then {"unsupported"} else {_entry get "status"}];
		if (count _entry > 0) then {
			_entry set ["siteEpoch", A3UE_FPV_siteEpoch];
			_entry set ["siteGeneration", _generation];
		};
	} else {
		// Bounded standoff retry for the current generation only (FS-03).
		private _entry = A3UE_FPV_registry getOrDefault [_markerX, createHashMap];
		if (_phase == "active" && {_state get "appliedActive"} && {(_state get "appliedGeneration") == _generation}
			&& {(_entry getOrDefault ["deferred", 0]) > 0} && {time >= (_entry getOrDefault ["deferRetryAt", 1e10])}) then {
			missionNamespace setVariable ["A3UE_FPV_siteStage", ["retry", _markerX, diag_tickTime]];
			private _profile = (missionNamespace getVariable ["A3UE_FPV_doctrine", createHashMap]) getOrDefault [_entry get "siteType", createHashMap];
			[_markerX, _entry get "siteType", _profile, _entry get "siteSide", _entry get "selectedFamily",
				_entry get "deferred", _entry, "retry"] call A3UE_fnc_fpv_managerDeployStock;
			_state set ["status", _entry getOrDefault ["status", "skipped"]];
		};
	};
	if (_phase == "closed") then {
		_state set ["status", ["inactive", "captured"] select (_state getOrDefault ["captured", false])];
		// A captured site's stock never carries over, even if it never deployed (FS-04).
		if (_state getOrDefault ["captured", false]) then {["CLEAR", _markerX] call A3UE_fnc_fpv_siteStock;};
		_tracked deleteAt _markerX;
	};
	missionNamespace setVariable ["A3UE_FPV_siteStage", ["txnEnd", _markerX, diag_tickTime]];
	if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {
		diag_log format ["[A3UE_FPV] siteApply marker=%1 generation=%2 phase=%3 status=%4 remote=%5 reason=%6", _markerX, _generation, _phase, _state get "status", isRemoteExecuted, _state getOrDefault ["closeReason", "event"]];
	};
};
true
