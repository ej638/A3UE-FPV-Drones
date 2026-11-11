params [
	["_side", sideUnknown],
	["_target", objNull],
	["_targPos", []],
	["_plan", createHashMap],
	["_observer", objNull],
	["_force", false]
];

if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};

if !(_plan isEqualType createHashMap) then {_plan = createHashMap;};
private _safetyRadius = _plan getOrDefault ["safetyRadius", 40];
if !(_safetyRadius isEqualType 0 && {finite _safetyRadius}) then {_safetyRadius = 40;};
if (_safetyRadius <= 0) exitWith {true};

// Precision locates a search area; an object engagement uses its current parent.
if (!isNull _target) then {
	if (_target isKindOf "Man" && {!isNull objectParent _target}) then {_target = objectParent _target;};
	_targPos = getPosATL _target;
};
if !(_targPos isEqualType [] && {count _targPos >= 2}) exitWith {false};

private _candidates = [];
private _generation = if (isNull _observer) then {-1} else {_observer getVariable ["A3UE_FPV_controllerGeneration", -1]};
private _cache = if (isNull _observer) then {[]} else {_observer getVariable ["A3UE_FPV_safetyCandidateCache", []]};
private _refresh = _force || {count _cache != 6};
if (!_refresh) then {
	_refresh = time >= (_cache # 0) || {_targPos distance2D (_cache # 1) > 10}
		|| {_safetyRadius != (_cache # 2)} || {_target isNotEqualTo (_cache # 4)} || {_generation != (_cache # 5)};
};
if (_refresh) then {
	// A padded discovery area catches ordinary entrants between the 0.5 s scans.
	// The final permission always scans fresh, including teleported/new objects.
	private _scanRadius = _safetyRadius + ([100, 0] select (isNull _observer || {_force}));
	_candidates = nearestObjects [_targPos, ["Man", "LandVehicle", "Ship", "StaticWeapon", "Air"], _scanRadius, true];
	if (!isNull _observer && {!_force}) then {
		_observer setVariable ["A3UE_FPV_safetyCandidateCache", [time + 0.5, +_targPos, _safetyRadius, _candidates, _target, _generation]];
	};
} else {_candidates = _cache # 3;};

private _protected = {
	params ["_unit"];
	alive _unit && {captive _unit || {side group _unit == civilian} || {side group _unit == _side} || {_side getFriend (side group _unit) >= 0.6}}
};
private _blocked = false;
{
	if (isNull _x || {!alive _x} || {_x getVariable ["A3UE_FPV_managed", false]}) then {continue;};
	private _parent = objectParent _x;
	if (!isNull _parent && {_parent getVariable ["A3UE_FPV_managed", false]}) then {continue;};
	private _subject = [_parent, _x] select (isNull _parent);
	if (_subject distance2D _targPos > _safetyRadius) then {continue;};
	// Check every occupant: a hostile commander cannot hide a protected passenger.
	if (_x isKindOf "Man") then {
		if ([_x] call _protected) exitWith {_blocked = true;};
	} else {
		if ((crew _x) findIf {[_x] call _protected} >= 0) exitWith {_blocked = true;};
	};
	if (_blocked) exitWith {};
} forEach _candidates;
!_blocked
