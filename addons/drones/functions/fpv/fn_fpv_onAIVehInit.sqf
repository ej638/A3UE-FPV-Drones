params ["_vehicle", "_side"];

// AU may invoke this synchronously inside authenticated support work.
// Do not turn arbitrary client RPCs into server-origin bootstrap/JIP work.
if (isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}) exitWith {false};

_side;

if (isNull _vehicle) exitWith {false};
if !(_vehicle getVariable ["A3UE_FPV_managed", false]) exitWith {false};

// Keep deletion and enqueue ordered even when invoked outside AU's unscheduled event.
private _published = false;
isNil {
	private _jipId = _vehicle getVariable ["A3UE_FPV_bootstrapJipId", ""];
	if (!isNull _vehicle && {_vehicle getVariable ["A3UE_FPV_managed", false]} && {_jipId isNotEqualTo ""}) then {
		[_vehicle] remoteExecCall ["A3UE_fnc_fpv_bootstrapLocal", 0, _jipId];
		_published = true;
	};
};

_published
