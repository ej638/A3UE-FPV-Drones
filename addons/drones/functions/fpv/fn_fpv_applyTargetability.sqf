params [["_uav", objNull], ["_generation", -1]];

if (isRemoteExecutedJIP || {isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}}) exitWith {false};

private _applied = false;
// Owner/control/generation checks and the write share one unscheduled slice.
isNil {
	if (isNull _uav || {!alive _uav} || {!local _uav}) exitWith {};
	if !(_uav getVariable ["A3UE_FPV_managed", false]) exitWith {};
	private _netId = netId _uav;
	if (_netId == "" || {_netId != (_uav getVariable ["A3UE_FPV_netId", ""])}) exitWith {};
	if (_generation >= 0 && {(_uav getVariable ["A3UE_FPV_controllerGeneration", 0]) != _generation}) exitWith {};
	if (_uav getVariable ["A3UE_FPV_preserveControlOnCleanup", false]) exitWith {};
	if !([_uav] call A3UE_fnc_fpv_isSiteDroneActive) exitWith {};
	if ([_uav] call A3UE_fnc_fpv_isExternallyControlled) exitWith {};
	// Native UAV captivity is AI immunity, not capture of a remote operator.
	// Direct player/Zeus control retains native policy; autonomy is targetable.
	if (captive _uav) then {_uav setCaptive false;};
	private _pilot = driver _uav;
	if (!isNull _pilot && {local _pilot} && {captive _pilot}) then {_pilot setCaptive false;};
	_applied = true;
};

_applied
