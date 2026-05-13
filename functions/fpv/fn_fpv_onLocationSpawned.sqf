params ["_markerX", "_locationType", "_isSpawning"];

if (!isServer) exitWith {};

private _siteType = [_markerX, _locationType] call A3UE_fnc_fpv_resolveSiteType;
if (_siteType isEqualTo "") exitWith {};

if (isNil "A3UE_FPV_registry") then {
	missionNamespace setVariable ["A3UE_FPV_registry", createHashMap];
};

[_markerX, _siteType, _isSpawning] call A3UE_fnc_fpv_managerEvaluateSite;