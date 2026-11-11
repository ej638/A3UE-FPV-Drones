// STRUCTURAL only; synthetic server records and a native callback spy.
// Disposable ready AU MP, server LOCAL scheduled Exec; no concurrent archive work.
// [] execVM "scripts\f05_kvn_archive.sqf"; restart mission after completion.
// Does not certify real registration, RPC provenance, native damage, JIP or HUD.
if (!isServer || {!canSuspend} || {isRemoteExecuted}) exitWith {false};
isNil {
    private _names = ["DB_kvn_fnc_fpv_onDestroy", "DB_kvn_fpv_dronesArray", "kvn_fiberTTL",
        "A3UE_FPV_kvnArchiveAdapterInstalled", "A3UE_FPV_kvnNativeOnDestroy", "A3UE_FPV_kvnCreatedEH",
        "A3UE_FPV_lifecycles", "A3UE_FPV_lifecycleIndex", "A3UE_FPV_lifecycleCapability",
        "A3UE_FPV_deadFibers", "A3UE_FPV_archiveRates", "A3UE_FPV_archiveGlobalRate",
        "A3UE_FPV_archivePoints", "A3UE_FPV_archivePublications", "A3UE_FPV_lifecycleRejected", "kvn_deadFibers"];
    private _saved = _names apply {[_x, !isNil {missionNamespace getVariable _x}, missionNamespace getVariable [_x, {}]]};
    private _cases = 0; private _failures = 0;
    private _check = {params ["_name", "_ok"]; _cases = _cases + 1; if (!_ok) then {_failures = _failures + 1;}; diag_log format ["[A3UE FPV TEST F05] STRUCTURAL case=%1 pass=%2", _name, _ok];};
    private _reset = {
        A3UE_FPV_lifecycles = createHashMap; A3UE_FPV_lifecycleIndex = createHashMap;
        A3UE_FPV_lifecycleCapability = createHashMapFromArray [["fixture", true]];
        A3UE_FPV_deadFibers = []; kvn_deadFibers = []; A3UE_FPV_archiveRates = createHashMap;
        A3UE_FPV_archiveGlobalRate = [serverTime, 0]; A3UE_FPV_archivePublications = 0;
    };
    private _seed = {
        params ["_id", ["_source", 2], ["_live", false], ["_uav", objNull]];
        private _r = createHashMapFromArray [["id", _id], ["owner", _source], ["episode", 1], ["generation", 1],
            ["token", "fixture"], ["object", _uav], ["netId", netId _uav], ["support", ""], ["site", ""], ["rival", ""],
            ["phase", ["closed", "live"] select _live], ["fiber", true], ["managed", false], ["path", []],
            ["closedAt", serverTime], ["lateUntil", serverTime + 5], ["outcome", "delete"], ["archived", false], ["sequences", createHashMap]];
        A3UE_FPV_lifecycles set [str _id, _r]; _r
    };
    call _reset;
    A3UE_FPV_kvnArchiveAdapterInstalled = false; DB_kvn_fnc_fpv_onDestroy = nil;
    ["absent vendor", !(call A3UE_fnc_fpv_installKvnArchiveAdapter)] call _check;
    DB_kvn_fnc_fpv_onDestroy = 17;
    ["invalid binding", !(call A3UE_fnc_fpv_installKvnArchiveAdapter)] call _check;
    DB_kvn_fnc_fpv_onDestroy = {
        params ["_uav"]; _uav setVariable ["QA_F05_args", _this];
        _uav setVariable ["QA_F05_calls", 1 + (_uav getVariable ["QA_F05_calls", 0])];
        _uav setVariable ["QA_F05_seenPath", +(_uav getVariable ["kvn_fiber_path", []])]; 19
    };
    ["install", call A3UE_fnc_fpv_installKvnArchiveAdapter] call _check;
    private _captured = A3UE_FPV_kvnNativeOnDestroy; private _wrapper = DB_kvn_fnc_fpv_onDestroy;
    ["idempotent capture", call A3UE_fnc_fpv_installKvnArchiveAdapter && {_captured isEqualTo A3UE_FPV_kvnNativeOnDestroy} && {_wrapper isEqualTo DB_kvn_fnc_fpv_onDestroy}] call _check;
    private _u = createVehicle ["Land_HelipadEmpty_F", [50, 50, 0], [], 0, "CAN_COLLIDE"];
    private _a = [[100, 10, 1], [102, 10, 1]]; private _b = [[200, 10, 1], [202, 10, 1]]; private _n = [[300, 10, 1], [302, 10, 1]];
    DB_kvn_fpv_dronesArray = [];
    ["non-KVN delegate arguments/return", ([_u, "EXTRA"] call DB_kvn_fnc_fpv_onDestroy) == 19 && {(_u getVariable "QA_F05_args") isEqualTo [_u, "EXTRA"]} && {isNil {_u getVariable "A3UE_FPV_kvnDestroyHandled"}}] call _check;
    DB_kvn_fpv_dronesArray = [typeOf _u]; kvn_fiberTTL = 20;
    {
        call _reset; [1] call _seed; [2] call _seed; [3, 2, true, _u] call _seed;
        _u setVariable ["A3UE_FPV_lifecycleTicket", [3, 1, "fixture"]]; _u setVariable ["A3UE_FPV_reportSequences", createHashMap];
        _u setVariable ["kvn_fiber_path", _n apply {+_x}]; _u setVariable ["A3UE_FPV_kvnDestroyHandled", false]; _u setVariable ["QA_F05_calls", 0];
        if (_x) then {[_a, 20, "1"] call A3UE_fnc_fpv_archiveFiber;};
        kvn_deadFibers = []; // Stale native whole-array state must never enter authority.
        private _returned = [_u, "ORIGINAL_EXTRA"] call DB_kvn_fnc_fpv_onDestroy;
        ["live native report cannot archive", count A3UE_FPV_deadFibers == ([0, 1] select _x)] call _check;
        [3, "delete"] call A3UE_fnc_fpv_endLifecycle;
        if (!_x) then {[_a, 20, "1"] call A3UE_fnc_fpv_archiveFiber;};
        [_b, 20, "2"] call A3UE_fnc_fpv_archiveFiber;
        private _expected = if (_x) then {[_a, _n, _b]} else {[_n, _a, _b]};
        ["both managed/native arrival orders", (A3UE_FPV_deadFibers apply {_x # 0}) isEqualTo _expected] call _check;
        ["native nonarchive effects/args/return", _returned == 19 && {(_u getVariable "QA_F05_args") isEqualTo [_u, "ORIGINAL_EXTRA"]} && {(_u getVariable "QA_F05_seenPath") isEqualTo []} && {(_u getVariable "kvn_fiber_path") isEqualTo _n}] call _check;
        private _pubs = A3UE_FPV_archivePublications;
        [_u] call DB_kvn_fnc_fpv_onDestroy; [_n, 20, "3"] call A3UE_fnc_fpv_archiveFiber;
        [3, 1, 2, "destroy", "fixture", [_n, 20]] call A3UE_fnc_fpv_reportLifecycle;
        ["native/managed same-lifetime duplicate no publication", count A3UE_FPV_deadFibers == 3 && {A3UE_FPV_archivePublications == _pubs} && {(_u getVariable "QA_F05_calls") == 1}] call _check;
    } forEach [true, false];
    private _before = str A3UE_FPV_deadFibers;
    (((kvn_deadFibers # 0) # 0) # 0) set [0, 999]; (((kvn_deadFibers # 0) # 3) # 0) set [0, 998]; (_a # 0) set [0, 997];
    ["deep raw/display/input isolation", str A3UE_FPV_deadFibers == _before] call _check;
    [4] call _seed;
    private _oversize = []; for "_i" from 0 to 256 do {_oversize pushBack [_i, 0, 0];};
    private _rejects = [!([_n, 20, ""] call A3UE_fnc_fpv_archiveFiber), !([_n, 20, "unknown"] call A3UE_fnc_fpv_archiveFiber),
        !([_n, 0, "4"] call A3UE_fnc_fpv_archiveFiber), !([_n, 301, "4"] call A3UE_fnc_fpv_archiveFiber),
        !([[[1, 2]], 20, "4"] call A3UE_fnc_fpv_archiveFiber), !([[[1, 2, "bad"]], 20, "4"] call A3UE_fnc_fpv_archiveFiber), !([_oversize, 20, "4"] call A3UE_fnc_fpv_archiveFiber)];
    ["empty/unique-ID/TTL/malformed/oversize bypass rejected", _rejects findIf {!_x} < 0 && {str A3UE_FPV_deadFibers == _before}] call _check;
    (A3UE_FPV_lifecycles get "3") set ["archived", true]; A3UE_FPV_deadFibers = [[_n, time - 1, time - 2, _n]];
    private _pubs = A3UE_FPV_archivePublications; [_n, 20, "3"] call A3UE_fnc_fpv_archiveFiber;
    ["expired-trail duplicate cannot resurrect/republish", A3UE_FPV_archivePublications == _pubs] call _check;
    [_b, 300, "4"] call A3UE_fnc_fpv_archiveFiber;
    ["accepted insertion prunes expired trails, TTL 300", count A3UE_FPV_deadFibers == 1 && {((A3UE_FPV_deadFibers # 0) # 0) isEqualTo _b} && {abs (((A3UE_FPV_deadFibers # 0) # 1) - ((A3UE_FPV_deadFibers # 0) # 2) - 300) < 0.01}] call _check;
    call _reset;
    for "_i" from 1 to 9 do {[_i] call _seed; [_n, 20, str _i] call A3UE_fnc_fpv_archiveFiber;};
    ["fixed nine-event source burst admits eight", count A3UE_FPV_deadFibers == 8 && {A3UE_FPV_archivePublications == 8}] call _check;
    call _reset;
    // Different synthetic sources isolate the global limit from eight/source.
    for "_i" from 1 to 17 do {[_i, 100 + _i] call _seed; [_n, 20, str _i] call A3UE_fnc_fpv_archiveFiber;};
    ["fixed global burst admits sixteen", count A3UE_FPV_deadFibers == 16 && {count A3UE_FPV_archiveRates == 16}] call _check;
    call _reset;
    // Simulate four global windows while retaining all ten-second source slots.
    for "_i" from 1 to 65 do {
        if ((_i - 1) mod 16 == 0) then {A3UE_FPV_archiveGlobalRate = [serverTime, 0];};
        [_i, 100 + _i] call _seed; [_n, 20, str _i] call A3UE_fnc_fpv_archiveFiber;
    };
    ["active source slots cap 64 without churn eviction", count A3UE_FPV_archiveRates == 64 && {!("165" in A3UE_FPV_archiveRates)} && {!((A3UE_FPV_lifecycles get "65") get "archived")}] call _check;
    {_y set [0, serverTime - 11];} forEach A3UE_FPV_archiveRates;
    A3UE_FPV_archiveGlobalRate = [serverTime, 0]; [66, 166] call _seed; [_n, 20, "66"] call A3UE_fnc_fpv_archiveFiber;
    ["expired source slots pruned before new admission", count A3UE_FPV_archiveRates == 1 && {"166" in A3UE_FPV_archiveRates}] call _check;
    call _reset;
    // Isolate aggregate eviction from rate tests by explicitly advancing fixture windows.
    for "_i" from 1 to 65 do {[_i] call _seed; A3UE_FPV_archiveRates = createHashMap; A3UE_FPV_archiveGlobalRate = [serverTime, 0]; [[[_i, 0, 0]], 300, str _i] call A3UE_fnc_fpv_archiveFiber;};
    ["FIFO entries cap 64 retains recent native/managed", count A3UE_FPV_deadFibers == 64 && {((((A3UE_FPV_deadFibers # 0) # 0) # 0) # 0) == 2} && {((((A3UE_FPV_deadFibers # 63) # 0) # 0) # 0) == 65}] call _check;
    call _reset; private _large = _oversize select [0, 256];
    for "_i" from 1 to 17 do {[_i] call _seed; A3UE_FPV_archiveRates = createHashMap; A3UE_FPV_archiveGlobalRate = [serverTime, 0]; [_large, 300, str _i] call A3UE_fnc_fpv_archiveFiber;};
    ["aggregate 4096-point cap", count A3UE_FPV_deadFibers == 16 && {A3UE_FPV_archivePoints == 4096}] call _check;
    for "_i" from 18 to 275 do {[_i] call _seed;}; call A3UE_fnc_fpv_pruneLifecycle;
    ["closed metadata cap 256", count A3UE_FPV_lifecycles == 256] call _check;
    { _y set ["closedAt", serverTime - 601]; } forEach A3UE_FPV_lifecycles; call A3UE_fnc_fpv_pruneLifecycle;
    ["expired identities removed", count A3UE_FPV_lifecycles == 0] call _check;
    deleteVehicle _u;
    if (!("A3UE_FPV_kvnCreatedEH" in (_saved select {_x # 1} apply {_x # 0})) && {!isNil "A3UE_FPV_kvnCreatedEH"}) then {removeMissionEventHandler ["EntityCreated", A3UE_FPV_kvnCreatedEH];};
    { _x params ["_name", "_existed", "_value"]; missionNamespace setVariable [_name, if (_existed) then {_value} else {nil}, _name == "kvn_deadFibers"]; } forEach _saved;
    diag_log format ["[A3UE FPV TEST F05] STRUCTURAL END cases=%1 failures=%2; real network/vendor/JIP NOT RUN", _cases, _failures];
};
true
