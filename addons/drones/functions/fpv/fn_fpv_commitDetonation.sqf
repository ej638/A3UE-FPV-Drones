params [
	["_uav", objNull, [objNull]],
	["_lifecycleId", -1, [0]],
	["_strike", createHashMap, [createHashMap]],
	["_path", [], [[]]],
	["_ttl", 20, [0]]
];

if !(call A3UE_fnc_fpv_lifecycleAccess) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
if (canSuspend) exitWith {
	private _result = false;
	isNil {_result = _this call A3UE_fnc_fpv_commitDetonation;};
	_result
};
// Test-owned, owner/server-local buffer; absent during ordinary play.
private _qaCommit = {
	params ["_outcome", "_reason"];
	if (!isNil "A3UE_FPV_QA_sink") then {
		[_uav, "COMMIT", [_outcome, _reason, _lifecycleId, remoteExecutedOwner]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);
	};
	_outcome == "COMMITTED"
};
if (isNull _uav || {!alive _uav} || {!(_uav getVariable ["A3UE_FPV_managed", false])}) exitWith {["REJECTED", "NOT_LIVE_MANAGED"] call _qaCommit};
if !([_uav] call A3UE_fnc_fpv_isSiteDroneActive) exitWith {["REJECTED", "INACTIVE_SITE"] call _qaCommit};
if (_lifecycleId < 0 || {_lifecycleId != (_uav getVariable ["A3UE_FPV_lifecycleIdServer", -1])}) exitWith {["REJECTED", "LIFETIME"] call _qaCommit};

private _record = (missionNamespace getVariable ["A3UE_FPV_lifecycles", createHashMap]) getOrDefault [str _lifecycleId, createHashMap];
if (count _record == 0 || {(_record get "phase") != "live"} || {!((_record get "object") isEqualTo _uav)}) exitWith {["REJECTED", "RECORD"] call _qaCommit};
private _ownerId = owner _uav;
private _sender = remoteExecutedOwner;
if (_ownerId != (_record get "owner")) exitWith {["REJECTED", "OWNER"] call _qaCommit};
if ([_uav] call A3UE_fnc_fpv_isExternallyControlled) exitWith {["REJECTED", "EXTERNAL_CONTROL"] call _qaCommit};
if (_uav getVariable ["A3UE_FPV_detonationCommitted", false]) exitWith {["DUPLICATE", "ALREADY_COMMITTED"] call _qaCommit; true};

private _netId = _uav getVariable ["A3UE_FPV_netId", netId _uav];
if ((_strike getOrDefault ["uavNetId", ""]) isNotEqualTo _netId || {count _strike > 32}) exitWith {["REJECTED", "SNAPSHOT_ID_OR_SIZE"] call _qaCommit};
private _invalidKeyIndex = (keys _strike) findIf {!(_x isEqualType "") || {count _x > 32}};
if (!(_invalidKeyIndex isEqualType 0) || {_invalidKeyIndex >= 0}) exitWith {["REJECTED", "SNAPSHOT_KEYS"] call _qaCommit};
// Bound every diagnostic value before retaining/broadcasting the owner snapshot.
private _invalidSnapshotIndex = (values _strike) findIf {
	private _value = _x;
	// Keep predicate results Boolean; findIf owns termination and index production.
	switch (true) do {
		case (_value isEqualType ""): {count _value > 128};
		case (_value isEqualType 0): {!finite _value};
		case (_value isEqualType true): {false};
		case (_value isEqualType []): {
			if (count _value > 3) then {true} else {
				private _invalidElementIndex = _value findIf {!(_x isEqualType 0) || {!finite _x}};
				!(_invalidElementIndex isEqualType 0) || {_invalidElementIndex >= 0}
			}
		};
		default {true};
	}
};
private _snapshotValid = (_invalidSnapshotIndex isEqualType 0) && {_invalidSnapshotIndex < 0};
if (!_snapshotValid) exitWith {["REJECTED", "SNAPSHOT_VALUES"] call _qaCommit};
private _supportName = _record get "support";
private _supportEntry = (missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap]) getOrDefault [_supportName, createHashMap];
if (_supportName != "" && {
	!(_uav in (_supportEntry getOrDefault ["drones", []])) ||
	{!(_netId in (_supportEntry getOrDefault ["droneNetIds", []]))} ||
	{"finishedAt" in _supportEntry}
}) exitWith {["REJECTED", "SUPPORT_MEMBERSHIP"] call _qaCommit};

private _invalidPoseIndex = ["deliveryPosASL", "deliveryDir", "deliveryUp"] findIf {
	private _vector = _strike getOrDefault [_x, []];
	if (!(_vector isEqualType []) || {count _vector != 3}) then {true} else {
		private _invalidComponentIndex = _vector findIf {!(_x isEqualType 0) || {!finite _x} || {abs _x > 1000000}};
		!(_invalidComponentIndex isEqualType 0) || {_invalidComponentIndex >= 0}
	}
};
private _poseValid = (_invalidPoseIndex isEqualType 0) && {_invalidPoseIndex < 0};
if (!_poseValid) exitWith {["REJECTED", "POSE_COMPONENTS"] call _qaCommit};
private _deliveryPos = _strike get "deliveryPosASL";
private _deliveryDir = _strike get "deliveryDir";
private _deliveryUp = _strike get "deliveryUp";
if (vectorMagnitude _deliveryDir < 0.01 || {vectorMagnitude (_deliveryDir vectorCrossProduct _deliveryUp) < 0.01}) exitWith {["REJECTED", "POSE_DEGENERATE"] call _qaCommit};
private _reason = _strike getOrDefault ["detonationReason", "NONE"];
private _fallback = _strike getOrDefault ["fallbackReason", "NONE"];
if !(_reason in ["DIRECT_CONTACT", "PREDICTED_IMPACT", "CLOSURE_QUALIFIED", "OBSTRUCTION_FALLBACK", "MISSED_PASS_FALLBACK", "PROXIMITY_FAILSAFE", "GROUND_CONTACT"]
    && {_fallback in ["NONE", "AIR_TARGET_PROXIMITY_POLICY", "TARGET_DUCKED_BEHIND_OBSTRUCTION", "OVERSHOOT_IMMINENT", "GUIDANCE_QUALITY_DEGRADED", "IMPACT_WINDOW_COLLAPSED", "NO_VALID_IMPACT_POINT"]}) exitWith {["REJECTED", "REASON_POLICY"] call _qaCommit};

// Derive the payload from actual class plus cached family/task eligibility.
// Neither the tactical role nor owner-supplied ammo/physical metadata selects ammo.
private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", ""];
if !(_payloadRole in ["AT", "AP", "RECON"]) exitWith {["REJECTED", "TASK_ROLE"] call _qaCommit};
private _descriptor = [typeOf _uav, _uav getVariable ["A3UE_FPV_vendorId", ""], _payloadRole] call A3UE_fnc_fpv_getClassDescriptor;
if (count _descriptor == 0 || {!(_descriptor get "canDetonate")}) exitWith {["REJECTED", "DESCRIPTOR"] call _qaCommit};
private _missileType = _descriptor get "ammoClass";
if (_missileType == "") exitWith {["REJECTED", "AMMO"] call _qaCommit};

// Recheck at actual payload creation, after any network/queue delay, using the
// server-held doctrine and live target identity. Never trust a submitted "safe" bit.
private _target = objectFromNetId (_strike getOrDefault ["targetNetId", ""]);
if (isNull _target || {(_uav getVariable ["A3UE_FPV_targetNetId",""]) != netId _target}
    || {(_strike getOrDefault ["targetRevision",-1]) != (_uav getVariable ["A3UE_FPV_targetRevision",0])}
    || {([_uav] call A3UE_fnc_fpv_resolveTarget) isNotEqualTo _target}) exitWith {["REJECTED","TARGET_CHANGED"] call _qaCommit};
if ((_uav getVariable ["A3UE_FPV_linkModel","RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState","OK"]) == "EW_DENIED"}) exitWith {["REJECTED","LINK"] call _qaCommit};
private _engagementFailure = "";
if (_supportName != "" && {(_supportEntry getOrDefault ["safetyRadius", 0]) > 0}) then {
	_engagementFailure = [_uav, _target, true, ASLToATL _deliveryPos, true, _supportEntry] call A3UE_fnc_fpv_supportEngagementReason;
	if (_engagementFailure != "") then {
		_supportEntry set ["lastEngagementFailureReason", _engagementFailure];
		_uav setVariable ["A3UE_FPV_engagementFailureReason", _engagementFailure, true];
        if (_engagementFailure == "UNSAFE_ENGAGEMENT") then {
            if ((_uav getVariable ["A3UE_FPV_engagementBlockedAt", -1]) < 0) then {_uav setVariable ["A3UE_FPV_engagementBlockedAt", serverTime, true];};
            _uav setVariable ["A3UE_FPV_mode", "SAFETY_HOLD", true];
        };
	};
};
if (_engagementFailure != "") exitWith {
	if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {
		diag_log format ["[A3UE_FPV] engagementCommitRejected id=%1 lifecycle=%2 sender=%3 target=%4 reason=%5 pose=%6", _netId, _lifecycleId, _sender, _strike getOrDefault ["targetNetId", ""], _engagementFailure, _deliveryPos];
	};
	["REJECTED", _engagementFailure] call _qaCommit
};

private _missile = createVehicle [_missileType, ASLToAGL _deliveryPos, [], 0, "CAN_COLLIDE"];
if (isNull _missile) exitWith {["REJECTED", "CREATE_PAYLOAD"] call _qaCommit};
private _projectileCreatedFrameNo = diag_frameNo;
// Correlate engine events even when ammo has no usable network object ID.
private _payloadEventId = format ["managed:%1:%2", _netId, _lifecycleId];
_missile setVariable ["A3UE_FPV_payloadEventId", _payloadEventId];
private _killer = driver _uav;
private _instigator = (UAVControl _uav) param [0, objNull];
if (!isNull _killer) then {_killer setCaptive false;};
_missile hideObjectGlobal true;

// Payload, support outcome and destructive cleanup share this server slice.
// Record success BEFORE triggerAmmo can synchronously invoke death handlers.
_uav setVariable ["A3UE_FPV_detonationCommitted", true];
// F5: the striking drone is consumed; a prepaid drone and crew get no AU surviving-asset refund.
[_uav] call A3UE_fnc_fpv_consumePool;
_uav setVariable ["A3UE_FPV_detonating", true, true];
_uav setVariable ["DB_fpv_isDetonating", true, true];
_uav setVariable ["A3UE_FPV_lastDetonationReason", _reason, true];
_uav setVariable ["A3UE_FPV_lastFallbackReason", _fallback, true];
[_supportName, "finished", _reason, _netId] call A3UE_fnc_fpv_supportFinalize;
// Retain final owner geometry, then fence every competing kill/delete callback.
_record set ["pendingGeometry", [+_path, _ttl]];
[_lifecycleId, "detonate"] call A3UE_fnc_fpv_endLifecycle;

_strike set ["at", time];
_strike set ["committedAt", serverTime];
_strike set ["lifecycleId", _lifecycleId];
_strike set ["controllerOwnerId", _ownerId];
_strike set ["vendorId", _uav getVariable ["A3UE_FPV_vendorId", ""]];
_strike set ["payloadRole", _payloadRole];
_strike set ["physicalPayload", _descriptor get "physicalPayload"];
_strike set ["uavClass", _descriptor get "className"];
_strike set ["ammoClass", _missileType];
_strike set ["payloadEventId", _payloadEventId];
_strike set ["projectileNetId", netId _missile];
_strike set ["projectileOwnerId", owner _missile];
_strike set ["projectileCreatedFrameNo", _projectileCreatedFrameNo];
_strike set ["requestedShotParentNetIds", [_killer, _instigator] apply {netId _x}];
// Native UA/KVN Hit callbacks can create another payload. Retire the managed
// airframe clear of its own blast while its crew remains a valid shot parent.
_uav hideObjectGlobal true;
_uav setPosASL [_deliveryPos # 0, _deliveryPos # 1, (_deliveryPos # 2) + 1000];

// Final pose, attribution and trigger share this non-suspending local block.
// No RPC, archive work or publication sits between placement and trigger.
_missile setPosASL _deliveryPos;
_missile setVectorDirAndUp [_deliveryDir, _deliveryUp];
_missile setVelocity [0, 0, 0];
_missile setShotParents [_killer, _instigator];
_strike set ["projectilePosASL", getPosASL _missile];
_strike set ["projectileDir", vectorDir _missile];
_strike set ["projectileUp", vectorUp _missile];
_strike set ["projectileVelocity", velocity _missile];
_strike set ["shotParentNetIds", (getShotParents _missile) apply {netId _x}];
_strike set ["shotParentsAlive", (getShotParents _missile) apply {!isNull _x && {alive _x}}];
_strike set ["triggerFrameNo", diag_frameNo];
_strike set ["triggerTickTime", diag_tickTime];
_strike set ["triggerAt", serverTime];
triggerAmmo _missile;

// F4-1 Info line for the committed pass outcome; the summary is not broadcast.
private _attackSummary = _strike getOrDefault ["attackPass", ""];
if (_attackSummary isEqualType "" && {_attackSummary != ""}) then {
	diag_log format ["[A3UE_FPV] attackPass id=%1 target=%2 outcome=%3 %4", _netId, _strike getOrDefault ["targetNetId", ""], _reason, _attackSummary];
};
_strike deleteAt "attackPass";
// Capture above, publish afterward: triggerAmmo may delete its parent projectile.
private _recent = missionNamespace getVariable ["A3UE_FPV_recentDetonations", []];
_recent pushBack _strike;
while {count _recent > 20} do {_recent deleteAt 0;};
missionNamespace setVariable ["A3UE_FPV_recentDetonations", _recent, true];
// Archive admission/identity is settled by endLifecycle; no second writer.
if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {
	diag_log format ["[A3UE_FPV] detonationCommit id=%1 lifecycle=%2 owner=%3 sender=%4 support=%5 pose=%6 parents=%7 ammo=%8 triggerAt=%9 frame=%10 velocity=%11 event=%12", _netId, _lifecycleId, _ownerId, _sender, _supportName, _strike get "projectilePosASL", _strike get "shotParentNetIds", _missileType, _strike get "triggerAt", _strike get "triggerFrameNo", _strike get "projectileVelocity", _payloadEventId];
};

["COMMITTED", _missileType] call _qaCommit;

// Cleanup is a server worker even when this call inherits the owner's RPC.
private _A3UE_FPV_strikeAuthorized = true;
[_uav] call A3UE_fnc_fpv_cleanupDrone;
true
