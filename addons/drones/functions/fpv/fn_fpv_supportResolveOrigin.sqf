params [
    ["_side", sideUnknown], ["_targPos", []], ["_plan", createHashMap],
    ["_contextMap", createHashMap], ["_planning", createHashMap]
];

private _contextKey = _plan getOrDefault ["context", "ReactiveSupport"];
private _failure = {
    params ["_reason"];
    createHashMapFromArray [["ok", false], ["reason", _reason], ["context", _contextKey]]
};
if !(_targPos isEqualType [] && {count _targPos >= 2}) exitWith {["NO_VALID_ORIGIN"] call _failure};
if (isNil "sidesX" || {isNull sidesX}) exitWith {["NO_VALID_ORIGIN"] call _failure};
private _targetPos = [_targPos # 0, _targPos # 1, _targPos param [2, 0]];
private _originMarker = _contextMap getOrDefault ["originMarker", _plan getOrDefault ["originMarker", ""]];
if !(_originMarker isEqualType "") exitWith {["NO_VALID_ORIGIN"] call _failure};
private _isOverride = _originMarker isNotEqualTo "";
if (_isOverride && {(toLower _originMarker find "carrier") >= 0}) exitWith {["CARRIER_ONLY_ORIGIN"] call _failure};

// Request-local eligibility snapshot, reused across class/role candidates only.
// A fresh snapshot is mandatory for the selected plan's launch check.
if !(_planning getOrDefault ["originsResolved", false]) then {
    private _origins = createHashMap;
    private _originNames = createHashMap;
    private _carrierOnly = false;
    if (!isNil "A3A_fnc_availableBasesAir") then {
        private _air = [_side, _targetPos, true] call A3A_fnc_availableBasesAir;
        {
            if ((toLower _x find "carrier") >= 0) then {_carrierOnly = true; continue;};
            if (_x in (missionNamespace getVariable ["airportsX", []]) && {markerShape _x != ""}
                && {sidesX getVariable [_x, sideUnknown] == _side}) then {
                _origins set [_x, ["AU_AIR", -1, -1]];
                _originNames set [toLower _x, _x];
            };
        } forEach (_air param [0, []]);
    };
    if (missionNamespace getVariable ["A3UE_FPV_siteReady", false] && {!isNil "spawner"} && {!isNull spawner}) then {
        {
            private _state = _y;
            if ((_state getOrDefault ["phase", ""]) == "active"
                && {(_state getOrDefault ["siteType", ""]) in ["Airport", "Outpost", "Resource"]}
                && {_state getOrDefault ["siteSide", sideUnknown] == _side}
                && {sidesX getVariable [_x, sideUnknown] == _side}
                && {(spawner getVariable [_x, -1]) in [0, 1]} && {markerShape _x != ""}
                && {!(_state getOrDefault ["captured", false])}
                && {(_state getOrDefault ["cleanupDrones", []]) isEqualTo []}) then {
                _origins set [_x, ["ACTIVE_SITE", missionNamespace getVariable ["A3UE_FPV_siteEpoch", -1], _state getOrDefault ["generation", -1]]];
                _originNames set [toLower _x, _x];
            };
        } forEach (missionNamespace getVariable ["A3UE_FPV_siteLifecycle", createHashMap]);
    };
    // Match caller spelling to authoritative keys, not merely a lowercase key.
    // This index is populated during the existing eligibility enumeration.
    private _originKey = toLower _originMarker;
    _originMarker = _originNames getOrDefault [_originKey, _originMarker];
    // Land eligibility includes AU's cached navigation, cooldown, garrison and
    // available spawn-position contract. Query only for an explicit land base.
    if (_isOverride && {!(_originMarker in _origins)} && {markerShape _originMarker != ""}
        && {!isNil "A3A_fnc_availableBasesLand"}) then {
        private _land = [_side, _targetPos, true] call A3A_fnc_availableBasesLand;
        private _landNames = _land param [0, []];
        private _landIndex = _landNames findIf {toLower _x == _originKey};
        if (_landIndex >= 0) then {
            _originMarker = _landNames # _landIndex;
            if (sidesX getVariable [_originMarker, sideUnknown] == _side) then {
                _origins set [_originMarker, ["AU_LAND", -1, -1]];
            };
        };
    };
    _planning set ["resolvedOriginMarker", _originMarker];
    _planning set ["eligibleOrigins", _origins];
    _planning set ["carrierOnly", _carrierOnly];
    _planning set ["originsResolved", true];
};
_originMarker = _planning get "resolvedOriginMarker";
private _origins = _planning get "eligibleOrigins";
if (_isOverride && {!(_originMarker in _origins)}) exitWith {["ORIGIN_INELIGIBLE"] call _failure};
if (count _origins == 0) exitWith {
    [["NO_VALID_ORIGIN", "CARRIER_ONLY_ORIGIN"] select (_planning get "carrierOnly")] call _failure
};
private _candidates = _planning getOrDefault ["originCandidates", []];
if (_candidates isEqualTo []) then {
    // FS-02 launch standoff (A3UE_FPV_launchStandoff, default 800 m). An origin whose
    // centre is inside the standoff of the target or a hostile player, or whose area
    // holds the target, may only launch from a displaced far-side point. Clear
    // origins are preferred; the shortlist stays bounded at 8.
    private _threats = [_targetPos] + ([_side] call A3UE_fnc_fpv_standoffThreats);
    _planning set ["standoffThreats", _threats];
    private _probe = createHashMapFromArray [["probeOnly", true]];
    private _clear = [];
    private _near = [];
    {
        if (!_isOverride || {_x == _originMarker}) then {
            private _centre = markerPos _x;
            private _ranked = [_centre distance2D _targetPos, _x];
            if ((([_centre, _centre, _threats, _probe] call A3UE_fnc_fpv_launchStandoff) # 1) == "DIRECT"
                && {!(_targetPos inArea _x)}) then {_clear pushBack _ranked;} else {_near pushBack _ranked;};
        };
    } forEach _origins;
    _clear sort true;
    _near sort true;
    // Prefer nearby feasible sites. Conservative bounded shortlist; no route solver.
    _candidates = (_clear apply {_x + [false]}) + (_near apply {_x + [true]});
    _candidates resize ((count _candidates) min 8);
    _planning set ["originCandidates", _candidates];
};
private _result = createHashMap;
private _reason = "NO_REACHABLE_ORIGIN";
{
    _x params ["", "_marker", ["_displace", false]];
    private _originPos = markerPos _marker;
    private _control = [_originPos # 0, _originPos # 1, 0.5];
    private _launchPoint = _originPos;
    private _launchMode = "ORIGIN";
    private _launchClearance = -1;
    if (_displace) then {
        private _standoff = [_originPos, _originPos, _planning getOrDefault ["standoffThreats", [_targetPos]]] call A3UE_fnc_fpv_launchStandoff;
        _launchClearance = _standoff # 2;
        if ((_standoff # 1) == "STANDOFF") then {
            _launchPoint = _standoff # 0;
            _launchMode = "STANDOFF";
        };
        if ((_standoff # 1) == "BLOCKED") then {_launchMode = "BLOCKED";};
    };
    if (_launchMode == "BLOCKED") then {
        _reason = "NO_STANDOFF_LAUNCH";
    } else {
        // The control node and KVN fiber anchor stay at the base; reach is checked from
        // the real launch point, including the base-to-launch leg for KVN endurance.
        private _reach = [_targetPos, _plan, _launchPoint, _planning, _control,
            [0, _launchPoint distance2D _originPos] select (_launchMode == "STANDOFF")] call A3UE_fnc_fpv_supportCheckReach;
        if !(_reach get "ok") then {
            _reason = _reach get "reason";
        } else {
            private _contract = _origins get _marker;
            _result = createHashMapFromArray [
                ["ok", true], ["context", _contextKey], ["originMarker", _marker],
                ["originPosATL", +_control], ["controlPosATL", +_control], ["fiberAnchorPos", +_control],
                ["launchPosATL", [_launchPoint # 0, _launchPoint # 1, _reach get "launchHeight"]],
                ["launchDir", _launchPoint getDir _targetPos],
                ["launchMode", _launchMode], ["launchClearance", _launchClearance],
                ["originSource", ["selection", "override"] select _isOverride],
                ["originContract", _contract # 0], ["originEpoch", _contract # 1], ["originGeneration", _contract # 2],
                ["reach", _reach]
            ];
        };
    };
    if (count _result > 0) exitWith {};
} forEach _candidates;
if (count _result == 0) exitWith {[_reason] call _failure};
_result
