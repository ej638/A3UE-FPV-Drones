// LOW_RUN tunables (EN-02, lowest line LL-1: docs/internal/FPV_LowLine_Design_20261116.md), read
// where they are used (owner-local missionNamespace). SI units: metres, seconds, m/s.
// A3UE_FPV_lowRun = false restores today's profile selection exactly; A3UE_FPV_contactFuseAny =
// false restores today's fuse rules exactly. QA switches (A3UE_FPV_QA_*) are for the disposable
// EJ_FPV_QA profile only. The fixed values below the tunables are design constants, not settings.
// Returns a hashmap; callers only read it. LT-2: inside one controller tick the values are read
// once (tick memo, like attackSettings). Outside a tick every call is live.
if (!isNil "_fpvTick" && {"lowRunSettings" in _fpvTick}) exitWith {_fpvTick get "lowRunSettings"};
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
private _floor = ["A3UE_FPV_lowRunFloorM", 1.0, 0.3, 10] call _number;
private _max = ["A3UE_FPV_lowRunMaxM", 4.0, _floor, 15] call _number;
private _speed = missionNamespace getVariable ["A3UE_FPV_lowRunSkimSpeed", [15, 20]];
if (!(_speed isEqualType []) || {count _speed != 2} || {(_speed findIf {!(_x isEqualType 0) || {!finite _x}}) >= 0}) then {
	_speed = [15, 20];
};
_speed = _speed apply {(_x max 5) min 40};
_speed = [selectMin _speed, selectMax _speed];
// QA: a forced skim height (clearance under the airframe); -1 = sampled.
private _forcedHeight = missionNamespace getVariable ["A3UE_FPV_QA_lowRunHeight", -1];
if (!(_forcedHeight isEqualType 0) || {!finite _forcedHeight} || {_forcedHeight <= 0}) then {
	_forcedHeight = -1;
} else {
	_forcedHeight = (_forcedHeight max 0.2) min 15;
};
private _result = createHashMapFromArray [
	["enabled", ["A3UE_FPV_lowRun", true] call _flag],
	// The natural share (LL-2, EJ 16 November): 1 in 3 eligible attacks. Only fiber drones are
	// eligible, so this is a third of KVN attacks on a man or a parked vehicle 300 m or more out.
	["weight", ["A3UE_FPV_lowRunWeight", 1 / 3, 0, 1] call _number],
	["minRange", ["A3UE_FPV_lowRunMinRangeM", 300, 100, 2000] call _number],
	// The nearest hand-off; a high arrival hands off farther out, up to handoffMax, so the drawn
	// 15-20 deg glide is down by skimFrom + levelOut (LR-1c, proven in engine sessions 1c and 1d).
	["handoff", ["A3UE_FPV_lowRunHandoffM", 350, 150, 1000] call _number],
	["handoffMax", ["A3UE_FPV_lowRunHandoffMaxM", 500, 150, 1500] call _number],
	["floor", _floor],
	["max", _max],
	["skimSpeed", _speed],
	// The weave's reach either side of the line; the surveyed corridor is 1.5 m wider (airframe and
	// tracking). Anything in that corridor is flown over.
	["weaveCap", ["A3UE_FPV_lowRunWeaveCapM", 3.5, 0, 8] call _number],
	// A drone waiting its turn that will go low waits on this ring instead of the 140 m overwatch
	// ring, so it has room to get down when it is cleared (LR-1c).
	["waitRing", ["A3UE_FPV_lowRunWaitRingM", 500, 300, 1000] call _number],
	// Survey work per call, in units of about 25 microseconds (about 0.4 ms).
	["checkUnits", ["A3UE_FPV_lowRunCheckUnits", 16, 2, 200] call _number],
	["contactAny", ["A3UE_FPV_contactFuseAny", true] call _flag],
	["forcedHeight", _forcedHeight],
	// Design constants.
	["sprintM", 60], ["sprintS", 2.2], ["recheck", 1.0], ["skimFrom", 200], ["levelOut", 50], ["glideMax", 30],
	// The line: 0.7 m over what it flies over, climbing at most 15 deg and coming down at most 30 deg.
	["over", 0.7], ["climb", tan 15], ["descent", tan 30]
];
if (!isNil "_fpvTick") then {_fpvTick set ["lowRunSettings", _result];};
_result
