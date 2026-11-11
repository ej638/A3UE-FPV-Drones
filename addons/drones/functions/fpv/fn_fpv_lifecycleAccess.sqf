// Internal server workers also run inside authenticated AU/report call stacks.
if (!isServer || {isRemoteExecutedJIP}) exitWith {false};
if (!isRemoteExecuted || {remoteExecutedOwner == 2}) exitWith {true};
if (!isNil "_A3UE_FPV_lifecycleAuthorized" && {_A3UE_FPV_lifecycleAuthorized isEqualRef (missionNamespace getVariable ["A3UE_FPV_lifecycleCapability", createHashMap])}) exitWith {true};
!isNil "_A3UE_FPV_spawnAuthorized" && {_A3UE_FPV_spawnAuthorized isEqualTo true}
    && {[true] call A3UE_fnc_fpv_isTrustedSupportCaller}
