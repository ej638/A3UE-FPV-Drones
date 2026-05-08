params [["_uav", objNull]];

if (isNull _uav) exitWith {false};
if (!isServer) exitWith {false};

[_uav, _uav getVariable ["A3UE_FPV_netId", netId _uav], "cleanup"] call A3UE_fnc_fpv_unregisterDrone;

_uav setVariable ["A3UE_FPV_managed", false, true];

{
	deleteVehicleCrew _x;
} forEach (crew _uav);

deleteVehicle _uav;

true