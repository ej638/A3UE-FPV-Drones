params [
	["_uavClass", "", [""]], ["_familyId", "", [""]],
	["_taskRole", "", [""]], ["_side", sideUnknown, [sideUnknown]]
];

private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) then {_catalog = call A3UE_fnc_fpv_buildCompatCatalog;};
private _family = _catalog getOrDefault [_familyId, createHashMap];
// Engine config names are case-insensitive; use their canonical spelling as key.
private _className = configName (configFile >> "CfgVehicles" >> _uavClass);
private _descriptor = (_family getOrDefault ["classDescriptors", createHashMap]) getOrDefault [_className, createHashMap];
if (count _descriptor == 0) exitWith {createHashMap};
if (_taskRole != "" && {!(_taskRole in (_descriptor get "taskRoles"))}) exitWith {createHashMap};
private _sideKey = switch (_side) do {
	case east: {"east"};
	case west: {"west"};
	case independent: {"independent"};
	default {""};
};
if (_sideKey != "" && {_sideKey != (_descriptor get "sideKey")}) exitWith {createHashMap};
_descriptor
