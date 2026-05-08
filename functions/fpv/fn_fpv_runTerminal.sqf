params [["_uav", objNull], ["_target", objNull], ["_profile", createHashMap]];

if (isNull _uav || {isNull _target}) exitWith {false};
if (!local _uav) exitWith {false};

private _targetPosAsl = getPosASL _target;
private _terminalInterceptAsl = [_uav, _target, _profile, true] call A3UE_fnc_fpv_computeIntercept;
private _finalHeightOffset = [_profile, "attackHeightASL", 6] call A3UE_fnc_fpv_profileValue;
if (!(_finalHeightOffset isEqualType 0)) then {
	_finalHeightOffset = 6;
};

private _terminalPosAsl = if (_terminalInterceptAsl isEqualTo [] || {count _terminalInterceptAsl < 3}) then {
	+_targetPosAsl
} else {
	+_terminalInterceptAsl
};
_terminalPosAsl set [2, ((_targetPosAsl select 2) + _finalHeightOffset) max (_terminalPosAsl select 2)];

private _terminalPosAtl = ASLToATL _terminalPosAsl;
private _terminalHeight = ((_terminalPosAtl select 2) max 5);
private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];

private _defaultTerminalSpeed = switch (_payloadRole) do {
	case "AT": { 110 };
	case "RECON": { 95 };
	default { 100 };
};

private _terminalSpeed = [_profile, "terminalSpeed", _defaultTerminalSpeed] call A3UE_fnc_fpv_profileValue;
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