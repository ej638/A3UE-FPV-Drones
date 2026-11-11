// _originPos is the launch point. A displaced standoff launch (FS-02) passes the
// base control node as _controlPos and the base-to-launch leg as _extraDistance;
// omitted, the control node is the launch point and behaviour is unchanged.
params [
    ["_targPos", []], ["_plan", createHashMap], ["_originPos", []],
    ["_planning", createHashMap], ["_controlPos", []], ["_extraDistance", 0]
];
if !(_extraDistance isEqualType 0) then {_extraDistance = 0;};
_extraDistance = _extraDistance max 0;

private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
private _familyId = _plan getOrDefault ["familyId", ""];
private _family = _catalog getOrDefault [_familyId, createHashMap];
private _capability = (_family getOrDefault ["classCapabilities", createHashMap])
    getOrDefault [_plan getOrDefault ["uavClass", ""], createHashMap];
private _doctrine = missionNamespace getVariable ["A3UE_FPV_doctrine", createHashMap];
private _behavior = (_doctrine getOrDefault [_plan getOrDefault ["siteType", ""], createHashMap])
    getOrDefault ["behavior", createHashMap];
private _profile = ((_behavior getOrDefault ["profiles", createHashMap])
    getOrDefault [_familyId, createHashMap]) getOrDefault [_plan getOrDefault ["payloadRole", ""], createHashMap];
private _search = _behavior getOrDefault ["search", createHashMap];
private _height = (_profile getOrDefault ["searchHeightAGL", _search getOrDefault ["searchHeightAGL", 35]]) max 20;
private _trackingHeight = (_profile getOrDefault ["trackingHeightASL", 10]) max 10;
private _speed = (_profile getOrDefault ["trackingSpeed", 85]) min (_capability getOrDefault ["maxSpeed", 0]);
private _radius = (_plan getOrDefault ["activeRadius", 350]) max 100;
private _distance = _originPos distance2D _targPos;
// Speeds are km/h. Reserve 25% path overhead, 30% speed margin and 60 s engagement.
private _travelDistance = 1.25 * (_distance + _radius) + (2 * _height);
private _travelTime = _travelDistance / ((_speed * 0.7 / 3.6) max 0.1);
private _result = createHashMapFromArray [
    ["ok", false], ["reason", "SUPPORT_LIFETIME_TOO_SHORT"], ["launchHeight", _height],
    ["travelTime", _travelTime], ["engagementReserve", 60], ["distance", _distance],
    ["extraDistance", _extraDistance]
];
if (_speed <= 0) exitWith {_result set ["reason", "NO_REACH_CAPABILITY"]; _result};
if (_travelTime + 60 > (_plan getOrDefault ["strikeDuration", 300])) exitWith {_result};

private _model = _family getOrDefault ["signalModel", ""];
if (_model isEqualTo "FIBER_VISUAL" && {_familyId isEqualTo "kvn"}) exitWith {
    // KVN's 15/20/25 labels are fuel/endurance, never a measured spool.
    private _endurance = (_capability getOrDefault ["nominalEnduranceDistance", 0]) * 0.75;
    _result set ["reason", "ENDURANCE_BUDGET_EXCEEDED"];
    _result set ["enduranceBudget", _endurance];
    // A displaced launch still had to fly out from the base: count that leg too.
    if (_travelDistance + _extraDistance <= _endurance && {_endurance > 0}) then {
        _result set ["ok", true]; _result set ["reason", ""];
    };
    _result
};
_result set ["reason", "NO_REACH_CAPABILITY"];
if (_model isNotEqualTo "RADIO") exitWith {_result};
private _baseRange = missionNamespace getVariable ["FPV_MaxFlightDistance", 4000];
if (!(_baseRange isEqualType 0) || {_baseRange <= 0}) then {_baseRange = 4000;};
_result set ["reason", "RADIO_REACH_DENIED"];
private _control = if (_controlPos isEqualType [] && {count _controlPos >= 2}) then {
    [_controlPos # 0, _controlPos # 1, 0.5]
} else {
    [_originPos # 0, _originPos # 1, 0.5]
};
// Farthest planned point from the control node; equals distance + radius when
// the control node is the launch point.
private _controlReach = (_control distance2D _originPos) max ((_control distance2D _targPos) + _radius);
// Even the most favorable supported relay (within 1500 m) cannot rescue this.
if (_controlReach > ((_baseRange + 2500) * (1 - (0.25 / 1.2)) + 1500)) exitWith {_result};

private _samples = [[_originPos # 0, _originPos # 1, _height]];
{
    private _point = _originPos vectorAdd ((_targPos vectorDiff _originPos) vectorMultiply _x);
    _point set [2, _trackingHeight];
    _samples pushBack _point;
} forEach [0.25, 0.5, 0.75, 1];
// Check terminal low altitude and the far edge of the engagement envelope.
private _terminal = +_targPos; _terminal set [2, 1.5];
_samples pushBack _terminal;
private _edge = _targPos getPos [_radius, _originPos getDir _targPos];
_edge set [2, 1.5]; _samples pushBack _edge;
private _minimumSignal = 1;
private _denied = false;
{
    private _cacheKey = str [_control, _x, _family getOrDefault ["retranslatorClass", ""], _family getOrDefault ["jammerClasses", []]];
    private _sample = _planning getOrDefault [_cacheKey, createHashMap];
    if (count _sample == 0 && {(_planning getOrDefault ["sampleCount", 0]) >= 96}) exitWith {
        _result set ["reason", "REACH_CHECK_LIMIT"]; _denied = true;
    };
    if (count _sample == 0) then {
        private _sampleCount = _planning getOrDefault ["sampleCount", 0];
        _planning set ["sampleCount", _sampleCount + 1];
        _sample = [_x, _control, _family, objNull, 0.25] call A3UE_fnc_fpv_sampleRadioLink;
        private _jammerClasses = _family getOrDefault ["jammerClasses", []];
        if (_jammerClasses isNotEqualTo [] && {
            (_x nearEntities [_jammerClasses, 1000]) findIf {_x getVariable ["DB_jammer_isActive", false]} > -1
        }) then {_sample set ["signal", 0];};
        _planning set [_cacheKey, _sample];
    };
    _minimumSignal = _minimumSignal min (_sample get "signal");
    if (_minimumSignal <= 0.25) exitWith {_denied = true;};
} forEach _samples;
_result set ["minimumSignal", _minimumSignal];
if (!_denied) then {_result set ["ok", true]; _result set ["reason", ""];};
_result
