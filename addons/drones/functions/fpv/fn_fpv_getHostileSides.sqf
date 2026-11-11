params [["_side", sideUnknown], ["_targetSide", sideUnknown]];

// sideUnknown means no encounter restriction, never an unknown target faction.
// Read live relations so cached contacts cannot retain a newly allied target.
private _combatSides = [west, east, independent];
if !(_side in _combatSides) exitWith {[]};
if !(_targetSide isEqualType sideUnknown) exitWith {[]};
if (_targetSide != sideUnknown && {!(_targetSide in _combatSides)}) exitWith {[]};

_combatSides select {
	_x != _side && {(_targetSide == sideUnknown || {_x == _targetSide})}
	&& {(_side getFriend _x) < 0.6}
}
