// Scheduling must not strip an untrusted caller's provenance.
if (isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}) exitWith {0};

private _managedDrones = allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] };

{
	[_x] spawn A3UE_fnc_fpv_bootstrapLocal;
} forEach _managedDrones;

count _managedDrones