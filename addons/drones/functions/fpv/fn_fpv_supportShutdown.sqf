// Mission-end settlement is transient. Nothing is restored as a pending flight
// on the next AU campaign load; abrupt process loss has no persistent timer.
params [];

if (!isServer || {isRemoteExecuted}) exitWith {false};
isNil {
	missionNamespace setVariable ["A3UE_FPV_supportShuttingDown", true];
	private _registry = missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap];
	{
		if ((_y getOrDefault ["status", ""]) == "preparing") then {
			[_x, "failed", "MISSION_SHUTDOWN", "", true] call A3UE_fnc_fpv_supportFinalize;
		};
	} forEach _registry;
};
true
