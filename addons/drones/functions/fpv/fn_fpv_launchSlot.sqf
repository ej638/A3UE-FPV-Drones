// Launch slot (F4-2 field fix): drones launched together must not share a point.
// The site standoff point depends only on the site and the players, so every drone of one
// deployment was placed on the same spot (support launches were 4 m apart). Colliding at
// launch, a KVN pair detonated through KVN's native hit handler before it ever flew.
// Each spawn reserves its point for 30 s. A spawn within 20 m (horizontal) of a reserved
// point moves to the next free slot across the launch heading: +-30 m steps out to 120 m,
// each step 5 m higher. Water slots are skipped; when every slot is taken the least crowded
// one is used. Server spawn time only: at most 9 candidates against at most 32 reservations.
// Metres; _dir is the compass launch heading (0 = north).
// [positionATL, launchDir] -> [positionATL, slot] (slot 0 = the requested point, unchanged)
params [["_pos", []], ["_dir", 0]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {[_pos, 0]};
if (!(_pos isEqualType []) || {count _pos < 2}
	|| {((_pos select [0, 2]) findIf {!(_x isEqualType 0) || {!finite _x}}) >= 0}) exitWith {[_pos, 0]};
if (!(_dir isEqualType 0) || {!finite _dir}) then {_dir = 0;};
private _height = _pos param [2, 0];
if (!(_height isEqualType 0) || {!finite _height}) then {_height = 0;};
private _now = time;
private _slots = missionNamespace getVariable ["A3UE_FPV_launchSlots", []];
if !(_slots isEqualType []) then {_slots = [];};
_slots = _slots select {_x isEqualType [] && {count _x == 4} && {(_now - (_x # 3)) >= 0} && {(_now - (_x # 3)) < 30}};

// Right of the launch heading.
private _acrossX = cos _dir;
private _acrossY = -(sin _dir);
private _best = [];
private _bestSlot = 0;
private _bestGap = -1;
{
	_x params ["_lateral", "_rise"];
	private _candidate = [(_pos # 0) + (_acrossX * _lateral), (_pos # 1) + (_acrossY * _lateral), _height + _rise];
	if (_forEachIndex == 0 || {!(surfaceIsWater _candidate)}) then {
		private _gap = 1e9;
		{_gap = _gap min ([_candidate # 0, _candidate # 1] distance2D [_x # 0, _x # 1]);} forEach _slots;
		if (_gap > _bestGap) then {
			_best = _candidate;
			_bestSlot = _forEachIndex;
			_bestGap = _gap;
		};
	};
	if (_bestGap >= 20) exitWith {};
} forEach [[0, 0], [30, 5], [-30, 5], [60, 10], [-60, 10], [90, 15], [-90, 15], [120, 20], [-120, 20]];

_slots pushBack [_best # 0, _best # 1, _best # 2, _now];
while {count _slots > 32} do {_slots deleteAt 0;};
missionNamespace setVariable ["A3UE_FPV_launchSlots", _slots];
[_best, _bestSlot]
