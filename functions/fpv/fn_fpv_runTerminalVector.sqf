params [["_uav", objNull], ["_target", objNull], ["_profile", createHashMap]];

if (isNull _uav || {isNull _target}) exitWith {false};
if (!local _uav) exitWith {false};
if ([_uav] call A3UE_fnc_fpv_isExternallyControlled) exitWith {false};
if ((_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) isEqualTo "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState", "OK"]) == "EW_DENIED"}) exitWith {false};

private _leadPosAsl = [_uav, _target, _profile, true] call A3UE_fnc_fpv_computeIntercept;
if (_leadPosAsl isEqualTo [] || {count _leadPosAsl < 3}) exitWith {false};

private _uavPosAsl = getPosASL _uav;
private _currentDir = vectorDir _uav;
private _aimVector = _leadPosAsl vectorDiff _uavPosAsl;
private _aimVectorMagnitude = vectorMagnitude _aimVector;
if (_aimVectorMagnitude <= 0.01) exitWith {false};

private _normalizedAimVector = _aimVector vectorMultiply (1 / _aimVectorMagnitude);
private _currentDirMagnitude = vectorMagnitude _currentDir;
private _normalizedCurrentDir = if (_currentDirMagnitude > 0.01) then {
	_currentDir vectorMultiply (1 / _currentDirMagnitude)
} else {
	_normalizedAimVector
};

private _terminalSpeed = [_profile, "terminalSpeed", 120] call A3UE_fnc_fpv_profileValue;
if (!(_terminalSpeed isEqualType 0) || {_terminalSpeed <= 0}) then {
	_terminalSpeed = 120;
};

private _turnBlend = [_profile, "terminalTurnBlend", 0.35] call A3UE_fnc_fpv_profileValue;
if (!(_turnBlend isEqualType 0) || {_turnBlend <= 0}) then {
	_turnBlend = 0.35;
};
	_turnBlend = _turnBlend min 1;

private _verticalGain = [_profile, "terminalVerticalGain", 0.65] call A3UE_fnc_fpv_profileValue;
if (!(_verticalGain isEqualType 0) || {_verticalGain <= 0}) then {
	_verticalGain = 0.65;
};

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

private _desiredVelocity = _blendedDir vectorMultiply _terminalSpeed;
private _verticalError = ((_leadPosAsl select 2) - (_uavPosAsl select 2));
_desiredVelocity set [2, (_desiredVelocity select 2) + (_verticalError * _verticalGain)];

{
	_x disableAI "PATH";
	_x disableAI "FSM";
	_x disableAI "AUTOCOMBAT";
} forEach crew _uav;

_uav enableAI "ALL";
_uav setBehaviour "CARELESS";
_uav setCombatMode "BLUE";
_uav setSpeedMode "FULL";
_uav forceSpeed _terminalSpeed;
_uav setVectorDirAndUp [_blendedDir, [0, 0, 1]];
_uav setVelocity _desiredVelocity;
_uav setVariable ["A3UE_FPV_terminalSteeringActive", true, true];

true