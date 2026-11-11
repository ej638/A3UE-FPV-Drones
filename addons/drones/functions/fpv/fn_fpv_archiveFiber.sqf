if !(call A3UE_fnc_fpv_lifecycleAccess) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
if (isNil "_this" || {!(_this isEqualType [])} || {count _this != 3}
    || {!((_this # 0) isEqualType [])} || {!((_this # 1) isEqualType 0)} || {!((_this # 2) isEqualType "")}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
params [["_path", [], [[]]], ["_ttl", 20, [0]], ["_eventId", "", [""]]];
if (canSuspend) exitWith {private _ok = false; isNil {_ok = _this call A3UE_fnc_fpv_archiveFiber;}; _ok};
// Only a server-issued recorded destruction identity can select this worker.
if (_eventId == "" || {count _eventId > 16}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
private _record = (missionNamespace getVariable ["A3UE_FPV_lifecycles", createHashMap]) getOrDefault [_eventId, createHashMap];
if (count _record == 0 || {(_record get "phase") != "closed"} || {!(_record get "fiber")}
    || {!((_record get "outcome") in ["kill", "delete", "detonate"])}
    || {serverTime >= (_record get "closedAt") + 600}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
if (_record get "archived") exitWith {true};
if (!finite _ttl || {_ttl <= 0} || {_ttl > 300} || {count _path == 0} || {count _path > 256}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
private _now = serverTime;
private _rates = missionNamespace getVariable ["A3UE_FPV_archiveRates", createHashMap];
{if (_now >= ((_rates get _x) # 0) + 10) then {_rates deleteAt _x;};} forEach keys _rates;
private _source = str (_record get "owner");
private _rate = _rates getOrDefault [_source, [_now, 0]];
if (_now >= (_rate # 0) + 10) then {_rate = [_now, 0];};
private _global = missionNamespace getVariable ["A3UE_FPV_archiveGlobalRate", [_now, 0]];
if (_now >= (_global # 0) + 1) then {_global = [_now, 0];};
if ((_rate # 1) >= 8 || {(_global # 1) >= 16} || {count _rates >= 64 && {!(_source in _rates)}}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
// Authorization, duplicate and rate checks precede traversal/copies/publication.
if !([_path] call A3UE_fnc_fpv_validFiberPath) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
_rate set [1, (_rate # 1) + 1]; _rates set [_source, _rate];
missionNamespace setVariable ["A3UE_FPV_archiveRates", _rates];
_global set [1, (_global # 1) + 1]; missionNamespace setVariable ["A3UE_FPV_archiveGlobalRate", _global];
// Vendor protocol uses mission time. Lifetime admission above uses serverTime.
private _displayNow = time;
private _dead = (missionNamespace getVariable ["A3UE_FPV_deadFibers", []]) select {(_x # 1) > _displayNow};
private _points = 0;
{_points = _points + count (_x # 0);} forEach _dead;
while {count _dead >= 64 || {_points + count _path > 4096}} do {
    private _old = _dead deleteAt 0;
    _points = _points - count (_old # 0);
};
_dead pushBack [_path apply {+_x}, _displayNow + _ttl, _displayNow, _path apply {+_x}];
_record set ["archived", true];
missionNamespace setVariable ["A3UE_FPV_deadFibers", _dead];
missionNamespace setVariable ["A3UE_FPV_archivePoints", _points + count _path];
missionNamespace setVariable ["A3UE_FPV_archivePublications", (1 + (missionNamespace getVariable ["A3UE_FPV_archivePublications", 0])) min 1000000];
// Renderer-local sag/whole-array snapshots never enter authority.
private _display = _dead apply {[(_x # 0) apply {+_x}, _x # 1, _x # 2, (_x # 3) apply {+_x}]};
missionNamespace setVariable ["kvn_deadFibers", _display, true];
true
