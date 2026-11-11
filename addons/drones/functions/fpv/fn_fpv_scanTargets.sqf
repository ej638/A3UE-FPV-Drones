// LT-2 shared target scan. Legal hostile candidates in one scan circle, cached on this machine
// (missionNamespace, never broadcast). Every drone of a site passes the same key, so the site
// circle is scanned and filtered once per TTL instead of once per drone and scan; a drone's own
// circle uses its netId as the key.
// - nearEntities walks the entity lists only (units, vehicles, statics), not every map object as
//   nearestObjects does. It leaves out the dead, which selection discards anyway.
// - filterTarget gives the same legality as before (hostile side, alive, not captive, crew in a
//   vehicle counted as the vehicle, no managed drones). The caller still runs every check on each
//   candidate, so a cached entry is only a candidate: at worst a new target is seen one TTL late.
// [key, centerATL, radius, ttl, hostileSides] -> array of objects (a copy)
params [["_key", ""], ["_center", []], ["_radius", 0], ["_ttl", 1], ["_hostileSides", []]];
// F5 / PB-01: an RPC from a client never mutates this machine's cache (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {[]};
if (_key isEqualTo "" || {!(_center isEqualType [])} || {count _center < 2} || {_radius <= 0} || {_hostileSides isEqualTo []}) exitWith {[]};
_key = format ["%1|%2", _key, _hostileSides];
private _cache = missionNamespace getVariable ["A3UE_FPV_scanCache", createHashMap];
if (count _cache == 0) then {missionNamespace setVariable ["A3UE_FPV_scanCache", _cache];};
private _now = time;
private _entry = _cache getOrDefault [_key, []];
if (count _entry != 4 || {_now >= (_entry # 0)} || {(_entry # 0) - _now > _ttl + 1}
	|| {_radius != (_entry # 2)} || {(_center distance2D (_entry # 1)) > 10}) then {
	// Drop entries of drones that are gone (their keys are never asked for again).
	if (count _cache >= 64) then {
		{
			if (_now > ((_cache get _x) # 0) + 30) then {_cache deleteAt _x;};
		} forEach (keys _cache);
	};
	private _legal = [];
	{
		private _candidate = [_x, _hostileSides] call A3UE_fnc_fpv_filterTarget;
		if (!isNull _candidate) then {_legal pushBackUnique _candidate;};
	} forEach (_center nearEntities [["Man", "LandVehicle", "Air", "Ship", "StaticWeapon"], _radius]);
	_entry = [_now + _ttl, +_center, _radius, _legal];
	_cache set [_key, _entry];
	missionNamespace setVariable ["A3UE_FPV_scanCount", (missionNamespace getVariable ["A3UE_FPV_scanCount", 0]) + 1];
};
+(_entry # 3)
