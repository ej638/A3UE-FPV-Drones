// Pure state admission. No object reads/writes, authority grant or physics effects.
// _tolerant: the caller's A3UE_FPV_loadTolerantDive reading; only an explicit false restores the legacy GAP.
params [["_state", []], ["_key", []], ["_now", -1], ["_observedAt", -1], ["_tolerant", true]];

private _validNumber = {_this isEqualType 0 && {finite _this} && {abs _this <= 1e6}};
private _validVector = {
	_this isEqualType [] && {count _this == 3} && {(_this findIf {!(_x call _validNumber)}) < 0}
};
private _validClock = {_this isEqualType 0 && {finite _this}};
if (!(_now call _validClock) || {!(_observedAt call _validClock)} || {_now < 0} || {_observedAt < 0}) exitWith {["CLOCK_INVALID", 0]};
if (_state isEqualTo []) exitWith {["INIT", 0]};
if (!(_state isEqualType []) || {count _state != 12}) exitWith {["INVALID", 0]};
if !((_state # 0) isEqualTo _key) exitWith {["KEY", 0]};
if (!((_state # 1) call _validClock) || {!((_state # 2) call _validClock)}
	|| {([5,7,9] findIf {!((_state # _x) call _validNumber)}) >= 0}
	|| {([3,4,6,10,11] findIf {!((_state # _x) call _validVector)}) >= 0}
	|| {!((_state # 8) isEqualType "")}) exitWith {["INVALID", 0]};
if ((_state # 1) < 0 || {(_state # 2) < 0} || {(_state # 5) < 0}
	|| {(_state # 7) < 1} || {(_state # 7) != floor (_state # 7)}
	|| {abs (vectorMagnitude (_state # 3) - 1) > 0.001}
	|| {abs (vectorMagnitude (_state # 4) - 1) > 0.001}
	|| {abs ((_state # 3) vectorDotProduct (_state # 4)) > 0.001}) exitWith {["INVALID", 0]};
private _dt = _now - (_state # 1);
private _observedGap = _observedAt - (_state # 2);
if (_dt < 0 || {_observedGap < 0}) exitWith {["TIME_REVERSE", 0]};
// LT-1 (2026-11-10): a scheduler-late step must not drop dive authority (dedicated, 5-6 drones:
// every step a GAP, native AI hovered). Unless switched off or the simulation stalled behind
// real time, a late step integrates a capped 0.25 s, never the missed time: LATE continues
// an already-driven state up to 1 s; STALL re-seeds from the real airframe first.
if (_dt > 0.25) exitWith {
	if (_tolerant isEqualTo false || {_observedGap > _dt + 0.5}) then {["GAP", 0]} else {
		[["STALL", "LATE"] select (_dt <= 1 && {(_state # 9) > 0}), 0.25]
	}
};
if (_observedGap > 0.5) exitWith {["PAUSE", 0]};
if (_dt == 0) exitWith {["DUPLICATE", 0]};
["STEP", _dt]
