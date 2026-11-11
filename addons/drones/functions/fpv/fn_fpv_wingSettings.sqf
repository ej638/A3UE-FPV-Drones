// LT-2 tunables, read where they are used (owner/server-local missionNamespace).
// Returns [frameDriver, frameBudgetMs, attackersPerTarget, followUpDelay s, overwatchRadius m,
//          overwatchRetarget, leanBrain, sharedScan, slotTimeout s, crowdPenalty, perfLog,
//          attackSpacing m].
//  0 A3UE_FPV_frameDriver          the frame director steps attacking drones (false = the
//                                  scheduled controller steps them, as in 1.0.3)
//  1 A3UE_FPV_frameBudgetMs        director time per frame before the rest wait a frame
//  2 A3UE_FPV_attackersPerTarget   drones cleared to attack one target at once (0 = no limit,
//                                  no overwatch: every tracking drone attacks, as in 1.0.3)
//  3 A3UE_FPV_attackFollowUpDelay  pause after an attack ends before the next drone is cleared
//  4 A3UE_FPV_overwatchRadius      ring the waiting drones fly around the target
//  5 A3UE_FPV_overwatchRetarget    a waiting drone may leave for a less crowded target
//  6 A3UE_FPV_leanBrain            lower controller rates outside the attack (false = 1.0.3 rates)
//  7 A3UE_FPV_sharedScan           one entity scan per site shared by its drones (false = 1.0.3 scans)
//  8 A3UE_FPV_attackSlotTimeout    a cleared drone that stays close without diving gives way
//  9 A3UE_FPV_targetCrowdPenalty   target score penalty per drone already on that target
// 10 A3UE_FPV_perfLog              director line every 10 s instead of every 60 s
// 11 A3UE_FPV_attackSpacing        targets this close together share one attack at a time (0 = off)
// Inside one controller tick the values are read once (tick memo); elsewhere every call is live.
if (!isNil "_fpvTick" && {"wingSettings" in _fpvTick}) exitWith {_fpvTick get "wingSettings"};
private _number = {
	params ["_name", "_default", "_min", "_max"];
	private _value = missionNamespace getVariable [_name, _default];
	if (!(_value isEqualType 0) || {!finite _value}) then {_value = _default;};
	(_value max _min) min _max
};
private _flag = {
	params ["_name", "_default"];
	private _value = missionNamespace getVariable [_name, _default];
	[_default, _value] select (_value isEqualType true)
};
private _result = [
	["A3UE_FPV_frameDriver", true] call _flag,
	["A3UE_FPV_frameBudgetMs", 2.5, 0.5, 10] call _number,
	floor (["A3UE_FPV_attackersPerTarget", 1, 0, 8] call _number),
	["A3UE_FPV_attackFollowUpDelay", 2.5, 0, 30] call _number,
	["A3UE_FPV_overwatchRadius", 140, 60, 400] call _number,
	["A3UE_FPV_overwatchRetarget", true] call _flag,
	["A3UE_FPV_leanBrain", true] call _flag,
	["A3UE_FPV_sharedScan", true] call _flag,
	["A3UE_FPV_attackSlotTimeout", 20, 5, 120] call _number,
	["A3UE_FPV_targetCrowdPenalty", 700, 0, 5000] call _number,
	["A3UE_FPV_perfLog", false] call _flag,
	["A3UE_FPV_attackSpacing", 25, 0, 200] call _number
];
if (!isNil "_fpvTick") then {_fpvTick set ["wingSettings", _result];};
_result
