// LOW_RUN line lookup (lowest line LL-1), owner-local, read-only: the latest survey's line at a
// point. lowRunAim flies it; attackNavigation's obstacle probe leaves alone what it already clears.
// [uav, posASL] -> [] (no survey yet), or [lineZ, along, sideways, dir]
//   lineZ: the line's height (ASL, the airframe's lowest point) level with the point, held at the
//   ends; along: metres from the survey's origin toward its target; sideways: metres off the line
//   (+ to the right of dir); dir: the line's unit direction (flat).
params [["_uav", objNull], ["_pos", []]];
if (isNull _uav || {!(_pos isEqualType [])} || {count _pos < 2}) exitWith {[]};
private _record = _uav getVariable ["A3UE_FPV_lowRun", createHashMap];
if !(_record isEqualType createHashMap) exitWith {[]};
private _result = _record getOrDefault ["result", []];
if (count _result < 4) exitWith {[]};
_result params ["", "_origin", "_targetAt", "_plan"];
private _n = count _plan;
if (_n == 0) exitWith {[]};
private _flat = [(_targetAt # 0) - (_origin # 0), (_targetAt # 1) - (_origin # 1), 0];
private _range = vectorMagnitude _flat;
private _dir = if (_range > 0.01) then {_flat vectorMultiply (1 / _range)} else {[0, 1, 0]};
private _length = (_range - 0.5) max 1;
private _rel = [(_pos # 0) - (_origin # 0), (_pos # 1) - (_origin # 1), 0];
private _along = _rel vectorDotProduct _dir;
private _side = ((_rel # 0) * (_dir # 1)) - ((_rel # 1) * (_dir # 0));
private _s = (_along max 0) min _length;
private _i = ((floor (_s / 5)) max 0) min (_n - 1);
private _j = (_i + 1) min (_n - 1);
private _s0 = (5 * _i) min _length;
private _s1 = (5 * _j) min _length;
private _u = if (_s1 > _s0) then {(((_s - _s0) / (_s1 - _s0)) max 0) min 1} else {0};
[(_plan # _i) + ((_plan # _j) - (_plan # _i)) * _u, _along, _side, _dir]
