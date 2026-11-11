// Site-specific wrapper around A3UE_fnc_fpv_spawnManagedDrone.
//
// Handles site-bound role selection with weighted fallback, spawn position
// computation from the site marker, and site-side crew initialization through
// A3A_fnc_NATOinit.  Delegates all vehicle creation, metadata stamping, crew
// creation, and init path to the generic helper.

// _placement (optional hashmap): in "threats" (hostile positions, gathered here when
// absent); out "mode" (DIRECT/STANDOFF/BLOCKED), "nearestHostile" (m, -1 none),
// "reason" ("STANDOFF" when no clear launch point), "spawnPosATL".
params ["_markerX", "_locationType", ["_profile", createHashMap], ["_siteSide", sideUnknown], ["_familyId", ""],
	["_placement", createHashMap]];

if (!isServer) exitWith {objNull};
if (_familyId isEqualTo "") exitWith {objNull};
if !(_placement isEqualType createHashMap) then {_placement = createHashMap;};

// --- Catalog validation -------------------------------------------------------
private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) then {
	_catalog = call A3UE_fnc_fpv_buildCompatCatalog;
};

private _familyData = _catalog getOrDefault [_familyId, createHashMap];
if (count _familyData == 0) exitWith {objNull};

// --- Weighted role selection with fallback ------------------------------------
private _sideKey = switch (_siteSide) do {
	case east:        { "east" };
	case west:        { "west" };
	case independent: { "independent" };
	default           { "east" };
};

private _classPools  = _profile getOrDefault ["classPools",  createHashMap];
private _sitePools   = _classPools getOrDefault [_sideKey,   createHashMap];
private _familyPools = _sitePools  getOrDefault [_familyId,  createHashMap];

private _roleWeights   = _profile getOrDefault ["roleWeights", createHashMap];
private _weightedRoles = [];

{
	private _roleId  = _x;
	private _entries = _familyPools getOrDefault [_roleId, []];

	if (_entries isNotEqualTo []) then {
		private _weight = (_roleWeights getOrDefault [_roleId, 0]) max 1;
		_weightedRoles pushBack [_roleId, _weight];
	};
} forEach ["AT", "AP", "RECON"];

private _pickWeightedValue = {
	params ["_entries"];

	if (_entries isEqualTo []) exitWith {""};

	private _totalWeight = 0;
	{_totalWeight = _totalWeight + ((_x param [1, 0]) max 0)} forEach _entries;

	if (_totalWeight <= 0) exitWith {(_entries select 0) param [0, ""]};

	private _roll = random _totalWeight;
	private _selection = "";
	{
		_roll = _roll - ((_x param [1, 0]) max 0);
		if (_roll <= 0) exitWith {_selection = _x param [0, ""]};
	} forEach _entries;

	if (_selection isEqualTo "") then {
		_selection = (_entries select ((count _entries) - 1)) param [0, ""];
	};

	_selection
};

private _payloadRole = [_weightedRoles] call _pickWeightedValue;
if (_payloadRole isEqualTo "") exitWith {objNull};

// Verify the selected role resolves to a valid class; try other roles as fallback.
private _resolvedClass = [_familyId, _payloadRole, _siteSide, _locationType] call A3UE_fnc_fpv_selectClassForRole;
if (_resolvedClass isEqualTo "") then {
	{
		private _roleId        = _x param [0, ""];
		private _candidateClass = [_familyId, _roleId, _siteSide, _locationType] call A3UE_fnc_fpv_selectClassForRole;
		if (_candidateClass isNotEqualTo "") exitWith {
			_payloadRole  = _roleId;
			_resolvedClass = _candidateClass;
		};
	} forEach _weightedRoles;
};
if (_resolvedClass isEqualTo "") exitWith {objNull};

// --- Spawn position -----------------------------------------------------------
private _spawnCenter = getMarkerPos _markerX;
private _spawnBand   = switch (_locationType) do {
	case "Airport": { [50, 100] };
	case "Milbase": { [40, 90]  };
	case "Seaport": { [30, 85]  };
	case "Outpost": { [20, 70]  };
	case "Factory": { [15, 60]  };
	default         { [10, 50]  };
};

private _spawnPos = if (!isNil "A3A_fnc_getSafePos") then {
	[_spawnCenter, _spawnBand # 0, _spawnBand # 1, 2, 0, -1, 0] call A3A_fnc_getSafePos
} else {
	_spawnCenter getPos [(_spawnBand # 0) + random ((_spawnBand # 1) - (_spawnBand # 0)), random 360]
};

private _spawnHeight = switch (_locationType) do {
	case "Airport": { 45 };
	case "Milbase": { 40 };
	case "Seaport": { 32 };
	case "Outpost": { 35 };
	case "Factory": { 28 };
	default         { 25 };
};

// FS-03 launch standoff: keep the band point unless hostile players are within the
// standoff; then launch from the far side and fly in. Never spawn overhead.
private _threats = if ("threats" in _placement) then {_placement get "threats"} else {[_siteSide] call A3UE_fnc_fpv_standoffThreats};
private _standoff = [_spawnCenter, _spawnPos, _threats,
	createHashMapFromArray [["minOffset", _spawnBand # 0], ["height", _spawnHeight]]] call A3UE_fnc_fpv_launchStandoff;
_placement set ["mode", _standoff # 1];
_placement set ["nearestHostile", _standoff # 2];
if ((_standoff # 1) == "BLOCKED") exitWith {
	_placement set ["reason", "STANDOFF"];
	objNull
};
private _displaced = (_standoff # 1) == "STANDOFF";
if (_displaced) then {_spawnPos = _standoff # 0;};

private _spawnPosATL = +_spawnPos;
_spawnPosATL set [2, _spawnHeight];
_placement set ["spawnPosATL", +_spawnPosATL];

// --- Build spec and delegate to generic helper --------------------------------
private _profileId = _profile getOrDefault ["profileId", format ["site_%1_default", toLower _locationType]];

private _spec = createHashMapFromArray [
	["spawnPosATL",        _spawnPosATL],
	["searchAnchorMarker", _markerX],
	["siteType",           _locationType],
	["profileId",          _profileId],
	["side",               _siteSide],
	["familyId",           _familyId],
	["payloadRole",        _payloadRole],
	["uavClass",           _resolvedClass],
	["vehicleInitMode",    "AIVEHINIT"],
	// Ambient site stock is unpaid: AU charges legacy losses, never refunds it.
	["resourcePool",       "legacy"],
	// No crewFactory: the generic helper's default creates the owned UAV crew group (F5).
	["postCrewInit", {
		params ["_uav", "_crewGroup", "_resourcePool"];
		if (!isNil "A3A_fnc_NATOinit" && {!isNull _crewGroup}) then {
			// Virtual UAV crew are transient assets, not human site garrisons.
			// Keep AU loss accounting without markerChange's surrenderAction route.
			{[_x, "", false, _resourcePool] call A3A_fnc_NATOinit} forEach (units _crewGroup);
		};
	}]
];

// A displaced launch keeps the radio node and KVN fiber anchor at the site.
if (_displaced) then {
	_spec set ["controlPosATL", [_spawnCenter # 0, _spawnCenter # 1, _spawnHeight]];
	_spec set ["fiberAnchorPos", [_spawnCenter # 0, _spawnCenter # 1, 0.5]];
	_spec set ["launchDir", ((_spawnCenter # 0) - (_spawnPos # 0)) atan2 ((_spawnCenter # 1) - (_spawnPos # 1))];
};

private _uav = [_spec] call A3UE_fnc_fpv_spawnManagedDrone;
if (!isNull _uav) then {
	_uav setVariable ["A3UE_FPV_siteEpoch", A3UE_FPV_siteEpoch, true];
	_uav setVariable ["A3UE_FPV_siteSide", _siteSide, true];
};
_uav
