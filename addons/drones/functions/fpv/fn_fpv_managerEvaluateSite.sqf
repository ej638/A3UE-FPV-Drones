params ["_markerX", "_locationType", "_isSpawning"];

if (!isServer) exitWith {false};
// Site RPCs enter receiveSiteIntent; the local queue owns spawning and cleanup.
if (isRemoteExecutedJIP || {isRemoteExecuted && {remoteExecutedOwner != 2}}) exitWith {false};

private _siteType = [_markerX, _locationType] call A3UE_fnc_fpv_resolveSiteType;
if (_siteType isEqualTo "") exitWith {false};
_locationType = _siteType;

private _registry = missionNamespace getVariable ["A3UE_FPV_registry", createHashMap];
private _existingEntry = _registry getOrDefault [_markerX, createHashMap];

if (!_isSpawning) exitWith {
	private _state = (missionNamespace getVariable ["A3UE_FPV_siteLifecycle", createHashMap]) getOrDefault [_markerX, createHashMap];
	private _pending = _state getOrDefault ["cleanupDrones", []];
	private _returned = 0;
	{
		if (!isNull _x) then {
			// Intact, still-managed drones go back into the site's stock (FS-04).
			if (alive _x && {_x getVariable ["A3UE_FPV_managed", false]} && {[_x] call A3UE_fnc_fpv_isSiteDroneActive}) then {
				_returned = _returned + 1;
			};
			_pending pushBackUnique _x;
			[_x, true] call A3UE_fnc_fpv_cleanupDrone;
		};
	} forEach (_existingEntry getOrDefault ["drones", []]);
	_state set ["cleanupDrones", _pending];
	if (_state getOrDefault ["captured", false]) then {
		["CLEAR", _markerX] call A3UE_fnc_fpv_siteStock;
	} else {
		if (_returned > 0) then {
			["RETURN", _markerX, _existingEntry getOrDefault ["siteSide", sideUnknown], _returned] call A3UE_fnc_fpv_siteStock;
		};
	};

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

if (!(missionNamespace getVariable ["A3UE_FPV_siteReady", false]) || {isNil "sidesX"}) exitWith {false};
private _siteSide = sidesX getVariable [_markerX, sideUnknown];

private _allowedSides = [];
if (!isNil "Occupants") then {
	_allowedSides pushBack Occupants;
};

if (!isNil "Invaders") then {
	_allowedSides pushBack Invaders;
};

if (_siteSide == sideUnknown || {!(_siteSide in _allowedSides)}) exitWith {false};

private _familyId = [_markerX, _locationType, _siteSide] call A3UE_fnc_fpv_selectFamilyForSite;
if (_familyId isEqualTo "") exitWith {false};

private _profileId = _profile getOrDefault ["profileId", format ["site_%1_default", toLower _locationType]];
// FS-04: spawn chance and stock are rolled once per side holding the site, then
// depleted by losses and refilled slowly, instead of re-rolled every activation.
(["OPEN", _markerX, _siteSide, _profile] call A3UE_fnc_fpv_siteStock) params [
	["_available", 0], ["_stockMax", 0], ["_skipped", true], ["_spawnRoll", 1]];

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

if (_skipped || {_available <= 0}) exitWith {
	_entry set ["status", ["depleted", "skipped"] select _skipped];
	_registry set [_markerX, _entry];
	missionNamespace setVariable ["A3UE_FPV_registry", _registry];
	[_markerX, _locationType, _profile, _siteSide, _familyId, 0, _entry, "activation"] call A3UE_fnc_fpv_managerDeployStock;
	true
};

_entry set ["plannedCount", _available];
_registry set [_markerX, _entry];
missionNamespace setVariable ["A3UE_FPV_registry", _registry];
[_markerX, _locationType, _profile, _siteSide, _familyId, _available, _entry, "activation"] call A3UE_fnc_fpv_managerDeployStock;

(_entry getOrDefault ["drones", []]) isNotEqualTo []
