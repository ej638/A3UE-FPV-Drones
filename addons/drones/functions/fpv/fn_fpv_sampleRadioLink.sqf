params [
    ["_positionATL", []],
    ["_controlPosATL", []],
    ["_familyData", createHashMap],
    ["_ignoreUav", objNull],
    ["_minimumSignal", -1],
    "_knownRetranslators"
];

// Shared managed-radio geometry. No object state writes or replication.
// LT-2: the two 1.5 km relay scans walk every object in range. A caller that sampled this drone
// a moment ago passes the relays it found then (_knownRetranslators) and the scans are skipped;
// the result carries the relays used. Without that argument every call scans, as before.
private _retranslatorClass = _familyData getOrDefault ["retranslatorClass", ""];
private _retranslators = [];
if (_retranslatorClass isNotEqualTo "") then {
    if (isNil "_knownRetranslators") then {
    {
        {if (alive _x) then {_retranslators pushBackUnique _x;};}
            forEach (_x nearObjects [_retranslatorClass, 1500]);
    } forEach [_positionATL, _controlPosATL];
    } else {
        _retranslators = _knownRetranslators select {!isNull _x && {alive _x}};
    };
};
private _hasRetranslator = _retranslators isNotEqualTo [];
private _nodes = [_controlPosATL];
{_nodes pushBackUnique (getPosATL _x);} forEach _retranslators;
private _bestNode = _controlPosATL;
private _distance = 1e9;
{
    private _candidateDistance = if (isNull _ignoreUav) then {_positionATL distance _x} else {_ignoreUav distance _x};
    if (_candidateDistance < _distance) then {
        _distance = _candidateDistance;
        _bestNode = _x;
    };
} forEach _nodes;

private _baseMaxDistance = missionNamespace getVariable ["FPV_MaxFlightDistance", 4000];
if (!(_baseMaxDistance isEqualType 0) || {_baseMaxDistance <= 0}) then {_baseMaxDistance = 4000;};
private _maxDistance = _baseMaxDistance + ([0, 2500] select _hasRetranslator);
private _distanceImpact = 1 - ((_distance / _maxDistance) min 1);
private _boost = [1, 1.2] select _hasRetranslator;
private _result = createHashMapFromArray [
    ["signal", _distanceImpact * _boost], ["distance", _distance],
    ["maxDistance", _maxDistance], ["obstacles", 0], ["terrainMask", 0],
    ["retranslators", _retranslators]
];
// Planning can reject by best possible signal before any line tests.
if ((_result get "signal") <= _minimumSignal) exitWith {_result};

private _startASL = AGLToASL [_bestNode # 0, _bestNode # 1, (_bestNode param [2, 0]) max 1.5];
private _endASL = if (isNull _ignoreUav) then {ATLToASL _positionATL} else {getPosWorld _ignoreUav};
private _terrainBlocked = terrainIntersectASL [_startASL, _endASL];
private _intersections = lineIntersectsSurfaces [_startASL, _endASL, objNull, _ignoreUav, true, 10, "FIRE", "NONE"];
private _parent = if (isNull _ignoreUav) then {objNull} else {objectParent _ignoreUav};
private _obstacleCount = count (_intersections select {
    private _hitObject = _x param [2, objNull];
    !isNull _hitObject && {_hitObject != _parent} && {!(_hitObject isKindOf "Man")}
});
private _altFactor = ((_positionATL param [2, 0]) / 40) min 1;
private _obstacleFactor = (1 - ((_obstacleCount min 8) * 0.05)) max 0;
private _terrainFactor = if (_terrainBlocked) then {0.3 + (0.4 * _altFactor)} else {1};
if (_terrainBlocked && {_distance <= 200}) then {
    private _closeAlpha = 1 - ((_distance / 200) min 1);
    _terrainFactor = _terrainFactor max (0.35 + (0.65 * _closeAlpha));
};
if (_hasRetranslator) then {_terrainFactor = _terrainFactor max (0.75 + (0.2 * _altFactor));};
private _signal = _distanceImpact * _terrainFactor * _obstacleFactor * _boost;
private _terrainMask = if (_terrainBlocked) then {1} else {(1 - _altFactor) max 0};
if (_hasRetranslator) then {_terrainMask = _terrainMask * 0.4;};
// The runtime caller applies jammer attenuation before the final [0,1] clamp.
_result set ["signal", _signal max 0];
_result set ["obstacles", _obstacleCount];
_result set ["terrainMask", _terrainMask];
_result
