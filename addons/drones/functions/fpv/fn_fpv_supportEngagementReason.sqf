// Empty reason grants permission only to this live target and current doctrine.
params [
	["_uav", objNull], ["_target", objNull], ["_force", false],
	["_deliveryPosATL", []], ["_terminal", false], ["_policy", createHashMap], ["_acquiring", false]
];

if !(call A3UE_fnc_fpv_helperAccess) exitWith {"AUTHORITY_REJECTED"};
if (isNull _uav) exitWith {"TARGET_CHANGED"};
private _radius = _policy getOrDefault ["safetyRadius", _uav getVariable ["A3UE_FPV_supportSafetyRadius", 0]];
if !(_radius isEqualType 0 && {finite _radius}) then {_radius = 40;};
// Only support packages opting into collateral avoidance acquire this policy.
if (_radius <= 0) exitWith {""};
if (_uav getVariable ["A3UE_FPV_engagementAborted", false]
	|| {private _blockedAt = _uav getVariable ["A3UE_FPV_engagementBlockedAt", -1]; _blockedAt >= 0 && {serverTime - _blockedAt >= 15}}) exitWith {"UNSAFE_ENGAGEMENT"};
private _side = _policy getOrDefault ["side", _uav getVariable ["A3UE_FPV_supportSide", sideUnknown]];
private _targetSide = _policy getOrDefault ["targetSide", _uav getVariable ["A3UE_FPV_targetSide", sideUnknown]];
private _hostileSides = [_side, _targetSide] call A3UE_fnc_fpv_getHostileSides;
private _legalTarget = [_target, _hostileSides] call A3UE_fnc_fpv_filterTarget;
if (isNull _legalTarget || {_legalTarget isNotEqualTo _target}
	|| {!_acquiring && {netId _target != (_uav getVariable ["A3UE_FPV_targetNetId", ""])}}) exitWith {"TARGET_CHANGED"};

private _targetPos = getPosATL _target;
private _uavPos = getPosATL _uav;
private _generation = _uav getVariable ["A3UE_FPV_controllerGeneration", -1];
private _cache = _uav getVariable ["A3UE_FPV_engagementPermissionCache", []];
if (!_force && {count _cache == 10} && {time < (_cache # 0)}
	&& {_target isEqualTo (_cache # 1)} && {_generation == (_cache # 2)}
	&& {_terminal == (_cache # 3)} && {_radius == (_cache # 7)}
	&& {_side == (_cache # 8)} && {_targetSide == (_cache # 9)} && {_targetPos distance2D (_cache # 4) <= 5}
	&& {_uavPos distance2D (_cache # 5) <= 10}) exitWith {_cache # 6};

private _plan = createHashMapFromArray [["safetyRadius", _radius]];
private _reason = "";
if !([_side, _target, _targetPos, _plan, _uav, _force] call A3UE_fnc_fpv_supportPassesSafetyRing) then {
	_reason = "UNSAFE_ENGAGEMENT";
};
if (_reason == "" && {_terminal || {_force}}) then {
	if (([_uav, _target] call A3UE_fnc_fpv_isTargetObstructed) getOrDefault ["blocked", true]) then {_reason = "NO_VISIBLE_TARGET";};
};
if (_reason != "UNSAFE_ENGAGEMENT" && {_deliveryPosATL isNotEqualTo []}) then {
	// Surface/proximity delivery can differ from the object's center.
	if !([_side, objNull, _deliveryPosATL, _plan, objNull, true] call A3UE_fnc_fpv_supportPassesSafetyRing) then {_reason = "UNSAFE_ENGAGEMENT";};
};
if (!_force) then {
	_uav setVariable ["A3UE_FPV_engagementPermissionCache", [time + 0.25, _target, _generation, _terminal, _targetPos, _uavPos, _reason, _radius, _side, _targetSide]];
};
_reason
