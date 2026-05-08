params [["_uav", objNull], ["_profile", createHashMap]];

if (isNull _uav) exitWith {"OK"};

private _linkModel = _uav getVariable ["A3UE_FPV_linkModel", "RADIO"];
if (_linkModel != "RADIO") exitWith {
	_uav setVariable ["A3UE_FPV_signalStrength", 1, true];
	"OK"
};

private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) then {
	_catalog = call A3UE_fnc_fpv_buildCompatCatalog;
};

private _vendorId = _uav getVariable ["A3UE_FPV_vendorId", ""];
private _familyData = _catalog getOrDefault [_vendorId, createHashMap];
private _retranslatorClass = _familyData getOrDefault ["retranslatorClass", ""];
private _jammerClasses = _familyData getOrDefault ["jammerClasses", []];

private _siteMarker = _uav getVariable ["A3UE_FPV_siteMarker", ""];
private _controlPosAtl = if (_siteMarker isEqualTo "") then {
	getPosATL _uav
} else {
	getMarkerPos _siteMarker
};

if (_controlPosAtl isEqualTo [0, 0, 0]) then {
	_controlPosAtl = getPosATL _uav;
};

private _findRetranslators = {
	params ["_centerPos", "_radius"];

	if (_retranslatorClass isEqualTo "") exitWith {[]};
	(_centerPos nearObjects [_retranslatorClass, _radius]) select { alive _x }
};

private _findJammers = {
	params ["_centerPos", "_radius"];

	if (_jammerClasses isEqualTo []) exitWith {[]};
	(_centerPos nearEntities [_jammerClasses, _radius]) select { _x getVariable ["DB_jammer_isActive", false] }
};

private _retranslatorsNearUav = [getPosATL _uav, 1500] call _findRetranslators;
private _retranslatorsNearControl = [_controlPosAtl, 1500] call _findRetranslators;
private _hasRetranslator = (_retranslatorsNearUav isNotEqualTo []) || (_retranslatorsNearControl isNotEqualTo []);

private _controlNodes = [_controlPosAtl];
{
	_controlNodes pushBackUnique (getPosATL _x);
} forEach (_retranslatorsNearUav + _retranslatorsNearControl);

private _bestNode = _controlPosAtl;
private _distance = 1e9;
{
	private _candidateDistance = _uav distance _x;
	if (_candidateDistance < _distance) then {
		_distance = _candidateDistance;
		_bestNode = _x;
	};
} forEach _controlNodes;

private _baseMaxDistance = missionNamespace getVariable ["FPV_MaxFlightDistance", 4000];
if (!(_baseMaxDistance isEqualType 0) || {_baseMaxDistance <= 0}) then {
	_baseMaxDistance = 4000;
};

private _maxDistance = _baseMaxDistance + ([0, 2500] select _hasRetranslator);

private _startASL = AGLToASL [_bestNode select 0, _bestNode select 1, ((_bestNode param [2, 0]) max 1.5)];
private _endASL = getPosWorld _uav;
private _terrainBlocked = terrainIntersectASL [_startASL, _endASL];

private _intersections = lineIntersectsSurfaces [
	_startASL,
	_endASL,
	objNull,
	_uav,
	true,
	10,
	"FIRE",
	"NONE"
];

private _obstacleCount = count (_intersections select {
	private _hitObject = _x param [2, objNull];
	!isNull _hitObject && {_hitObject != objectParent _uav} && {!(_hitObject isKindOf "Man")}
});

private _altAGL = (getPosATL _uav) select 2;
private _altFactor = (_altAGL / 40) min 1;
private _distanceImpact = 1 - ((_distance / _maxDistance) min 1);
private _obstacleFactor = (1 - ((_obstacleCount min 8) * 0.05)) max 0;
private _terrainFactor = if (_terrainBlocked) then {
	0.3 + (0.4 * _altFactor)
} else {
	1
};

if (_terrainBlocked && {_distance <= 200}) then {
	private _closeAlpha = 1 - ((_distance / 200) min 1);
	private _closeMin = 0.35 + ((1 - 0.35) * _closeAlpha);
	_terrainFactor = _terrainFactor max _closeMin;
};

if (_hasRetranslator) then {
	private _boost = 0.75 + (0.2 * _altFactor);
	_terrainFactor = _terrainFactor max _boost;
};

private _signalStrength = _distanceImpact * _terrainFactor * _obstacleFactor;
if (_hasRetranslator) then {
	_signalStrength = _signalStrength * 1.2;
};

private _timeInJammerZone = _uav getVariable ["A3UE_FPV_timeInJammerZone", 0];
private _jammersNearUav = [getPosATL _uav, 1000] call _findJammers;
if (_jammersNearUav isNotEqualTo []) then {
	_timeInJammerZone = _timeInJammerZone + diag_deltaTime;
	private _jammerImpact = 1 - (_timeInJammerZone * 1.75);
	_signalStrength = (_signalStrength * _jammerImpact) max 0;
} else {
	_timeInJammerZone = 0;
};

_uav setVariable ["A3UE_FPV_timeInJammerZone", _timeInJammerZone];

if (_distance > _maxDistance) then {
	_signalStrength = 0;
};

private _terrainMask = if (_terrainBlocked) then { 1 } else { (1 - _altFactor) max 0 };
if (_hasRetranslator) then {
	_terrainMask = _terrainMask * 0.4;
};

_signalStrength = (_signalStrength max 0) min 1;
_uav setVariable ["A3UE_FPV_signalStrength", _signalStrength, true];

if (_vendorId isEqualTo "armafpv") then {
	_uav setVariable ["DB_fpv_signal_obstacles", _obstacleCount, true];
	_uav setVariable ["DB_fpv_signal_terrainMask", _terrainMask, true];
};

private _linkState = switch (true) do {
	case (_signalStrength <= 0.15): { "EW_DENIED" };
	case (_signalStrength <= 0.45): { "DEGRADED" };
	default { "OK" };
};

switch (_vendorId) do {
	case "armafpv": {
		_uav setVariable ["DB_fpv_isUAVsignalLost", _linkState == "EW_DENIED", true];
	};

	case "fpv_ua": {
		_uav setVariable ["UA_fpv_isUAVsignalLost", _linkState == "EW_DENIED", true];
	};
};

_linkState