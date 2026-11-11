// LT-2: how many other drones of this machine are already on that target, attacking or waiting.
// Target selection subtracts A3UE_FPV_targetCrowdPenalty per drone, so a flight spreads over the
// targets it can see instead of stacking on one. Read-only, linear in that target's drones.
// [target, uav] -> number
params [["_target", objNull], ["_uav", objNull]];
if (isNull _target) exitWith {0};
private _record = (missionNamespace getVariable ["A3UE_FPV_attackBoard", createHashMap]) getOrDefault [netId _target, createHashMap];
if (count _record == 0) exitWith {0};
private _count = 0;
{
	if (!isNull _x && {alive _x} && {_x isNotEqualTo _uav}) then {_count = _count + 1;};
} forEach (((_record get "holders") apply {_x # 0}) + (_record get "queue"));
_count
