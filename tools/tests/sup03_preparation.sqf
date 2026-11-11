// Server-local STRUCTURAL test with synthetic AU dispatch/debit and launch spies.
// Copy to a disposable ready campaign: [] execVM "scripts\sup03_preparation.sqf";
// No actual AU request, vendor flight, mission-end delivery or campaign save is certified.
if (!isServer || {isRemoteExecuted} || {!(missionNamespace getVariable ["A3UE_FPV_siteReady", false])}) exitWith {
    diag_log "[A3UE FPV TEST SUP-03] BLOCKED: server-local ready disposable campaign";
};
private _functions = ["A3UE_fnc_fpv_resolveSupportPackage", "A3UE_fnc_fpv_supportResolveOrigin",
    "A3UE_fnc_fpv_supportPassesSafetyRing", "A3UE_fnc_fpv_supportCreateMarker",
    "A3UE_fnc_fpv_spawnManagedDrone", "A3UE_fnc_fpv_filterTarget", "A3UE_fnc_fpv_cleanupDrone",
    "A3A_fnc_addEnemyResources", "A3A_fnc_showInterceptedSetupCall", "A3A_fnc_showInterceptedSupportCall"];
if (_functions findIf {isFinal (missionNamespace getVariable [_x, {}])} >= 0) exitWith {
    diag_log "[A3UE FPV TEST SUP-03] BLOCKED: immutable spies; use recompile-enabled disposable mission";
};
private _names = _functions + ["A3UE_FPV_supportRegistry", "A3UE_FPV_supportTransientMarkers",
    "A3A_activeSupports", "A3A_supportStrikes", "A3A_supportCount", "A3A_supportCallInProgress",
    "A3UE_FPV_supportShuttingDown", "A3UE_FPV_supportEndedEH", "A3UE_FPV_supportMPEndedEH",
    "A3UE_FPV_lastSupportFailureReason", "A3UE_FPV_lastSupportPlan", "A3UE_FPV_lastSupportContext", "A3UE_QA_sup03"];
private _saved = _names apply {[_x, !isNil _x, missionNamespace getVariable [_x, 0]]};
private _state = createHashMapFromArray [["balance", 10000], ["debits", 0], ["credits", 0],
    ["spawns", []], ["quota", 2], ["originValid", true], ["generation", 1], ["safe", true],
    ["objects", []], ["markers", []], ["cases", 0], ["failures", 0]];
A3UE_QA_sup03 = _state;
A3UE_FPV_supportRegistry = createHashMap; A3UE_FPV_supportTransientMarkers = [];
A3A_activeSupports = []; A3A_supportStrikes = []; A3A_supportCallInProgress = nil;
A3UE_FPV_supportShuttingDown = false;
A3UE_fnc_fpv_resolveSupportPackage = {
    private _origin = createHashMapFromArray [["ok", true], ["originMarker", "QA_SUP03_origin"],
        ["originPosATL", [0, 0, 0]], ["launchPosATL", [0, 0, 35]], ["originContract", "ACTIVE_SITE"],
        ["originEpoch", "QA_SUP03"], ["originGeneration", 1], ["reach", createHashMap]];
    createHashMapFromArray [["ok", true], ["origin", _origin], ["familyId", "armafpv"],
        ["uavClass", "B_UAV_01_F"], ["payloadRole", "AP"], ["siteType", "ReactiveSupport"],
        ["droneCount", 2], ["estimatedCost", 170], ["costOverhead", 20], ["activeRadius", 100], ["strikeDuration", 2]]
};
A3UE_fnc_fpv_supportResolveOrigin = {
    private _state = A3UE_QA_sup03;
    if !(_state get "originValid") exitWith {createHashMapFromArray [["ok", false], ["reason", "ORIGIN_INELIGIBLE"]]};
    private _result = createHashMap;
    {_result set [_x, _y];} forEach ((_this # 2) get "origin");
    _result set ["originGeneration", _state get "generation"];
    _result
};
A3UE_fnc_fpv_supportPassesSafetyRing = {A3UE_QA_sup03 get "safe"};
A3UE_fnc_fpv_supportCreateMarker = {
    params ["_name", "_pos"];
    private _marker = createMarker [format ["%1_search_%2", _name, count (A3UE_QA_sup03 get "markers")], _pos];
    _marker setMarkerShape "ICON";
    (A3UE_QA_sup03 get "markers") pushBack _marker;
    A3UE_FPV_supportTransientMarkers pushBack _marker;
    _marker
};
A3UE_fnc_fpv_filterTarget = {params ["_object"]; [objNull, _object] select (!isNull _object && {alive _object})};
A3UE_fnc_fpv_spawnManagedDrone = {
    private _state = A3UE_QA_sup03;
    if ((_state get "quota") <= 0) exitWith {objNull};
    _state set ["quota", (_state get "quota") - 1];
    private _uav = createVehicle ["B_UAV_01_F", (_this # 0) get "spawnPosATL", [], 0, "FLY"];
    (_state get "objects") pushBack _uav;
    (_state get "spawns") pushBack time;
    _uav
};
A3UE_fnc_fpv_cleanupDrone = {
    params ["_uav"];
    [_uav, "finished", "cleanup"] call A3UE_fnc_fpv_supportFinalize;
    deleteVehicle _uav;
};
A3A_fnc_addEnemyResources = {
    params ["_amount"];
    private _state = A3UE_QA_sup03;
    _state set ["balance", (_state get "balance") + _amount];
    private _key = ["debits", "credits"] select (_amount > 0);
    _state set [_key, (_state get _key) + 1];
};
A3A_fnc_showInterceptedSetupCall = {};
A3A_fnc_showInterceptedSupportCall = {};
if (_functions findIf {(missionNamespace getVariable [_x, {}]) isEqualTo (_saved # (_functions find _x) # 2)} >= 0) exitWith {
    {_x params ["_name", "_present", "_value"]; missionNamespace setVariable [_name, if (_present) then {_value} else {nil}];} forEach _saved;
    diag_log "[A3UE FPV TEST SUP-03] BLOCKED: spy assignment failed";
};
private _assert = {
    params ["_case", "_ok"];
    _state set ["cases", (_state get "cases") + 1];
    if (!_ok) then {_state set ["failures", (_state get "failures") + 1];};
    diag_log format ["[A3UE FPV TEST SUP-03] STRUCTURAL case=%1 pass=%2", _case, _ok];
};
// SUP-05 requires an actual seed; preparation/economic cases use this stable object.
private _fixtureTarget = createAgent ["C_man_1", [1400, 0, 0], [], 0, "NONE"];
_fixtureTarget enableSimulationGlobal false;
(_state get "objects") pushBack _fixtureTarget;
private _create = {
    params ["_delay", ["_target", objNull], ["_paid", true]];
    if (isNull _target) then {_target = _fixtureTarget;};
    private _name = "";
    isNil {
        A3A_supportCount = A3A_supportCount + 1;
        _name = format ["FPV%1", A3A_supportCount];
        private _type = ["", "FPV"] select _paid;
        private _createFunc = A3A_fnc_SUP_FPV;
        A3A_supportCallInProgress = true;
        private _cost = [_name, Occupants, "attack", 500, _target, [1400, 0, 0], 0, _delay] call A3A_fnc_SUP_FPV;
        if (_paid && {_cost >= 0}) then {[-_cost, Occupants, "attack"] call A3A_fnc_addEnemyResources;};
        A3A_supportCallInProgress = nil;
    };
    _name
};
private _entry = {A3UE_FPV_supportRegistry get (_this # 0)};
private _cancel = {[_this # 0, "failed", "QA_CANCEL", "", true] call A3UE_fnc_fpv_supportFinalize};
private _reset = {_state set ["quota", 2]; _state set ["originValid", true]; _state set ["generation", 1]; _state set ["safe", true];};
private _awaitClosed = {
    params ["_name"];
    private _timeout = time + 4;
    waitUntil {sleep 0.05; (([_name] call _entry) get "status") in ["active", "failed", "finished"] || {time > _timeout}};
};
private _before = count (_state get "spawns");
private _zero = [0] call _create;
private _e = [_zero] call _entry;
["zero launches synchronously", (_e get "status") == "active" && {count (_state get "spawns") == _before + 2}] call _assert;
["zero one debit", (_state get "debits") == 1 && {(_state get "balance") == 9830}] call _assert;
call _reset;
private _start = time;
private _positive = [1] call _create;
_e = [_positive] call _entry;
["positive preparing no vehicles", (_e get "status") == "preparing" && {(_e get "drones") isEqualTo []}] call _assert;
["AU lock released on return", isNil "A3A_supportCallInProgress"] call _assert;
["positive reserves once", (_state get "debits") == 2 && {(_e get "reservationState") == "reserved"}] call _assert;
["early helper cannot bypass deadline", ([_positive, _e get "preparationId"] call A3UE_fnc_fpv_supportLaunch) == -1 && {(_e get "status") == "preparing"}] call _assert;
["duplicate name cannot replace reservation", ([_positive, Occupants, "attack", 500, _fixtureTarget, [1400, 0, 0], 0, 1] call A3A_fnc_SUP_FPV) == -1 && {([_positive] call _entry) isEqualRef _e} && {markerShape (_e get "searchMarker") != ""}] call _assert;
private _before = count (_state get "spawns");
sleep 0.15;
["no early launch", count (_state get "spawns") == _before] call _assert;
call _reset;
private _overlap = [0] call _create;
["another request progresses during preparation", (([_overlap] call _entry) get "status") == "active" && {(([_positive] call _entry) get "status") == "preparing"}] call _assert;
call _reset;
_before = count (_state get "spawns");
[_positive] call _awaitClosed;
_e = [_positive] call _entry;
["launch after deadline", (_e get "status") == "active" && {((_state get "spawns") # _before) >= _start + 1}] call _assert;
["full active lifetime after preparation", abs ((_e get "strikeExpiresAt") - time - 2) < 0.2] call _assert;
["launch releases plan and timer", !("preparation" in _e) && {!("preparationHandle" in _e)}] call _assert;
["duplicate launch rejected", ([_positive, _e get "preparationId"] call A3UE_fnc_fpv_supportLaunch) == -1] call _assert;
call _reset;
private _automatic = [-1] call _create;
_e = [_automatic] call _entry;
["automatic distance delay", (_e get "setupDelay") == 20 && {(_e get "status") == "preparing"}] call _assert;
private _credits = _state get "credits";
[_automatic] call _cancel;
["automatic cancellation full refund", (_state get "credits") == _credits + 1 && {(_e get "refundedCost") == 170}] call _assert;
private _stamp = _e get "finishedAt";
["duplicate cancellation inert", !([_automatic] call _cancel) && {(_e get "finishedAt") == _stamp} && {(_state get "credits") == _credits + 1}] call _assert;
["cancel removes marker and pending strike", markerShape (_e get "searchMarker") == "" && {!("pendingStrike" in _e)}] call _assert;
["cancel releases plan and handle", !("preparation" in _e) && {!("preparationHandle" in _e)}] call _assert;
call _reset;
private _unpaid = [0.3, objNull, false] call _create;
_credits = _state get "credits";
[_unpaid] call _cancel;
["unpaid helper cannot fabricate refund", (_state get "credits") == _credits] call _assert;
private _spawns = count (_state get "spawns");
sleep 0.6;
["cancelled timer never launches", count (_state get "spawns") == _spawns] call _assert;
{
    call _reset;
    private _name = [0.25] call _create;
    private _e = [_name] call _entry;
    private _credits = _state get "credits";
    switch (_x) do {
        case "capture": {_state set ["originValid", false];};
        case "generation": {_state set ["generation", 2];};
        case "safety": {_state set ["safe", false];};
        case "marker": {deleteMarker (_e get "searchMarker");};
        case "spawn": {_state set ["quota", 0];};
    };
    [_name] call _awaitClosed;
    [format ["%1 rejected and refunded once", _x], (_e get "status") == "failed" && {(_e get "refundedCost") == 170} && {(_state get "credits") == _credits + 1}] call _assert;
} forEach ["capture", "generation", "safety", "marker", "spawn"];
{
    call _reset;
    private _target = createAgent ["C_man_1", [1400, 0, 0], [], 0, "NONE"];
    (_state get "objects") pushBack _target;
    private _name = [0.25, _target] call _create;
    private _e = [_name] call _entry;
    if (_x == "death") then {_target setDamage 1;} else {deleteVehicle _target;};
    [_name] call _awaitClosed;
    [format ["target %1 cancels stable object reference", _x], (_e get "status") == "failed" && {(_e get "lastFailureReason") == "TARGET_INELIGIBLE"}] call _assert;
} forEach ["death", "delete"];
call _reset;
private _partial = [0.25] call _create;
_state set ["quota", 1];
[_partial] call _awaitClosed;
_e = [_partial] call _entry;
["partial creation refunds only missing aircraft", (_e get "status") == "active" && {(_e get "resourceCost") == 95} && {(_e get "refundedCost") == 75}] call _assert;
_credits = _state get "credits";
[_partial] call _cancel;
["active finalization adds no reservation refund", (_state get "credits") == _credits] call _assert;
call _reset;
private _new = [0.5] call _create;
_e = [_new] call _entry;
["stale identity cannot launch newer package", ([_new, (_e get "preparationId") - 1] call A3UE_fnc_fpv_supportLaunch) == -1 && {(_e get "status") == "preparing"}] call _assert;
call _reset;
private _other = [0.5] call _create;
_credits = _state get "credits";
call A3UE_fnc_fpv_supportShutdown;
["shutdown settles all pending packages", (([_new] call _entry) get "status") == "failed" && {(([_other] call _entry) get "status") == "failed"} && {(_state get "credits") == _credits + 2}] call _assert;
call A3UE_fnc_fpv_supportShutdown;
["shutdown duplicate no extra refund", (_state get "credits") == _credits + 2] call _assert;
_spawns = count (_state get "spawns");
sleep 0.75;
["shutdown timers cannot launch", count (_state get "spawns") == _spawns] call _assert;
["shutdown rejects new package", (["QA_after_end", Occupants, "attack", 500, objNull, [1400, 0, 0], 0, 0] call A3A_fnc_SUP_FPV) == -1] call _assert;
// Restore all spies/state; names and IDs in delayed retention callbacks are unique.
isNil {
    {if (!isNull _x) then {deleteVehicle _x;};} forEach (_state get "objects");
    {if (markerShape _x != "") then {deleteMarker _x;};} forEach (_state get "markers");
    if !((_saved # (_names find "A3UE_FPV_supportEndedEH")) # 1) then {
        removeMissionEventHandler ["Ended", A3UE_FPV_supportEndedEH];
        removeMissionEventHandler ["MPEnded", A3UE_FPV_supportMPEndedEH];
    };
    {_x params ["_name", "_present", "_value"]; missionNamespace setVariable [_name, if (_present) then {_value} else {nil}];} forEach _saved;
};
diag_log format ["[A3UE FPV TEST SUP-03] END result=%1 cases=%2 failures=%3; STRUCTURAL ONLY; restart", ["PASS", "FAIL"] select ((_state get "failures") > 0), _state get "cases", _state get "failures"];
