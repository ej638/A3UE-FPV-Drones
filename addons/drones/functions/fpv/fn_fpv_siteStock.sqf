// Session site drone stock (field finding FS-04). Server-only, spawn-time only.
// A site rolls spawn chance and stock once per side holding it. Destroyed or spent
// drones deplete it, intact drones return when the site despawns, and one drone
// refills per interval (A3UE_FPV_siteStockRefillSeconds, default 900 s) up to the
// rolled maximum. A capture clears it, so a retaken site rolls fresh.
// Session means this mission run: nothing is written to the AU save.
//   ["OPEN", marker, side, profile] -> [available, max, skipped, spawnRoll]
//   ["SPEND", marker, side, count]  -> remaining (-1 when no record)
//   ["RETURN", marker, side, count] -> remaining (-1 when no record)
//   ["CLEAR", marker]               -> true
params [["_mode", ""], ["_markerX", ""], ["_siteSide", sideUnknown], ["_arg", 0]];

if (!isServer) exitWith {[]};
private _store = missionNamespace getVariable ["A3UE_FPV_siteStock", createHashMap];
if !(_store isEqualType createHashMap) then {_store = createHashMap;};
missionNamespace setVariable ["A3UE_FPV_siteStock", _store];

if (_mode == "CLEAR") exitWith {_store deleteAt _markerX; true};

private _interval = missionNamespace getVariable ["A3UE_FPV_siteStockRefillSeconds", 900];
if (!(_interval isEqualType 0) || {!finite _interval} || {_interval < 60} || {_interval > 7200}) then {_interval = 900;};

private _record = _store getOrDefault [_markerX, createHashMap];
if (count _record > 0 && {(_record getOrDefault ["side", sideUnknown]) != _siteSide}) then {
	_store deleteAt _markerX;
	_record = createHashMap;
};

if (_mode == "OPEN" && {count _record == 0}) then {
	private _profile = [_arg, createHashMap] select !(_arg isEqualType createHashMap);
	// Same rolls and order as the original per-activation stock.
	private _spawnChance = [_profile, "spawnChance", 1] call A3UE_fnc_fpv_profileValue;
	private _spawnRoll = if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {0} else {random 1};
	private _skipped = _spawnRoll > _spawnChance;
	private _count = 0;
	if (!_skipped) then {
		private _stockRange = [_profile, "stock", [1, 1]] call A3UE_fnc_fpv_profileValue;
		private _stockMin = ((_stockRange param [0, 1]) max 1);
		private _stockMax = ((_stockRange param [1, _stockMin]) max _stockMin);
		_count = _stockMin;
		if (_stockMax > _stockMin) then {
			_count = _stockMin + floor (random ((_stockMax - _stockMin) + 1));
		};
	};
	_record = createHashMapFromArray [
		["side", _siteSide], ["max", _count], ["remaining", _count], ["refillAt", -1],
		["skipped", _skipped], ["spawnRoll", _spawnRoll], ["rolledAt", time]
	];
	_store set [_markerX, _record];
};
if (count _record == 0) exitWith {-1};

// Lazy refill: no timer or worker; applied whenever the record is used.
private _max = _record get "max";
private _remaining = _record get "remaining";
private _refillAt = _record get "refillAt";
if (_remaining < _max && {_refillAt >= 0} && {time >= _refillAt}) then {
	private _steps = 1 + floor ((time - _refillAt) / _interval);
	_remaining = (_remaining + _steps) min _max;
	_refillAt = _refillAt + (_steps * _interval);
};

switch (_mode) do {
	case "SPEND": {
		_remaining = _remaining - ((_arg max 0) min _remaining);
	};
	case "RETURN": {
		_remaining = (_remaining + (_arg max 0)) min _max;
	};
};
// Invariant: below maximum always has a running refill timer; full has none.
if (_remaining < _max && {_refillAt < 0}) then {_refillAt = time + _interval;};
if (_remaining >= _max) then {_refillAt = -1;};
_record set ["remaining", _remaining];
_record set ["refillAt", _refillAt];

if (_mode == "OPEN") exitWith {[_remaining, _max, _record get "skipped", _record get "spawnRoll"]};
_remaining
