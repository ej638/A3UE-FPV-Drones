// Explicit UAV-free preflight. Scheduled elapsed includes scheduler preemption.
// No specimen, movement writer, capture sink or production function replacement.
params [["_action","status"],["_class","B_UAV_01_F"],["_caller",scriptNull]];
private _state = missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap];
private _status = {
    ["MOTION_PREPARATION",_state getOrDefault ["class",""],_state getOrDefault ["active",false],
        _state getOrDefault ["phase","IDLE"],_state getOrDefault ["progress",0],128,
        _state getOrDefault ["item",""],
        if (_state getOrDefault ["active",false]) then {diag_tickTime-(_state get "started")} else {_state getOrDefault ["elapsed",0]},
        _state getOrDefault ["reason",[]],_state getOrDefault ["counts",[]],_state getOrDefault ["costs",[]],
        _state getOrDefault ["ready",false],_state getOrDefault ["exported",false],_state getOrDefault ["kind","PENDING"],
        ["unmatchedCallback",_state getOrDefault ["unmatched",[]]]]
};
if (_action == "status") exitWith {
    private _result = call _status;
    if (hasInterface) then {copyToClipboard str _result;};
    _result
};
private _refuse = {
    params ["_reason"];
    diag_log ["A3UE_FPV_QA_MOTION_PREP_REFUSED",_action,_class,"NOT RUN",_reason];
    if (hasInterface) then {copyToClipboard str ["NOT RUN",_reason];};
    createHashMap
};
if (isRemoteExecuted || {!isServer} || {!canSuspend}) exitWith {["CONTEXT: qualified scheduled server-local dispatcher required"] call _refuse};
if (_action == "cancel") exitWith {
    if (_state getOrDefault ["active",false]) then {_state set ["cancel",true];};
    if (hasInterface) then {copyToClipboard str ["PREPARATION_CANCEL_REQUESTED",_state getOrDefault ["active",false]];};
    createHashMap
};
if (!(_action in ["start","admit"])) exitWith {["UNKNOWN_PREPARATION_ACTION"] call _refuse};
if (!(_class in ["B_UAV_01_F","O_UAFPV_PG7VL_AT","frtz_O_KVN_AT_20KM"])
    || {!isClass (configFile >> "CfgVehicles" >> _class)}
    || {!(missionNamespace getVariable ["A3UE_FPV_registrationComplete",false])}
    || {missionNamespace getVariable ["A3UE_FPV_debug",false]}) exitWith {["CLASS_OR_INITIALIZATION"] call _refuse};
if (_action == "admit" && {!(_state getOrDefault ["ready",false]) || {(_state getOrDefault ["class",""]) != _class}}) exitWith {
    ["PREPARATION_REQUIRED: run preparation-only start for this class first"] call _refuse
};
if (!fileExists "scripts\ua_dive\motion_policy.sqf" || {!fileExists "scripts\ua_dive\motion_policy_data.sqf"}) exitWith {
    ["QA_POLICY_HELPERS_MISSING"] call _refuse
};
private _busy = {
    private _motion = missionNamespace getVariable ["A3UE_FPV_QA_motionState",createHashMap];
    private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState",createHashMap];
    (missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap]) getOrDefault ["active",false]
        || {count _motion > 0 && {!(_motion getOrDefault ["finished",false])}}
        || {count _cap > 0 && {!(_cap getOrDefault ["exported",false])}}
        || {missionNamespace getVariable ["A3UE_FPV_QA_startupRunning",false]}
        || {values (missionNamespace getVariable ["A3UE_FPV_QA_runs",createHashMap]) findIf {!(_x getOrDefault ["cleaned",false])} >= 0}
};
private _reserved = false;
if (_action == "start") then {_caller = _thisScript;};
if (isNull _caller) exitWith {["PREPARATION_WORKER_HANDLE_REQUIRED"] call _refuse};
// Reserve and expose state before data loading, preprocessing or lexical work.
isNil {
    if (call _busy) exitWith {};
    _state = createHashMapFromArray [["class",_class],["active",true],["ready",false],["exported",false],
        ["phase","ACKNOWLEDGED"],["progress",0],["item",""],["started",diag_tickTime],["deadline",diag_tickTime+30],
        ["cancel",false],["reason",[]],["unmatched",[]],["worker",_caller],["counts",[]],["costs",[]]];
    missionNamespace setVariable ["A3UE_FPV_QA_motionPreparation",_state];
    _reserved = true;
};
if (!_reserved) exitWith {["PREPARATION_FIXTURE_CAPTURE_EXPORT_OR_ROSTER_BUSY"] call _refuse};
if (hasInterface) then {copyToClipboard str ["PREPARATION_ACKNOWLEDGED",_class,_action,30,"scheduled elapsed seconds; no specimens"];};
// Supervisor owns only this QA worker. Terminal state is retained, not a stale lock.
[_state] spawn {
    params ["_s"];
    waitUntil {sleep .1; !(_s get "active") || {_s get "cancel"} || {diag_tickTime >= (_s get "deadline")} || {scriptDone (_s get "worker")}};
    if (!(_s get "active")) exitWith {};
    private _why = if (_s get "cancel") then {["PREPARATION_CANCELLED"]} else {
        if (diag_tickTime >= (_s get "deadline")) then {["POLICY_ADMISSION_DEADLINE"]} else {["PREPARATION_WORKER_ERROR"]}
    };
    _s set ["cancel",true];
    sleep .2;
    if (!(_s get "active")) exitWith {};
    private _worker = _s get "worker";
    if (!scriptDone _worker) then {terminate _worker;};
    _s set ["ready",false]; _s set ["reason",_why]; _s set ["phase","NOT_RUN"];
    _s set ["elapsed",diag_tickTime-(_s get "started")];
    diag_log ["A3UE_FPV_QA_MOTION_PREP_END",_s get "class",false,_why,_s get "elapsed",_s get "counts",_s get "costs","scheduled elapsed; worker interrupted; partial material discarded",["progressItem",_s get "item"],["unmatchedCallback",_s get "unmatched"]];
    _s set ["exported",true]; _s set ["active",false];
};
// Give explicit status/cancellation commands an observable scheduling boundary.
sleep .01;
_state set ["phase","LOAD_REVIEWED_DATA"];
private _loadAt = diag_tickTime;
A3UE_FPV_QA_motionPolicy = compileScript ["scripts\ua_dive\motion_policy.sqf"];
private _policy = ["inventory",_class] call A3UE_FPV_QA_motionPolicy;
private _elapsed = diag_tickTime-(_state get "started");
private _why = _policy getOrDefault ["reason",["PREPARATION_NO_RESULT"]];
if (_state get "cancel") then {_why = ["PREPARATION_CANCELLED"];};
if (diag_tickTime >= (_state get "deadline") && {_why isEqualTo []}) then {_why = ["POLICY_ADMISSION_DEADLINE"];};
private _ok = (_policy getOrDefault ["ok",false]) && {_why isEqualTo []};
_policy set ["ok",_ok]; _policy set ["reason",_why];
_state set ["phase","DEFERRED_EVIDENCE"];
// Compact evidence only, no source/function strings. Rows remain bounded at 256.
diag_log ["A3UE_FPV_QA_MOTION_PREP_END",_class,_ok,_why,_elapsed,_state get "counts",_state get "costs",
    ["inventoryScheduledSeconds",_policy getOrDefault ["admissionSeconds",0]],
    ["helperDataAndCacheSetupScheduledSeconds",diag_tickTime-_loadAt-(_policy getOrDefault ["admissionSeconds",0])],
    _state getOrDefault ["kind","PENDING"],_state getOrDefault ["mountedImmutable",false],
    "scheduled elapsed includes preemption; preparation only, no AI/motion/cleanup/performance PASS",
    ["progressItem",_state get "item"],["unmatchedCallback",_state get "unmatched"]];
{
    diag_log ["A3UE_FPV_QA_MOTION_ADMISSION",_policy getOrDefault ["version",""],_x];
    if (_forEachIndex mod 32 == 31) then {sleep .001;};
} forEach (_policy getOrDefault ["rows",[]]);
// Commit once, after complete qualification and evidence; cancellation/deadline
// can still discard this transaction. An older successful material cache is safe.
isNil {
    if (_state get "cancel" || {diag_tickTime >= (_state get "deadline")}) then {
        _ok = false; _why = ["PREPARATION_CANCELLED_OR_DEADLINE_DURING_EXPORT"];
    };
    if (_ok) then {
        private _issue = ["precreate",[_policy,objNull]] call A3UE_FPV_QA_motionPolicy;
        if (_issue isNotEqualTo []) then {_ok = false; _why = _issue;};
    };
    if (_ok) then {missionNamespace setVariable ["A3UE_FPV_QA_motionMaterial",_policy get "material"];};
    _policy deleteAt "material";
    _state set ["ready",_ok]; _state set ["reason",_why]; _state set ["phase",["NOT_RUN","PREPARED_ONLY"] select _ok];
    _state set ["elapsed",diag_tickTime-(_state get "started")]; _state set ["exported",true]; _state set ["active",false];
};
diag_log ["A3UE_FPV_QA_MOTION_PREP_CLOSED",_class,_ok,_why,_state get "elapsed",_state get "counts",_state get "costs",_state getOrDefault ["kind","PENDING"],["progressItem",_state get "item"],["unmatchedCallback",_state get "unmatched"]];
if (_action == "start" && {hasInterface}) then {copyToClipboard str (call _status);};
if (!_ok) exitWith {createHashMap};
_policy
