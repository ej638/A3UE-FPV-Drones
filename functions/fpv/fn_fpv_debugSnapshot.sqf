private _registry = missionNamespace getVariable ["A3UE_FPV_registry", createHashMap];
private _registrySnapshot = [];
private _loadedMods = missionNamespace getVariable ["A3UE_FPV_loadedMods", createHashMap];
private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
private _recentDetonations = missionNamespace getVariable ["A3UE_FPV_recentDetonations", []];
private _loadedFamilies = [];
private _catalogFamilies = [];
private _directHitModes = ["DIRECT_BODY", "DIRECT_HULL", "DIRECT_STATIC"];
private _fallbackSurfaceModes = ["GROUND_NEAR_TARGET", "OBSTRUCTION_SURFACE"];
private _directHitPrimaryReasons = ["DIRECT_CONTACT", "PREDICTED_IMPACT"];
private _fallbackSurfacePrimaryReasons = ["CLOSURE_QUALIFIED", "OBSTRUCTION_FALLBACK"];
private _emergencyFallbackReasons = ["MISSED_PASS_FALLBACK", "PROXIMITY_FAILSAFE"];
private _holdoffContractKey = "terminalImpactHoldoffDistance";
private _holdoffContractStatus = "ENFORCED_MODE_AWARE";

private _normalizeRecentDetonation = {
	params [["_record", createHashMap]];

	private _impactMode = _record getOrDefault ["impactMode", "NONE"];
	private _detonationReason = _record getOrDefault ["detonationReason", "NONE"];
	private _fallbackReason = _record getOrDefault ["fallbackReason", "NONE"];
	private _deliveryMode = _record getOrDefault ["deliveryMode", "UAV_POSITION"];
	private _strikePathClass = _record getOrDefault ["strikePathClass", switch (true) do {
		case (_impactMode in _directHitModes): {"DIRECT_HIT"};
		case (_impactMode in _fallbackSurfaceModes): {"FALLBACK_SURFACE"};
		case (_impactMode == "AIR_PROXIMITY"): {"AIR_POLICY"};
		case (_fallbackReason != "NONE"): {"EMERGENCY_FALLBACK"};
		default {"UNCLASSIFIED"};
	}];
	private _approvalPolicyClass = _record getOrDefault ["approvalPolicyClass", switch (true) do {
		case (_detonationReason in _directHitPrimaryReasons): {"DIRECT_HIT_PRIMARY"};
		case (_detonationReason in _fallbackSurfacePrimaryReasons): {"SURFACE_PRIMARY"};
		case (_detonationReason in _emergencyFallbackReasons): {"EMERGENCY_FALLBACK"};
		default {"UNCLASSIFIED"};
	}];
	private _policyDeliveryMode = _record getOrDefault ["policyDeliveryMode", switch (_strikePathClass) do {
		case "DIRECT_HIT": {"IMPACT_POINT"};
		case "FALLBACK_SURFACE": {"IMPACT_POINT"};
		default {"UAV_POSITION"};
	}];
	private _deliveryPolicyMatch = _record getOrDefault ["deliveryPolicyMatch", _deliveryMode == _policyDeliveryMode];
	private _knownBadPattern = _record getOrDefault ["knownBadPattern", (_impactMode == "GROUND_NEAR_TARGET") && {_detonationReason == "CLOSURE_QUALIFIED"} && {_deliveryMode == "UAV_POSITION"}];

	createHashMapFromArray [
		["at", _record getOrDefault ["at", -1]],
		["uavNetId", _record getOrDefault ["uavNetId", ""]],
		["targetNetId", _record getOrDefault ["targetNetId", ""]],
		["siteMarker", _record getOrDefault ["siteMarker", ""]],
		["vendorId", _record getOrDefault ["vendorId", ""]],
		["payloadRole", _record getOrDefault ["payloadRole", ""]],
		["profileId", _record getOrDefault ["profileId", ""]],
		["impactMode", _impactMode],
		["surfaceType", _record getOrDefault ["surfaceType", "none"]],
		["detonationReason", _detonationReason],
		["fallbackReason", _fallbackReason],
		["deliveryMode", _deliveryMode],
		["strikePathClass", _strikePathClass],
		["approvalPolicyClass", _approvalPolicyClass],
		["policyDeliveryMode", _policyDeliveryMode],
		["deliveryPolicyMatch", _deliveryPolicyMatch],
		["knownBadPattern", _knownBadPattern],
		["impactPointASL", _record getOrDefault ["impactPointASL", []]],
		["uavPosASL", _record getOrDefault ["uavPosASL", []]],
		["deliveryPosASL", _record getOrDefault ["deliveryPosASL", []]],
		["controllerOwnerId", _record getOrDefault ["controllerOwnerId", -1]],
		["linkState", _record getOrDefault ["linkState", ""]]
	]
};

private _recentDetonationSnapshot = _recentDetonations apply {
	[_x] call _normalizeRecentDetonation
};

{
	if (_y) then {
		_loadedFamilies pushBack _x;
	};
} forEach _loadedMods;

{
	_catalogFamilies pushBack _x;
} forEach _catalog;

{
	private _entry = _y;
	private _drones = (_entry getOrDefault ["drones", []]) apply {
		if (isNull _x) then {
			""
		} else {
			_x getVariable ["A3UE_FPV_netId", netId _x]
		}
	};

	_registrySnapshot pushBack createHashMapFromArray [
		["siteMarker", _x],
		["siteType", _entry getOrDefault ["siteType", ""]],
		["profileId", _entry getOrDefault ["profileId", ""]],
		["status", _entry getOrDefault ["status", ""]],
		["selectedFamily", _entry getOrDefault ["selectedFamily", ""]],
		["plannedCount", _entry getOrDefault ["plannedCount", 0]],
		["droneNetIds", _drones],
		["lastRoll", _entry getOrDefault ["lastRoll", -1]],
		["lastCleanup", _entry getOrDefault ["lastCleanup", -1]],
		["lastCleanupReason", _entry getOrDefault ["lastCleanupReason", ""]],
		["lastCleanupNetId", _entry getOrDefault ["lastCleanupNetId", ""]]
	];
} forEach _registry;

private _managedDrones = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) apply {
	private _profile = [_x] call A3UE_fnc_fpv_getProfile;
	private _profileSummary = createHashMapFromArray [
		["trackingSpeed", _profile getOrDefault ["trackingSpeed", -1]],
		["terminalAttackSpeed", _profile getOrDefault ["terminalAttackSpeed", -1]],
		["terminalSpeed", _profile getOrDefault ["terminalSpeed", -1]],
		["terminalVectorEntrySpeed", _profile getOrDefault ["terminalVectorEntrySpeed", -1]],
		["terminalVectorMaxSpeed", _profile getOrDefault ["terminalVectorMaxSpeed", -1]],
		["terminalVectorAccel", _profile getOrDefault ["terminalVectorAccel", -1]],
		["terminalVectorDecel", _profile getOrDefault ["terminalVectorDecel", -1]],
		["terminalGateDistance", _profile getOrDefault ["terminalGateDistance", -1]],
		["terminalSteeringDistance", _profile getOrDefault ["terminalSteeringDistance", -1]],
		["terminalVectorRampDistance", _profile getOrDefault ["terminalVectorRampDistance", -1]],
		["terminalVectorInnerFuseSlowdownDistance", _profile getOrDefault ["terminalVectorInnerFuseSlowdownDistance", -1]],
		["terminalVectorInnerFuseMinSpeed", _profile getOrDefault ["terminalVectorInnerFuseMinSpeed", -1]],
		["terminalVectorFullAccelAlignment", _profile getOrDefault ["terminalVectorFullAccelAlignment", -1]],
		["terminalVectorMinAccelAlignment", _profile getOrDefault ["terminalVectorMinAccelAlignment", -1]],
		["terminalVectorTurnBlendMin", _profile getOrDefault ["terminalVectorTurnBlendMin", -1]],
		["terminalVectorTurnBlendMax", _profile getOrDefault ["terminalVectorTurnBlendMax", -1]],
		["terminalVectorSpeedLagTolerance", _profile getOrDefault ["terminalVectorSpeedLagTolerance", -1]],
		["terminalImpactMode", _profile getOrDefault ["terminalImpactMode", ""]],
		["terminalImpactOffsetFar", _profile getOrDefault ["terminalImpactOffsetFar", -1]],
		["terminalImpactOffsetNear", _profile getOrDefault ["terminalImpactOffsetNear", -1]],
		["terminalDescentMinRate", _profile getOrDefault ["terminalDescentMinRate", -1]],
		["terminalDescentEnforceDistance", _profile getOrDefault ["terminalDescentEnforceDistance", -1]],
		["directContactDistanceBody", _profile getOrDefault ["directContactDistanceBody", -1]],
		["directContactDistanceHull", _profile getOrDefault ["directContactDistanceHull", -1]],
		["predictedImpactMaxTimeToContactBody", _profile getOrDefault ["predictedImpactMaxTimeToContactBody", -1]],
		["predictedImpactMaxTimeToContactHull", _profile getOrDefault ["predictedImpactMaxTimeToContactHull", -1]],
		["directHitClosureQualifiedAllowed", _profile getOrDefault ["directHitClosureQualifiedAllowed", false]],
		["fallbackSurfaceHoldoffDistance", _profile getOrDefault ["fallbackSurfaceHoldoffDistance", -1]],
		["detonationMaxTimeToContact", _profile getOrDefault ["detonationMaxTimeToContact", -1]],
		["detonationMinClosingDot", _profile getOrDefault ["detonationMinClosingDot", -2]],
		["detonationMaxAltitudeAGL", _profile getOrDefault ["detonationMaxAltitudeAGL", -1]],
		["impactFallbackRadius", _profile getOrDefault ["impactFallbackRadius", -1]],
		["impactFallbackGroundOffset", _profile getOrDefault ["impactFallbackGroundOffset", -1]],
		["impactProbeDistance", _profile getOrDefault ["impactProbeDistance", -1]],
		["impactAbortTimeout", _profile getOrDefault ["impactAbortTimeout", -1]],
		["terminalImpactHoldoffDistance", _profile getOrDefault ["terminalImpactHoldoffDistance", -1]],
		["impactSurfaceRefreshDistance", _profile getOrDefault ["impactSurfaceRefreshDistance", -1]],
		["impactSurfaceRefreshTTL", _profile getOrDefault ["impactSurfaceRefreshTTL", -1]],
		["detonationVehicleHullBias", _profile getOrDefault ["detonationVehicleHullBias", -1]],
		["detonationInfantryGroundLead", _profile getOrDefault ["detonationInfantryGroundLead", -1]],
		["impactFallbackAllowObstructionSurface", _profile getOrDefault ["impactFallbackAllowObstructionSurface", false]],
		["detonationDistance", _profile getOrDefault ["detonationDistance", -1]],
		["searchRadius", _profile getOrDefault ["searchRadius", -1]],
		["lostTargetTTL", _profile getOrDefault ["lostTargetTTL", -1]],
		["familyMaxSpeed", _profile getOrDefault ["familyMaxSpeed", -1]],
		["maxLeadTimeNear", _profile getOrDefault ["maxLeadTimeNear", -1]],
		["maxLeadTimeFar", _profile getOrDefault ["maxLeadTimeFar", -1]],
		["trackingMoveDelta", _profile getOrDefault ["trackingMoveDelta", -1]],
		["terminalMoveDelta", _profile getOrDefault ["terminalMoveDelta", -1]]
	];

	createHashMapFromArray [
		["netId", _x getVariable ["A3UE_FPV_netId", netId _x]],
		["type", typeOf _x],
		["vendorId", _x getVariable ["A3UE_FPV_vendorId", ""]],
		["payloadRole", _x getVariable ["A3UE_FPV_payloadRole", ""]],
		["profileId", _x getVariable ["A3UE_FPV_profileId", ""]],
		["mode", _x getVariable ["A3UE_FPV_mode", ""]],
		["linkState", _x getVariable ["A3UE_FPV_linkState", ""]],
		["cachedLinkState", _x getVariable ["A3UE_FPV_cachedLinkState", ""]],
		["signalStrength", _x getVariable ["A3UE_FPV_signalStrength", -1]],
		["cachedSignalStrength", _x getVariable ["A3UE_FPV_cachedSignalStrength", -1]],
		["nextLinkEvalAt", _x getVariable ["A3UE_FPV_nextLinkEvalAt", -1]],
		["siteMarker", _x getVariable ["A3UE_FPV_siteMarker", ""]],
		["targetNetId", _x getVariable ["A3UE_FPV_targetNetId", ""]],
		["lastKnownTargetNetId", _x getVariable ["A3UE_FPV_lastKnownTargetNetId", ""]],
		["lastKnownTargetPosASL", _x getVariable ["A3UE_FPV_lastKnownTargetPosASL", []]],
		["lastKnownTargetVel", _x getVariable ["A3UE_FPV_lastKnownTargetVel", []]],
		["lostTargetExpireAt", _x getVariable ["A3UE_FPV_lostTargetExpireAt", -1]],
		["lastLeadTime", _x getVariable ["A3UE_FPV_lastLeadTime", -1]],
		["lastTargetScore", _x getVariable ["A3UE_FPV_lastTargetScore", -1e9]],
		["lastTargetScoreBreakdown", _x getVariable ["A3UE_FPV_lastTargetScoreBreakdown", createHashMap]],
		["terminalSteeringActive", _x getVariable ["A3UE_FPV_terminalSteeringActive", false]],
		["terminalVectorEnteredAt", _x getVariable ["A3UE_FPV_terminalVectorEnteredAt", -1]],
		["terminalVectorEntrySpeed", _x getVariable ["A3UE_FPV_terminalVectorEntrySpeed", -1]],
		["terminalVectorEntryDistance", _x getVariable ["A3UE_FPV_terminalVectorEntryDistance", -1]],
		["terminalVectorCurrentSpeed", _x getVariable ["A3UE_FPV_terminalVectorCurrentSpeed", -1]],
		["terminalVectorTargetSpeed", _x getVariable ["A3UE_FPV_terminalVectorTargetSpeed", -1]],
		["terminalVectorAccelApplied", _x getVariable ["A3UE_FPV_terminalVectorAccelApplied", -1]],
		["terminalVectorAlignment", _x getVariable ["A3UE_FPV_terminalVectorAlignment", -2]],
		["terminalVectorDt", _x getVariable ["A3UE_FPV_terminalVectorDt", -1]],
		["terminalVectorSpeedJump", _x getVariable ["A3UE_FPV_terminalVectorSpeedJump", -1]],
		["terminalImpactMode", _x getVariable ["A3UE_FPV_terminalImpactMode", ""]],
		["lastImpactValid", _x getVariable ["A3UE_FPV_lastImpactValid", false]],
		["lastImpactPointASL", _x getVariable ["A3UE_FPV_lastImpactPointASL", []]],
		["lastImpactSurfaceType", _x getVariable ["A3UE_FPV_lastImpactSurfaceType", ""]],
		["lastImpactSurfaceObjectNetId", _x getVariable ["A3UE_FPV_lastImpactSurfaceObjectNetId", ""]],
		["lastImpactTargetNetId", _x getVariable ["A3UE_FPV_lastImpactTargetNetId", ""]],
		["lastImpactReason", _x getVariable ["A3UE_FPV_lastImpactReason", ""]],
		["lastImpactFallbackAllowed", _x getVariable ["A3UE_FPV_lastImpactFallbackAllowed", true]],
		["lastImpactFallbackRadius", _x getVariable ["A3UE_FPV_lastImpactFallbackRadius", 0]],
		["lastImpactEvalPosASL", _x getVariable ["A3UE_FPV_lastImpactEvalPosASL", []]],
		["lastImpactTargetPosASL", _x getVariable ["A3UE_FPV_lastImpactTargetPosASL", []]],
		["lastClosingDot", _x getVariable ["A3UE_FPV_lastClosingDot", -2]],
		["lastTimeToContact", _x getVariable ["A3UE_FPV_lastTimeToContact", -1]],
		["lastDetonationReason", _x getVariable ["A3UE_FPV_lastDetonationReason", ""]],
		["lastFallbackReason", _x getVariable ["A3UE_FPV_lastFallbackReason", ""]],
		["lastImpactTelemetryAt", _x getVariable ["A3UE_FPV_lastImpactTelemetryAt", -1]],
		["lastTerminalVectorDistance", _x getVariable ["A3UE_FPV_lastTerminalVectorDistance", -1]],
		["controllerRunning", _x getVariable ["A3UE_FPV_controllerRunning", false]],
		["controllerOwnerId", _x getVariable ["A3UE_FPV_controllerOwnerId", -1]],
		["currentOwnerId", owner _x],
		["isLocal", local _x],
		["profileSummary", _profileSummary]
	]
};

private _registryDroneNetIds = [];
{
	{
		if !(_x isEqualTo "") then {
			_registryDroneNetIds pushBackUnique _x;
		};
	} forEach (_x getOrDefault ["droneNetIds", []]);
} forEach _registrySnapshot;

private _managedDroneNetIds = [];
{
	private _netId = _x getOrDefault ["netId", ""];
	if !(_netId isEqualTo "") then {
		_managedDroneNetIds pushBack _netId;
	};
} forEach _managedDrones;

private _terminalVectorActiveDrones = _managedDrones select {
	(_x getOrDefault ["mode", ""]) == "TERMINAL_VECTOR"
};
private _impactActiveDrones = _managedDrones select {
	(_x getOrDefault ["mode", ""]) in ["TERMINAL_ATTACK", "TERMINAL_VECTOR"]
};
private _impactActiveNetIds = _impactActiveDrones apply {
	_x getOrDefault ["netId", ""]
};
private _impactLocalNetIds = (_impactActiveDrones select {
	_x getOrDefault ["isLocal", false]
}) apply {
	_x getOrDefault ["netId", ""]
};
private _impactTelemetryReadyNetIds = (_impactActiveDrones select {
	private _impactMode = _x getOrDefault ["terminalImpactMode", ""];
	private _impactPoint = _x getOrDefault ["lastImpactPointASL", []];
	private _impactTelemetryAt = _x getOrDefault ["lastImpactTelemetryAt", -1];
	private _impactTargetNetId = _x getOrDefault ["lastImpactTargetNetId", ""];
	!(_impactMode isEqualTo "") &&
	(_impactTelemetryAt >= 0) &&
	!(_impactTargetNetId isEqualTo "") && {
		!(_x getOrDefault ["lastImpactValid", false]) || {(_impactPoint isEqualType []) && {count _impactPoint >= 3}}
	}
}) apply {
	_x getOrDefault ["netId", ""]
};
private _terminalVectorActiveNetIds = _terminalVectorActiveDrones apply {
	_x getOrDefault ["netId", ""]
};
private _terminalVectorLocalNetIds = (_terminalVectorActiveDrones select {
	_x getOrDefault ["isLocal", false]
}) apply {
	_x getOrDefault ["netId", ""]
};
private _terminalVectorTelemetryReadyNetIds = (_terminalVectorActiveDrones select {
	(_x getOrDefault ["terminalVectorCurrentSpeed", -1]) >= 0 &&
	(_x getOrDefault ["terminalVectorTargetSpeed", -1]) >= 0 &&
	(_x getOrDefault ["terminalVectorDt", -1]) > 0
}) apply {
	_x getOrDefault ["netId", ""]
};
private _terminalVectorActiveVendors = [];
private _terminalVectorActiveSites = [];
private _impactActiveVendors = [];
private _impactActiveSites = [];
private _holdoffConfiguredImpactNetIds = (_impactActiveDrones select {
	((_x getOrDefault ["profileSummary", createHashMap]) getOrDefault [_holdoffContractKey, -1]) > 0
}) apply {
	_x getOrDefault ["netId", ""]
};

private _recentDirectHitRecords = _recentDetonationSnapshot select {
	(_x getOrDefault ["strikePathClass", ""]) == "DIRECT_HIT"
};
private _recentFallbackSurfaceRecords = _recentDetonationSnapshot select {
	(_x getOrDefault ["strikePathClass", ""]) == "FALLBACK_SURFACE"
};
private _recentAirPolicyRecords = _recentDetonationSnapshot select {
	(_x getOrDefault ["strikePathClass", ""]) == "AIR_POLICY"
};
private _recentEmergencyFallbackRecords = _recentDetonationSnapshot select {
	(_x getOrDefault ["approvalPolicyClass", ""]) == "EMERGENCY_FALLBACK"
};
private _recentKnownBadPatternRecords = _recentDetonationSnapshot select {
	_x getOrDefault ["knownBadPattern", false]
};
private _recentDeliveryPolicyMismatchRecords = _recentDetonationSnapshot select {
	!(_x getOrDefault ["deliveryPolicyMatch", true])
};
private _recentDirectBodyRecords = _recentDetonationSnapshot select {
	(_x getOrDefault ["impactMode", ""]) == "DIRECT_BODY"
};
private _recentDirectBodyPrimaryRecords = _recentDirectBodyRecords select {
	(_x getOrDefault ["approvalPolicyClass", ""]) == "DIRECT_HIT_PRIMARY"
};
private _recentDirectHitImpactDeliveryRecords = _recentDirectHitRecords select {
	(_x getOrDefault ["deliveryMode", ""]) == "IMPACT_POINT"
};
private _recentDirectHitUavDeliveryRecords = _recentDirectHitRecords select {
	(_x getOrDefault ["deliveryMode", ""]) == "UAV_POSITION"
};
private _recentFallbackSurfaceImpactDeliveryRecords = _recentFallbackSurfaceRecords select {
	(_x getOrDefault ["deliveryMode", ""]) == "IMPACT_POINT"
};
private _recentFallbackSurfaceUavDeliveryRecords = _recentFallbackSurfaceRecords select {
	(_x getOrDefault ["deliveryMode", ""]) == "UAV_POSITION"
};
private _recentSurfacePrimaryUavDeliveryRecords = _recentFallbackSurfaceUavDeliveryRecords select {
	(_x getOrDefault ["approvalPolicyClass", ""]) == "SURFACE_PRIMARY"
};
private _recentClosureQualifiedDirectHitRecords = _recentDetonationSnapshot select {
	(_x getOrDefault ["strikePathClass", ""]) == "DIRECT_HIT" && {
		(_x getOrDefault ["detonationReason", ""]) == "CLOSURE_QUALIFIED"
	}
};
private _recentClosureQualifiedFallbackSurfaceRecords = _recentDetonationSnapshot select {
	(_x getOrDefault ["strikePathClass", ""]) == "FALLBACK_SURFACE" && {
		(_x getOrDefault ["detonationReason", ""]) == "CLOSURE_QUALIFIED"
	}
};
private _recentKnownBadPatternUavNetIds = _recentKnownBadPatternRecords apply {
	_x getOrDefault ["uavNetId", ""]
};
private _recentDeliveryPolicyMismatchUavNetIds = _recentDeliveryPolicyMismatchRecords apply {
	_x getOrDefault ["uavNetId", ""]
};
private _activeDirectHitNetIds = (_impactActiveDrones select {
	(_x getOrDefault ["terminalImpactMode", ""]) in _directHitModes
}) apply {
	_x getOrDefault ["netId", ""]
};
private _activeFallbackSurfaceNetIds = (_impactActiveDrones select {
	(_x getOrDefault ["terminalImpactMode", ""]) in _fallbackSurfaceModes
}) apply {
	_x getOrDefault ["netId", ""]
};
private _phase4TuningInvalidNetIds = (_impactActiveDrones select {
	private _profileSummary = _x getOrDefault ["profileSummary", createHashMap];
	private _bodyContact = _profileSummary getOrDefault ["directContactDistanceBody", -1];
	private _hullContact = _profileSummary getOrDefault ["directContactDistanceHull", -1];
	private _bodyTtc = _profileSummary getOrDefault ["predictedImpactMaxTimeToContactBody", -1];
	private _hullTtc = _profileSummary getOrDefault ["predictedImpactMaxTimeToContactHull", -1];
	private _directHoldoff = _profileSummary getOrDefault ["terminalImpactHoldoffDistance", -1];
	private _fallbackHoldoff = _profileSummary getOrDefault ["fallbackSurfaceHoldoffDistance", -1];
	(_bodyContact <= 0) ||
	(_hullContact < _bodyContact) ||
	(_bodyTtc <= 0) ||
	(_hullTtc < _bodyTtc) ||
	(_directHoldoff <= 0) ||
	(_fallbackHoldoff < _directHoldoff)
}) apply {
	_x getOrDefault ["netId", ""]
};

{
	private _vendorId = _x getOrDefault ["vendorId", ""];
	if !(_vendorId isEqualTo "") then {
		_terminalVectorActiveVendors pushBackUnique _vendorId;
	};

	private _siteMarker = _x getOrDefault ["siteMarker", ""];
	if !(_siteMarker isEqualTo "") then {
		_terminalVectorActiveSites pushBackUnique _siteMarker;
	};
} forEach _terminalVectorActiveDrones;

{
	private _vendorId = _x getOrDefault ["vendorId", ""];
	if !(_vendorId isEqualTo "") then {
		_impactActiveVendors pushBackUnique _vendorId;
	};

	private _siteMarker = _x getOrDefault ["siteMarker", ""];
	if !(_siteMarker isEqualTo "") then {
		_impactActiveSites pushBackUnique _siteMarker;
	};
} forEach _impactActiveDrones;

private _netIdCounts = createHashMap;
{
	_netIdCounts set [_x, (_netIdCounts getOrDefault [_x, 0]) + 1];
} forEach _managedDroneNetIds;

private _duplicateManagedNetIds = [];
{
	if (_y > 1) then {
		_duplicateManagedNetIds pushBack _x;
	};
} forEach _netIdCounts;

private _orphanManagedDroneNetIds = _managedDroneNetIds select { !(_x in _registryDroneNetIds) };
private _missingManagedDroneNetIds = _registryDroneNetIds select { !(_x in _managedDroneNetIds) };
private _nonLocalControllers = (_managedDrones select {
	(_x getOrDefault ["controllerRunning", false]) && {!(_x getOrDefault ["isLocal", false])}
}) apply { _x getOrDefault ["netId", ""] };
private _controllerOwnerMismatches = (_managedDrones select {
	(_x getOrDefault ["controllerRunning", false]) && {(_x getOrDefault ["controllerOwnerId", -1]) != (_x getOrDefault ["currentOwnerId", -1])}
}) apply { _x getOrDefault ["netId", ""] };
private _activeEmptySites = (_registrySnapshot select {
	(_x getOrDefault ["status", ""]) == "active" && {((_x getOrDefault ["droneNetIds", []]) isEqualTo [])}
}) apply { _x getOrDefault ["siteMarker", ""] };
private _bootSafetyViolation = (_loadedFamilies isEqualTo []) && {(count _registrySnapshot > 0) || {(count _managedDrones) > 0}};
private _vectorJumpViolations = (_managedDrones select {
	private _speedJump = _x getOrDefault ["terminalVectorSpeedJump", -1];
	private _dt = _x getOrDefault ["terminalVectorDt", -1];
	private _accelApplied = _x getOrDefault ["terminalVectorAccelApplied", -1];
	(_x getOrDefault ["mode", ""]) == "TERMINAL_VECTOR" && {
		_speedJump >= 0 &&
		_dt > 0 &&
		_accelApplied >= 0 &&
		(_speedJump > (((abs _accelApplied) * _dt) + 0.5))
	}
}) apply { _x getOrDefault ["netId", ""] };
private _vectorDtViolations = (_managedDrones select {
	private _dt = _x getOrDefault ["terminalVectorDt", -1];
	(_x getOrDefault ["mode", ""]) == "TERMINAL_VECTOR" && {(_dt > 0) && {(_dt < 0.004 || {_dt > 0.06})}}
}) apply { _x getOrDefault ["netId", ""] };
private _vectorTelemetryMissing = (_managedDrones select {
	(_x getOrDefault ["mode", ""]) == "TERMINAL_VECTOR" && {
		(_x getOrDefault ["isLocal", false]) && {
			(_x getOrDefault ["terminalVectorCurrentSpeed", -1]) < 0 ||
			(_x getOrDefault ["terminalVectorTargetSpeed", -1]) < 0 ||
			(_x getOrDefault ["terminalVectorDt", -1]) <= 0
		}
	}
}) apply { _x getOrDefault ["netId", ""] };
private _validImpactModes = ["DIRECT_BODY", "DIRECT_HULL", "DIRECT_STATIC", "GROUND_NEAR_TARGET", "OBSTRUCTION_SURFACE", "AIR_PROXIMITY", "NONE"];
private _impactTelemetryMissing = (_impactActiveDrones select {
	(_x getOrDefault ["isLocal", false]) && {
		private _impactMode = _x getOrDefault ["terminalImpactMode", ""];
		private _impactPoint = _x getOrDefault ["lastImpactPointASL", []];
		private _impactTargetNetId = _x getOrDefault ["lastImpactTargetNetId", ""];
		private _impactTelemetryAt = _x getOrDefault ["lastImpactTelemetryAt", -1];
		private _impactValid = _x getOrDefault ["lastImpactValid", false];
		(_impactMode isEqualTo "") ||
		(_impactTargetNetId isEqualTo "") ||
		(_impactTelemetryAt < 0) ||
		(_impactValid && {(!(_impactPoint isEqualType [])) || {count _impactPoint < 3}})
	}
}) apply { _x getOrDefault ["netId", ""] };
private _staleImpactSolutions = (_impactActiveDrones select {
	(_x getOrDefault ["isLocal", false]) && {
		private _impactTelemetryAt = _x getOrDefault ["lastImpactTelemetryAt", -1];
		private _profileSummary = _x getOrDefault ["profileSummary", createHashMap];
		private _impactTTL = _profileSummary getOrDefault ["impactSurfaceRefreshTTL", -1];
		private _allowedStaleness = if ((_impactTTL isEqualType 0) && {_impactTTL > 0}) then {
			(_impactTTL * 3) max 0.45
		} else {
			0.45
		};
		(_impactTelemetryAt < 0) || {time > (_impactTelemetryAt + _allowedStaleness)}
	}
}) apply { _x getOrDefault ["netId", ""] };
private _invalidImpactModes = (_managedDrones select {
	private _impactMode = _x getOrDefault ["terminalImpactMode", ""];
	!(_impactMode isEqualTo "") && {!(_impactMode in _validImpactModes)}
}) apply { _x getOrDefault ["netId", ""] };
private _nonLocalImpactControllers = (_impactActiveDrones select {
	(_x getOrDefault ["controllerRunning", false]) && {!(_x getOrDefault ["isLocal", false])}
}) apply { _x getOrDefault ["netId", ""] };
private _impactControllerOwnerMismatches = (_impactActiveDrones select {
	(_x getOrDefault ["controllerRunning", false]) && {(_x getOrDefault ["controllerOwnerId", -1]) != (_x getOrDefault ["currentOwnerId", -1])}
}) apply { _x getOrDefault ["netId", ""] };
private _validationWarnings = [];

if (_bootSafetyViolation) then {
	_validationWarnings pushBack "managed drones or registry entries exist while no supported FPV family is loaded";
};

if (_duplicateManagedNetIds isNotEqualTo []) then {
	_validationWarnings pushBack format ["duplicate managed drone netIds detected: %1", _duplicateManagedNetIds];
};

if (_orphanManagedDroneNetIds isNotEqualTo []) then {
	_validationWarnings pushBack format ["managed drones missing from registry: %1", _orphanManagedDroneNetIds];
};

if (_missingManagedDroneNetIds isNotEqualTo []) then {
	_validationWarnings pushBack format ["registry netIds missing from managed drone set: %1", _missingManagedDroneNetIds];
};

if (_nonLocalControllers isNotEqualTo []) then {
	_validationWarnings pushBack format ["controllers marked running on non-local drones: %1", _nonLocalControllers];
};

if (_controllerOwnerMismatches isNotEqualTo []) then {
	_validationWarnings pushBack format ["stored controllerOwnerId mismatches current owner: %1", _controllerOwnerMismatches];
};

if (_activeEmptySites isNotEqualTo []) then {
	_validationWarnings pushBack format ["active registry sites have no drones: %1", _activeEmptySites];
};

if (_vectorJumpViolations isNotEqualTo []) then {
	_validationWarnings pushBack format ["terminal vector speed jump exceeds accel envelope: %1", _vectorJumpViolations];
};

if (_vectorDtViolations isNotEqualTo []) then {
	_validationWarnings pushBack format ["terminal vector dt outside expected range: %1", _vectorDtViolations];
};

if (_vectorTelemetryMissing isNotEqualTo []) then {
	_validationWarnings pushBack format ["local terminal vector drones are missing telemetry fields: %1", _vectorTelemetryMissing];
};

if (_impactTelemetryMissing isNotEqualTo []) then {
	_validationWarnings pushBack format ["local terminal impact drones are missing telemetry fields: %1", _impactTelemetryMissing];
};

if (_staleImpactSolutions isNotEqualTo []) then {
	_validationWarnings pushBack format ["terminal impact solutions are stale beyond refresh policy: %1", _staleImpactSolutions];
};

if (_invalidImpactModes isNotEqualTo []) then {
	_validationWarnings pushBack format ["terminal impact mode values are invalid: %1", _invalidImpactModes];
};

if (_nonLocalImpactControllers isNotEqualTo []) then {
	_validationWarnings pushBack format ["impact controller activity detected on non-local drones: %1", _nonLocalImpactControllers];
};

if (_impactControllerOwnerMismatches isNotEqualTo []) then {
	_validationWarnings pushBack format ["impact controller owner mismatches detected during terminal phases: %1", _impactControllerOwnerMismatches];
};

if (_phase4TuningInvalidNetIds isNotEqualTo []) then {
	_validationWarnings pushBack format ["phase 4 direct-hit or fallback-surface tuning values are invalid on active impact drones: %1", _phase4TuningInvalidNetIds];
};

private _recentEvidenceAvailable = (count _recentDetonationSnapshot) > 0;
private _validationHealthy = _validationWarnings isEqualTo [];
private _knownBadPatternCleared = (count _recentKnownBadPatternRecords) == 0;
private _directHitDeliveryHealthy = (count _recentDirectHitUavDeliveryRecords) == 0;
private _surfaceDeliveryHealthy = (count _recentSurfacePrimaryUavDeliveryRecords) == 0;
private _directBodyEvidenceAvailable = (count _recentDirectBodyRecords) > 0;
private _directBodyPrimaryEvidenceAvailable = (count _recentDirectBodyPrimaryRecords) > 0;
private _readyForLanAcceptanceRuns = _validationHealthy;
private _acceptanceGateClear = _validationHealthy && {
	_recentEvidenceAvailable && {
		_knownBadPatternCleared && {
			_directHitDeliveryHealthy && {
				_surfaceDeliveryHealthy && {
					_directBodyPrimaryEvidenceAvailable
				}
			}
		}
	}
};
private _acceptanceStatus = switch (true) do {
	case (!_validationHealthy): {"BLOCKED_BY_VALIDATION_WARNINGS"};
	case (!_recentEvidenceAvailable): {"READY_FOR_LAN_RUNS"};
	case (_acceptanceGateClear): {"ACCEPTANCE_EVIDENCE_HEALTHY"};
	default {"NEEDS_TARGETED_LAN_VERIFICATION"};
};
private _acceptanceFocusAreas = [];

if (!_validationHealthy) then {
	_acceptanceFocusAreas pushBack "Resolve validation warnings before trusting LAN acceptance results.";
};

if (!_recentEvidenceAvailable) then {
	_acceptanceFocusAreas pushBack "Run at least one local-LAN terminal strike to populate recentDetonations evidence.";
};

if (!_directBodyEvidenceAvailable) then {
	_acceptanceFocusAreas pushBack "Run exposed infantry scenarios until recentDetonations records DIRECT_BODY impact modes.";
};

if (!_directBodyPrimaryEvidenceAvailable) then {
	_acceptanceFocusAreas pushBack "Run exposed infantry scenarios until DIRECT_BODY strikes detonate through DIRECT_CONTACT or PREDICTED_IMPACT.";
};

if (!_knownBadPatternCleared) then {
	_acceptanceFocusAreas pushBack "Recent strikes still match the known bad GROUND_NEAR_TARGET plus CLOSURE_QUALIFIED plus UAV_POSITION signature.";
};

if (!_directHitDeliveryHealthy) then {
	_acceptanceFocusAreas pushBack "Recent direct-hit records still include UAV_POSITION delivery.";
};

if (!_surfaceDeliveryHealthy) then {
	_acceptanceFocusAreas pushBack "Recent intentional surface-primary strikes still include UAV_POSITION delivery.";
};

createHashMapFromArray [
	["environment", createHashMapFromArray [
		["registrationComplete", missionNamespace getVariable ["A3UE_FPV_registrationComplete", false]],
		["registrationPending", missionNamespace getVariable ["A3UE_FPV_registrationPending", false]],
		["loadedFamilies", _loadedFamilies],
		["catalogFamilies", _catalogFamilies],
		["registryEntryCount", count _registrySnapshot],
		["managedDroneCount", count _managedDrones]
	]],
	["directContactPolicy", createHashMapFromArray [
		["phase", "PHASE_2_MODE_AWARE_FUSE"],
		["directHitModes", _directHitModes],
		["fallbackSurfaceModes", _fallbackSurfaceModes],
		["directHitPrimaryReasons", _directHitPrimaryReasons],
		["fallbackSurfacePrimaryReasons", _fallbackSurfacePrimaryReasons],
		["emergencyFallbackReasons", _emergencyFallbackReasons],
		["holdoffContractKey", _holdoffContractKey],
		["holdoffContractStatus", _holdoffContractStatus],
		["holdoffEnforcedByFuse", true],
		["supportedTuningKeys", ["directContactDistanceBody", "directContactDistanceHull", "predictedImpactMaxTimeToContactBody", "predictedImpactMaxTimeToContactHull", "directHitClosureQualifiedAllowed", "fallbackSurfaceHoldoffDistance"]],
		["knownBadPattern", createHashMapFromArray [
			["impactMode", "GROUND_NEAR_TARGET"],
			["detonationReason", "CLOSURE_QUALIFIED"],
			["deliveryMode", "UAV_POSITION"]
		]]
	]],
	["phase1EvidenceSummary", createHashMapFromArray [
		["recentDetonationCount", count _recentDetonationSnapshot],
		["recentDirectHitCount", count _recentDirectHitRecords],
		["recentFallbackSurfaceCount", count _recentFallbackSurfaceRecords],
		["recentAirPolicyCount", count _recentAirPolicyRecords],
		["recentEmergencyFallbackCount", count _recentEmergencyFallbackRecords],
		["recentKnownBadPatternCount", count _recentKnownBadPatternRecords],
		["recentKnownBadPatternUavNetIds", _recentKnownBadPatternUavNetIds],
		["recentDeliveryPolicyMismatchCount", count _recentDeliveryPolicyMismatchRecords],
		["recentDeliveryPolicyMismatchUavNetIds", _recentDeliveryPolicyMismatchUavNetIds],
		["recentClosureQualifiedDirectHitCount", count _recentClosureQualifiedDirectHitRecords],
		["recentClosureQualifiedFallbackSurfaceCount", count _recentClosureQualifiedFallbackSurfaceRecords],
		["holdoffConfiguredActiveCount", count _holdoffConfiguredImpactNetIds],
		["holdoffConfiguredActiveNetIds", _holdoffConfiguredImpactNetIds]
	]],
	["phase4IntegrationSummary", createHashMapFromArray [
		["activeDirectHitCount", count _activeDirectHitNetIds],
		["activeDirectHitNetIds", _activeDirectHitNetIds],
		["activeFallbackSurfaceCount", count _activeFallbackSurfaceNetIds],
		["activeFallbackSurfaceNetIds", _activeFallbackSurfaceNetIds],
		["phase4TuningInvalidNetIds", _phase4TuningInvalidNetIds],
		["recentDirectBodyCount", count _recentDirectBodyRecords],
		["recentDirectBodyPrimaryCount", count _recentDirectBodyPrimaryRecords],
		["recentDirectHitImpactDeliveryCount", count _recentDirectHitImpactDeliveryRecords],
		["recentDirectHitUavDeliveryCount", count _recentDirectHitUavDeliveryRecords],
		["recentFallbackSurfaceImpactDeliveryCount", count _recentFallbackSurfaceImpactDeliveryRecords],
		["recentFallbackSurfaceUavDeliveryCount", count _recentFallbackSurfaceUavDeliveryRecords],
		["recentSurfacePrimaryUavDeliveryCount", count _recentSurfacePrimaryUavDeliveryRecords],
		["recentKnownBadPatternCount", count _recentKnownBadPatternRecords]
	]],
	["phase5AcceptanceSummary", createHashMapFromArray [
		["status", _acceptanceStatus],
		["readyForLanAcceptanceRuns", _readyForLanAcceptanceRuns],
		["acceptanceGateClear", _acceptanceGateClear],
		["validationHealthy", _validationHealthy],
		["validationWarningCount", count _validationWarnings],
		["recentEvidenceAvailable", _recentEvidenceAvailable],
		["knownBadPatternCleared", _knownBadPatternCleared],
		["directHitDeliveryHealthy", _directHitDeliveryHealthy],
		["surfaceDeliveryHealthy", _surfaceDeliveryHealthy],
		["directBodyEvidenceAvailable", _directBodyEvidenceAvailable],
		["directBodyPrimaryEvidenceAvailable", _directBodyPrimaryEvidenceAvailable],
		["phase4TuningInvalidCount", count _phase4TuningInvalidNetIds],
		["recentDetonationCount", count _recentDetonationSnapshot],
		["recentDirectBodyCount", count _recentDirectBodyRecords],
		["recentDirectBodyPrimaryCount", count _recentDirectBodyPrimaryRecords],
		["recentKnownBadPatternCount", count _recentKnownBadPatternRecords],
		["recentDirectHitUavDeliveryCount", count _recentDirectHitUavDeliveryRecords],
		["recentSurfacePrimaryUavDeliveryCount", count _recentSurfacePrimaryUavDeliveryRecords],
		["focusAreas", _acceptanceFocusAreas]
	]],
	["validation", createHashMapFromArray [
		["warnings", _validationWarnings],
		["duplicateManagedNetIds", _duplicateManagedNetIds],
		["orphanManagedDroneNetIds", _orphanManagedDroneNetIds],
		["missingManagedDroneNetIds", _missingManagedDroneNetIds],
		["nonLocalControllers", _nonLocalControllers],
		["controllerOwnerMismatches", _controllerOwnerMismatches],
		["activeEmptySites", _activeEmptySites],
		["bootSafetyViolation", _bootSafetyViolation],
		["vectorJumpViolations", _vectorJumpViolations],
		["vectorDtViolations", _vectorDtViolations],
		["vectorTelemetryMissing", _vectorTelemetryMissing],
		["impactTelemetryMissing", _impactTelemetryMissing],
		["staleImpactSolutions", _staleImpactSolutions],
		["invalidImpactModes", _invalidImpactModes],
		["nonLocalImpactControllers", _nonLocalImpactControllers],
		["impactControllerOwnerMismatches", _impactControllerOwnerMismatches]
	]],
	["terminalVectorSummary", createHashMapFromArray [
		["activeCount", count _terminalVectorActiveNetIds],
		["activeNetIds", _terminalVectorActiveNetIds],
		["localCount", count _terminalVectorLocalNetIds],
		["localNetIds", _terminalVectorLocalNetIds],
		["telemetryReadyCount", count _terminalVectorTelemetryReadyNetIds],
		["telemetryReadyNetIds", _terminalVectorTelemetryReadyNetIds],
		["activeVendors", _terminalVectorActiveVendors],
		["activeSites", _terminalVectorActiveSites]
	]],
	["impactSummary", createHashMapFromArray [
		["activeCount", count _impactActiveNetIds],
		["activeNetIds", _impactActiveNetIds],
		["localCount", count _impactLocalNetIds],
		["localNetIds", _impactLocalNetIds],
		["telemetryReadyCount", count _impactTelemetryReadyNetIds],
		["telemetryReadyNetIds", _impactTelemetryReadyNetIds],
		["activeVendors", _impactActiveVendors],
		["activeSites", _impactActiveSites],
		["recentDetonationCount", count _recentDetonationSnapshot]
	]],
	["recentDetonations", _recentDetonationSnapshot],
	["registry", _registrySnapshot],
	["managedDrones", _managedDrones]
]