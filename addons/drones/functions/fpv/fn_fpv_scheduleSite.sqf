params [["_params", [], [[]]], ["_function", "", [""]]];

if (!isServer) exitWith {false};
// Do not let a direct RPC launder an addon-helper/support-ingress call through
// the captured scheduler into a fresh server-origin RPC. AU's real support
// route calls its ingress directly, not via scheduler; envelopes use _original.
private _functionKey = toLowerANSI _function;
private _protectedIngress = (_functionKey find "a3ue_fnc_") == 0
	|| {_functionKey in ["a3a_fnc_sup_fpv", "a3a_fnc_createsupport", "a3a_fnc_requestsupport", "a3a_fnc_callforsupport"]};
if (_protectedIngress
	&& {isRemoteExecutedJIP || {isRemoteExecuted && {remoteExecutedOwner != 2}}}) exitWith {false};
private _original = missionNamespace getVariable ["A3UE_FPV_originalScheduler", {}];
private _eventType = switch (_function) do {
	case "A3A_fnc_createAIAirplane": {"Airport"};
	case "A3A_fnc_createAIOutposts": {"Outpost"};
	case "A3A_fnc_createAIresources": {"Resource"};
	case "A3A_fnc_createAIMilbase": {"Milbase"};
	default {""};
};
// All other AU scheduler traffic uses exactly the previous provider/arguments.
if (_eventType == "") exitWith {_this call _original};
if (isRemoteExecutedJIP || {isRemoteExecuted && {remoteExecutedOwner != 2}}) exitWith {false};
private _markerX = _params param [0, ""];
if !(_markerX isEqualType "") exitWith {false};
private _siteType = [_markerX, ""] call A3UE_fnc_fpv_resolveSiteType;
private _compatible = switch (_eventType) do {
	case "Airport": {_siteType == "Airport"};
	case "Outpost": {_siteType in ["Outpost", "Seaport"]};
	case "Resource": {_siteType in ["Resource", "Factory"]};
	case "Milbase": {_siteType == "Milbase"};
	default {false};
};
if (!_compatible || {markerShape _markerX == ""}) exitWith {_this call _original};

private _context = [];
isNil {
	private _states = missionNamespace getVariable ["A3UE_FPV_siteLifecycle", createHashMap];
	private _previous = _states getOrDefault [_markerX, createHashMap];
	private _generation = 1 + (_previous getOrDefault ["generation", 0]);
	private _epoch = missionNamespace getVariable ["A3UE_FPV_siteEpoch", ""];
	private _state = createHashMapFromArray [
		["generation", _generation], ["siteType", _siteType], ["phase", "pending"],
		["producer", -1], ["appliedGeneration", _previous getOrDefault ["appliedGeneration", 0]],
		["appliedActive", _previous getOrDefault ["appliedActive", false]]
	];
	_state set ["status", "pending"];
	// Server-issued recovery fence; simulation time gives the event fast path 5 s.
	_state set ["epoch", _epoch];
	_state set ["scheduledAt", time];
	_state set ["cleanupDrones", _previous getOrDefault ["cleanupDrones", []]];
	_state set ["siteSide", if (isNil "sidesX") then {sideUnknown} else {sidesX getVariable [_markerX, sideUnknown]}];
	_states set [_markerX, _state];
	(A3UE_FPV_siteTracked) set [_markerX, true];
	(A3UE_FPV_siteQueue) set [_markerX, true];
	_context = [_markerX, _eventType, _siteType, _epoch, _generation];
};
// AU still chooses the target using its original scheduler and unit counts.
[[_params, _function, _context], "A3UE_fnc_fpv_runSiteWorker"] call _original
