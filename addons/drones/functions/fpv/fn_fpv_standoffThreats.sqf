// Positions of alive hostile players for launch standoff (FS-02/FS-03).
// Spawn-time only: one bounded pass over allPlayers, never from a flight loop.
params [["_side", sideUnknown]];

private _hostileSides = [_side] call A3UE_fnc_fpv_getHostileSides;
if (_hostileSides isEqualTo []) exitWith {[]};
private _positions = [];
{
	if (alive _x && {!(_x isKindOf "HeadlessClient_F")} && {(side group _x) in _hostileSides}) then {
		_positions pushBack (getPosATL _x);
	};
} forEach allPlayers;
_positions
