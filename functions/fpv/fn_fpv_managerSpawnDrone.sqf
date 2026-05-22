// Site-specific wrapper around A3UE_fnc_fpv_spawnManagedDrone.
//
// Handles site-bound role selection with weighted fallback, spawn position
// computation from the site marker, and site-side crew initialization through
// A3A_fnc_NATOinit.  Delegates all vehicle creation, metadata stamping, crew
// creation, and init path to the generic helper.

params ["_markerX", "_locationType", ["_profile", createHashMap], ["_siteSide", sideUnknown], ["_familyId", ""]];

if (!isServer) exitWith {objNull};
if (_familyId isEqualTo "") exitWith {objNull};

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

	if (_resolvedClass isEqualTo "") exitWith {objNull};
};

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

private _spawnPosATL = +_spawnPos;
_spawnPosATL set [2, _spawnHeight];

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
	["vehicleInitMode",    "AIVEHINIT"],
	["resourcePool",       "defence"],
	["crewFactory", {
		params ["_side", "_uav"];
		if (!isNil "A3A_fnc_createVehicleCrew") then {
			[_side, _uav] call A3A_fnc_createVehicleCrew
		} else {
			createVehicleCrew _uav;
			if (crew _uav isNotEqualTo []) then {
				group ((crew _uav) select 0)
			} else {
				grpNull
			}
		}
	}],
	["postCrewInit", {
		params ["_uav", "_crewGroup"];
		if (!isNil "A3A_fnc_NATOinit" && {!isNull _crewGroup}) then {
			private _marker = _uav getVariable ["A3UE_FPV_siteMarker", ""];
			{[_x, _marker, false, "defence"] call A3A_fnc_NATOinit} forEach (units _crewGroup);
		};
	}]
];

[_spec] call A3UE_fnc_fpv_spawnManagedDrone