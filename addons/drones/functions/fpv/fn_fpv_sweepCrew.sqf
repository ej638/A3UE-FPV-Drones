// F5 natural cleanup: a managed drone's own crew and groups never outlive its airframe.
// Started on the server by the drone's lifecycle Deleted handler, whatever deleted it (strike
// retirement, site despawn, support expiry, a vendor's native detonate-and-delete). Each pass
// deletes recorded crew that are still alive outside any vehicle (KVN's native detonation deletes
// only the airframe) and recorded groups that are local and empty. AU's lazy delete-when-empty
// processing missed the 10 s deadline, so the groups are deleted explicitly. Dead crew are left to
// AU's post-mortem. Bounded: at most _passes passes, _interval seconds apart when it can suspend.
// [crew, groups, netId, passes, interval] -> [crewDeleted, groupsDeleted, remaining]
params [["_crew", []], ["_groups", []], ["_netId", ""], ["_passes", 20], ["_interval", 0.5]];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {[0, 0, -1]};
if (!isServer || {!(_crew isEqualType [])} || {!(_groups isEqualType [])}) exitWith {[0, 0, -1]};
_crew = (_crew select {_x isEqualType objNull}) select [0, 8];
_groups = (_groups select {_x isEqualType grpNull}) select [0, 8];
private _crewDeleted = 0;
private _groupsDeleted = 0;
private _remaining = 0;
private _started = time;
for "_pass" from 1 to (_passes max 1) do {
	if (canSuspend && {_interval > 0}) then {sleep _interval;};
	{
		if (!isNull _x && {alive _x} && {isNull objectParent _x}) then {
			deleteVehicle _x;
			_crewDeleted = _crewDeleted + 1;
		};
	} forEach _crew;
	{
		if (!isNull _x && {local _x} && {(units _x) isEqualTo []}) then {
			deleteGroup _x;
			_groupsDeleted = _groupsDeleted + 1;
		};
	} forEach _groups;
	// Deletion completes at the end of the frame: count what is still really there.
	_remaining = ({!isNull _x && {alive _x} && {isNull objectParent _x}} count _crew) + ({!isNull _x && {(units _x) isEqualTo []}} count _groups);
	if (_remaining == 0 && {({!isNull _x} count _groups) == 0}) exitWith {};
};
private _left = {!isNull _x} count _groups;
if (_crewDeleted > 0 || {_left > 0} || {missionNamespace getVariable ["A3UE_FPV_debug", false]}) then {
	diag_log format ["[A3UE_FPV] crewCleanup id=%1 crewDeleted=%2 groupsDeleted=%3 groupsLeft=%4 afterS=%5",
		_netId, _crewDeleted, _groupsDeleted, _left, (round ((time - _started) * 10)) / 10];
};
[_crewDeleted, _groupsDeleted, _left]
