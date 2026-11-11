// CHECK refreshes diagnostics without writing AU bindings. INSTALL reconciles;
// RESTORE releases only still-owned values. Use server-local, never as an RPC.
params [["_mode", "CHECK"]];
if (!isServer || {isRemoteExecuted} || {!(_mode in ["CHECK", "INSTALL", "RESTORE"])}) exitWith {createHashMap};
if (_mode != "CHECK") then {missionNamespace setVariable ["A3UE_FPV_integrationHooksEnabled", _mode == "INSTALL"];};
[_mode] call A3UE_fnc_fpv_patchSupportRegistries;
[_mode] call A3UE_fnc_fpv_installRivalsHooks;
private _rows = missionNamespace getVariable ["A3UE_FPV_hookStatus", createHashMap];
private _copy = createHashMap;
{_copy set [_x, +_y];} forEach _rows;
_copy
