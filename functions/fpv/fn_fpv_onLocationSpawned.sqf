params ["_markerX", "_locationType", "_isSpawning"];

if (!isServer) exitWith {};
if !(_locationType in ["Airport", "Outpost", "Resource"]) exitWith {};

if (isNil "A3UE_FPV_registry") then {
	missionNamespace setVariable ["A3UE_FPV_registry", createHashMap];
};

[_markerX, _locationType, _isSpawning] call A3UE_fnc_fpv_managerEvaluateSite;