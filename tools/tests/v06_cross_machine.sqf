// Real-process observation: no packet seeding or production-function replacement.
// Ready disposable AU + ArmaFPV. Use a naturally deployed managed Crocus.
// Server-local: [uav, "producer", 2] execVM "scripts\v06_cross_machine.sqf";
// Separate interface client Local Exec after passive terminal/native view opens:
// [getConnectedUAV player, "consumer", 2] execVM "scripts\v06_cross_machine.sqf";
// Repeat expected owner IDs for client/HC; capture ALL process RPTs. See session card.
// Producer temporarily places the real control node out of range, then restores it.
params [["_u", objNull], ["_role", "consumer"], ["_expectedOwner", 2]];
if (!canSuspend || {isRemoteExecuted} || {isNull _u} || {!alive _u}
    || {!(_u getVariable ["A3UE_FPV_managed", false])} || {(_u getVariable ["A3UE_FPV_vendorId", ""]) != "armafpv"}
    || {isNil "DB_fnc_fpv_getSignal"} || {isNil "DB_fnc_fpv_ppfx_setInput"} || {isNil "DB_fnc_fpv_onSignalLost"}) exitWith {diag_log "[A3UE FPV TEST V06] CROSS_PROCESS BLOCKED prerequisites"; false};
private _end = diag_tickTime + 30;
if (_role == "producer") exitWith {
    if (!local _u || {clientOwner != _expectedOwner} || {[_u] call A3UE_fnc_fpv_isExternallyControlled}) exitWith {diag_log "[A3UE FPV TEST V06] CROSS_PROCESS BLOCKED producer locality/control"; false};
    private _oldNode = _u getVariable ["A3UE_FPV_controlPosATL", []];
    _u setVariable ["A3UE_FPV_controlPosATL", (getPosATL _u) vectorAdd [15000, 0, 0]];
    private _degraded = false;
    while {diag_tickTime < _end && {alive _u} && {local _u}} do {
        private _state = [_u] call A3UE_fnc_fpv_evaluateLinkState; // Actual range/terrain/jammer sampler.
        private _p = _u getVariable ["A3UE_FPV_crocusSignalSnapshot", []];
        private _id = _u getVariable ["A3UE_FPV_controllerIdentity", []];
        if (_state in ["DEGRADED", "EW_DENIED"] && {count _p == 6} && {count _id == 4}
            && {(_id # 1) == _expectedOwner} && {((_p # 1) select [0,4]) isEqualTo _id}
            && {(_p # 1) isEqualTo (_u getVariable ["A3UE_FPV_signalIdentity", []])}
            && {serverTime - (_p # 3) >= 0} && {serverTime - (_p # 3) <= 2}
            && {(_p # 4) <= 0.45}) then {_degraded = true;};
        diag_log format ["[A3UE FPV TEST V06] REAL_PRODUCER process=%1 server=%2 local=%3 generation=%4 state=%5 packet=%6", clientOwner, isServer, local _u, _u getVariable ["A3UE_FPV_controllerGeneration", -1], _state, _p];
        sleep 0.5;
    };
    if (!isNull _u && {local _u}) then {_u setVariable ["A3UE_FPV_controlPosATL", _oldNode];};
    diag_log format ["[A3UE FPV TEST V06] REAL_PRODUCER END degradedObserved=%1; separate consumer required", _degraded]; _degraded
};
if (!hasInterface || {!(missionNamespace getVariable ["A3UE_FPV_crocusSignalAdapterInstalled", false])}
    || {isNull player} || {getConnectedUAV player isNotEqualTo _u} || {local _u} || {clientOwner == _expectedOwner}) exitWith {diag_log "[A3UE FPV TEST V06] CROSS_PROCESS BLOCKED need separate passive viewing client"; false};
private _matched = 0;
while {diag_tickTime < _end && {alive _u} && {getConnectedUAV player isEqualTo _u}} do {
    private _p = _u getVariable ["A3UE_FPV_crocusSignalSnapshot", []];
    private _ctx = [_u] call A3UE_fnc_fpv_getCrocusSignalContext;
    private _q = [player, _u] call DB_fnc_fpv_getSignal; // Real installed adapter/native API.
    private _id = _u getVariable ["A3UE_FPV_controllerIdentity", []];
    private _ok = count _p == 6 && {count _id == 4} && {(_id # 1) == _expectedOwner}
        && {(_p # 1) isEqualTo (_u getVariable ["A3UE_FPV_signalIdentity", []])}
        && {((_p # 1) select [0,4]) isEqualTo _id}
        && {serverTime - (_p # 3) >= 0} && {serverTime - (_p # 3) <= 2}
        && {(_p # 4) <= 0.45} && {count _ctx == 2} && {abs ((_ctx # 0) - (_p # 4)) < 0.001}
        && {_q <= 0.45} && {abs (_q - (_ctx # 0)) < 0.001};
    if (_ok) then {_matched = _matched + 1;};
    diag_log format ["[A3UE FPV TEST V06] REAL_CONSUMER process=%1 local=%2 selected=%3 nativeSignal=%4 packet=%5 obstacles=%6 terrain=%7 jammer=%8", clientOwner, local _u, _ok, _q, _p, _u getVariable ["DB_fpv_signalObstacles", -1], _u getVariable ["DB_fpv_signalTerrainMask", -1], _u getVariable ["DB_fpv_inJammer", false]];
    sleep 0.5;
};
diag_log format ["[A3UE FPV TEST V06] CROSS_PROCESS SELECTOR END matched=%1 pass=%2; HUD/PPFX activation needs video/native-view evidence", _matched, _matched >= 3];
_matched >= 3
