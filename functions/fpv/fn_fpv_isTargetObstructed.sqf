params [["_uav", objNull], ["_target", objNull]];

if (isNull _uav || {isNull _target}) exitWith {
	createHashMapFromArray [
		["blocked", false],
		["terrainBlocked", false],
		["obstructionCount", 0]
	]
};

private _startPosAsl = getPosASL _uav;
private _endPosAsl = getPosASL _target;

if (_target isKindOf "Man") then {
	_endPosAsl set [2, (_endPosAsl select 2) + 1.4];
} else {
	_endPosAsl set [2, (_endPosAsl select 2) + 1.0];
};

private _terrainBlocked = terrainIntersectASL [_startPosAsl, _endPosAsl];
private _intersections = lineIntersectsSurfaces [
	_startPosAsl,
	_endPosAsl,
	_uav,
	_target,
	true,
	4,
	"VIEW",
	"NONE"
];

private _obstructionCount = count (_intersections select {
	private _hitObject = _x param [2, objNull];
	!isNull _hitObject && {
		_hitObject != _uav &&
		_hitObject != _target &&
		_hitObject != objectParent _uav &&
		_hitObject != objectParent _target
	}
});

createHashMapFromArray [
	["blocked", _terrainBlocked || {_obstructionCount > 0}],
	["terrainBlocked", _terrainBlocked],
	["obstructionCount", _obstructionCount]
]