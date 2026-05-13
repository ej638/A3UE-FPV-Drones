params ["_markerX", "_locationType", "_isSpawning"];

if (!isServer) exitWith {false};

private _siteType = [_markerX, _locationType] call A3UE_fnc_fpv_resolveSiteType;
if (_siteType isEqualTo "") exitWith {false};
_locationType = _siteType;

private _registry = missionNamespace getVariable ["A3UE_FPV_registry", createHashMap];
private _existingEntry = _registry getOrDefault [_markerX, createHashMap];

if (!_isSpawning) exitWith {
	{
		[_x] call A3UE_fnc_fpv_cleanupDrone;
	} forEach (_existingEntry getOrDefault ["drones", []]);

	_registry deleteAt _markerX;
	missionNamespace setVariable ["A3UE_FPV_registry", _registry];
	true
};

if (count _existingEntry > 0) exitWith {false};

private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) then {
	_catalog = call A3UE_fnc_fpv_buildCompatCatalog;
};

private _doctrine = missionNamespace getVariable ["A3UE_FPV_doctrine", createHashMap];
if (count _doctrine == 0) then {
	_doctrine = call A3UE_fnc_fpv_buildDoctrine;
};

private _profile = _doctrine getOrDefault [_locationType, createHashMap];
if (count _profile == 0) exitWith {false};

private _siteSide = sideUnknown;
if (!isNil "sidesX") then {
	_siteSide = sidesX getVariable [_markerX, sideUnknown];
};

private _allowedSides = [];
if (!isNil "Occupants") then {
	_allowedSides pushBack Occupants;
};

if (!isNil "Invaders") then {
	_allowedSides pushBack Invaders;
};

if (_siteSide == sideUnknown) then {
	if (_allowedSides isNotEqualTo []) then {
		_siteSide = _allowedSides select 0;
	} else {
		_siteSide = east;
	};
};

if (_allowedSides isNotEqualTo [] && {!(_siteSide in _allowedSides)}) exitWith {false};

private _familyId = [_markerX, _locationType, _siteSide] call A3UE_fnc_fpv_selectFamilyForSite;
if (_familyId isEqualTo "") exitWith {false};

private _profileId = _profile getOrDefault ["profileId", format ["site_%1_default", toLower _locationType]];
private _debugEnabled = missionNamespace getVariable ["A3UE_FPV_debug", false];
private _spawnChance = [_profile, "spawnChance", 1] call A3UE_fnc_fpv_profileValue;
private _spawnRoll = if (_debugEnabled) then {0} else {random 1};

private _entry = createHashMapFromArray [
	["siteType", _locationType],
	["profileId", _profileId],
	["siteSide", _siteSide],
	["selectedFamily", _familyId],
	["drones", []],
	["spawnRoll", _spawnRoll],
	["plannedCount", 0],
	["lastRoll", serverTime],
	["status", "registered"]
];

if (_spawnRoll > _spawnChance) exitWith {
	_entry set ["status", "skipped"];
	_registry set [_markerX, _entry];
	missionNamespace setVariable ["A3UE_FPV_registry", _registry];
	true
};

private _stockRange = [_profile, "stock", [1, 1]] call A3UE_fnc_fpv_profileValue;
private _stockMin = ((_stockRange param [0, 1]) max 1);
private _stockMax = ((_stockRange param [1, _stockMin]) max _stockMin);
private _spawnCount = _stockMin;

if (_stockMax > _stockMin) then {
	_spawnCount = _stockMin + floor (random ((_stockMax - _stockMin) + 1));
};

_entry set ["plannedCount", _spawnCount];

private _spawnedDrones = [];
for "_index" from 1 to _spawnCount do {
	private _uav = [_markerX, _locationType, _profile, _siteSide, _familyId] call A3UE_fnc_fpv_managerSpawnDrone;
	if (!isNull _uav) then {
		_spawnedDrones pushBack _uav;
	};
};

_entry set ["drones", _spawnedDrones];
_entry set ["status", ["spawn_failed", "active"] select (_spawnedDrones isNotEqualTo [])];

_registry set [_markerX, _entry];
missionNamespace setVariable ["A3UE_FPV_registry", _registry];

_spawnedDrones isNotEqualTo []