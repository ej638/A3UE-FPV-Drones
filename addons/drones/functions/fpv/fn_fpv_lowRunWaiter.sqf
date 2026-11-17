// LOW_RUN for a drone waiting its turn (LR-1c; EJ, 16 November: every drone may go low, the second
// of a pair too), owner-local. The attack board makes the other drones on a target wait on the
// 140 m overwatch ring, inside the low run's 300 m minimum, so they could never go low. A waiting
// drone that would be low when it is cleared (the same draw attackEngagement makes then: peek)
// waits on the low run's outer ring instead (waitRing), far enough out to glide down and skim in.
// Decided once per engagement key (identity, target, target revision), with one RPT line when a
// drone is nominated. The controller calls it from its unscheduled tick (never suspends).
// [uav, target, controllerIdentity] -> true when it waits on the outer ring
params [["_uav", objNull], ["_target", objNull], ["_controllerIdentity", []]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};
if (isNull _uav || {isNull _target} || {!local _uav}) exitWith {false};
private _key = [+_controllerIdentity, netId _target, _uav getVariable ["A3UE_FPV_targetRevision", 0]];
private _known = _uav getVariable ["A3UE_FPV_lowWaiter", []];
if (_known isEqualType [] && {count _known == 2} && {(_known # 0) isEqualTo _key}) exitWith {_known # 1};
// LR-1d, QA LOW_RUN_WING: only a drone waiting behind another drone's attack is the second drone.
// Every pair starts with a short wait for both (the board's follow-up delay after an earlier
// attack on the same target), so in engine session 1c the first drone was forced low too. Not
// decided until then. The board is current: attackSlot ran earlier in this same tick.
if (((call A3UE_fnc_fpv_attackSettings) # 7) == "LOW_RUN_WING"
	&& {((((missionNamespace getVariable ["A3UE_FPV_attackBoard", createHashMap]) getOrDefault [netId _target, createHashMap])
		getOrDefault ["holders", []]) findIf {!((_x # 0) isEqualTo _uav)}) < 0}) exitWith {false};
private _engagement = [_uav, _target, _controllerIdentity, true, true] call A3UE_fnc_fpv_attackEngagement;
private _low = (_engagement param [1, ""]) == "LOW_RUN";
_uav setVariable ["A3UE_FPV_lowWaiter", [_key, _low]];
if (_low) then {
	diag_log format ["[A3UE_FPV] lowWait id=%1 target=%2 ringM=%3 rangeM=%4",
		_uav getVariable ["A3UE_FPV_netId", netId _uav], netId _target,
		round ((call A3UE_fnc_fpv_lowRunSettings) get "waitRing"), round ((getPosASL _uav) distance2D (getPosASL _target))];
};
_low
