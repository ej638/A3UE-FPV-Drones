params [["_uav", objNull], ["_target", objNull], ["_profile", createHashMap]];

if (isNull _uav || {isNull _target}) exitWith {false};
if (!local _uav) exitWith {false};
if ([_uav] call A3UE_fnc_fpv_isExternallyControlled) exitWith {false};
if ((_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) isEqualTo "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState", "OK"]) == "EW_DENIED"}) exitWith {false};

private _leadPosAsl = [_uav, _target, _profile, true] call A3UE_fnc_fpv_computeIntercept;
if (_leadPosAsl isEqualTo [] || {count _leadPosAsl < 3}) exitWith {false};

private _uavPosAsl = getPosASL _uav;
private _currentVelocity = velocity _uav;
private _currentSpeedBudget = (vectorMagnitude _currentVelocity) * 3.6;
private _currentDir = vectorDir _uav;
private _targetPosAsl = getPosASL _target;
private _currentDistance = _uavPosAsl vectorDistance _targetPosAsl;
private _aimVector = _leadPosAsl vectorDiff _uavPosAsl;
private _verticalGain = [_profile, "terminalVerticalGain", 0.65] call A3UE_fnc_fpv_profileValue;
if (!(_verticalGain isEqualType 0) || {_verticalGain <= 0}) then {
	_verticalGain = 0.65;
};

private _guidedAimVector = +_aimVector;
_guidedAimVector set [2, (_guidedAimVector select 2) * (1 + _verticalGain)];

private _aimVectorMagnitude = vectorMagnitude _guidedAimVector;
if (_aimVectorMagnitude <= 0.01) exitWith {false};

private _normalizedAimVector = _guidedAimVector vectorMultiply (1 / _aimVectorMagnitude);
private _currentDirMagnitude = vectorMagnitude _currentDir;
private _normalizedCurrentDir = if (_currentDirMagnitude > 0.01) then {
	_currentDir vectorMultiply (1 / _currentDirMagnitude)
} else {
	_normalizedAimVector
};

private _terminalSpeedFallback = [_profile, "terminalSpeed", 120] call A3UE_fnc_fpv_profileValue;
if (!(_terminalSpeedFallback isEqualType 0) || {_terminalSpeedFallback <= 0}) then {
	_terminalSpeedFallback = 120;
};

private _terminalVectorMaxSpeed = [_profile, "terminalVectorMaxSpeed", _terminalSpeedFallback] call A3UE_fnc_fpv_profileValue;
if (!(_terminalVectorMaxSpeed isEqualType 0) || {_terminalVectorMaxSpeed <= 0}) then {
	_terminalVectorMaxSpeed = _terminalSpeedFallback;
};

private _terminalVectorEntrySpeed = [_profile, "terminalVectorEntrySpeed", _terminalVectorMaxSpeed] call A3UE_fnc_fpv_profileValue;
if (!(_terminalVectorEntrySpeed isEqualType 0) || {_terminalVectorEntrySpeed <= 0}) then {
	_terminalVectorEntrySpeed = _terminalVectorMaxSpeed;
};

private _terminalVectorAccel = [_profile, "terminalVectorAccel", 24] call A3UE_fnc_fpv_profileValue;
if (!(_terminalVectorAccel isEqualType 0) || {_terminalVectorAccel <= 0}) then {
	_terminalVectorAccel = 24;
};

private _terminalVectorDecel = [_profile, "terminalVectorDecel", 30] call A3UE_fnc_fpv_profileValue;
if (!(_terminalVectorDecel isEqualType 0) || {_terminalVectorDecel <= 0}) then {
	_terminalVectorDecel = 30;
};

private _terminalVectorEntryDistance = _uav getVariable ["A3UE_FPV_terminalVectorEntryDistance", _currentDistance];
if (!(_terminalVectorEntryDistance isEqualType 0) || {_terminalVectorEntryDistance <= 0}) then {
	_terminalVectorEntryDistance = _currentDistance;
};

private _terminalVectorRampDistance = [_profile, "terminalVectorRampDistance", _terminalVectorEntryDistance] call A3UE_fnc_fpv_profileValue;
if (!(_terminalVectorRampDistance isEqualType 0) || {_terminalVectorRampDistance <= 0}) then {
	_terminalVectorRampDistance = _terminalVectorEntryDistance;
};

private _terminalVectorInnerFuseSlowdownDistance = [_profile, "terminalVectorInnerFuseSlowdownDistance", 22] call A3UE_fnc_fpv_profileValue;
if (!(_terminalVectorInnerFuseSlowdownDistance isEqualType 0) || {_terminalVectorInnerFuseSlowdownDistance <= 0}) then {
	_terminalVectorInnerFuseSlowdownDistance = 22;
};

private _terminalVectorInnerFuseMinSpeed = [_profile, "terminalVectorInnerFuseMinSpeed", _terminalVectorEntrySpeed] call A3UE_fnc_fpv_profileValue;
if (!(_terminalVectorInnerFuseMinSpeed isEqualType 0) || {_terminalVectorInnerFuseMinSpeed <= 0}) then {
	_terminalVectorInnerFuseMinSpeed = _terminalVectorEntrySpeed;
};

private _terminalVectorMinAccelAlignment = [_profile, "terminalVectorMinAccelAlignment", 0.70] call A3UE_fnc_fpv_profileValue;
if (!(_terminalVectorMinAccelAlignment isEqualType 0)) then {
	_terminalVectorMinAccelAlignment = 0.70;
};

private _terminalVectorFullAccelAlignment = [_profile, "terminalVectorFullAccelAlignment", 0.94] call A3UE_fnc_fpv_profileValue;
if (!(_terminalVectorFullAccelAlignment isEqualType 0)) then {
	_terminalVectorFullAccelAlignment = 0.94;
};

private _terminalVectorTurnBlendMin = [_profile, "terminalVectorTurnBlendMin", 0.22] call A3UE_fnc_fpv_profileValue;
if (!(_terminalVectorTurnBlendMin isEqualType 0)) then {
	_terminalVectorTurnBlendMin = 0.22;
};

private _terminalVectorTurnBlendMax = [_profile, "terminalVectorTurnBlendMax", (_profile getOrDefault ["terminalTurnBlend", 0.35])] call A3UE_fnc_fpv_profileValue;
if (!(_terminalVectorTurnBlendMax isEqualType 0)) then {
	_terminalVectorTurnBlendMax = _profile getOrDefault ["terminalTurnBlend", 0.35];
};

private _terminalVectorSpeedLagTolerance = [_profile, "terminalVectorSpeedLagTolerance", 6] call A3UE_fnc_fpv_profileValue;
if (!(_terminalVectorSpeedLagTolerance isEqualType 0) || {_terminalVectorSpeedLagTolerance < 0}) then {
	_terminalVectorSpeedLagTolerance = 6;
};

_terminalVectorInnerFuseMinSpeed = (_terminalVectorInnerFuseMinSpeed min _terminalVectorMaxSpeed) max 1;
_terminalVectorMinAccelAlignment = (_terminalVectorMinAccelAlignment max -1) min 1;
_terminalVectorFullAccelAlignment = (_terminalVectorFullAccelAlignment max _terminalVectorMinAccelAlignment) min 1;
_terminalVectorTurnBlendMin = (_terminalVectorTurnBlendMin max 0) min 1;
_terminalVectorTurnBlendMax = (_terminalVectorTurnBlendMax max _terminalVectorTurnBlendMin) min 1;

private _alignment = ((_normalizedCurrentDir vectorDotProduct _normalizedAimVector) max -1) min 1;
private _alignmentAccelFactor = linearConversion [_terminalVectorMinAccelAlignment, _terminalVectorFullAccelAlignment, _alignment, 0, 1, true];
private _turnBlend = linearConversion [_terminalVectorMinAccelAlignment, _terminalVectorFullAccelAlignment, _alignment, _terminalVectorTurnBlendMin, _terminalVectorTurnBlendMax, true];

private _blendedDir = [
	((_normalizedCurrentDir select 0) * (1 - _turnBlend)) + ((_normalizedAimVector select 0) * _turnBlend),
	((_normalizedCurrentDir select 1) * (1 - _turnBlend)) + ((_normalizedAimVector select 1) * _turnBlend),
	((_normalizedCurrentDir select 2) * (1 - _turnBlend)) + ((_normalizedAimVector select 2) * _turnBlend)
];
private _blendedDirMagnitude = vectorMagnitude _blendedDir;
if (_blendedDirMagnitude <= 0.01) then {
	_blendedDir = _normalizedAimVector;
} else {
	_blendedDir = _blendedDir vectorMultiply (1 / _blendedDirMagnitude);
};

private _terminalVectorEnteredAt = _uav getVariable ["A3UE_FPV_terminalVectorEnteredAt", -1];
private _lastVectorUpdateAt = _uav getVariable ["A3UE_FPV_terminalVectorLastUpdateAt", -1];
private _isFirstVectorTick = (_lastVectorUpdateAt < 0) || {_terminalVectorEnteredAt > _lastVectorUpdateAt};
private _dt = if (_isFirstVectorTick) then {
	0.01
} else {
	((time - _lastVectorUpdateAt) max 0.005) min 0.05
};

private _speedBudgetNow = if (_currentSpeedBudget < 1) then {
	_terminalVectorEntrySpeed min _terminalVectorMaxSpeed
} else {
	_currentSpeedBudget
};

private _distanceClosed = (_terminalVectorEntryDistance - _currentDistance) max 0;
private _rampProgress = linearConversion [0, _terminalVectorRampDistance, _distanceClosed, 0, 1, true];
private _rampedTargetSpeed = linearConversion [0, 1, _rampProgress, _terminalVectorEntrySpeed, _terminalVectorMaxSpeed, true];
private _baseTargetSpeed = _rampedTargetSpeed;

if (_currentDistance <= _terminalVectorInnerFuseSlowdownDistance) then {
	_baseTargetSpeed = linearConversion [
		_terminalVectorInnerFuseSlowdownDistance,
		0,
		_currentDistance,
		_rampedTargetSpeed,
		_terminalVectorInnerFuseMinSpeed,
		true
	];
};

private _desiredTargetSpeed = _baseTargetSpeed min (_speedBudgetNow + _terminalVectorSpeedLagTolerance);
private _effectiveAccel = _terminalVectorAccel * _alignmentAccelFactor;
private _speedDelta = _desiredTargetSpeed - _speedBudgetNow;
private _speedDeltaMin = -(_terminalVectorDecel * _dt);
private _speedDeltaMax = (_effectiveAccel max 0) * _dt;
private _appliedSpeedDelta = (_speedDelta max _speedDeltaMin) min _speedDeltaMax;
private _appliedAcceleration = if (_dt > 0) then {
	_appliedSpeedDelta / _dt
} else {
	0
};
private _nextSpeedBudget = if (_speedDelta >= 0) then {
	(_speedBudgetNow + _appliedSpeedDelta) min _desiredTargetSpeed
	} else {
	(_speedBudgetNow + _appliedSpeedDelta) max _desiredTargetSpeed
};

private _desiredVelocity = _blendedDir vectorMultiply (_nextSpeedBudget / 3.6);

{
	_x disableAI "PATH";
	_x disableAI "FSM";
	_x disableAI "AUTOCOMBAT";
} forEach crew _uav;

_uav enableAI "ALL";
_uav setBehaviour "CARELESS";
_uav setCombatMode "BLUE";
_uav setSpeedMode "FULL";
_uav forceSpeed _terminalVectorMaxSpeed;
_uav setVectorDirAndUp [_blendedDir, [0, 0, 1]];
_uav setVelocity _desiredVelocity;
_uav setVariable ["A3UE_FPV_terminalVectorLastUpdateAt", time];

if (_isFirstVectorTick) then {
	_uav setVariable ["A3UE_FPV_terminalVectorEntrySpeed", _speedBudgetNow, true];
	_uav setVariable ["A3UE_FPV_terminalVectorEntryDistance", _terminalVectorEntryDistance, true];
};

_uav setVariable ["A3UE_FPV_terminalVectorCurrentSpeed", _speedBudgetNow, true];
_uav setVariable ["A3UE_FPV_terminalVectorTargetSpeed", _desiredTargetSpeed, true];
_uav setVariable ["A3UE_FPV_terminalVectorAccelApplied", _appliedAcceleration, true];
_uav setVariable ["A3UE_FPV_terminalVectorAlignment", _alignment, true];
_uav setVariable ["A3UE_FPV_terminalVectorDt", _dt, true];
_uav setVariable ["A3UE_FPV_terminalVectorSpeedJump", _appliedSpeedDelta, true];
_uav setVariable ["A3UE_FPV_terminalSteeringActive", true, true];

true