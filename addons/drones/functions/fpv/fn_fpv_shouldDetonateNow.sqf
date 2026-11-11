params [["_uav", objNull], ["_target", objNull], ["_profile", createHashMap]];

if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};

if (isNull _uav || {isNull _target}) exitWith {false};
if (_uav getVariable ["A3UE_FPV_detonating", false]) exitWith {false};

private _evaluation = [_uav, _target, _profile] call A3UE_fnc_fpv_evaluateImpactWindow;

{
	_x params ["_key", "_evaluationKey", "_default"];
	[_uav, _key, _evaluation getOrDefault [_evaluationKey, _default]] call A3UE_fnc_fpv_publishTelemetry;
} forEach [
	["A3UE_FPV_lastClosingDot", "closingDot", -2],
	["A3UE_FPV_lastTimeToContact", "timeToContact", -1],
	["A3UE_FPV_lastDetonationReason", "detonationReason", "NONE"],
	["A3UE_FPV_lastFallbackReason", "fallbackReason", "NONE"]
];

_evaluation getOrDefault ["approved", false]
