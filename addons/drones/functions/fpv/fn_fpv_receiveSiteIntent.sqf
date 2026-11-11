// No code, spawn spec, group or vehicle may be supplied at this ingress.
private _payload = if (!isNil "_this" && {_this isEqualType []}) then {_this} else {[]};
_payload params [["_markerX", ""], ["_siteType", ""], ["_isSpawning", false], ["_epoch", ""], ["_generation", -1], ["_producer", -1]];

if (!isServer) exitWith {false};
// Capture engine provenance at entry, before entering the atomic transaction.
// These are locals, never extra RPC arguments or a receiver-side authority flag.
private _remote = isRemoteExecuted;
private _jip = isRemoteExecutedJIP;
private _sender = remoteExecutedOwner;
private _trustedCaller = [false] call A3UE_fnc_fpv_isTrustedSupportCaller;
private _accepted = false;
private _rejection = "payloadOrJIP";
isNil {
	private _valid = !isNil "_this" && {_this isEqualType []} && {count _this == 6}
		&& {_markerX isEqualType ""} && {_siteType isEqualType ""} && {_isSpawning isEqualType true}
		&& {_epoch isEqualType ""} && {_generation isEqualType 0} && {_producer isEqualType 0}
		&& {count _markerX <= 128} && {count _siteType <= 32} && {count _epoch <= 128};
	if (!_valid || {_jip}) exitWith {};
	_rejection = "caller";
	if (!_trustedCaller) exitWith {};
	// Zero authenticates only the trusted HC role, never an individual HC. Match
	// the claimed producer to a live registered HC; nonzero senders must match it.
	if (_producer != 2) then {
		private _registered = missionNamespace getVariable ["hcArray", []];
		_valid = _registered isEqualType [] && {_producer in _registered}
			&& {(entities "HeadlessClient_F") findIf {owner _x == _producer && {_producer > 2}} > -1}
			&& {_remote && {_sender in [0, _producer]}};
	} else {
		_valid = !_remote || {_sender == 2};
	};
	_rejection = "producerOrEpoch";
	if (!_valid || {_epoch != (missionNamespace getVariable ["A3UE_FPV_siteEpoch", ""])}) exitWith {};
	private _states = missionNamespace getVariable ["A3UE_FPV_siteLifecycle", createHashMap];
	private _state = _states getOrDefault [_markerX, createHashMap];
	_rejection = "generationOrType";
	if (count _state == 0 || {_generation != (_state get "generation")} || {_siteType != (_state get "siteType")}) exitWith {};
	_rejection = "siteState";
	if (markerShape _markerX == "" || {isNil "spawner"} || {isNull spawner}) exitWith {};
	private _spawnState = spawner getVariable [_markerX, -1];
	if !(_spawnState in [0, 1, 2]) exitWith {};
	private _phase = _state get "phase";
	// 1.0.6: AU's own event often arrives after the server already closed this generation
	// (its spawner check runs first). A trusted, matching producer for a closed generation is
	// a late duplicate, not an attack: refused the same, but not logged as a fault.
	_rejection = "lateClosed";
	if (_phase == "closed" && {(_state get "producer") in [-1, _producer]}) exitWith {};
	_rejection = "phaseOrProducer";
	if (_phase == "closed" || {(_state get "producer") != -1 && {(_state get "producer") != _producer}}) exitWith {};
	if (_isSpawning) then {
		// A delayed authentic event may bind the producer after server recovery.
		// appliedGeneration still prevents another roll/debit/deployment.
		private _lateRecovery = _phase == "active" && {_state getOrDefault ["recovered", false]} && {(_state get "producer") == -1};
		_valid = (_phase == "pending" || {_lateRecovery}) && {_spawnState in [0, 1]} && {!isNil "sidesX"};
		private _siteSide = if (_valid) then {sidesX getVariable [_markerX, sideUnknown]} else {sideUnknown};
		private _enemySides = [missionNamespace getVariable ["Occupants", sideUnknown], missionNamespace getVariable ["Invaders", sideUnknown]];
		_valid = _valid && {_siteSide != sideUnknown} && {_siteSide in _enemySides}
			&& {!(_state getOrDefault ["captured", false])}
			&& {_siteSide == (_state getOrDefault ["siteSide", sideUnknown])};
	} else {
		_valid = _spawnState == 2;
	};
	_rejection = "sideOrSpawnState";
	if (!_valid) exitWith {};
	_state set ["phase", ["closed", "active"] select _isSpawning];
	if (_isSpawning) then {_state set ["siteSide", sidesX getVariable [_markerX, sideUnknown]];};
	_state set ["producer", _producer];
	A3UE_FPV_siteQueue set [_markerX, true];
	_accepted = true;
};
if (!_accepted && {_rejection == "lateClosed"}) exitWith {
	if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {
		diag_log format ["[A3UE_FPV] siteIntent late marker=%1 sender=%2 remote=%3 generation=%4 spawning=%5",
			_markerX, _sender, _remote, _generation, _isSpawning];
	};
	false
};
if (!_accepted) then {
	missionNamespace setVariable ["A3UE_FPV_siteIngressRejected", (1 + (missionNamespace getVariable ["A3UE_FPV_siteIngressRejected", 0])) min 1000000];
	missionNamespace setVariable ["A3UE_FPV_siteLastRejection", _rejection];
	// Bounded diagnostics: each reason once per current server site generation.
	// Unknown/malformed traffic shares a 5 s bucket; it cannot grow a keyed map.
	private _label = if (_markerX isEqualType "") then {_markerX select [0, 128]} else {"<invalid>"};
	private _state = (missionNamespace getVariable ["A3UE_FPV_siteLifecycle", createHashMap]) getOrDefault [_label, createHashMap];
	private _log = false;
	if (count _state > 0) then {
		private _reasons = _state getOrDefault ["refusalReasons", []];
		_log = !(_rejection in _reasons);
		if (_log) then {_reasons pushBack _rejection; _state set ["refusalReasons", _reasons];};
	} else {
		_log = diag_tickTime >= (missionNamespace getVariable ["A3UE_FPV_siteRejectLogAt", 0]);
		if (_log) then {missionNamespace setVariable ["A3UE_FPV_siteRejectLogAt", diag_tickTime + 5];};
	};
	if (_log) then {
		diag_log format ["[A3UE_FPV] siteIntent refused marker=%1 reason=%2 sender=%3 remote=%4 jip=%5 generation=%6 requestGeneration=%7 producer=%8",
			_label, _rejection, _sender, _remote, _jip, _state getOrDefault ["generation", -1],
			if (_generation isEqualType 0) then {_generation} else {-1}, if (_producer isEqualType 0) then {_producer} else {-1}];
	};
};
if (_accepted) then {
	diag_log format ["[A3UE_FPV] siteIntent accepted=%1 remote=%2 sender=%3", _this, _remote, _sender];
};
_accepted
