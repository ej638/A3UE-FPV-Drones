params [["_uav", objNull], ["_preserveControl", false]];

if (isRemoteExecuted && {remoteExecutedOwner != 2}) exitWith {false};
if (!isServer && {!isRemoteExecuted}) exitWith {false};
if (isNull _uav) exitWith {false};

private _deleted = false;
// The server already cleared managed; keep the local check and deletion in one slice.
isNil {
	if (local _uav) then {
		_uav setVariable ["A3UE_FPV_terminalPoseContext", []];
		_uav setVariable ["A3UE_FPV_terminalSteeringState", []];
		_uav setVariable ["A3UE_FPV_trajectory",[]];
		_uav setVariable ["A3UE_FPV_trajectoryAttemptAt",-1];
		_uav setVariable ["A3UE_FPV_steeringReconstruction",[]];
		// Check on the owner in the deletion slice: server-side Zeus inspection
		// cannot see every remoteControlled crew, and control can change in transit.
		if ((_preserveControl || {_uav getVariable ["A3UE_FPV_preserveControlOnCleanup", false]})
			&& {[_uav] call A3UE_fnc_fpv_isExternallyControlled}) exitWith {};
		{_uav deleteVehicleCrew _x;} forEach (crew _uav);
		deleteVehicle _uav;
		_deleted = true;
	};
};

_deleted
