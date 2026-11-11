params [["_target", objNull], ["_hostileSides", []]];

if (isNull _target || {!alive _target}) exitWith {objNull};
if (_target isKindOf "Man") then {
	private _parent = objectParent _target;
	if (!isNull _parent) then {_target = _parent;};
};
if (isNull _target || {!alive _target} || {_target getVariable ["A3UE_FPV_managed", false]}) exitWith {objNull};

private _commander = if (_target isKindOf "Man") then {_target} else {effectiveCommander _target};
if (isNull _commander || {!alive _commander}) then {_commander = driver _target;};
if (isNull _commander || {!alive _commander}) then {
	_commander = ((crew _target) select {alive _x}) param [0, objNull];
};
// Empty vehicles/statics and captive commanders have no eligible target side.
if (isNull _commander || {!alive _commander} || {captive _commander}) exitWith {objNull};
if !((side group _commander) in _hostileSides) exitWith {objNull};

_target
