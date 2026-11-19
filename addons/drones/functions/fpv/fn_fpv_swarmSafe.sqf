// 1.0.9 friendly FPV swarm (SW-1e): is a strike on this target safe for our side? The swarm's own
// friendly-safety check: at the reservation, at the dive gate and once a second in the dive.
// - Protected within "radius" m of the target (or of the vehicle it is in), measured in 3D (SW-1f):
//   civilians, our side and its friends, crews included. Undercover rebels are our side.
// - Not protected: any enemy, captive or not. SW-1e: one lying wounded (AU makes a downed enemy
//   captive for up to 5 minutes while a player is near, fn_unconsciousAAF; in SW1d such men kept
//   their comrades safe for minutes). SW-1f (EJ after SW1e: "surrendered enemies should not shield
//   active enemies"): one who has surrendered (AU keeps him captive in his own side's group). Neither
//   is ever a target himself (filterTarget leaves captives out), but a blast at a comrade beside him
//   can kill him, and AU counts a dead unarmed enemy against the rebels (aggression, city support).
// - Managed drones and their crews never count, nor a spent one (SW-1f): a struck drone is parked,
//   unmanaged, 1000 m over its strike for 1.5 s with its crew alive (commitDetonation). Measured flat,
//   SW-1e took it for a friendly beside the next target and broke dives on it (SW1e: 3 times).
// The shared supportPassesSafetyRing keeps its rules for its other callers (backlog BL-24).
// [side, target, radius m] -> "" when safe, else what protects it ("class/side/captive" or "free")
params [["_side", sideUnknown], ["_target", objNull], ["_radius", 15]];
if (isNull _target) exitWith {"NO_TARGET"};
if !(_radius isEqualType 0 && {finite _radius}) then {_radius = 15;};
if (_radius <= 0) exitWith {""};
private _anchor = if (_target isKindOf "Man" && {!isNull objectParent _target}) then {objectParent _target} else {_target};
private _pos = getPosATL _anchor;
private _posASL = getPosASL _anchor;
private _protects = {
	params ["_unit"];
	private _group = side group _unit;
	alive _unit && {_group == civilian || {_group == _side} || {(_side getFriend _group) >= 0.6}}
};
// One of ours (managed), or one that has struck or is being removed.
private _ours = {
	params ["_object"];
	_object getVariable ["A3UE_FPV_managed", false] || {_object getVariable ["A3UE_FPV_detonationCommitted", false]}
		|| {_object getVariable ["A3UE_FPV_cleanupPending", false]}
};
private _why = "";
{
	if (!isNull _x && {alive _x} && {!([_x] call _ours)}) then {
		private _parent = objectParent _x;
		if (isNull _parent || {!([_parent] call _ours)}) then {
			private _subject = [_parent, _x] select (isNull _parent);
			if (((getPosASL _subject) vectorDistance _posASL) <= _radius) then {
				private _units = if (_x isKindOf "Man") then {[_x]} else {crew _x};
				private _found = _units findIf {[_x] call _protects};
				if (_found >= 0) then {
					private _unit = _units # _found;
					_why = format ["%1/%2/%3", typeOf _unit, side group _unit, ["free", "captive"] select (captive _unit)];
				};
			};
		};
	};
	if (_why != "") exitWith {};
} forEach (nearestObjects [_pos, ["Man", "LandVehicle", "Ship", "StaticWeapon", "Air"], _radius]);
_why
