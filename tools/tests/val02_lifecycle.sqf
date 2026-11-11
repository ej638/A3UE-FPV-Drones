// Real registration + local mutation contracts, NOT remote provenance/HC qualification.
// Disposable ready AU MP, server-local scheduled Exec; no concurrent packages.
// [] execVM "scripts\val02_lifecycle.sqf"; capture RPT and restart afterward.
if (!isServer || {!canSuspend} || {isRemoteExecuted} || {isNil "A3A_activeSupports"}) exitWith {false};
private _name = format ["QA_VAL02_%1", diag_tickTime];
private _uavs = [createVehicle ["O_UAV_01_F", [50,50,100], [], 0, "NONE"], createVehicle ["O_UAV_01_F", [60,50,100], [], 0, "NONE"]];
{_x enableSimulationGlobal false; _x setVariable ["A3UE_FPV_managed", true]; _x setVariable ["A3UE_FPV_netId", netId _x];} forEach _uavs;
private _ids = _uavs apply {[_x, true, _name] call A3UE_fnc_fpv_registerLifecycle};
if (_ids findIf {_x < 0} >= 0) exitWith {{deleteVehicle _x;} forEach _uavs; false};
private _marker = createMarker [_name, [50,50,0]]; _marker setMarkerShape "ELLIPSE";
private _entry = createHashMapFromArray [["status", "active"], ["drones", +_uavs], ["droneNetIds", _uavs apply {netId _x}], ["searchMarker", _marker]];
A3UE_FPV_supportRegistry set [_name, _entry]; A3UE_FPV_supportTransientMarkers pushBack _marker;
A3A_activeSupports pushBack [_name, east, "FPV", [50,50,0], 350, [], 0];
private _r = A3UE_FPV_lifecycles get str (_ids # 0);
// Synthetic ticket isolates validation/sequence; real challenge is a separate MP case.
_r set ["episode", 1]; _r set ["token", "fixture"]; _r set ["generation", 1];
private _before = str _entry; private _cases = 0; private _fail = 0;
private _check = {params ["_case", "_ok"]; _cases = _cases + 1; if (!_ok) then {_fail = _fail + 1;}; diag_log format ["[A3UE FPV TEST VAL-02] case=%1 pass=%2", _case, _ok];};
isNil {
    private _id = _ids # 0;
    private _rejects = [!([_id,0,1,"control","fixture",[true]] call A3UE_fnc_fpv_reportLifecycle),
        !([_id,1,1,"control","wrong",[true]] call A3UE_fnc_fpv_reportLifecycle),
        !([10000000,1,1,"control","fixture",[true]] call A3UE_fnc_fpv_reportLifecycle),
        !([_id,1,1,"finished","fixture",[_name,true]] call A3UE_fnc_fpv_reportLifecycle),
        !([_id,1,1,"control","fixture",[{}]] call A3UE_fnc_fpv_reportLifecycle),
        !([_id,1,1,"release","fixture",{}] call A3UE_fnc_fpv_reportLifecycle),
        !([_id,1,1,"fiber","fixture",[[[1,2,"bad"]]]] call A3UE_fnc_fpv_reportLifecycle),
        !([[[1,2,3]],20,""] call A3UE_fnc_fpv_archiveFiber),
        !([[[1,2,3]],20,str _id] call A3UE_fnc_fpv_archiveFiber)];
    ["stale/token/unknown/forced/code/geometry/live archive rejected", _rejects findIf {!_x} < 0 && {str _entry == _before} && {markerShape _marker != ""}] call _check;
    ["valid control transition", [_id,1,1,"control","fixture",[true]] call A3UE_fnc_fpv_reportLifecycle] call _check;
    private _epoch = _r get "signalEpoch";
    ["duplicate and reordered sequence reject before mutation", !([_id,1,1,"control","fixture",[false]] call A3UE_fnc_fpv_reportLifecycle) && {(_r get "signalEpoch") == _epoch} && {str _entry == _before}] call _check;
    _r set ["released", true];
    ["pending/released episode cannot report", !([_id,1,2,"control","fixture",[false]] call A3UE_fnc_fpv_reportLifecycle)] call _check;
    _r set ["released", false];
};
(_uavs # 0) setDamage 1;
sleep 0.2;
["server MPKilled settles only registered member", (_r get "phase") == "closed" && {count (_entry get "droneNetIds") == 1} && {!("finishedAt" in _entry)} && {markerShape _marker != ""}] call _check;
deleteVehicle (_uavs # 1); sleep 0.2;
["server Deleted closes paired loss once", (_entry get "status") == "failed" && {count (_entry get "droneOutcomes") == 2} && {(_entry get "droneNetIds") isEqualTo []} && {markerShape _marker == ""}] call _check;
private _finished = str _entry;
["late worker/event cannot resettle", !([_ids # 0,"kill"] call A3UE_fnc_fpv_endLifecycle) && {str _entry == _finished}] call _check;
private _retention = _entry getOrDefault ["retentionHandle", scriptNull]; if !(scriptDone _retention) then {terminate _retention;};
{if (!isNull _x) then {deleteVehicle _x;};} forEach _uavs;
{A3UE_FPV_lifecycles deleteAt str _x;} forEach _ids;
A3UE_FPV_supportRegistry deleteAt _name; A3UE_FPV_supportTransientMarkers = A3UE_FPV_supportTransientMarkers select {_x != _marker};
A3A_activeSupports = A3A_activeSupports select {(_x # 0) != _name}; deleteMarker _marker;
diag_log format ["[A3UE FPV TEST VAL-02] LOCAL END cases=%1 failures=%2; client/HC/real detonation/expiry/transport NOT RUN", _cases, _fail]; _fail == 0
