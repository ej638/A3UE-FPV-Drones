params [
	["_supportRef", objNull],
	["_status", "finished"],
	["_reason", ""],
	["_uavNetId", ""],
	["_forceComplete", false]
];

if !(call A3UE_fnc_fpv_lifecycleAccess) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
if (canSuspend) exitWith {
	private _result = false;
	// All member updates and terminal cleanup are one server transaction.
	isNil {_result = _this call A3UE_fnc_fpv_supportFinalize;};
	_result
};

private _uav = objNull;
private _supportName = "";

if (_supportRef isEqualType objNull) then {
	_uav = _supportRef;
	if (!isNull _uav) then {
		_supportName = _uav getVariable ["A3UE_FPV_supportName", ""];
		if (_uavNetId isEqualTo "") then {
			_uavNetId = _uav getVariable ["A3UE_FPV_netId", netId _uav];
		};
	};
} else {
	if (_supportRef isEqualType "") then {
		_supportName = _supportRef;
	};
};

private _registry = missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap];
if !(_registry isEqualType createHashMap) then {
	_registry = createHashMap;
};

if (_supportName isEqualTo "" && {_uavNetId isNotEqualTo ""}) then {
	{
		private _entry = _y;
		private _candidateNetIds = _entry getOrDefault ["droneNetIds", []];
		if (_candidateNetIds findIf { _x isEqualTo _uavNetId } > -1) exitWith {
			_supportName = _x;
		};

		private _drones = _entry getOrDefault ["drones", []];
		if (_supportName isEqualTo "" && {_drones findIf { !isNull _x && {(_x getVariable ["A3UE_FPV_netId", netId _x]) isEqualTo _uavNetId} } > -1}) exitWith {
			_supportName = _x;
		};
	} forEach _registry;
};

if (_supportName isEqualTo "") exitWith {false};

private _entry = _registry getOrDefault [_supportName, createHashMap];
if (count _entry == 0) exitWith {false};
if ((_entry getOrDefault ["status", ""]) in ["finished", "failed"] && {"finishedAt" in _entry}) exitWith {false};
// Pending settlement is server-local administrative/worker work. Lifecycle
// reports have no pending members and cannot turn a remote name into a refund.
private _preparing = (_entry getOrDefault ["status", ""]) == "preparing";
if (_preparing && {!_forceComplete}) exitWith {false};

private _drones = _entry getOrDefault ["drones", []];
private _droneNetIds = _entry getOrDefault ["droneNetIds", []];
if !(_droneNetIds isEqualType []) then {
	_droneNetIds = [];
};

private _remainingDrones = [];
private _remainingNetIds = [];
private _removedDrone = false;
private _entryCount = (count _drones) max (count _droneNetIds);
private _outcomes = _entry getOrDefault ["droneOutcomes", createHashMap];

for "_i" from 0 to (_entryCount - 1) do {
	private _candidateDrone = if (_i < count _drones) then { _drones select _i } else { objNull };
	private _candidateNetId = if (_i < count _droneNetIds) then { _droneNetIds select _i } else { "" };

	if (_candidateNetId isEqualTo "" && {!isNull _candidateDrone}) then {
		_candidateNetId = _candidateDrone getVariable ["A3UE_FPV_netId", netId _candidateDrone];
	};

	if ((_uavNetId isNotEqualTo "" && {_candidateNetId isEqualTo _uavNetId}) || {_forceComplete}) then {
		_removedDrone = true;
		private _lost = _status == "failed" || {
			(isNull _candidateDrone || {!alive _candidateDrone}) &&
			{isNull _candidateDrone || {!(_candidateDrone getVariable ["A3UE_FPV_detonationCommitted", false])}}
		};
		if (_candidateNetId != "" && {!(_candidateNetId in _outcomes)}) then {
			_outcomes set [_candidateNetId, [["finished", "failed"] select _lost, [_reason, "DRONE_LOST"] select _lost, serverTime]];
		};
		continue;
	};

	// Another dead/null member still needs its own lifecycle event. Pruning it
	// here loses both its identity and its outcome during simultaneous callbacks.
	if (_candidateNetId != "") then {
		_remainingDrones pushBack _candidateDrone;
		_remainingNetIds pushBack _candidateNetId;
	};
};

// Late/duplicate member callbacks cannot change an active paired package either.
if (!_removedDrone && {!_forceComplete}) exitWith {false};
_entry set ["drones", _remainingDrones];
_entry set ["droneNetIds", _remainingNetIds];
_entry set ["droneOutcomes", _outcomes];

private _hasLoss = (values _outcomes) findIf {(_x # 0) == "failed"} >= 0;
if (_hasLoss) then {
	_entry set ["lastFailureReason", "DRONE_LOST"];
	missionNamespace setVariable ["A3UE_FPV_lastSupportFailureReason", "DRONE_LOST"];
};

private _closeSupport = _forceComplete || {_remainingNetIds isEqualTo []};
if (_closeSupport) then {
	if (_preparing) then {
		private _handle = _entry getOrDefault ["preparationHandle", scriptNull];
		if (!isNull _handle && {!scriptDone _handle}) then {terminate _handle;};
		_entry deleteAt "preparationHandle";
		_entry deleteAt "preparation";
		private _pendingStrike = _entry getOrDefault ["pendingStrike", []];
		A3A_supportStrikes = A3A_supportStrikes select {!(_x isEqualRef _pendingStrike)};
		_entry deleteAt "pendingStrike";
		if ((_entry getOrDefault ["reservationState", ""]) == "reserved") then {
			private _refund = _entry get "reservedCost";
			// Mark first: duplicate cancellation/end/deadline paths cannot credit twice.
			_entry set ["reservationState", "refunded"];
			_entry set ["refundedCost", _refund];
			_entry set ["resourceCost", 0];
			[_refund, _entry get "side", _entry get "resourcePool"] call A3A_fnc_addEnemyResources;
		};
		_entry set ["resourceCost", 0];
		if (_status == "failed") then {_entry set ["lastFailureReason", _reason];};
		if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {
			diag_log format ["[A3UE_FPV] supportPreparationClosed name=%1 id=%2 reason=%3 settlement=%4 refund=%5", _supportName, _entry get "preparationId", _reason, _entry get "reservationState", _entry get "refundedCost"];
		};
	};
	// Conservative aggregate: every member must finish; any genuine loss fails
	// the package irrespective of whether a successful strike arrives first.
	private _terminalStatus = [_status, "failed"] select _hasLoss;
	private _terminalReason = _reason;
	if (count _outcomes > 0) then {
		_terminalStatus = ["finished", "failed"] select _hasLoss;
		private _hasFinished = (values _outcomes) findIf {(_x # 0) == "finished"} >= 0;
		if (_hasLoss) then {
			_terminalReason = ["DRONE_LOST", "PARTIAL_LOSS"] select _hasFinished;
		} else {
			private _outcomeIds = keys _outcomes;
			_outcomeIds sort true;
			_terminalReason = (_outcomes get (_outcomeIds # 0)) # 1;
		};
	};
	private _activeSupportIndex = A3A_activeSupports findIf { (_x param [0, ""]) isEqualTo _supportName };
	if (_activeSupportIndex != -1) then {
		private _activeSupport = + (A3A_activeSupports select _activeSupportIndex);
		_activeSupport set [4, 0];
		A3A_activeSupports set [_activeSupportIndex, _activeSupport];
	};

	private _searchMarker = _entry getOrDefault ["searchMarker", ""];
	if (_searchMarker isNotEqualTo "" && {(markerShape _searchMarker) isNotEqualTo ""}) then {
		deleteMarker _searchMarker;
	};

	private _trackedSupportMarkers = missionNamespace getVariable ["A3UE_FPV_supportTransientMarkers", []];
	if !(_trackedSupportMarkers isEqualType []) then {
		_trackedSupportMarkers = [];
	};
	_trackedSupportMarkers = _trackedSupportMarkers select { _x != _searchMarker };
	missionNamespace setVariable ["A3UE_FPV_supportTransientMarkers", _trackedSupportMarkers];

	_entry deleteAt "preparation";
	_entry set ["status", _terminalStatus];
	_entry set ["lastCleanupReason", _terminalReason];
	_entry set ["finishedAt", serverTime];
	_entry set ["drones", []];
	_entry set ["droneNetIds", []];
	private _retention = [_supportName, _entry get "finishedAt", _entry getOrDefault ["preparationId", -1]] spawn {
		params ["_closedName", "_closedAt", "_closedIdentity"];
		sleep ((_closedAt + 600 - serverTime) max 0);
		// Keep the identity check and removal together if the name is reused.
		isNil {
			private _closedRegistry = missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap];
			private _closedEntry = _closedRegistry getOrDefault [_closedName, createHashMap];
			if ((_closedEntry getOrDefault ["status", ""]) in ["finished", "failed"] && {(_closedEntry getOrDefault ["finishedAt", -1]) == _closedAt} && {(_closedEntry getOrDefault ["preparationId", -1]) == _closedIdentity}) then {
				_closedRegistry deleteAt _closedName;
				missionNamespace setVariable ["A3UE_FPV_supportRegistry", _closedRegistry];
			};
		};
	};
    _entry set ["retentionHandle", _retention];
} else {
	if ((_entry getOrDefault ["status", ""]) in ["", "initializing"]) then {
		_entry set ["status", "active"];
	};
};

_registry set [_supportName, _entry];
missionNamespace setVariable ["A3UE_FPV_supportRegistry", _registry];
private _closed = [];
{if ("finishedAt" in _y) then {_closed pushBack [_y get "finishedAt", _x];};} forEach _registry;
_closed sort true;
while {count _closed > 256} do {
    private _evicted = _registry deleteAt ((_closed deleteAt 0) # 1);
    private _retention = _evicted getOrDefault ["retentionHandle", scriptNull];
    if !(scriptDone _retention) then {terminate _retention;};
};

_closeSupport || _removedDrone
