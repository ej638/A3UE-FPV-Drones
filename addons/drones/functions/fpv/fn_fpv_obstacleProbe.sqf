// F4-2 obstacle probe (trees, buildings, terrain). One ray from _from to _to and, only when
// asked and an object is hit, one ray straight down from above the hit for the obstacle's top.
// Moving things (units, vehicles, other drones) are not static obstacles and are skipped.
// Callers bound the rate (transit 2 Hz, dive lift 10 Hz, entry line 4 Hz, flip check once).
// [uav, target or objNull, fromASL, toASL, ignoreTerrain, wantTop] -> [] when clear, else
// [hitASL, top z ASL, object (objNull = terrain), terrain z ASL under the hit]
params [["_uav", objNull], ["_target", objNull], ["_from", []], ["_to", []], ["_ignoreTerrain", false], ["_wantTop", false]];
if (!(_from isEqualType []) || {!(_to isEqualType [])} || {count _from != 3} || {count _to != 3}
	|| {(_from vectorDistance _to) < 0.1}) exitWith {[]};
private _owner = {
	params ["_hit"];
	private _object = _hit param [3, objNull];
	if (isNull _object) then {_object = _hit param [2, objNull];};
	_object
};
private _hits = lineIntersectsSurfaces [_from, _to, _uav, _target, true, 4, "VIEW", "GEOM"];
private _index = _hits findIf {
	private _object = [_x] call _owner;
	if (isNull _object) then {!_ignoreTerrain} else {!(_object isKindOf "AllVehicles")}
};
if (_index < 0) exitWith {[]};
private _hit = _hits # _index;
private _hitPos = +(_hit # 0);
private _object = [_hit] call _owner;
private _terrainZ = getTerrainHeightASL [_hitPos # 0, _hitPos # 1];
private _top = _hitPos # 2;
if (_wantTop && {!isNull _object}) then {
	private _down = lineIntersectsSurfaces [[_hitPos # 0, _hitPos # 1, ((_hitPos # 2) max (_from # 2)) + 40],
		[_hitPos # 0, _hitPos # 1, _terrainZ - 0.5], _uav, _target, true, 1, "VIEW", "GEOM"];
	_top = if (_down isEqualTo []) then {(_hitPos # 2) + 10} else {(((_down # 0) # 0) # 2) max (_hitPos # 2)};
};
[_hitPos, _top, _object, _terrainZ]
