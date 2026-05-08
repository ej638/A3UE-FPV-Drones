params [["_uav", objNull], ["_target", objNull], ["_profile", createHashMap]];

if (isNull _uav || {isNull _target}) exitWith {false};
if (_uav getVariable ["A3UE_FPV_detonating", false]) exitWith {false};

private _evaluation = [_uav, _target, _profile] call A3UE_fnc_fpv_evaluateImpactWindow;

_uav setVariable ["A3UE_FPV_lastClosingDot", _evaluation getOrDefault ["closingDot", -2], true];
_uav setVariable ["A3UE_FPV_lastTimeToContact", _evaluation getOrDefault ["timeToContact", -1], true];
_uav setVariable ["A3UE_FPV_lastDetonationReason", _evaluation getOrDefault ["detonationReason", "NONE"], true];
_uav setVariable ["A3UE_FPV_lastFallbackReason", _evaluation getOrDefault ["fallbackReason", "NONE"], true];

_evaluation getOrDefault ["approved", false]