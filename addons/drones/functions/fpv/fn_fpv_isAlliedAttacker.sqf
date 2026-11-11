// A crossing autonomous managed attacker is incidental ray geometry, not a fuse target.
// Explicit targets, uncontrolled/native UAVs, wrecks and controlled assets remain obstacles.
params ["_uav", "_target", "_object"];
private _identity = _object getVariable ["A3UE_FPV_controllerIdentity", []];
if (isNull _object || {_object == _target} || {_object == objectParent _target}
	|| {!alive _object} || {!(_object getVariable ["A3UE_FPV_managed", false])}
	|| {count _identity != 4} || {(_identity # 3) < 0} || {(_identity # 1) != owner _object}
	|| {_object getVariable ["A3UE_FPV_detonating", false]}
	|| {!([_object] call A3UE_fnc_fpv_isSiteDroneActive)}
	|| {!((_object getVariable ["A3UE_FPV_mode", ""]) in ["TRACKING", "TERMINAL_ATTACK", "TERMINAL_VECTOR"])}
	|| {[_object] call A3UE_fnc_fpv_isExternallyControlled}) exitWith {false};
private _pilot = effectiveCommander _uav;
private _otherPilot = effectiveCommander _object;
if (isNull _pilot || {isNull _otherPilot} || {!alive _otherPilot}) exitWith {false};
private _side = side group _pilot;
private _otherSide = side group _otherPilot;
(_side in [east, west, independent]) && {_otherSide in [east, west, independent]}
	&& {(_side getFriend _otherSide) >= 0.6} && {(_otherSide getFriend _side) >= 0.6}
