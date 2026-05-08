params [
	["_uav", objNull],
	["_target", objNull],
	["_profile", createHashMap]
];

if (isNull _uav || {isNull _target} || {!alive _target}) exitWith {
	[_target, "NONE", "NO_TARGET"] call A3UE_fnc_fpv_emptyImpactSolution
};

private _configuredImpactMode = [_profile, "terminalImpactMode", "DIRECT_BODY"] call A3UE_fnc_fpv_profileValue;
if !(_configuredImpactMode isEqualType "") then {
	_configuredImpactMode = "DIRECT_BODY";
};

private _fallbackAllowed = [_profile, "impactFallbackAllowObstructionSurface", true] call A3UE_fnc_fpv_profileValue;
if !(_fallbackAllowed isEqualType true) then {
	_fallbackAllowed = true;
};

private _fallbackRadius = [_profile, "impactFallbackRadius", 0] call A3UE_fnc_fpv_profileValue;
if (!(_fallbackRadius isEqualType 0) || {_fallbackRadius < 0}) then {
	_fallbackRadius = 0;
};

private _groundOffset = [_profile, "impactFallbackGroundOffset", 0] call A3UE_fnc_fpv_profileValue;
if (!(_groundOffset isEqualType 0) || {_groundOffset < 0}) then {
	_groundOffset = 0;
};

private _infantryGroundLead = [_profile, "detonationInfantryGroundLead", 0] call A3UE_fnc_fpv_profileValue;
if (!(_infantryGroundLead isEqualType 0) || {_infantryGroundLead < 0}) then {
	_infantryGroundLead = 0;
};

private _uavPosAsl = getPosASL _uav;
private _targetPosAsl = getPosASL _target;
private _obstructionInfo = [_uav, _target] call A3UE_fnc_fpv_isTargetObstructed;
private _targetObstructed = _obstructionInfo getOrDefault ["blocked", false];
private _incomingVector = _targetPosAsl vectorDiff _uavPosAsl;
private _incomingDir2D = [_incomingVector select 0, _incomingVector select 1, 0];
private _incomingDir2DMag = vectorMagnitude _incomingDir2D;

if (_incomingDir2DMag <= 0.01) then {
	private _fallbackDir = vectorDir _uav;
	_incomingDir2D = [_fallbackDir select 0, _fallbackDir select 1, 0];
	_incomingDir2DMag = vectorMagnitude _incomingDir2D;
};

if (_incomingDir2DMag <= 0.01) then {
	_incomingDir2D = [0, 1, 0];
	_incomingDir2DMag = 1;
};

_incomingDir2D = _incomingDir2D vectorMultiply (1 / _incomingDir2DMag);

private _targetVelocity = velocity _target;
private _targetVelocity2D = [_targetVelocity select 0, _targetVelocity select 1, 0];
private _targetVelocity2DMag = vectorMagnitude _targetVelocity2D;
private _targetMoveDir2D = if (_targetVelocity2DMag > 0.1) then {
	_targetVelocity2D vectorMultiply (1 / _targetVelocity2DMag)
} else {
	_incomingDir2D
};

private _makeGroundPoint = {
	params ["_originAsl", ["_leadDir2D", [0, 0, 0]], ["_leadDistance", 0], ["_heightOffset", 0]];

	private _pointAsl = +_originAsl;
	_pointAsl set [0, (_pointAsl select 0) + ((_leadDir2D select 0) * _leadDistance)];
	_pointAsl set [1, (_pointAsl select 1) + ((_leadDir2D select 1) * _leadDistance)];
	_pointAsl set [2, (getTerrainHeightASL [_pointAsl select 0, _pointAsl select 1]) + _heightOffset];

	_pointAsl
};

private _traceSurface = {
	params ["_startAsl", "_endAsl"];

	private _hits = lineIntersectsSurfaces [
		_startAsl,
		_endAsl,
		_uav,
		objNull,
		true,
		8,
		"GEOM",
		"NONE"
	];

	_hits select {
		private _hitObject = _x param [2, objNull];
		isNull _hitObject || {
			_hitObject != _uav &&
			_hitObject != objectParent _uav
		}
	}
};

private _buildSolution = {
	params ["_valid", "_impactMode", "_impactPointAsl", "_surfaceType", "_surfaceObject", "_reason", ["_solutionFallbackRadius", _fallbackRadius]];

	createHashMapFromArray [
		["valid", _valid],
		["impactMode", _impactMode],
		["impactPointASL", _impactPointAsl],
		["surfaceType", _surfaceType],
		["surfaceObject", _surfaceObject],
		["targetNetId", netId _target],
		["reason", _reason],
		["fallbackAllowed", _fallbackAllowed],
		["fallbackRadius", _solutionFallbackRadius],
		["updatedAt", time]
	]
};

private _isAirTarget = _target isKindOf "Air";
private _isManTarget = _target isKindOf "Man";
private _isStaticTarget = _target isKindOf "StaticWeapon";
private _isVehicleTarget = (_target isKindOf "LandVehicle") || {_target isKindOf "Ship"};

private _desiredMode = switch (true) do {
	case (_isAirTarget): {"AIR_PROXIMITY"};
	case (_isStaticTarget): {"DIRECT_STATIC"};
	case (_isVehicleTarget): {"DIRECT_HULL"};
	case (_isManTarget): {"DIRECT_BODY"};
	default {_configuredImpactMode};
};

private _primaryPointAsl = +_targetPosAsl;
switch (_desiredMode) do {
	case "DIRECT_BODY": {
		_primaryPointAsl set [2, (_primaryPointAsl select 2) + 1.15];
	};

	case "DIRECT_HULL": {
		_primaryPointAsl set [2, (_primaryPointAsl select 2) + 1.2];
	};

	case "DIRECT_STATIC": {
		_primaryPointAsl set [2, (_primaryPointAsl select 2) + 0.9];
	};

	case "AIR_PROXIMITY": {
		_primaryPointAsl = +_targetPosAsl;
	};

	default {
		_primaryPointAsl set [2, (_primaryPointAsl select 2) + 1.0];
	};
};

private _surfaceHits = [_uavPosAsl, _primaryPointAsl] call _traceSurface;
if (_surfaceHits isNotEqualTo []) then {
	private _firstHit = _surfaceHits select 0;
	private _hitPointAsl = _firstHit param [0, []];
	private _hitObject = _firstHit param [2, objNull];
	private _hitTarget = !isNull _hitObject && {
		_hitObject == _target || {
			_hitObject == objectParent _target
		}
	};

	if (_hitTarget) exitWith {
		private _surfaceType = switch (_desiredMode) do {
			case "DIRECT_BODY": {"body"};
			case "DIRECT_HULL": {"vehicle"};
			case "DIRECT_STATIC": {"static"};
			case "AIR_PROXIMITY": {"air"};
			default {"target"};
		};

		[true, _desiredMode, _hitPointAsl, _surfaceType, _target, _desiredMode] call _buildSolution
	};

	if (_fallbackAllowed && {!isNull _hitObject}) exitWith {
		[true, "OBSTRUCTION_SURFACE", _hitPointAsl, "obstruction", _hitObject, "OBSTRUCTION_PRIMARY"] call _buildSolution
	};
};

if (_fallbackAllowed && {_targetObstructed}) then {
	private _obstructionProbeAsl = +_targetPosAsl;
	_obstructionProbeAsl set [2, (_obstructionProbeAsl select 2) + (if (_isManTarget) then {1.15} else {1.0})];
	private _obstructionHits = ([_uavPosAsl, _obstructionProbeAsl] call _traceSurface) select {
		private _hitObject = _x param [2, objNull];
		!isNull _hitObject && {
			_hitObject != _target &&
			_hitObject != objectParent _target
		}
	};

	if (_obstructionHits isNotEqualTo []) exitWith {
		private _obstructionHit = _obstructionHits select 0;
		private _hitPointAsl = _obstructionHit param [0, []];
		private _hitObject = _obstructionHit param [2, objNull];
		[true, "OBSTRUCTION_SURFACE", _hitPointAsl, "obstruction", _hitObject, "OBSTRUCTION_REUSED"] call _buildSolution
	};
};

if (_desiredMode == "AIR_PROXIMITY") exitWith {
	[true, "AIR_PROXIMITY", _primaryPointAsl, "air", _target, "AIR_TARGET_PROXIMITY"] call _buildSolution
};

if (_desiredMode == "DIRECT_BODY") exitWith {
	private _groundPoint = [_targetPosAsl, _targetMoveDir2D, _infantryGroundLead, _groundOffset] call _makeGroundPoint;
	[true, "GROUND_NEAR_TARGET", _groundPoint, "ground", objNull, "GROUND_NEAR_TARGET"] call _buildSolution
};

if (_desiredMode in ["DIRECT_HULL", "DIRECT_STATIC"]) exitWith {
	private _offsetDir = _incomingDir2D vectorMultiply -1;
	private _groundPoint = [_targetPosAsl, _offsetDir, _fallbackRadius, _groundOffset] call _makeGroundPoint;
	[true, "GROUND_NEAR_TARGET", _groundPoint, "ground", objNull, "GROUND_NEAR_OBJECT"] call _buildSolution
};

[true, _desiredMode, _primaryPointAsl, "target", _target, "DIRECT_POINT"] call _buildSolution