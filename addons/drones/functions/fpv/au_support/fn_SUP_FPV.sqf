params ["_supportName", "_side", "_resPool", "_maxSpend", "_target", "_targPos", "_reveal", "_delay"];

if (!isServer || {missionNamespace getVariable ["A3UE_FPV_supportShuttingDown", false]}) exitWith {-1};

// AU 12.0.3 createSupport supplies these private locals while holding its
// support lock. A remote SUP_FPV call has no such dispatch scope. Do not use
// the global lock alone as authority, or accept a flag from the RPC payload.
private _auDispatch = !isNil "_type" && {_type isEqualTo "FPV"}
	&& {!isNil "_createFunc" && {_createFunc isEqualTo A3A_fnc_SUP_FPV}}
	&& {missionNamespace getVariable ["A3A_supportCallInProgress", false]}
	&& {_supportName isEqualTo format ["FPV%1", missionNamespace getVariable ["A3A_supportCount", -1]]};
private _trustedCaller = [true] call A3UE_fnc_fpv_isTrustedSupportCaller;
if (!_trustedCaller || {isRemoteExecuted && {remoteExecutedOwner != 2} && {!_auDispatch}}) exitWith {
	private _rejected = missionNamespace getVariable ["A3UE_FPV_supportIngressRejected", 0];
	missionNamespace setVariable ["A3UE_FPV_supportIngressRejected", (_rejected + 1) min 1000000];
	-1
};

// Inherited only by synchronous server work below; never stored in the spec,
// replicated, or forwarded to a new script. Preserve AU's numeric cost return.
private _A3UE_FPV_spawnAuthorized = true;
if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {
	diag_log format ["[A3UE_FPV] supportIngress name=%1 remote=%2 sender=%3 scheduled=%4 auDispatch=%5", _supportName, isRemoteExecuted, remoteExecutedOwner, canSuspend, _auDispatch];
};

private _targetObject = objNull;
if (_target isEqualType objNull) then {
	_targetObject = _target;
};

private _targetWasObject = !isNull _targetObject;

if (!(_targPos isEqualType [] && {count _targPos >= 2}) && {!isNull _targetObject}) then {
	_targPos = getPosATL _targetObject;
};

if !(_targPos isEqualType [] && {count _targPos >= 2}) exitWith {
	missionNamespace setVariable ["A3UE_FPV_lastSupportFailureReason", "INVALID_TARGET_POSITION"];
	-1
};

private _dropTransientMarker = {
	params [["_markerName", ""]];

	if !(_markerName isEqualType "") exitWith {};

	private _trackedSupportMarkers = missionNamespace getVariable ["A3UE_FPV_supportTransientMarkers", []];
	if !(_trackedSupportMarkers isEqualType []) then {
		_trackedSupportMarkers = [];
	};

	_trackedSupportMarkers = _trackedSupportMarkers select { _x != _markerName };
	missionNamespace setVariable ["A3UE_FPV_supportTransientMarkers", _trackedSupportMarkers];
};

private _supportFailure = {
	params ["_reason", ["_searchMarker", ""]];

	missionNamespace setVariable ["A3UE_FPV_lastSupportFailureReason", _reason];
	// F5 evidence: every refused FPV support call names its reason (war tier, no standoff
	// launch, unsafe engagement, no visible target, ...). One line per refusal, never per frame.
	diag_log format ["[A3UE_FPV] supportRefused name=%1 side=%2 pool=%3 reason=%4 target=%5",
		_supportName, _side, _resPool, _reason, if (_targPos isEqualType [] && {count _targPos >= 2}) then {(_targPos select [0, 2]) apply {round _x}} else {[]}];

	if (_searchMarker isNotEqualTo "" && {(markerShape _searchMarker) isNotEqualTo ""}) then {
		deleteMarker _searchMarker;
	};

	[_searchMarker] call _dropTransientMarker;
	-1
};

private _resolveSeedTarget = {
	params ["_seedSide", "_seedPos", "_seedPlan"];

	private _payloadRole = _seedPlan getOrDefault ["payloadRole", "AP"];
	private _seedSearchRadius = ((_seedPlan getOrDefault ["activeRadius", 350]) min 250) max 120;
	private _hostileSides = [_seedSide, _seedPlan getOrDefault ["targetSide", sideUnknown]] call A3UE_fnc_fpv_getHostileSides;

	private _candidates = [];
	{
		private _candidate = [_x, _hostileSides] call A3UE_fnc_fpv_filterTarget;
		if (isNull _candidate) then { continue };
		if (_candidate isKindOf "Air") then { continue };

		_candidates pushBackUnique _candidate;
	} forEach (nearestObjects [_seedPos, ["Man", "LandVehicle", "Ship", "StaticWeapon"], _seedSearchRadius, true]);

	if (_candidates isEqualTo []) exitWith {objNull};

	private _scoredCandidates = _candidates apply {
		private _score = 1000 - (_x distance2D _seedPos);

		switch (_payloadRole) do {
			case "AT": {
				if (_x isKindOf "Tank" || {_x isKindOf "Wheeled_APC_F"} || {_x isKindOf "Tracked_APC_F"}) then {
					_score = _score + 3500;
				} else {
					if (_x isKindOf "LandVehicle" || {_x isKindOf "Ship"}) then {
						_score = _score + 1800;
					};
				};

				if (_x isKindOf "Man") then {
					_score = _score - 2500;
				};
			};
			case "RECON": {
				if (_x isKindOf "Man") then {
					_score = _score + 1800;
				} else {
					if (_x isKindOf "Car" || {_x isKindOf "StaticWeapon"}) then {
						_score = _score + 1200;
					};
				};
			};
			default {
				if (_x isKindOf "Man") then {
					_score = _score + 2600;
				} else {
					if (_x isKindOf "Car" || {_x isKindOf "StaticWeapon"}) then {
						_score = _score + 1400;
					};
				};

				if (_x isKindOf "Tank" || {_x isKindOf "Wheeled_APC_F"} || {_x isKindOf "Tracked_APC_F"}) then {
					_score = _score - 1500;
				};
			};
		};

		[_score, _x]
	};

	_scoredCandidates sort false;
	(_scoredCandidates select 0) param [1, objNull]
};

private _sourceContext = [_resPool, createHashMap] call A3UE_fnc_fpv_getSupportContext;
private _contextMap = createHashMap;
{_contextMap set [_x, _y];} forEach _sourceContext;
private _plan = [_side, _targetObject, _maxSpend, _contextMap, _resPool, _targPos] call A3UE_fnc_fpv_resolveSupportPackage;
if !(_plan getOrDefault ["ok", false]) exitWith {
	[_plan getOrDefault ["failure", "NO_FEASIBLE_PACKAGE"]] call _supportFailure
};

private _origin = _plan get "origin";
if !(_origin getOrDefault ["ok", false]) exitWith {
	[_origin getOrDefault ["reason", "NO_VALID_ORIGIN"]] call _supportFailure
};
_contextMap set ["originMarker", _origin get "originMarker"];

private _searchMarker = [_supportName, _targPos, _side, _contextMap] call A3UE_fnc_fpv_supportCreateMarker;
if (_searchMarker isEqualTo "") exitWith {
	["MARKER_CREATE_FAILED"] call _supportFailure
};

private _seedTarget = _targetObject;
if (isNull _seedTarget) then {
	_seedTarget = [_side, _targPos, _plan] call _resolveSeedTarget;
};

private _requiresSeed = (_plan getOrDefault ["safetyRadius", 40]) > 0
	|| {(_contextMap getOrDefault ["context", "ReactiveSupport"]) == "PunishmentSupport"};
if (isNull _seedTarget && {_requiresSeed}) exitWith {
	["NO_VISIBLE_TARGET", _searchMarker] call _supportFailure
};
if !([_side, _seedTarget, _targPos, _plan] call A3UE_fnc_fpv_supportPassesSafetyRing) exitWith {
	["UNSAFE_ENGAGEMENT", _searchMarker] call _supportFailure
};

private _plannedDroneCount = (_plan getOrDefault ["droneCount", 1]) max 1;
private _safeTargPos = +_targPos;
if (count _safeTargPos < 3) then {
	_safeTargPos pushBack 0;
};
private _setupDelay = _delay;
if !(_setupDelay isEqualType 0 && {finite _setupDelay}) then {
	_setupDelay = -1;
};
if (_setupDelay < 0) then {
	private _originPosATL = _origin getOrDefault ["originPosATL", []];
	if (_originPosATL isEqualType [] && {count _originPosATL >= 2}) then {
		_setupDelay = ((_originPosATL distance2D _safeTargPos) / 70) max 15;
	} else {
		_setupDelay = 30;
	};
};

private _preparationId = -1;
isNil {
	_preparationId = 1 + (missionNamespace getVariable ["A3UE_FPV_nextSupportId", 0]);
	missionNamespace setVariable ["A3UE_FPV_nextSupportId", _preparationId];
};
private _registry = missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap];
if !(_registry isEqualType createHashMap) then {
	_registry = createHashMap;
};

private _registryEntry = createHashMapFromArray [
	["supportName", _supportName],
	["context", _contextMap getOrDefault ["context", "ReactiveSupport"]],
	["side", _side],
	["targetSide", _plan getOrDefault ["targetSide", sideUnknown]],
	["resourcePool", _resPool],
	["originMarker", _origin getOrDefault ["originMarker", ""]],
	["originPosATL", _origin getOrDefault ["originPosATL", []]],
	["controlPosATL", _origin getOrDefault ["controlPosATL", []]],
	["originContract", _origin getOrDefault ["originContract", ""]],
	["originEpoch", _origin getOrDefault ["originEpoch", -1]],
	["originGeneration", _origin getOrDefault ["originGeneration", -1]],
	["reach", _origin getOrDefault ["reach", createHashMap]],
	["searchMarker", _searchMarker],
	["status", ["initializing", "preparing"] select (_setupDelay > 0)],
	["preparationId", _preparationId],
	["setupDelay", _setupDelay],
	["launchDeadline", time + _setupDelay],
	["reservedCost", _plan getOrDefault ["estimatedCost", 0]],
	["reservationState", ["unpaid", ["synchronous", "reserved"] select (_setupDelay > 0)] select _auDispatch],
	["refundedCost", 0],
	["resourceCost", [0, _plan getOrDefault ["estimatedCost", 0]] select (_setupDelay > 0)],
	["preparation", createHashMapFromArray [
		["plan", _plan], ["context", _contextMap], ["target", _targetObject],
		["targetWasObject", _targetWasObject], ["seedTarget", _seedTarget],
		["seedWasObject", !isNull _seedTarget], ["reveal", _reveal]
	]],
	["profileId", _plan getOrDefault ["profileId", ""]],
	["siteType", _plan getOrDefault ["siteType", ""]],
	["familyId", _plan getOrDefault ["familyId", ""]],
	["payloadRole", _plan getOrDefault ["payloadRole", ""]],
	["uavClass", _plan getOrDefault ["uavClass", ""]],
	["plannedDroneCount", _plannedDroneCount],
	["estimatedCost", _plan getOrDefault ["estimatedCost", 0]],
	["activeRadius", _plan getOrDefault ["activeRadius", 350]],
	["strikeDuration", _plan getOrDefault ["strikeDuration", 300]],
	["safetyRadius", _plan getOrDefault ["safetyRadius", 40]],
	["targetNetId", if (isNull _targetObject) then {""} else {netId _targetObject}],
	["targetPosATL", _safeTargPos],
	["startedAt", serverTime],
	["lastFailureReason", ""],
	["lastCleanupReason", ""],
	["drones", []],
	["droneNetIds", []]
];

private _admit = {
	_registry = missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap];
	if (missionNamespace getVariable ["A3UE_FPV_supportShuttingDown", false]) exitWith {
		missionNamespace setVariable ["A3UE_FPV_lastSupportFailureReason", "MISSION_SHUTDOWN"];
		false
	};
	private _previous = _registry getOrDefault [_supportName, createHashMap];
	if ((_previous getOrDefault ["status", ""]) in ["initializing", "preparing", "active"]) exitWith {
		missionNamespace setVariable ["A3UE_FPV_lastSupportFailureReason", "SUPPORT_NAME_BUSY"];
		false
	};
	_registry set [_supportName, _registryEntry];
	missionNamespace setVariable ["A3UE_FPV_supportRegistry", _registry];
	true
};
if (_setupDelay == 0) exitWith {
	private _cost = -1;
	isNil {
		if (call _admit) then {_cost = [_supportName, _preparationId] call A3UE_fnc_fpv_supportLaunch;};
	};
	if (_cost < 0) exitWith {[missionNamespace getVariable ["A3UE_FPV_lastSupportFailureReason", "LAUNCH_REJECTED"], _searchMarker] call _supportFailure;};
	if (!isNil "A3A_fnc_showInterceptedSetupCall") then {
		[_reveal, _side, "FPV", _safeTargPos, 0] spawn A3A_fnc_showInterceptedSetupCall;
	};
	_cost
};

// The normal AU dispatcher debits this reservation after return. No sleep
// occurs under its global lock. Raw local helper controls are unpaid.
private _reserved = false;
isNil {
	if !(call _admit) exitWith {};
	_reserved = true;
	private _activeSupport = [_supportName, _side, "FPV", _safeTargPos,
		_plan getOrDefault ["activeRadius", 350], [_targetObject, _safeTargPos], 0];
	A3A_activeSupports pushBack _activeSupport;
	_registryEntry set ["activeSupport", _activeSupport];
	private _duration = _setupDelay + (_plan getOrDefault ["strikeDuration", 300]);
	private _strikeType = ["TROOPS", "TARGET"] select _targetWasObject;
	private _strikeTarget = [_safeTargPos, _targetObject] select _targetWasObject;
	private _pendingStrike = [_side, _strikeType, _strikeTarget, time + _duration, _duration, _plan get "estimatedCost"];
	A3A_supportStrikes pushBack _pendingStrike;
	_registryEntry set ["pendingStrike", _pendingStrike];
	if (isNil "A3UE_FPV_supportEndedEH") then {
		A3UE_FPV_supportEndedEH = addMissionEventHandler ["Ended", {call A3UE_fnc_fpv_supportShutdown;}];
		A3UE_FPV_supportMPEndedEH = addMissionEventHandler ["MPEnded", {call A3UE_fnc_fpv_supportShutdown;}];
	};
	private _handle = [_supportName, _preparationId, _registryEntry get "launchDeadline", missionNamespace getVariable ["A3A_supportCount", -1]] spawn {
		params ["_name", "_identity", "_deadline", "_dispatchCount"];
		sleep ((_deadline - time) max 0);
		// Very short explicit delays can wake before AU has completed its debit.
		// Only wait for dispatch completion; never acquire or hold the AU lock.
		waitUntil {
			sleep 0.1;
			isNil "A3A_supportCallInProgress"
			|| {(missionNamespace getVariable ["A3A_supportCount", -1]) != _dispatchCount}
			|| {missionNamespace getVariable ["A3UE_FPV_supportShuttingDown", false]}
		};
		[_name, _identity] call A3UE_fnc_fpv_supportLaunch;
	};
	_registryEntry set ["preparationHandle", _handle];
};
if (!_reserved) exitWith {[missionNamespace getVariable ["A3UE_FPV_lastSupportFailureReason", "PREPARATION_REJECTED"], _searchMarker] call _supportFailure;};
if (!isNil "A3A_fnc_showInterceptedSetupCall") then {
	[_reveal, _side, "FPV", _safeTargPos, _setupDelay] spawn A3A_fnc_showInterceptedSetupCall;
};
if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {
	diag_log format ["[A3UE_FPV] supportPreparing name=%1 id=%2 delay=%3 deadline=%4 cost=%5 settlement=%6", _supportName, _preparationId, _setupDelay, _registryEntry get "launchDeadline", _registryEntry get "reservedCost", _registryEntry get "reservationState"];
};
_plan get "estimatedCost"
