// Launch only a server-held package; callers cannot supply a replacement plan.
params ["_supportName", "_preparationId"];

if (!isServer) exitWith {-1};
private _inheritedAuthority = !isNil "_A3UE_FPV_spawnAuthorized" && {_A3UE_FPV_spawnAuthorized isEqualTo true};
if (isRemoteExecuted && {!_inheritedAuthority || {!([true] call A3UE_fnc_fpv_isTrustedSupportCaller)}}) exitWith {-1};
if (canSuspend) exitWith {
	private _result = -1;
	isNil {_result = _this call A3UE_fnc_fpv_supportLaunch;};
	_result
};

private _registry = missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap];
private _registryEntry = _registry getOrDefault [_supportName, createHashMap];
if ((_registryEntry getOrDefault ["preparationId", -1]) != _preparationId
	|| {!((_registryEntry getOrDefault ["status", ""]) in ["initializing", "preparing"])}) exitWith {-1};
if (time < (_registryEntry getOrDefault ["launchDeadline", 0])) exitWith {-1};
if (missionNamespace getVariable ["A3UE_FPV_supportShuttingDown", false]) exitWith {
	[_supportName, "failed", "MISSION_SHUTDOWN", "", true] call A3UE_fnc_fpv_supportFinalize;
	-1
};
private _preparation = _registryEntry get "preparation";
private _plan = _preparation get "plan";
private _contextMap = _preparation get "context";
private _origin = _plan get "origin";
private _side = _registryEntry get "side";
private _resPool = _registryEntry get "resourcePool";
private _targetObject = _preparation get "target";
private _targetWasObject = _preparation get "targetWasObject";
private _seedTarget = _preparation get "seedTarget";
private _seedWasObject = _preparation get "seedWasObject";
private _safeTargPos = _registryEntry get "targetPosATL";
private _searchMarker = _registryEntry get "searchMarker";
private _plannedDroneCount = _registryEntry get "plannedDroneCount";
private _reveal = _preparation get "reveal";
// Re-established from the server-held identity, never carried in the plan/RPC.
private _A3UE_FPV_spawnAuthorized = true;

private _postCrewInit = {
	params ["_uav", "_crewGroup", "_resourcePool"];

	if (!isNil "A3A_fnc_NATOinit" && {!isNull _crewGroup}) then {
		{ [_x, nil, false, _resourcePool] call A3A_fnc_NATOinit } forEach (units _crewGroup);
	};
};

private _spawnedDrones = [];
private _launchFailure = "SPAWN_FAILED";
// One unscheduled check-and-spawn transaction: no capture, marker move or
// activation-generation change can interleave with the selected package launch.
isNil {
    if ((_targetWasObject && {isNull _targetObject || {!alive _targetObject}})
        || {_seedWasObject && {isNull _seedTarget}}) exitWith {_launchFailure = "TARGET_INELIGIBLE";};
    private _reachPos = _safeTargPos;
    if (!isNull _seedTarget) then {
        private _hostileSides = [_side, _plan getOrDefault ["targetSide", sideUnknown]] call A3UE_fnc_fpv_getHostileSides;
        private _legalSeed = [_seedTarget, _hostileSides] call A3UE_fnc_fpv_filterTarget;
        if (isNull _legalSeed) exitWith {_reachPos = [];};
        _seedTarget = _legalSeed;
        _reachPos = getPosATL _seedTarget;
    };
    if (_reachPos isEqualTo []) exitWith {_launchFailure = "TARGET_INELIGIBLE";};
    if (markerShape _searchMarker == "") exitWith {_launchFailure = "SEARCH_MARKER_REMOVED";};
    if !([_side, _seedTarget, _safeTargPos, _plan] call A3UE_fnc_fpv_supportPassesSafetyRing) exitWith {_launchFailure = "UNSAFE_ENGAGEMENT";};
    private _launchContext = createHashMap;
    {_launchContext set [_x, _y];} forEach _contextMap;
    _launchContext set ["originMarker", _origin get "originMarker"];
    private _checkedOrigin = [_side, _reachPos, _plan, _launchContext] call A3UE_fnc_fpv_supportResolveOrigin;
    if !(_checkedOrigin get "ok") exitWith {_launchFailure = _checkedOrigin get "reason";};
    if ((_checkedOrigin get "originMarker") isNotEqualTo (_origin get "originMarker")
        || {(_checkedOrigin get "originPosATL") isNotEqualTo (_origin get "originPosATL")}
        || {(_checkedOrigin get "originContract") != (_origin get "originContract")}
        || {(_checkedOrigin get "originEpoch") isNotEqualTo (_origin get "originEpoch")}
        || {(_checkedOrigin get "originGeneration") != (_origin get "originGeneration")}) exitWith {_launchFailure = "ORIGIN_CHANGED";};
    _origin = _checkedOrigin;
    _registryEntry set ["reach", _origin get "reach"];
    if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {
        diag_log format ["[A3UE_FPV] supportReach name=%1 origin=%2 contract=%3 epoch=%4 generation=%5 class=%6 role=%7 reach=%8", _supportName, _origin get "originMarker", _origin get "originContract", _origin get "originEpoch", _origin get "originGeneration", _plan get "uavClass", _plan get "payloadRole", _origin get "reach"];
    };
	private _launchBase = _origin getOrDefault ["launchPosATL", []];
	private _controlPosATL = _origin getOrDefault ["controlPosATL", []];
	private _fiberAnchorPos = _origin getOrDefault ["fiberAnchorPos", []];
	private _launchDirBase = _origin getOrDefault ["launchDir", 0];
	private _initialMode = ["TRACKING", "SEARCHING"] select (isNull _seedTarget);

	for "_i" from 0 to (_plannedDroneCount - 1) do {
		private _launchPosATL = +_launchBase;
		if (_launchPosATL isEqualType [] && {count _launchPosATL >= 3}) then {
			private _spacing = _i * 4;
			_launchPosATL set [0, (_launchPosATL # 0) + (sin (_launchDirBase + 90)) * _spacing];
			_launchPosATL set [1, (_launchPosATL # 1) + (cos (_launchDirBase + 90)) * _spacing];
		};

		private _spec = createHashMapFromArray [
			["supportName", _supportName],
        ["spawnPosATL", _launchPosATL],
			["searchAnchorMarker", _searchMarker],
			["controlPosATL", _controlPosATL],
			["fiberAnchorPos", _fiberAnchorPos],
			["launchDir", _launchDirBase],
			["siteType", _plan getOrDefault ["siteType", ""]],
			["profileId", _plan getOrDefault ["profileId", ""]],
			["side", _side],
			["supportSafetyRadius", _plan getOrDefault ["safetyRadius", 40]],
			["targetSide", _plan getOrDefault ["targetSide", sideUnknown]],
			["familyId", _plan getOrDefault ["familyId", ""]],
			["payloadRole", _plan getOrDefault ["payloadRole", ""]],
			["uavClass", _plan getOrDefault ["uavClass", ""]],
			["initialMode", _initialMode],
			["postCrewInit", _postCrewInit],
			["vehicleInitMode", "AIVEHINIT"],
			["resourcePool", _resPool]
		];

		if (!isNull _seedTarget) then {
			_spec set ["seedTarget", _seedTarget];
		};

		private _uav = [_spec] call A3UE_fnc_fpv_spawnManagedDrone;
		if (isNull _uav) then { continue };

		_uav setVariable ["A3UE_FPV_supportName", _supportName, true];
		_uav setVariable ["A3UE_FPV_supportContext", _contextMap getOrDefault ["context", "ReactiveSupport"], true];
		_uav setVariable ["A3UE_FPV_supportSearchMarker", _searchMarker, true];
		_uav setVariable ["A3UE_FPV_supportResourcePool", _resPool, true];
		_uav setVariable ["A3UE_FPV_supportOriginMarker", _origin getOrDefault ["originMarker", ""], true];
		_uav setVariable ["A3UE_FPV_supportTargetPosATL", _safeTargPos, true];

		_spawnedDrones pushBack _uav;
	};

};

if (_spawnedDrones isEqualTo []) exitWith {
	diag_log format ["[A3UE_FPV] supportDeployFailed name=%1 origin=%2 reason=%3", _supportName, _origin getOrDefault ["originMarker", ""], _launchFailure];
	_registryEntry set ["lastFailureReason", _launchFailure];
	missionNamespace setVariable ["A3UE_FPV_lastSupportFailureReason", _launchFailure];
	[_supportName, "failed", _launchFailure, "", true] call A3UE_fnc_fpv_supportFinalize;
	-1
};

// FS-05: one Info line per support launch (spawn time only, never in flight).
private _launchAt = _origin getOrDefault ["launchPosATL", [0, 0, 0]];
private _nearestHostile = -1;
{
	private _distance = _launchAt distance2D _x;
	if (_nearestHostile < 0 || {_distance < _nearestHostile}) then {_nearestHostile = _distance;};
} forEach ([_side] call A3UE_fnc_fpv_standoffThreats);
diag_log format ["[A3UE_FPV] supportDeploy name=%1 context=%2 origin=%3 contract=%4 mode=%5 class=%6 role=%7 count=%8 launchToTargetM=%9 nearestHostileM=%10 launchPos=%11",
	_supportName, _contextMap getOrDefault ["context", "ReactiveSupport"], _origin getOrDefault ["originMarker", ""],
	_origin getOrDefault ["originContract", ""], _origin getOrDefault ["launchMode", "ORIGIN"],
	_plan getOrDefault ["uavClass", ""], _plan getOrDefault ["payloadRole", ""], count _spawnedDrones,
	round (_launchAt distance2D _safeTargPos), round _nearestHostile, _launchAt apply {round _x}];

private _activeSupport = [
	_supportName,
	_side,
	"FPV",
	_safeTargPos,
	_plan getOrDefault ["activeRadius", 350],
	if (isNull _targetObject) then { [objNull, _safeTargPos] } else { [_targetObject, _safeTargPos] },
	0
];
// A preparing package already owns an AU suppression record.
if ((_registryEntry getOrDefault ["status", ""]) == "preparing") then {
	private _index = A3A_activeSupports findIf {(_x # 0) == _supportName};
	if (_index >= 0) then {A3A_activeSupports set [_index, _activeSupport];} else {A3A_activeSupports pushBack _activeSupport;};
} else {
	A3A_activeSupports pushBack _activeSupport;
};

private _strikeDuration = _plan getOrDefault ["strikeDuration", 300];
private _strikeType = ["TARGET", "TROOPS"] select (isNull _targetObject);
private _strikeTarget = [_safeTargPos, _targetObject] select (_strikeType == "TARGET");
private _strikePower = _plan getOrDefault ["estimatedCost", 0];
private _strikeExpiresAt = time + _strikeDuration;
private _pendingStrike = _registryEntry getOrDefault ["pendingStrike", []];
A3A_supportStrikes = A3A_supportStrikes select {!(_x isEqualRef _pendingStrike)};
A3A_supportStrikes pushBack [_side, _strikeType, _strikeTarget, _strikeExpiresAt, _strikeDuration, _strikePower];
_registryEntry deleteAt "pendingStrike";

// Use the reservation's fixed unit price, even if the AU cost table changes
// while preparing. Zero-delay calls preserve the same planned price.
private _plannedCost = _plan getOrDefault ["estimatedCost", 0];
private _overhead = _plan getOrDefault ["costOverhead", 20];
private _resourceCost = ((_plannedCost - _overhead) / _plannedDroneCount * count _spawnedDrones) + _overhead;
if ((_registryEntry getOrDefault ["reservationState", ""]) == "reserved") then {
	private _refund = ((_registryEntry get "reservedCost") - _resourceCost) max 0;
	_registryEntry set ["reservationState", "spent"];
	_registryEntry set ["refundedCost", _refund];
	if (_refund > 0) then {[_refund, _side, _resPool] call A3A_fnc_addEnemyResources;};
};

private _activeRegistry = missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap];
private _activeEntry = _activeRegistry getOrDefault [_supportName, _registryEntry];
_activeEntry set ["status", "active"];
_activeEntry set ["launchedAt", serverTime];
_activeEntry set ["strikeExpiresAt", _strikeExpiresAt];
_activeEntry deleteAt "preparation";
_activeEntry deleteAt "preparationHandle";
_activeEntry set ["drones", _spawnedDrones];
_activeEntry set ["droneNetIds", _spawnedDrones apply { _x getVariable ["A3UE_FPV_netId", netId _x] }];
_activeEntry set ["activeSupport", _activeSupport];
_activeEntry set ["resourceCost", _resourceCost];
_activeEntry set ["strikeType", _strikeType];
_activeRegistry set [_supportName, _activeEntry];
missionNamespace setVariable ["A3UE_FPV_supportRegistry", _activeRegistry];
// Creation diagnostics describe an actual launch, never an availability probe.
missionNamespace setVariable ["A3UE_FPV_lastSupportFailureReason", ""];
missionNamespace setVariable ["A3UE_FPV_lastSupportPlan", _plan];
missionNamespace setVariable ["A3UE_FPV_lastSupportContext", _contextMap];

if (!isNil "A3A_fnc_showInterceptedSupportCall") then {
	private _markerTypeForNotification = if (_strikeType isEqualTo "TARGET" && {_strikeTarget isEqualType objNull && {!isNull _strikeTarget}}) then {
		_strikeTarget
	} else {
		(((_plan getOrDefault ["activeRadius", 350]) min 150) max 80)
	};

	[_spawnedDrones, _reveal, _safeTargPos, _side, _markerTypeForNotification, _strikeDuration] spawn {
		params ["_drones", "_notifyReveal", "_notifyPos", "_notifySide", "_notifyMarkerType", "_notifyLifetime"];

		if (_notifyReveal <= 0.2) exitWith {};

		private _deadline = time + 180;
		waitUntil {
			sleep 0.5;
			private _aliveDrones = _drones select { !isNull _x && { alive _x } };
			(_aliveDrones isEqualTo [])
			|| {_aliveDrones findIf { (_x getVariable ["A3UE_FPV_mode", "IDLE"]) in ["TRACKING", "TERMINAL_ATTACK", "TERMINAL_VECTOR"] } > -1}
			|| {time > _deadline}
		};

		private _aliveDrones = _drones select { !isNull _x && { alive _x } };
		if (_aliveDrones isEqualTo [] || {time > _deadline}) exitWith {};

		[_notifyReveal, _notifyPos, _notifySide, "FPV", _notifyMarkerType, _notifyLifetime] spawn A3A_fnc_showInterceptedSupportCall;
	};
};

[_supportName, _preparationId, +_spawnedDrones, _strikeExpiresAt] spawn {
	params ["_supportName", "_preparationId", "_drones", "_deadline"];
	sleep ((_deadline - time) max 0);
	isNil {
		private _current = (missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap]) getOrDefault [_supportName, createHashMap];
		if ((_current getOrDefault ["preparationId", -1]) != _preparationId || {(_current getOrDefault ["status", ""]) != "active"}) exitWith {};
		{
			if (!isNull _x) then {[_x] call A3UE_fnc_fpv_cleanupDrone;};
		} forEach _drones;
		[_supportName, "finished", "support_lifetime_end", "", true] call A3UE_fnc_fpv_supportFinalize;
	};
};

if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {
	diag_log format ["[A3UE_FPV] supportResult name=%1 cost=%2 drones=%3 id=%4 time=%5 deadline=%6 expiry=%7", _supportName, _resourceCost, _activeEntry getOrDefault ["droneNetIds", []], _preparationId, time, _registryEntry get "launchDeadline", _strikeExpiresAt];
};

_resourceCost
