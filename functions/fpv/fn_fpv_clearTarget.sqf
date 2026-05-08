params [["_uav", objNull]];

if (isNull _uav) exitWith {false};

_uav setVariable ["A3UE_FPV_targetNetId", "", true];
_uav setVariable ["A3UE_FPV_lastInterceptASL", [], true];
_uav setVariable ["A3UE_FPV_terminalImpactMode", "NONE", true];
_uav setVariable ["A3UE_FPV_lastDetonationReason", "NONE", true];
_uav setVariable ["A3UE_FPV_lastFallbackReason", "NONE", true];
_uav setVariable ["A3UE_FPV_lastClosingDot", -2, true];
_uav setVariable ["A3UE_FPV_lastTimeToContact", -1, true];

true