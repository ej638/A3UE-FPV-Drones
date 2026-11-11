// LT-2 overwatch: a drone waiting for its turn watches the target from a ring instead of diving.
// The native AI flies it (TRACKING mode, no second movement writer): one order at most every
// second, or sooner when the ring point has moved 40 m. Outside the ring it closes at tracking
// speed; on the ring it loiters at ring speed. Height is the transit floor plus the drone's stagger.
// The controller calls this from its unscheduled tick with its own identity.
// [uav, target, profile, drone number, targetNetId, targetRevision] -> true when the order is current
params [["_uav", objNull], ["_target", objNull], ["_profile", createHashMap], ["_index", 0], ["_targetNetId", ""], ["_targetRevision", -1]];

if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};

if (isNull _uav || {isNull _target}) exitWith {false};
if (!local _uav) exitWith {false};

// Inherit the controller's original identity across scheduler preemption.
private _helperIdentity = if (isNil "_controllerIdentity") then {
    +(_uav getVariable ["A3UE_FPV_controllerIdentity", []])
} else {+_controllerIdentity};
if !([_uav, _helperIdentity] call A3UE_fnc_fpv_canActuate) exitWith {false};

private _uavPos = getPosASL _uav;
private _targetPos = getPosASL _target;
private _targetVelocity = velocity _target;
if (([_uavPos, _targetPos, _targetVelocity] findIf {count _x != 3 || {(_x findIf {!(_x isEqualType 0) || {!finite _x} || {abs _x > 1e6}}) >= 0}}) >= 0) exitWith {false};

private _settings = call A3UE_fnc_fpv_wingSettings;
private _point = [_uavPos, _targetPos, _targetVelocity, _settings # 4, _index] call A3UE_fnc_fpv_overwatchPoint;

private _trackingSpeed = [_profile, "trackingSpeed", 90] call A3UE_fnc_fpv_profileValue;
if (!(_trackingSpeed isEqualType 0) || {_trackingSpeed <= 0}) then {
	_trackingSpeed = 90;
};
private _speed = if (_point # 4) then {(_point # 3) min (_trackingSpeed / 3.6)} else {_trackingSpeed / 3.6};

private _heightFloor = [_profile, "trackingHeightASL", 10] call A3UE_fnc_fpv_profileValue;
if (!(_heightFloor isEqualType 0) || {_heightFloor < 0}) then {
	_heightFloor = 10;
};
// F4-2 transit floor (canopy clearance, raised over tall obstacles ahead), never below 30 m.
private _height = ((_heightFloor max ([_uav] call A3UE_fnc_fpv_transitHeight)) max 30) + (_point # 2);
private _moveTargetAtl = [_point # 0, _point # 1, _height];

private _applied = false;
isNil {
if !([_uav, _helperIdentity] call A3UE_fnc_fpv_canActuate) exitWith {};
if ((_uav getVariable ["A3UE_FPV_mode", ""]) != "TRACKING" || {!((_uav getVariable ["A3UE_FPV_nativeControl",[]]) isEqualTo [])}) exitWith {};
if (!(_targetNetId isEqualType "") || {(_uav getVariable ["A3UE_FPV_targetNetId", ""]) isNotEqualTo _targetNetId}
	|| {(_uav getVariable ["A3UE_FPV_targetRevision",0]) != _targetRevision}) exitWith {};
if !(([_uav,_target,false,[],false] call A3UE_fnc_fpv_supportEngagementReason) in ["","NO_VISIBLE_TARGET"]) exitWith {};
private _order = _uav getVariable ["A3UE_FPV_overwatchOrder", []];
private _orderReady = _order isEqualType [] && {count _order == 2} && {(_order # 0) isEqualType 0}
	&& {time >= (_order # 0)} && {(_order # 1) isEqualType []} && {count (_order # 1) == 3};
if (!_orderReady || {time - (_order # 0) >= 1} || {((_order # 1) distance2D _moveTargetAtl) > 40}) then {
_uav enableAI "ALL";
_uav setBehaviour "CARELESS";
_uav setCombatMode "BLUE";
_uav setSpeedMode "NORMAL";
_uav flyInHeight _height;
_uav forceSpeed _speed;

	_uav doMove _moveTargetAtl;
	_uav setVariable ["A3UE_FPV_overwatchOrder", [time, _moveTargetAtl]];
	// When this drone is cleared, its first attack order must not wait on the tracking order cache.
	_uav setVariable ["A3UE_FPV_lastMoveUpdate", -1];
};

_applied = true;
};
_applied
