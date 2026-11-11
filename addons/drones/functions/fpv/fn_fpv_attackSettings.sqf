// F4 attack-run tunables, read where they are used (owner/server-local missionNamespace).
// Returns [enabled, speedScale, weaveScale, pilotReaction, profiles, outcomeIntents,
//          contactFuse, forcedProfile, forcedIntent, qaSeed,
//          reversal, obstacleAvoid, transitFloorAGL, forcedReturnIntent, reversalMinAGL].
// The master switch A3UE_FPV_attackRun = false turns every F4 feature off (F2C-L).
// trajectoryLimits reads the master switch and speed scale itself so it stays dependency-free.
// LT-2: inside one controller tick the values are read once (tick memo; a dive pass asked for
// them six times). Callers only read the array. Outside a tick every call is live.
if (!isNil "_fpvTick" && {"attackSettings" in _fpvTick}) exitWith {_fpvTick get "attackSettings"};
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
private _choice = {
	params ["_name", "_allowed"];
	private _value = missionNamespace getVariable [_name, ""];
	if (!(_value isEqualType "") || {!(_value in _allowed)}) then {_value = "";};
	_value
};
private _read = {
if !(["A3UE_FPV_attackRun", true] call _flag) exitWith {[false, 0, 0, false, false, false, false, "", "", -1, false, false, 0, "", 0]};
// OVER is a fly-past near miss; OVER_TOP / OVER_SIDE force its style (just over the head / just beside it).
private _intents = ["", "DIRECT", "GROUND_SHORT", "GROUND_SIDE", "OVER", "OVER_TOP", "OVER_SIDE"];
private _seed = missionNamespace getVariable ["A3UE_FPV_QA_seed", -1];
if (!(_seed isEqualType 0) || {!finite _seed} || {_seed < 0}) then {_seed = -1;} else {_seed = (floor _seed) mod 4096;};
[true,
	["A3UE_FPV_attackSpeedScale", 1, 0, 1.5] call _number,
	["A3UE_FPV_weaveScale", 1, 0, 2] call _number,
	["A3UE_FPV_pilotReaction", true] call _flag,
	["A3UE_FPV_attackProfiles", true] call _flag,
	["A3UE_FPV_outcomeIntents", true] call _flag,
	["A3UE_FPV_fuseContactOnly", true] call _flag,
	["A3UE_FPV_QA_forceProfile", ["", "DIRECT", "HIGH_DIVE", "FLANK"]] call _choice,
	["A3UE_FPV_QA_forceIntent", _intents] call _choice,
	_seed,
	// F4-2: missed-pass flip, tree/obstacle awareness, native transit floor.
	["A3UE_FPV_attackReversal", true] call _flag,
	["A3UE_FPV_obstacleAvoid", true] call _flag,
	["A3UE_FPV_transitFloorAGL", 35, 0, 120] call _number,
	["A3UE_FPV_QA_forceReturnIntent", _intents] call _choice,
	["A3UE_FPV_reversalMinAGL", 1.2, 0, 100] call _number]
};
private _result = call _read;
if (!isNil "_fpvTick") then {_fpvTick set ["attackSettings", _result];};
_result
