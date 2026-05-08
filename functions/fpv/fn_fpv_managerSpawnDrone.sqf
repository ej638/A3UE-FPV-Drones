params ["_markerX", "_locationType", ["_profile", createHashMap], ["_siteSide", sideUnknown], ["_familyId", ""]];

if (!isServer) exitWith {objNull};
if (_familyId isEqualTo "") exitWith {objNull};

private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) then {
	_catalog = call A3UE_fnc_fpv_buildCompatCatalog;
};

private _familyData = _catalog getOrDefault [_familyId, createHashMap];
if (count _familyData == 0) exitWith {objNull};

private _sideKey = switch (_siteSide) do {
	case east: { "east" };
	case west: { "west" };
	case independent: { "independent" };
	default { "east" };
};

private _classPools = _profile getOrDefault ["classPools", createHashMap];
private _sitePools = _classPools getOrDefault [_sideKey, createHashMap];
private _familyPools = _sitePools getOrDefault [_familyId, createHashMap];

private _roleWeights = _profile getOrDefault ["roleWeights", createHashMap];
private _weightedRoles = [];

{
	private _roleId = _x;
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
	{
		_totalWeight = _totalWeight + ((_x param [1, 0]) max 0);
	} forEach _entries;

	if (_totalWeight <= 0) exitWith {(_entries select 0) param [0, ""]};

	private _roll = random _totalWeight;
	private _selection = "";
	{
		_roll = _roll - ((_x param [1, 0]) max 0);
		if (_roll <= 0) exitWith {
			_selection = _x param [0, ""];
		};
	} forEach _entries;

	if (_selection isEqualTo "") then {
		_selection = (_entries select ((count _entries) - 1)) param [0, ""];
	};

	_selection
};

private _payloadRole = [_weightedRoles] call _pickWeightedValue;
if (_payloadRole isEqualTo "") exitWith {objNull};

private _uavClass = [_familyId, _payloadRole, _siteSide, _locationType] call A3UE_fnc_fpv_selectClassForRole;
if (_uavClass isEqualTo "") then {
	{
		private _roleId = _x param [0, ""];
		private _candidateClass = [_familyId, _roleId, _siteSide, _locationType] call A3UE_fnc_fpv_selectClassForRole;
		if (_candidateClass isNotEqualTo "") exitWith {
			_payloadRole = _roleId;
			_uavClass = _candidateClass;
		};
	} forEach _weightedRoles;
	if (_uavClass isEqualTo "") exitWith {objNull};
};

private _spawnCenter = getMarkerPos _markerX;
private _spawnBand = switch (_locationType) do {
	case "Airport": { [50, 100] };
	case "Outpost": { [20, 70] };
	default { [10, 50] };
};

private _spawnPos = if (!isNil "A3A_fnc_getSafePos") then {
	[_spawnCenter, _spawnBand # 0, _spawnBand # 1, 2, 0, -1, 0] call A3A_fnc_getSafePos
} else {
	_spawnCenter getPos [(_spawnBand # 0) + random ((_spawnBand # 1) - (_spawnBand # 0)), random 360]
};

private _spawnHeight = switch (_locationType) do {
	case "Airport": { 45 };
	case "Outpost": { 35 };
	default { 25 };
};

private _spawnPosATL = +_spawnPos;
_spawnPosATL set [2, _spawnHeight];

private _rangeTier = "STD";
if (_uavClass find "_25KM" > -1) then {
	_rangeTier = "25KM";
} else {
	if (_uavClass find "_20KM" > -1) then {
		_rangeTier = "20KM";
	};
};

private _profileId = _profile getOrDefault ["profileId", format ["site_%1_default", toLower _locationType]];
private _linkModel = _familyData getOrDefault ["signalModel", "RADIO"];

private _uav = createVehicle [_uavClass, _spawnPosATL, [], 0, "FLY"];
if (isNull _uav) exitWith {objNull};

_uav setDir (random 360);
_uav setPosATL _spawnPosATL;
_uav flyInHeight _spawnHeight;

_uav setVariable ["A3UE_FPV_managed", true, true];
_uav setVariable ["A3UE_FPV_mode", "IDLE", true];
_uav setVariable ["A3UE_FPV_siteMarker", _markerX, true];
_uav setVariable ["A3UE_FPV_siteType", _locationType, true];
_uav setVariable ["A3UE_FPV_profileId", _profileId, true];
_uav setVariable ["A3UE_FPV_vendorId", _familyId, true];
_uav setVariable ["A3UE_FPV_payloadRole", _payloadRole, true];
_uav setVariable ["A3UE_FPV_linkModel", _linkModel, true];
_uav setVariable ["A3UE_FPV_rangeTier", _rangeTier, true];
_uav setVariable ["A3UE_FPV_netId", netId _uav, true];
_uav setVariable ["A3UE_FPV_targetNetId", "", true];
_uav setVariable ["A3UE_FPV_lastInterceptASL", [], true];
_uav setVariable ["A3UE_FPV_linkState", "OK", true];
_uav setVariable ["A3UE_FPV_spawnTime", serverTime, true];

private _crewGroup = grpNull;
if (!isNil "A3A_fnc_createVehicleCrew") then {
	_crewGroup = [_siteSide, _uav] call A3A_fnc_createVehicleCrew;
} else {
	createVehicleCrew _uav;
	if (crew _uav isNotEqualTo []) then {
		_crewGroup = group ((crew _uav) select 0);
	};
};

if (!isNil "A3A_fnc_NATOinit" && {!isNull _crewGroup}) then {
	{
		[_x, _markerX, false, "defence"] call A3A_fnc_NATOinit;
	} forEach (units _crewGroup);
};

if (!isNil "A3A_fnc_AIVEHinit") then {
	[_uav, _siteSide, "defence"] call A3A_fnc_AIVEHinit;
};

[_uav] call A3UE_fnc_fpv_applyCompatInit;

_uav