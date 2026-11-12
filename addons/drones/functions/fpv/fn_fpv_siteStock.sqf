// Session site drone stock (field finding FS-04). Server-only, spawn-time only.
// A site rolls spawn chance and stock once per side holding it. Destroyed or spent
// drones deplete it, intact drones return when the site despawns, and one drone
// refills per interval (A3UE_FPV_siteStockRefillSeconds, default 900 s) up to the
// rolled maximum. A capture clears it, so a retaken site rolls fresh.
// Session means this mission run: nothing is written to the AU save.
// User settings (1.0.7), applied when a site rolls (so they affect sites rolled afterwards):
//   frequency OFF   -> no drones and no roll recorded (re-enabling lets the site roll later);
//             LESS/MORE -> spawn chance x0.5 / x1.5 (capped at 1); ALWAYS -> chance 1, no roll;
//   per site  FEWER/MORE -> one drone fewer / more at both ends of the stock range (at least 1);
//   refill    0 = never; otherwise the interval (default 900 s). Read live on every use.
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

// Default 900 s; 0 = never (validated by userSetting, which reads A3UE_FPV_siteStockRefillSeconds).
private _interval = ["siteRefillSeconds"] call A3UE_fnc_fpv_userSetting;

private _record = _store getOrDefault [_markerX, createHashMap];
if (count _record > 0 && {(_record getOrDefault ["side", sideUnknown]) != _siteSide}) then {
	_store deleteAt _markerX;
	_record = createHashMap;
};

private _frequency = ["siteFrequency"] call A3UE_fnc_fpv_userSetting;
// OFF: this activation gets nothing, and nothing is recorded, so the site rolls normally on a
// later activation once the setting is back on. A site that already rolled keeps its stock.
if (_mode == "OPEN" && {count _record == 0} && {_frequency == "OFF"}) exitWith {[0, 0, true, 1]};

if (_mode == "OPEN" && {count _record == 0}) then {
	private _profile = [_arg, createHashMap] select !(_arg isEqualType createHashMap);
	// Same rolls and order as the original per-activation stock.
	private _spawnChance = [_profile, "spawnChance", 1] call A3UE_fnc_fpv_profileValue;
	_spawnChance = switch (_frequency) do {
		case "LESS": {_spawnChance * 0.5};
		case "MORE": {(_spawnChance * 1.5) min 1};
		case "ALWAYS": {1};
		default {_spawnChance};
	};
	private _spawnRoll = if (_frequency == "ALWAYS") then {0} else {random 1};
	private _skipped = _spawnRoll > _spawnChance;
	private _count = 0;
	if (!_skipped) then {
		private _stockRange = [_profile, "stock", [1, 1]] call A3UE_fnc_fpv_profileValue;
		private _delta = switch (["sitePerSite"] call A3UE_fnc_fpv_userSetting) do {
			case "FEWER": {-1};
			case "MORE": {1};
			default {0};
		};
		private _rawMin = _stockRange param [0, 1];
		private _rawMax = _stockRange param [1, _rawMin];
		private _stockMin = (_rawMin + _delta) max 1;
		private _stockMax = (_rawMax + _delta) max _stockMin;
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
if (_interval > 0 && {_remaining < _max} && {_refillAt >= 0} && {time >= _refillAt}) then {
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
// Invariant: below maximum always has a running refill timer; full, or refill set to never, has none.
if (_interval > 0 && {_remaining < _max} && {_refillAt < 0}) then {_refillAt = time + _interval;};
if (_remaining >= _max || {_interval <= 0}) then {_refillAt = -1;};
_record set ["remaining", _remaining];
_record set ["refillAt", _refillAt];

if (_mode == "OPEN") exitWith {[_remaining, _max, _record get "skipped", _record get "spawnRoll"]};
_remaining
