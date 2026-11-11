params [["_uav", objNull], ["_identity", []]];

// Call within the same unscheduled slice as every AI/movement effect.
if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};
if (isNull _uav || {!alive _uav} || {!local _uav}) exitWith {false};
if (!(_uav getVariable ["A3UE_FPV_managed", false])
    || {!(_uav getVariable ["A3UE_FPV_controllerRunning", false])}
    || {_uav getVariable ["A3UE_FPV_cleanupPending", false]}
    || {_uav getVariable ["A3UE_FPV_detonating", false]}) exitWith {false};
if (!(_identity isEqualType []) || {count _identity != 4}
    || {(_identity findIf {!(_x isEqualType 0) || {!finite _x} || {_x < 0} || {_x != floor _x}}) >= 0}) exitWith {false};
private _generation = _identity # 3;
if (netId _uav == "" || {netId _uav != (_uav getVariable ["A3UE_FPV_netId", ""])}
    || {(_uav getVariable ["A3UE_FPV_controllerGeneration", -1]) != _generation}
    || {(_uav getVariable ["A3UE_FPV_controllerIdentity", []]) isNotEqualTo _identity}) exitWith {false};
// LT-2 tick memo. A controller tick is one unscheduled slice, so the lifecycle ticket, site
// ownership and direct control it saw at its first check are still the facts at its last one.
// Everything above (alive, local, spent, cleanup, generation, identity) is read fresh every
// time, including after this tick's own strike. Outside a tick there is no memo.
private _memo = if (isNil "_fpvTick") then {[]} else {_fpvTick getOrDefault ["actuate", []]};
if (count _memo == 3 && {(_memo # 0) isEqualTo _uav} && {(_memo # 1) == _generation}) exitWith {_memo # 2};
private _result = [_uav, _generation] call A3UE_fnc_fpv_hasCurrentLifecycle
    && {[_uav] call A3UE_fnc_fpv_isSiteDroneActive}
    && {!([_uav] call A3UE_fnc_fpv_isExternallyControlled)};
if (!isNil "_fpvTick") then {_fpvTick set ["actuate", [_uav, _generation, _result]];};
_result
