// STRUCTURAL continuity; ready AU MP server-local scheduled, disposable mission.
// [] execVM "scripts\val01_kvn_history.sqf". No real transfer/JIP/vendor evidence.
if (!isServer || {!canSuspend} || {isRemoteExecuted} || {isNil "sidesX"}) exitWith {false};
private _u = createVehicle ["O_UAV_01_F", [50, 50, 100], [], 0, "NONE"];
_u enableSimulationGlobal false; createVehicleCrew _u;
if (isNull driver _u || {netId _u == ""}) exitWith {deleteVehicle _u; false};
private _g = group driver _u;
_u setVariable ["A3UE_FPV_managed", true]; _u setVariable ["A3UE_FPV_netId", netId _u];
_u setVariable ["A3UE_FPV_vendorId", "kvn"]; _u setVariable ["A3UE_FPV_controllerGeneration", 7];
private _curve = [[50, 50, 100], [55, 50, 100], [55, 55, 100], [60, 55, 100]];
private _fail = 0;
private _check = {params ["_name", "_ok"]; if (!_ok) then {_fail = _fail + 1;}; diag_log format ["[A3UE FPV TEST VAL-01] STRUCTURAL case=%1 pass=%2 path=%3 length=%4 count=%5", _name, _ok, _u getVariable ["kvn_fiber_path", []], _u getVariable ["kvn_fiber_length", -1], _u getVariable ["kvn_fiber_length_count", -1]];};
[_u, _curve, 7] call A3UE_fnc_fpv_adoptFiberPath;
["claim reconciles curved path caches", (_u getVariable "kvn_fiber_path") isEqualTo _curve && {(_u getVariable "kvn_fiber_length") == 15} && {(_u getVariable "kvn_fiber_length_count") == 4}] call _check;
[_u] call A3UE_fnc_fpv_applyCompatInit;
["immediate normalization preserves accepted bends", (_u getVariable "kvn_fiber_path") isEqualTo _curve] call _check;
sleep 1.4;
["same-generation delayed normalization preserves bends and caches", (_u getVariable "kvn_fiber_path") isEqualTo _curve && {(_u getVariable "kvn_fiber_length") == 15} && {(_u getVariable "kvn_fiber_length_count") == 4}] call _check;
private _tail = _curve + [[60, 60, 100]];
_u setVariable ["kvn_fiber_path", _tail]; _u setVariable ["A3UE_FPV_fiberLocalPath", _tail];
[_u, _curve, 7] call A3UE_fnc_fpv_adoptFiberPath;
["same-claim duplicate adoption preserves unsent tail", (_u getVariable "kvn_fiber_path") isEqualTo _tail] call _check;
[_u] call A3UE_fnc_fpv_applyCompatInit; // Queue old-generation pass.
_u setVariable ["A3UE_FPV_controllerGeneration", 9];
private _returned = _curve + [[60, 65, 100], [55, 65, 100]];
[_u, _returned, 9] call A3UE_fnc_fpv_adoptFiberPath; [_u] call A3UE_fnc_fpv_applyCompatInit;
sleep 1.4;
["rapid return old callback cannot change adopted history", (_u getVariable "kvn_fiber_path") isEqualTo _returned && {(_u getVariable "kvn_fiber_length") == 30} && {(_u getVariable "kvn_fiber_length_count") == 6} && {!(_u getVariable ["A3UE_FPV_compatNormalizeQueued", true])}] call _check;
["stale claim rejected", !([_u, [], 7] call A3UE_fnc_fpv_adoptFiberPath) && {(_u getVariable "kvn_fiber_path") isEqualTo _returned}] call _check;
_u setVariable ["A3UE_FPV_controllerGeneration", 10]; [_u, [], 10] call A3UE_fnc_fpv_adoptFiberPath;
["empty stationary startup initializes caches", (_u getVariable "kvn_fiber_path") isEqualTo [] && {(_u getVariable "kvn_fiber_length") == 0} && {(_u getVariable "kvn_fiber_length_count") == 0}] call _check;
_u setVariable ["A3UE_FPV_managed", false];
["unmanaged adoption rejected", !([_u, _curve, 10] call A3UE_fnc_fpv_adoptFiberPath)] call _check;
{_u deleteVehicleCrew _x;} forEach crew _u; deleteVehicle _u; deleteGroup _g;
diag_log format ["[A3UE FPV TEST VAL-01] STRUCTURAL END failures=%1; moving/ownership/control/JIP/native archive NOT RUN", _fail]; _fail == 0
