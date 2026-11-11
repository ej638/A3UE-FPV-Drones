// F4 one-line summary of the current attack pass for the RPT (at most ~140 chars),
// or "" when there is no pass for this exact target and target revision.
// pass=1 is the first pass, pass=2 the return pass after a flip; lifts = obstacle hops.
// [uav, target] -> string
params [["_uav", objNull], ["_target", objNull]];
if (isNull _uav || {isNull _target}) exitWith {""};
private _pass = _uav getVariable ["A3UE_FPV_attackPass", createHashMap];
if (!(_pass isEqualType createHashMap) || {count _pass == 0}) exitWith {""};
private _key = _pass getOrDefault ["key", []];
if (!(_key isEqualType []) || {count _key != 5} || {(_key # 1) != netId _target}
	|| {(_key # 2) != (_uav getVariable ["A3UE_FPV_targetRevision", 0])}) exitWith {""};
// A near miss names its style: OVER_TOP (just over the head) or OVER_SIDE (just beside it).
private _intent = _pass getOrDefault ["intent", ""];
if (_intent == "OVER") then {_intent = format ["OVER_%1", _pass getOrDefault ["overStyle", "TOP"]];};
// LT-1: step=written/late/zeroDt/refused/maxGapMs shows scheduler load on the dive.
private _steps = _pass getOrDefault ["steps", []];
if (!(_steps isEqualType []) || {count _steps != 5}) then {_steps = [0, 0, 0, 0, 0];};
format ["profile=%1 intent=%2 seed=%3 closestM=%4 maxSpeed=%5 entryM=%6 pass=%7 lifts=%8 step=%9",
	_pass getOrDefault ["profile", ""], _intent, _pass getOrDefault ["seed", -1],
	(round ((_pass getOrDefault ["closest", -1]) * 10)) / 10,
	(round ((_pass getOrDefault ["maxSpeed", 0]) * 10)) / 10,
	round (_pass getOrDefault ["entryRange", -1]),
	(_pass getOrDefault ["passIndex", 0]) + 1, _pass getOrDefault ["lifts", 0], _steps joinString "/"]
