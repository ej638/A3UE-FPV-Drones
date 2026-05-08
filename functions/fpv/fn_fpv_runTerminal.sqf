params [["_uav", objNull], ["_target", objNull], ["_profile", createHashMap]];

if (isNull _uav || {isNull _target}) exitWith {false};
if (!local _uav) exitWith {false};

private _targetPosAsl = getPosASL _target;
private _impactPointAsl = _uav getVariable ["A3UE_FPV_lastImpactPointASL", []];
private _impactMode = _uav getVariable ["A3UE_FPV_terminalImpactMode", "NONE"];
private _hasImpactPoint = (_uav getVariable ["A3UE_FPV_lastImpactValid", false]) && {
	(_uav getVariable ["A3UE_FPV_lastImpactTargetNetId", ""]) == netId _target && {
		_impactPointAsl isEqualType [] && {
			count _impactPointAsl >= 3
		}
	}
};

private _terminalAimBaseAsl = if (_hasImpactPoint) then {
	+_impactPointAsl
} else {
	+_targetPosAsl
};

private _terminalInterceptAsl = [_uav, _target, _profile, true] call A3UE_fnc_fpv_computeIntercept;

private _terminalPosAsl = if (_terminalInterceptAsl isEqualTo [] || {count _terminalInterceptAsl < 3}) then {
	+_terminalAimBaseAsl
} else {
	+_terminalInterceptAsl
};

private _terminalPosAtl = ASLToATL _terminalPosAsl;
private _terminalImpactOffsetNear = [_profile, "terminalImpactOffsetNear", 1] call A3UE_fnc_fpv_profileValue;
if (!(_terminalImpactOffsetNear isEqualType 0) || {_terminalImpactOffsetNear < 0}) then {
	_terminalImpactOffsetNear = 1;
};

private _terminalHeightFloor = if (_impactMode == "AIR_PROXIMITY") then {5} else {_terminalImpactOffsetNear max 1};
private _terminalHeight = ((_terminalPosAtl select 2) max _terminalHeightFloor);
private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];

private _defaultTerminalSpeed = switch (_payloadRole) do {
	case "AT": { 110 };
	case "RECON": { 95 };
	default { 100 };
};

private _terminalSpeed = [_profile, "terminalAttackSpeed", [_profile, "terminalSpeed", _defaultTerminalSpeed] call A3UE_fnc_fpv_profileValue] call A3UE_fnc_fpv_profileValue;
if (!(_terminalSpeed isEqualType 0) || {_terminalSpeed <= 0}) then {
	_terminalSpeed = _defaultTerminalSpeed;
};

private _moveDelta = [_profile, "terminalMoveDelta", 5] call A3UE_fnc_fpv_profileValue;
if (!(_moveDelta isEqualType 0) || {_moveDelta <= 0}) then {
	_moveDelta = 5;
};

private _lastMoveTarget = _uav getVariable ["A3UE_FPV_lastTerminalMoveTarget", []];
private _lastMoveUpdate = _uav getVariable ["A3UE_FPV_lastTerminalMoveUpdate", -1];

_uav enableAI "ALL";
_uav setBehaviour "CARELESS";
_uav setCombatMode "BLUE";
_uav setSpeedMode "FULL";
_uav flyInHeight _terminalHeight;
_uav forceSpeed _terminalSpeed;

if (_lastMoveTarget isEqualTo [] || {_lastMoveTarget distance2D _terminalPosAtl > _moveDelta} || {time > (_lastMoveUpdate + 0.05)}) then {
	_uav doMove _terminalPosAtl;
	_uav setVariable ["A3UE_FPV_lastTerminalMoveTarget", _terminalPosAtl];
	_uav setVariable ["A3UE_FPV_lastTerminalMoveUpdate", time];
};

true