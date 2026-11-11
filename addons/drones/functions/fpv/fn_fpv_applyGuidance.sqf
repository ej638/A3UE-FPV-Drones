params [["_uav", objNull], ["_intercept", []], ["_profile", createHashMap], ["_targetNetId", ""], ["_targetRevision", -1]];

if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};

if (isNull _uav) exitWith {false};
if (!local _uav) exitWith {false};
if (_intercept isEqualTo [] || {count _intercept < 3}) exitWith {false};
if ((_intercept findIf {!(_x isEqualType 0) || {!finite _x} || {abs _x > 1e6}}) >= 0) exitWith {false};

// Inherit the controller's original identity across scheduler preemption.
private _helperIdentity = if (isNil "_controllerIdentity") then {
    +(_uav getVariable ["A3UE_FPV_controllerIdentity", []])
} else {+_controllerIdentity};
if !([_uav, _helperIdentity] call A3UE_fnc_fpv_canActuate) exitWith {false};

// The controller supplies the target used to compute this intercept. Legacy callers
// capture intent at helper entry; they cannot fence a target change before entry.
private _explicitTarget = count _this >= 4;
if (!_explicitTarget) then {_targetNetId = _uav getVariable ["A3UE_FPV_targetNetId", ""];};
private _guidanceMode = _uav getVariable ["A3UE_FPV_mode", ""];
if (_targetRevision < 0) then {_targetRevision = _uav getVariable ["A3UE_FPV_targetRevision",0];};

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
// F4-2: never below the canopy-clearing transit floor, higher over tall obstacles ahead.
_trackingHeight = _trackingHeight max ([_uav] call A3UE_fnc_fpv_transitHeight);

private _moveInterval = [_profile, "trackingMoveInterval", 0.15] call A3UE_fnc_fpv_profileValue;
if (!(_moveInterval isEqualType 0) || {!finite _moveInterval} || {_moveInterval < 0.15} || {_moveInterval > 1.0}) then {
	_moveInterval = 0.15;
};

private _applied = false;
isNil {
if !([_uav, _helperIdentity] call A3UE_fnc_fpv_canActuate) exitWith {};
if (_guidanceMode == "TERMINAL_VECTOR" || {!((_uav getVariable ["A3UE_FPV_nativeControl",[]]) isEqualTo [])}) exitWith {};
if (!(_targetNetId isEqualType "") || {(_uav getVariable ["A3UE_FPV_targetNetId", ""]) isNotEqualTo _targetNetId}
	|| {(_uav getVariable ["A3UE_FPV_targetRevision",0]) != _targetRevision}
	|| {(_uav getVariable ["A3UE_FPV_mode", ""]) isNotEqualTo _guidanceMode}
	|| {_explicitTarget && {_guidanceMode != "TRACKING"}}) exitWith {};
private _currentTarget = if (_guidanceMode == "TRACKING") then {[_uav] call A3UE_fnc_fpv_resolveTarget} else {objNull};
if (_guidanceMode == "TRACKING" && {isNull _currentTarget || {netId _currentTarget != _targetNetId}}) exitWith {};
if (_guidanceMode == "TRACKING" && {!(([_uav,_currentTarget,false,[],false] call A3UE_fnc_fpv_supportEngagementReason) in ["","NO_VISIBLE_TARGET"])}) exitWith {};
// Read current cache only after the original identity/intent passes the effect fence.
private _lastMoveTarget = _uav getVariable ["A3UE_FPV_lastMoveTarget", []];
private _lastMoveUpdate = _uav getVariable ["A3UE_FPV_lastMoveUpdate", -1];
private _orderContext = _uav getVariable ["A3UE_FPV_trackingOrderContext", []];
private _tracking = _guidanceMode == "TRACKING";
private _contextReady = _orderContext isEqualType [] && {count _orderContext == 2}
	&& {(_orderContext # 0) isEqualTo _helperIdentity} && {(_orderContext # 1) isEqualTo _targetNetId};
private _cacheReady = _lastMoveTarget isEqualType [] && {count _lastMoveTarget == 3}
	&& {(_lastMoveTarget findIf {!(_x isEqualType 0) || {!finite _x}}) < 0}
	&& {_lastMoveUpdate isEqualType 0} && {finite _lastMoveUpdate}
	&& {_lastMoveUpdate >= 0} && {time >= _lastMoveUpdate};
// Lost-target prediction also uses this helper; retain its legacy refresh policy.
if (!_tracking) then {_moveInterval = 0.15;};

if (!_cacheReady || {_tracking && {!_contextReady}} || {_lastMoveTarget distance2D _moveTargetAtl > _moveDelta} || {time > (_lastMoveUpdate + _moveInterval)}) then {
_uav enableAI "ALL";
_uav setBehaviour "CARELESS";
_uav setCombatMode "BLUE";
_uav setSpeedMode "FULL";
_uav flyInHeight _trackingHeight;
_uav forceSpeed (_trackingSpeed / 3.6);

	_uav doMove _moveTargetAtl;
	_uav setVariable ["A3UE_FPV_lastMoveTarget", _moveTargetAtl];
	_uav setVariable ["A3UE_FPV_lastMoveUpdate", time];
	if (_tracking) then {_uav setVariable ["A3UE_FPV_trackingOrderContext", [+_helperIdentity, _targetNetId]];};
};

_applied = true;
};
_applied
