params [["_uav", objNull], ["_intercept", []], ["_profile", createHashMap]];

if (isNull _uav) exitWith {false};
if (!local _uav) exitWith {false};
if (_intercept isEqualTo [] || {count _intercept < 3}) exitWith {false};

private _moveTargetAtl = ASLToATL _intercept;
private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];

private _defaultTrackingSpeed = switch (_payloadRole) do {
	case "AT": { 95 };
	case "RECON": { 85 };
	default { 90 };
};

private _trackingSpeed = [_profile, "trackingSpeed", _defaultTrackingSpeed] call A3UE_fnc_fpv_profileValue;
if (!(_trackingSpeed isEqualType 0) || {_trackingSpeed <= 0}) then {
	_trackingSpeed = _defaultTrackingSpeed;
};

private _moveDelta = [_profile, "trackingMoveDelta", 15] call A3UE_fnc_fpv_profileValue;
if (!(_moveDelta isEqualType 0) || {_moveDelta <= 0}) then {
	_moveDelta = 15;
};

private _trackingHeightFloor = [_profile, "trackingHeightASL", 10] call A3UE_fnc_fpv_profileValue;
if (!(_trackingHeightFloor isEqualType 0) || {_trackingHeightFloor < 0}) then {
	_trackingHeightFloor = 10;
};

private _trackingHeight = ((_moveTargetAtl select 2) max _trackingHeightFloor);

private _lastMoveTarget = _uav getVariable ["A3UE_FPV_lastMoveTarget", []];
private _lastMoveUpdate = _uav getVariable ["A3UE_FPV_lastMoveUpdate", -1];

_uav enableAI "ALL";
_uav setBehaviour "CARELESS";
_uav setCombatMode "BLUE";
_uav setSpeedMode "FULL";
_uav flyInHeight _trackingHeight;
_uav forceSpeed _trackingSpeed;

if (_lastMoveTarget isEqualTo [] || {_lastMoveTarget distance2D _moveTargetAtl > _moveDelta} || {time > (_lastMoveUpdate + 0.15)}) then {
	_uav doMove _moveTargetAtl;
	_uav setVariable ["A3UE_FPV_lastMoveTarget", _moveTargetAtl];
	_uav setVariable ["A3UE_FPV_lastMoveUpdate", time];
};

true