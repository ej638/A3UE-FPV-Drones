params [["_uav", objNull]];

if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};

if (isNull _uav || {!local _uav}) exitWith {false};

// LT-2: every path that drops a target also leaves the attack board for it.
[_uav, "TARGET_DROPPED"] call A3UE_fnc_fpv_attackRelease;
if ((_uav getVariable ["A3UE_FPV_attackRole", ""]) isNotEqualTo "") then {_uav setVariable ["A3UE_FPV_attackRole", "", true];};
_uav setVariable ["A3UE_FPV_overwatchOrder", []];
_uav setVariable ["A3UE_FPV_targetNetId", "", true];
// Distinguish a later engagement with the same object from a queued old proposal.
_uav setVariable ["A3UE_FPV_targetRevision", 1 + (_uav getVariable ["A3UE_FPV_targetRevision", 0]), true];
_uav setVariable ["A3UE_FPV_navigation", []];
_uav setVariable ["A3UE_FPV_trajectory", []];
_uav setVariable ["A3UE_FPV_trajectoryAttemptAt", -1];
_uav setVariable ["A3UE_FPV_terminalSteeringState", []];
_uav setVariable ["A3UE_FPV_terminalPoseContext", []];
_uav setVariable ["A3UE_FPV_lastImpactValid", false, true];
_uav setVariable ["A3UE_FPV_lastImpactPointASL", []];
_uav setVariable ["A3UE_FPV_lastImpactTargetNetId", "", true];
_uav setVariable ["A3UE_FPV_engagementPermissionCache", []];
_uav setVariable ["A3UE_FPV_lastInterceptASL", [], true];
_uav setVariable ["A3UE_FPV_terminalImpactMode", "NONE", true];
_uav setVariable ["A3UE_FPV_impactLocalAnchor", []];
_uav setVariable ["A3UE_FPV_impactAnchorObject", objNull];
_uav setVariable ["A3UE_FPV_lastImpactTelemetryAt", -1];
_uav setVariable ["A3UE_FPV_lastDetonationReason", "NONE", true];
_uav setVariable ["A3UE_FPV_lastFallbackReason", "NONE", true];
_uav setVariable ["A3UE_FPV_lastClosingDot", -2, true];
_uav setVariable ["A3UE_FPV_lastTimeToContact", -1, true];

true
