// Executes an A3UE-managed FPV rival strike behind the wrapped UAVGRENADE handler.
//
// Called by A3UE_fnc_fpv_rivalsUavFlyby when A3UE managed FPV is available and
// stock rival UAVs are absent.  Runs on the server inside a scheduled environment
// (the AU rival event loop dispatches via A3A_fnc_scheduler).
//
// Drone count by inactivityLevelRivals:
//   INTRUSIVE_ACTIVITY  (2)  ->  1..2 drones
//   OMNIPRESENT_ACTIVITY (1) ->  2..4 drones, hard cap 4
//
// Outputs:
//   A3UE_FPV_rivalsActiveEvent  - transient event state hashmap (cleared on completion)
//
// State cleanup always runs before the function exits, including on all early failure paths.

params [["_overridePosition", []]];

if (!isServer) exitWith {};
// Managed Rivals remains a server route; reject before marker/AU state mutation.
if (isRemoteExecutedJIP || {isRemoteExecuted && {remoteExecutedOwner != 2}}) exitWith {call A3UE_fnc_fpv_rejectLifecycle;};

private _eventId = format ["rivfpv_%1_%2", round time, round (random 9999)];

// --- 1. Resolve attack origin -----------------------------------------------
// Prefer caller-supplied override; fall back to AU's player-context finder.
private _originPos = [];
if (_overridePosition isNotEqualTo []) then {
	_originPos = _overridePosition;
} else {
	if (!isNil "SCRT_fnc_rivals_findSuitableEncounterPosition") then {
		_originPos = [] call SCRT_fnc_rivals_findSuitableEncounterPosition;
	};
};

if (_originPos isEqualTo []) exitWith {
	diag_log "[A3UE_FPV] rivalsEventExecute: No suitable encounter position. Resetting rival state.";
	isRivalEventInProgress = false;
	publicVariableServer "isRivalEventInProgress";
	rivalEventCooldown = 300;
	publicVariableServer "rivalEventCooldown";
};

// --- 2. Compute launch / control position (900..1400m behind target area) ---
private _launchDir  = random 360;
private _launchDist = 900 + (random 500);
private _launchPosWorld = [_originPos, _launchDist, _launchDir] call BIS_fnc_relPos;

// Ask Arma for a safe ground point near the computed launch direction.
private _safeLaunchGround = [
	_launchPosWorld, 0, 200, 5, 0, 0.5, 0, [], [_launchPosWorld, _launchPosWorld]
] call BIS_fnc_findSafePos;

if (_safeLaunchGround isEqualTo []) then {
	_safeLaunchGround = _launchPosWorld;
};

private _spawnHeight   = 40 + (random 20);
private _launchPosATL  = [_safeLaunchGround # 0, _safeLaunchGround # 1, _spawnHeight];

// --- 3. Create hidden global search-anchor marker at origin area -------------
// Global so that getMarkerPos works on any machine that may own the controller.
private _markerName = format ["A3UE_FPV_rivals_%1", _eventId];
createMarker [_markerName, _originPos];
_markerName setMarkerType  "EMPTY";
_markerName setMarkerAlpha 0;
_markerName setMarkerText  "";

// --- 4. Determine drone count from inactivityLevelRivals --------------------
private _level = if (isNil "inactivityLevelRivals") then { 2 } else { inactivityLevelRivals };

private _droneCount = switch (true) do {
	case (_level <= 1): {
		// OMNIPRESENT_ACTIVITY: 2..4, hard cap 4
		(round (random [2, 3, 4])) min 4
	};
	case (_level <= 2): {
		// INTRUSIVE_ACTIVITY: 1..2
		round (random [1, 1.5, 2])
	};
	default { 1 };
};

_droneCount = (_droneCount max 1) min 4;

// --- 5. Resolve rival side and matching doctrine key ------------------------
private _rivalSide = if (isNil "Rivals") then { east } else { Rivals };
private _sideKey = switch (_rivalSide) do {
	case east:        { "east" };
	case west:        { "west" };
	case independent: { "independent" };
	default           { "east" };
};

private _doctrine = missionNamespace getVariable ["A3UE_FPV_doctrine", createHashMap];
if (count _doctrine == 0) then {
	_doctrine = call A3UE_fnc_fpv_buildDoctrine;
};

private _rivalsEntry  = _doctrine getOrDefault ["RivalsSupport", createHashMap];
private _familyWeights = _rivalsEntry getOrDefault ["familyWeights", createHashMap];
private _roleWeights   = _rivalsEntry getOrDefault ["roleWeights",   createHashMap];
private _classPools    = _rivalsEntry getOrDefault ["classPools",    createHashMap];
private _sidePools     = _classPools  getOrDefault [_sideKey,        createHashMap];

// Build weighted family pool filtered to families that have usable side class pools.
private _familyPool = [];
{
	private _familyId = _x;
	private _weight   = _familyWeights getOrDefault [_familyId, 0];
	if (_weight > 0 && { count (_sidePools getOrDefault [_familyId, createHashMap]) > 0 }) then {
		_familyPool pushBack [_familyId, _weight];
	};
} forEach ["armafpv", "fpv_ua", "kvn"];

if (_familyPool isEqualTo []) exitWith {
	diag_log "[A3UE_FPV] rivalsEventExecute: No usable FPV families in RivalsSupport doctrine. Resetting rival state.";
	deleteMarker _markerName;
	isRivalEventInProgress = false;
	publicVariableServer "isRivalEventInProgress";
	rivalEventCooldown = 300;
	publicVariableServer "rivalEventCooldown";
};

// Weighted selection helper private to this function.
private _fnc_weightedPick = {
	params ["_pool"];
	if (_pool isEqualTo []) exitWith {""};
	private _totalW = 0;
	{ _totalW = _totalW + ((_x param [1, 0]) max 0) } forEach _pool;
	if (_totalW <= 0) exitWith { (_pool select 0) param [0, ""] };
	private _roll   = random _totalW;
	private _result = "";
	{
		_roll = _roll - ((_x param [1, 0]) max 0);
		if (_roll <= 0) exitWith { _result = _x param [0, "" ] };
	} forEach _pool;
	if (_result isEqualTo "") then { _result = (_pool select ((count _pool) - 1)) param [0, ""] };
	_result
};

// --- 6. Pre-seed target near origin (optional) -------------------------------
// Look for hostile (rebel) units nearby.  A seeded target arms drones with
// TRACKING mode from first spawn, shortening the approach time.
private _seedTarget = objNull;
private _nearHostiles = (_originPos nearEntities [["Man", "Car", "Tank", "Armored_Car", "APC", "Tank_F", "Wheeled_APC_F"], 250]) select {
	alive _x && { side _x in [west, teamPlayer] } && { !(_x getVariable ["A3UE_FPV_managed", false]) }
};
if (_nearHostiles isNotEqualTo []) then {
	_seedTarget = selectRandom _nearHostiles;
};

// --- 7. Rival crew post-init callback (Section 3A of design document) --------
// Engine-created UAV crew (via createVehicleCrew inside RivalsCreateVehicleCrew)
// does not automatically receive isRival, unitType, or AU unit handlers.
// This callback stamps those fields and calls A3A_fnc_NATOinit per unit.
private _rivalPostCrewInit = {
	params ["_uav", "_crewGroup"];

	private _crewType = "";
	if (!isNil "A3A_fnc_RivalsCrewTypeForVehicle") then {
		_crewType = [Rivals, _uav] call A3A_fnc_RivalsCrewTypeForVehicle;
	};

	{
		private _unit = _x;

		if (!(_unit getVariable ["isRival", false])) then {
			_unit setVariable ["isRival", true];
		};

		private _existingType = _unit getVariable ["unitType", ""];
		if (_existingType isEqualTo "" && { _crewType isNotEqualTo "" }) then {
			_unit setVariable ["unitType", _crewType];
		};

		// Run AU unit init: installs killed/deleted handlers, rival identity and
		// skill, and AIInit.  Empty-marker + non-spawner matches the legacy call
		// convention used in rival wandering-group and scrt trySpawn paths.
		if (!isNil "A3A_fnc_NATOinit") then {
			[_unit, "", false] call A3A_fnc_NATOinit;
		};
	} forEach (crew _uav);
};

// --- 8. Spawn each managed drone --------------------------------------------
private _spawnedDrones = [];

for "_i" from 0 to (_droneCount - 1) do {
	// Small stagger to avoid creating all vehicles in the same frame.
	if (_i > 0) then { sleep 1.5 };

	private _familyId = [_familyPool] call _fnc_weightedPick;
	if (_familyId isEqualTo "") then { continue };

	// Role selection: weighted by doctrine, only for roles that have class entries.
	private _familyRolePools = _sidePools getOrDefault [_familyId, createHashMap];
	private _rolePool = [];
	{
		private _roleId = _x;
		if (count (_familyRolePools getOrDefault [_roleId, []]) > 0) then {
			private _roleWeight = _roleWeights getOrDefault [_roleId, 0];
			if (_roleWeight > 0) then {
				_rolePool pushBack [_roleId, _roleWeight];
			};
		};
	} forEach ["AT", "AP", "RECON"];

	if (_rolePool isEqualTo []) then { continue };

	private _payloadRole = [_rolePool] call _fnc_weightedPick;
	if (_payloadRole isEqualTo "") then { continue };

	private _initialMode = if (isNull _seedTarget) then { "IDLE" } else { "TRACKING" };

	private _spec = createHashMapFromArray [
		["spawnPosATL",        _launchPosATL],
		["searchAnchorMarker", _markerName],
		["controlPosATL",      _launchPosATL],
		["fiberAnchorPos",     [_launchPosATL # 0, _launchPosATL # 1, 0.5]],
		["siteType",           "RivalsSupport"],
		["profileId",          "rivals_support_default"],
		["side",               _rivalSide],
		["targetSide",         teamPlayer],
		["familyId",           _familyId],
		["payloadRole",        _payloadRole],
		["crewFactory",        {
			params ["_side", "_uav"];
			[_side, _uav] call A3A_fnc_RivalsCreateVehicleCrew
		}],
		["postCrewInit",       _rivalPostCrewInit],
		["vehicleInitMode",    "DIRECT_BOOTSTRAP"],
		["initialMode",        _initialMode],
		["eventId",            _eventId]
	];

	if (!isNull _seedTarget && { alive _seedTarget }) then {
		_spec set ["seedTarget", _seedTarget];
	};

	private _uav = _spec call A3UE_fnc_fpv_spawnManagedDrone;

	if (!isNull _uav) then {
		_spawnedDrones pushBack _uav;
		diag_log format [
			"[A3UE_FPV] rivalsEventExecute: spawned drone %1 (%2/%3) family=%4 role=%5 mode=%6.",
			netId _uav, _i + 1, _droneCount, _familyId, _payloadRole, _initialMode
		];
	} else {
		diag_log format [
			"[A3UE_FPV] rivalsEventExecute: spawnManagedDrone returned null for drone %1/%2 family=%3 role=%4.",
			_i + 1, _droneCount, _familyId, _payloadRole
		];
	};
};

// Fail-closed: no drones spawned means nothing to orchestrate.
if (_spawnedDrones isEqualTo []) exitWith {
	diag_log "[A3UE_FPV] rivalsEventExecute: No drones were spawned. Resetting rival state.";
	deleteMarker _markerName;
	isRivalEventInProgress = false;
	publicVariableServer "isRivalEventInProgress";
	rivalEventCooldown = 300;
	publicVariableServer "rivalEventCooldown";
};

// --- 9. Store transient event state -----------------------------------------
private _eventState = createHashMapFromArray [
	["eventId",      _eventId],
	["originPosATL", _originPos],
	["launchPosATL", _launchPosATL],
	["searchMarker", _markerName],
	["drones",       _spawnedDrones],
	["startedAt",    serverTime],
	["notified",     false],
	["hookMode",     "WRAPPED_UAVGRENADE"]
];

missionNamespace setVariable ["A3UE_FPV_rivalsActiveEvent", _eventState];

diag_log format [
	"[A3UE_FPV] rivalsEventExecute: event %1 active with %2/%3 drones at level %4.",
	_eventId, count _spawnedDrones, _droneCount, _level
];

// --- 10. Notification monitor (spawned fiber at 0.5s resolution) ------------
// Fires RivalsActivityDetected once when the first drone approaches the target area
// or enters an active engagement state.  Description text is resolved from
// STR_A3UE_FPV_RIVALS_ACTIVITY_DESCRIPTION in stringtable.xml; a bounded literal
// fallback is kept in case the key is absent at runtime.
private _fpvActivityDescription = localize "STR_A3UE_FPV_RIVALS_ACTIVITY_DESCRIPTION";
if (_fpvActivityDescription isEqualTo "") then {
	_fpvActivityDescription = "Hostile FPV drones inbound.";
};

[_spawnedDrones, _originPos, _eventId, time + 600, _fpvActivityDescription] spawn {
	params ["_drones", "_origin", "_evtId", "_deadline", "_activityDescription"];

	while { time < _deadline } do {
		sleep 0.5;

		private _state = missionNamespace getVariable ["A3UE_FPV_rivalsActiveEvent", createHashMap];
		if (count _state == 0)                                      exitWith {};
		if ((_state getOrDefault ["eventId", ""]) != _evtId)       exitWith {};
		if (_state getOrDefault ["notified", false])                exitWith {};

		private _alive = _drones select { !isNull _x && { alive _x } };
		if (_alive isEqualTo []) exitWith {};

		private _shouldNotify = (_alive findIf {
			(_x distance2D _origin < 600) || {
				(_x getVariable ["A3UE_FPV_mode", "IDLE"]) in [
					"TRACKING", "TERMINAL_ATTACK", "TERMINAL_VECTOR"
				]
			}
		}) != -1;

		if (_shouldNotify) then {
			{
				[
					"RivalsActivityDetected",
					[
						format [localize "STR_rivals_activity_header", A3A_faction_riv get "name"],
						_activityDescription
					]
				] remoteExec ["BIS_fnc_showNotification", _x];
			} forEach ((call BIS_fnc_listPlayers) select {
				side _x in [teamPlayer, civilian] && {
					(position _x) distance2D _origin < 200
				}
			});

			// Update notified flag in the active-event state.
			// The while loop guard at the top of the next tick will detect
			// notified = true and exit cleanly without needing exitWith here.
			private _updState = missionNamespace getVariable ["A3UE_FPV_rivalsActiveEvent", createHashMap];
			if (count _updState > 0 && { (_updState getOrDefault ["eventId", ""]) isEqualTo _evtId }) then {
				_updState set ["notified", true];
				missionNamespace setVariable ["A3UE_FPV_rivalsActiveEvent", _updState];
			};
		};
	};
};

// --- 11. Wait for timeout or full depletion ---------------------------------
private _eventTimeout = time + 600;
waitUntil {
	sleep 5;
	(time > _eventTimeout) || {
		(_spawnedDrones findIf { !isNull _x && { alive _x } }) == -1
	}
};

// --- 12. Cleanup: surviving drones, hidden marker, transient state ----------
{
	if (!isNull _x && { alive _x }) then {
		// cleanupDrone handles crew deletion and vehicle deletion; unregisterDrone
		// is a safe no-op when the drone is not in the site registry.
		if (!isNil "A3UE_fnc_fpv_cleanupDrone") then {
			[_x] call A3UE_fnc_fpv_cleanupDrone;
		} else {
			{ deleteVehicleCrew _x } forEach (crew _x);
			deleteVehicle _x;
		};
	};
} forEach _spawnedDrones;

deleteMarker _markerName;
missionNamespace setVariable ["A3UE_FPV_rivalsActiveEvent", nil];

// --- 13. Restore AU rival state ---------------------------------------------
isRivalEventInProgress = false;
publicVariableServer "isRivalEventInProgress";

rivalEventCooldown = if (!isNil "SCRT_fnc_rivals_getEventCooldown") then {
	[] call SCRT_fnc_rivals_getEventCooldown
} else {
	300
};
publicVariableServer "rivalEventCooldown";

diag_log format ["[A3UE_FPV] rivalsEventExecute: event %1 complete.", _eventId];
