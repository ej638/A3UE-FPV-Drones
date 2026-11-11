// One bounded counter, no per-request key or log allocation.
if (isServer) then {
    missionNamespace setVariable ["A3UE_FPV_lifecycleRejected", (1 + (missionNamespace getVariable ["A3UE_FPV_lifecycleRejected", 0])) min 1000000];
};
false
