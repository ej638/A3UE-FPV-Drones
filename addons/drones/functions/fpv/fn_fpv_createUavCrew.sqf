// F5 owned UAV crew. AU 12.0.3's createVehicleCrew does the same for a UAV (the engine creates
// the crew, which then joins a new group of the requested side) but leaves the engine's own group
// behind, empty and unmarked, at every spawn. Here the new group is created delete-when-empty and
// the emptied engine group is deleted at once. Unscheduled spawn path, constant work per spawn.
// [side, uav] -> group (grpNull when the UAV has no crew)
params [["_side", sideUnknown], ["_uav", objNull]];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {grpNull};
if (isNull _uav || {!(_side isEqualType sideUnknown)}) exitWith {grpNull};
private _group = grpNull;
isNil {
	if ((crew _uav) isEqualTo []) then {createVehicleCrew _uav;};
	private _crew = crew _uav;
	if (_crew isEqualTo []) exitWith {};
	private _engineGroups = [];
	{_engineGroups pushBackUnique (group _x);} forEach _crew;
	_group = createGroup [_side, true];
	if (isNull _group) exitWith {
		// Group limit reached: the crew stay in the engine group, marked like any crew group.
		_group = _engineGroups # 0;
		_group deleteGroupWhenEmpty true;
	};
	_crew joinSilent _group;
	_group selectLeader (effectiveCommander _uav);
	_group addVehicle _uav;
	{
		if (!isNull _x && {_x isNotEqualTo _group} && {(units _x) isEqualTo []}) then {deleteGroup _x;};
	} forEach _engineGroups;
	// Not yet empty (membership settling): mark it and hand it to the deletion sweep.
	private _kept = _engineGroups select {!isNull _x && {_x isNotEqualTo _group}};
	{_x deleteGroupWhenEmpty true;} forEach _kept;
	if (_kept isNotEqualTo []) then {_uav setVariable ["A3UE_FPV_crewGroups", _kept];};
};
_group
