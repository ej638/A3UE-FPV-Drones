private _registry = missionNamespace getVariable ["A3UE_FPV_registry", createHashMap];
private _registrySnapshot = [];
private _loadedMods = missionNamespace getVariable ["A3UE_FPV_loadedMods", createHashMap];
private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
private _loadedFamilies = [];
private _catalogFamilies = [];

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
		["terminalSpeed", _profile getOrDefault ["terminalSpeed", -1]],
		["terminalGateDistance", _profile getOrDefault ["terminalGateDistance", -1]],
		["terminalSteeringDistance", _profile getOrDefault ["terminalSteeringDistance", -1]],
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

createHashMapFromArray [
	["environment", createHashMapFromArray [
		["registrationComplete", missionNamespace getVariable ["A3UE_FPV_registrationComplete", false]],
		["registrationPending", missionNamespace getVariable ["A3UE_FPV_registrationPending", false]],
		["loadedFamilies", _loadedFamilies],
		["catalogFamilies", _catalogFamilies],
		["registryEntryCount", count _registrySnapshot],
		["managedDroneCount", count _managedDrones]
	]],
	["validation", createHashMapFromArray [
		["warnings", _validationWarnings],
		["duplicateManagedNetIds", _duplicateManagedNetIds],
		["orphanManagedDroneNetIds", _orphanManagedDroneNetIds],
		["missingManagedDroneNetIds", _missingManagedDroneNetIds],
		["nonLocalControllers", _nonLocalControllers],
		["controllerOwnerMismatches", _controllerOwnerMismatches],
		["activeEmptySites", _activeEmptySites],
		["bootSafetyViolation", _bootSafetyViolation]
	]],
	["registry", _registrySnapshot],
	["managedDrones", _managedDrones]
]