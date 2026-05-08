params ["_vehicle", "_side"];

_side;

if (isNull _vehicle) exitWith {false};
if !(_vehicle getVariable ["A3UE_FPV_managed", false]) exitWith {false};

[_vehicle] remoteExecCall ["A3UE_fnc_fpv_bootstrapLocal", 0, _vehicle];

true