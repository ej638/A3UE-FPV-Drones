// ENGINE regression: production lifecycle functions, no replacement functions.
// Use the qualified QA dispatcher in a fresh disposable host mission, no capture.
// [["frtz_O_KVN_AT_20KM", [50,50,100]], "scripts\ua_dive\startup.sqf"] call A3UE_FPV_QA_dispatch;
// Simulation-disabled specimens test startup only, never qualify flight/transport.
params [["_kvnClass", "frtz_O_KVN_AT_20KM"], ["_pos", [50,50,100]]];
private _motion = missionNamespace getVariable ["A3UE_FPV_QA_motionState",createHashMap];
if ((missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap]) getOrDefault ["active",false]) exitWith {diag_log ["A3UE_FPV_QA_STARTUP_BLOCKED","MOTION_PREPARATION_BUSY"];};
if (count _motion > 0 && {!(_motion getOrDefault ["finished",false])}) exitWith {diag_log ["A3UE_FPV_QA_STARTUP_BLOCKED","MOTION_FIXTURE_BUSY"];};
if (isRemoteExecuted || {!isServer} || {!canSuspend}
    || {!(missionNamespace getVariable ["A3UE_FPV_registrationComplete", false])}
    || {!(isClass (configFile >> "CfgVehicles" >> _kvnClass))}
    || {count _pos != 3}) exitWith {diag_log ["A3UE_FPV_QA_STARTUP_BLOCKED", "PREREQUISITES"];};
private _capture = missionNamespace getVariable ["A3UE_FPV_QA_captureState", createHashMap];
private _admitted = false;
isNil {
    private _currentMotion = missionNamespace getVariable ["A3UE_FPV_QA_motionState",createHashMap];
    if ((missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap]) getOrDefault ["active",false]) exitWith {};
    if (count _currentMotion > 0 && {!(_currentMotion getOrDefault ["finished",false])}) exitWith {};
    if (count _capture > 0 && {!(_capture getOrDefault ["exported", false])}
        || {missionNamespace getVariable ["A3UE_FPV_QA_startupRunning", false]}) exitWith {};
    A3UE_FPV_QA_startupRunning = true;
    _admitted = true;
};
if (!_admitted) exitWith {diag_log ["A3UE_FPV_QA_STARTUP_BLOCKED", "BUSY"];};
private _cases = 0;
private _failures = 0;
private _notRun = 0;
private _requiredCases = [
    "unmanaged native generation zero tracked without controller",
    "promotion revokes pending native challenge",
    "native ticket survives but cannot suppress managed retry",
    "overlapping callbacks retain one retry and generation",
    "bounded recovery starts real controller after throttled initial claim",
    "duplicate ready keeps one controller and sequence state",
    "delayed native replies cannot replace managed state",
    "late native tracker cannot overwrite identity or restart native retry",
    "delayed native broker request cannot release managed claim",
    "older episode and wrong lifetime replies rejected",
    "newer public episode fences delayed duplicate ready before episode replication",
    "lost ready restored without new episode or controller",
    "bounded worker exhausts with diagnostic and no controller",
    "exhausted generation cannot recreate worker or issue another automatic request",
    "late authenticated ready can complete exhausted reservation",
    "generation replacement cancels old retry without timeout",
    "production retirement cancels retry and closes lifetime",
    "unmanaged duplicate tracking retains ticket and no managed workers",
    "unmanaged base-episode correction recovers through native retry",
    "native throttle reserves a finite native retry",
    "promotion cancels native worker while reserving one managed retry",
    "all fixture airframes cleaned",
    "retained fixture crew and groups cleaned"
];
private _caseResults = createHashMap;
private _specimens = [];
private _check = {
    params ["_case", "_ok"];
    _cases = _cases + 1;
    if (!_ok) then {_failures = _failures + 1;};
    _caseResults set [_case, ["FAIL", "PASS"] select _ok];
    diag_log ["A3UE_FPV_QA_STARTUP_CASE", _case, _ok];
};
private _skip = {
    params ["_case", "_reason"];
    _notRun = _notRun + 1;
    _caseResults set [_case, "NOT RUN"];
    diag_log ["A3UE_FPV_QA_STARTUP_CASE", _case, "NOT RUN", _reason];
};
private _make = {
    params ["_class", "_managed"];
    private _u = objNull;
    isNil {
        _u = createVehicle [_class, _pos, [], 0, "NONE"];
        _u enableSimulationGlobal false;
        _u setVariable ["A3UE_FPV_netId", netId _u];
        _u setVariable ["A3UE_FPV_managed", _managed];
        _u setVariable ["A3UE_FPV_siteType", "Outpost"];
        _u setVariable ["A3UE_FPV_vendorId", ["", "kvn"] select (_class == _kvnClass)];
        _u setVariable ["A3UE_FPV_mode", "IDLE"];
        _u setVariable ["A3UE_FPV_controlPosATL", +_pos];
        [_u, _managed] call A3UE_fnc_fpv_registerLifecycle;
    };
    _specimens pushBack _u;
    _u
};
private _ready = {
    params ["_u"];
    private _g = _u getVariable ["A3UE_FPV_controllerGeneration", -1];
    [_u, _g] call A3UE_fnc_fpv_hasCurrentLifecycle
        && {(_u getVariable ["A3UE_FPV_startedGeneration", -1]) == _g}
        && {!(scriptDone (_u getVariable ["A3UE_FPV_controllerHandle", scriptNull]))}
};
private _awaitNative = {
    params ["_label", "_u"];
    private _start = diag_tickTime;
    private _until = _start + 8;
    private _polls = 0;
    private _ok = false;
    // Observe the real native retry path; never repair ownership or ready state.
    waitUntil {
        sleep 0.1;
        _polls = _polls + 1;
        _ok = !isNull _u && {local _u} && {owner _u == clientOwner}
            && {!(_u getVariable ["A3UE_FPV_managed", false])}
            && {(_u getVariable ["A3UE_FPV_nativeGeneration", -1]) == 0}
            && {[_u,0] call A3UE_fnc_fpv_hasCurrentLifecycle};
        _ok || {diag_tickTime >= _until}
    };
    // One bounded success/timeout row. Only ticket presence, never its token.
    diag_log ["A3UE_FPV_QA_STARTUP_NATIVE_READY", _label, ["TIMEOUT", "READY"] select _ok,
        diag_tickTime - _start, _polls, clientOwner, owner _u, local _u,
        _u getVariable ["A3UE_FPV_nativeGeneration", -1],
        _u getVariable ["A3UE_FPV_controllerGeneration", -1],
        _u getVariable ["A3UE_FPV_lifecycleEpisode", -1],
        count (_u getVariable ["A3UE_FPV_lifecycleTicket", []]) == 3,
        +(_u getVariable ["A3UE_FPV_controllerIdentity", []]),
        +(_u getVariable ["A3UE_FPV_lifecycleTicketIdentity", []])];
    _ok
};
diag_log ["A3UE_FPV_QA_STARTUP_BEGIN", productVersion, _kvnClass, count _requiredCases];
diag_log ["A3UE_FPV_QA_STARTUP_REQUIRED", _requiredCases];
private _u = [_kvnClass, false] call _make;
[_u] call A3UE_fnc_fpv_trackKvnLifecycle;
private _initialNativeReady = ["initial-native", _u] call _awaitNative;
private _id = _u getVariable ["A3UE_FPV_lifecycleId", -1];
private _record = A3UE_FPV_lifecycles get str _id;
private _nativeTicket = [];
private _nativeIdentity = [];
if (_initialNativeReady) then {
    _nativeTicket = +(_u getVariable ["A3UE_FPV_lifecycleTicket", []]);
    _nativeIdentity = +(_u getVariable ["A3UE_FPV_lifecycleTicketIdentity", []]);
};
private _nativePrerequisite = _initialNativeReady && {!(_record get "managed")}
    && {scriptDone (_u getVariable ["A3UE_FPV_controllerHandle", scriptNull])};
["unmanaged native generation zero tracked without controller", _nativePrerequisite] call _check;
// Fail closed and still reach specimen cleanup if native prerequisites failed.
if (_nativePrerequisite && {count _nativeTicket == 3} && {count _nativeIdentity == 4}) then {
    private _nativeEpisode = _nativeTicket # 1;
    isNil {
        // Represent a native confirmation already in transit at promotion.
        _record set ["challenge", [clientOwner,0,"QA_PENDING_NATIVE",serverTime+5]];
        _u setVariable ["A3UE_FPV_managed", true];
        [_u,true] call A3UE_fnc_fpv_registerLifecycle;
        ["promotion revokes pending native challenge", !("challenge" in _record)
            && {!([_id,_nativeEpisode,0,"claim","QA_PENDING_NATIVE",[]] call A3UE_fnc_fpv_reportLifecycle)}] call _check;
        // Real broker throttle, not a stub of claimLifecycle.
        _record set ["nextClaimAt", serverTime + 0.25];
        [_u] call A3UE_fnc_fpv_bootstrapLocal;
        ["native ticket survives but cannot suppress managed retry", (_u getVariable "A3UE_FPV_lifecycleTicket") isEqualTo _nativeTicket
            && {(_u getVariable "A3UE_FPV_controllerGeneration") == 1}
            && {!([_u,1] call A3UE_fnc_fpv_hasCurrentLifecycle)}
            && {(_u getVariable ["A3UE_FPV_claimRetryGeneration",-2]) == 1}
            && {!(scriptDone (_u getVariable ["A3UE_FPV_claimRetryHandle",scriptNull]))}
            && {scriptDone (_u getVariable ["A3UE_FPV_controllerHandle",scriptNull])}] call _check;
    };
    private _retry = _u getVariable ["A3UE_FPV_claimRetryHandle",scriptNull];
    private _callbacks = [[_u] spawn A3UE_fnc_fpv_bootstrapLocal, [_u] spawn A3UE_fnc_fpv_bootstrapLocal];
    sleep 0.1;
    ["overlapping callbacks retain one retry and generation", (_u getVariable "A3UE_FPV_claimRetryHandle") isEqualTo _retry
        && {(_u getVariable "A3UE_FPV_controllerGeneration") == 1}] call _check;
    private _until = diag_tickTime + 4;
    waitUntil {sleep 0.05; [_u] call _ready || {diag_tickTime >= _until}};
    private _recovered = [_u] call _ready
        && {(_record get "generation") == 1} && {!(_record get "released")};
    ["bounded recovery starts real controller after throttled initial claim", _recovered] call _check;
    if (_recovered) then {
        private _controller = _u getVariable "A3UE_FPV_controllerHandle";
        private _ticket = +(_u getVariable "A3UE_FPV_lifecycleTicket");
        private _identity = +(_u getVariable "A3UE_FPV_lifecycleTicketIdentity");
        private _sequences = _u getVariable ["A3UE_FPV_reportSequences",createHashMap];
        _sequences set ["control",7];
        private _reply = [_u,"ready",_id,clientOwner,_ticket # 1,1,_ticket # 2,[]];
        private _duplicates = [_reply spawn A3UE_fnc_fpv_acceptLifecycle, _reply spawn A3UE_fnc_fpv_acceptLifecycle];
        sleep 0.2;
        ["duplicate ready keeps one controller and sequence state", (_u getVariable "A3UE_FPV_controllerHandle") isEqualTo _controller
            && {((_u getVariable "A3UE_FPV_reportSequences") get "control") == 7}] call _check;
        isNil {
            private _stale = ["retry","challenge","ready"] apply {
                !([_u,_x,_id,clientOwner,_nativeEpisode,0,_nativeTicket # 2,[]] call A3UE_fnc_fpv_acceptLifecycle)
            };
            ["delayed native replies cannot replace managed state", _stale findIf {!_x} < 0
                && {(_u getVariable "A3UE_FPV_lifecycleTicketIdentity") isEqualTo _identity}] call _check;
            [_u,_nativeIdentity] call A3UE_fnc_fpv_trackKvnLifecycle;
            ["late native tracker cannot overwrite identity or restart native retry", (_u getVariable "A3UE_FPV_controllerIdentity") isEqualTo _identity
                && {scriptDone (_u getVariable ["A3UE_FPV_nativeClaimRetry",scriptNull])}] call _check;
            ["delayed native broker request cannot release managed claim", !([_u,_nativeEpisode,0] call A3UE_fnc_fpv_claimLifecycle)
                && {(_record get "generation") == 1} && {!(_record get "released")}] call _check;
            ["older episode and wrong lifetime replies rejected", !([_u,"ready",_id,clientOwner,(_ticket # 1)-1,1,_ticket # 2,[]] call A3UE_fnc_fpv_acceptLifecycle)
                && {!([_u,"ready",_id+1,clientOwner,_ticket # 1,1,_ticket # 2,[]] call A3UE_fnc_fpv_acceptLifecycle)}] call _check;
            _u setVariable ["A3UE_FPV_controllerIdentity",[_id,clientOwner,(_ticket # 1)+1,1]];
            ["newer public episode fences delayed duplicate ready before episode replication", !(_reply call A3UE_fnc_fpv_acceptLifecycle)
                && {((_u getVariable "A3UE_FPV_controllerIdentity") # 2) == (_ticket # 1)+1}] call _check;
            _u setVariable ["A3UE_FPV_controllerIdentity",_identity];
            // Lose only local ready state, then use the real broker resend route.
            _u setVariable ["A3UE_FPV_lifecycleTicket",[]];
            _u setVariable ["A3UE_FPV_lifecycleTicketIdentity",[]];
            _record set ["nextClaimAt",serverTime-1];
            [_u,(_ticket # 1)-1,1] call A3UE_fnc_fpv_claimLifecycle;
            ["lost ready restored without new episode or controller", (_u getVariable "A3UE_FPV_lifecycleTicket") isEqualTo _ticket
                && {(_record get "episode") == (_ticket # 1)}
                && {(_u getVariable "A3UE_FPV_controllerHandle") isEqualTo _controller}] call _check;
        };
    } else {
        {[_x, "MANAGED_RECOVERY_NOT_READY"] call _skip;} forEach (_requiredCases select [5,7]);
    };
} else {
    {[_x, "INITIAL_NATIVE_NOT_READY"] call _skip;} forEach (_requiredCases select [1,11]);
};
private _exhaust = ["O_UAV_01_F",true] call _make;
private _exhaustRecord = A3UE_FPV_lifecycles get str (_exhaust getVariable "A3UE_FPV_lifecycleId");
_exhaustRecord set ["nextClaimAt",serverTime+60];
[_exhaust] call A3UE_fnc_fpv_bootstrapLocal;
private _worker = _exhaust getVariable "A3UE_FPV_claimRetryHandle";
private _deadline = diag_tickTime+8;
waitUntil {sleep 0.05; scriptDone _worker || {diag_tickTime >= _deadline}};
["bounded worker exhausts with diagnostic and no controller", scriptDone _worker
    && {(_exhaust getVariable ["A3UE_FPV_lifecycleClaimFailure",""]) == "BROKER_TIMEOUT"}
    && {scriptDone (_exhaust getVariable ["A3UE_FPV_controllerHandle",scriptNull])}] call _check;
private _requestAt = _exhaust getVariable "A3UE_FPV_nextClaimRequestAt";
[_exhaust] call A3UE_fnc_fpv_bootstrapLocal;
["exhausted generation cannot recreate worker or issue another automatic request", (_exhaust getVariable "A3UE_FPV_claimRetryHandle") isEqualTo _worker
    && {(_exhaust getVariable "A3UE_FPV_nextClaimRequestAt") == _requestAt}] call _check;
_exhaustRecord set ["nextClaimAt",serverTime-1];
[_exhaust,_exhaustRecord get "episode",1] call A3UE_fnc_fpv_claimLifecycle;
["late authenticated ready can complete exhausted reservation", [_exhaust] call _ready
    && {(_exhaust getVariable ["A3UE_FPV_lifecycleClaimFailure",""]) == ""}] call _check;
private _cancel = ["O_UAV_01_F",true] call _make;
private _cancelRecord = A3UE_FPV_lifecycles get str (_cancel getVariable "A3UE_FPV_lifecycleId");
_cancelRecord set ["nextClaimAt",serverTime+60];
[_cancel] call A3UE_fnc_fpv_bootstrapLocal;
private _cancelWorker = _cancel getVariable "A3UE_FPV_claimRetryHandle";
_cancel setVariable ["A3UE_FPV_controllerGeneration",2];
sleep 1.2;
["generation replacement cancels old retry without timeout", scriptDone _cancelWorker
    && {(_cancel getVariable ["A3UE_FPV_lifecycleClaimFailure",""]) == ""}
    && {scriptDone (_cancel getVariable ["A3UE_FPV_controllerHandle",scriptNull])}] call _check;
private _retire = ["O_UAV_01_F",true] call _make;
private _retireRecord = A3UE_FPV_lifecycles get str (_retire getVariable "A3UE_FPV_lifecycleId");
_retireRecord set ["nextClaimAt",serverTime+60];
[_retire] call A3UE_fnc_fpv_bootstrapLocal;
private _retireWorker = _retire getVariable "A3UE_FPV_claimRetryHandle";
[_retire] call A3UE_fnc_fpv_cleanupDrone;
sleep 1.2;
["production retirement cancels retry and closes lifetime", scriptDone _retireWorker
    && {(_retireRecord get "phase") == "closed"}] call _check;
private _native = [_kvnClass,false] call _make;
[_native] call A3UE_fnc_fpv_trackKvnLifecycle;
private _duplicateNativeReady = ["duplicate-tracking", _native] call _awaitNative;
private _before = [];
if (_duplicateNativeReady) then {
    _before = +(_native getVariable ["A3UE_FPV_lifecycleTicket",[]]);
    [_native] call A3UE_fnc_fpv_trackKvnLifecycle;
};
["unmanaged duplicate tracking retains ticket and no managed workers", _duplicateNativeReady && {count _before == 3}
    && {(_native getVariable "A3UE_FPV_lifecycleTicket") isEqualTo _before}
    && {!(_native getVariable ["A3UE_FPV_managed",false])}
    && {scriptDone (_native getVariable ["A3UE_FPV_claimRetryHandle",scriptNull])}
    && {scriptDone (_native getVariable ["A3UE_FPV_controllerHandle",scriptNull])}] call _check;
if (_duplicateNativeReady) then {
    isNil {
        private _r = A3UE_FPV_lifecycles get str (_native getVariable "A3UE_FPV_lifecycleId");
        _r set ["released",true];
        _r set ["nextClaimAt",serverTime-1];
        _native setVariable ["A3UE_FPV_lifecycleTicket",[]];
        _native setVariable ["A3UE_FPV_lifecycleTicketIdentity",[]];
        _native setVariable ["A3UE_FPV_lifecycleEpisode",0];
        [_native] call A3UE_fnc_fpv_trackKvnLifecycle;
    };
    private _nativeUntil = diag_tickTime+4;
    waitUntil {sleep 0.05; [_native,0] call A3UE_fnc_fpv_hasCurrentLifecycle || {diag_tickTime >= _nativeUntil}};
    ["unmanaged base-episode correction recovers through native retry", [_native,0] call A3UE_fnc_fpv_hasCurrentLifecycle
        && {!(_native getVariable ["A3UE_FPV_managed",false])}
        && {scriptDone (_native getVariable ["A3UE_FPV_controllerHandle",scriptNull])}] call _check;
} else {
    ["unmanaged base-episode correction recovers through native retry", "DUPLICATE_NATIVE_NOT_READY"] call _skip;
};
private _nativePending = objNull;
private _nativeWorker = scriptNull;
isNil {
    _nativePending = [_kvnClass,false] call _make;
    private _r = A3UE_FPV_lifecycles get str (_nativePending getVariable "A3UE_FPV_lifecycleId");
    _r set ["nextClaimAt",serverTime+60];
    [_nativePending] call A3UE_fnc_fpv_trackKvnLifecycle;
    _nativeWorker = _nativePending getVariable ["A3UE_FPV_nativeClaimRetry",scriptNull];
    ["native throttle reserves a finite native retry", !(scriptDone _nativeWorker)] call _check;
    _nativePending setVariable ["A3UE_FPV_managed",true];
    [_nativePending,true] call A3UE_fnc_fpv_registerLifecycle;
    [_nativePending] call A3UE_fnc_fpv_bootstrapLocal;
};
sleep 0.1;
["promotion cancels native worker while reserving one managed retry", scriptDone _nativeWorker
    && {scriptDone (_nativePending getVariable ["A3UE_FPV_nativeClaimRetry",scriptNull])}
    && {!(scriptDone (_nativePending getVariable ["A3UE_FPV_claimRetryHandle",scriptNull]))}] call _check;
// Exact fixture objects only; no global lifecycle/manager reset or vendor edits.
private _retainedCrew = [];
{if (!isNull _x) then {{_retainedCrew pushBackUnique _x;} forEach crew _x;};} forEach _specimens;
private _retainedGroups = [];
{_retainedGroups pushBackUnique group _x;} forEach _retainedCrew;
{
    if (!isNull _x) then {
        if (_x getVariable ["A3UE_FPV_managed",false]) then {[_x] call A3UE_fnc_fpv_cleanupDrone;} else {deleteVehicle _x;};
    };
} forEach _specimens;
private _cleanupUntil = diag_tickTime+5;
waitUntil {sleep 0.05; _specimens findIf {!isNull _x} < 0 || {diag_tickTime >= _cleanupUntil}};
["all fixture airframes cleaned", _specimens findIf {!isNull _x} < 0] call _check;
{if (!isNull _x && {local _x}) then {deleteVehicle _x;};} forEach _retainedCrew;
{if (!isNull _x && {local _x} && {units _x isEqualTo []}) then {deleteGroup _x;};} forEach _retainedGroups;
["retained fixture crew and groups cleaned", _retainedCrew findIf {!isNull _x} < 0
    && {_retainedGroups findIf {!isNull _x} < 0}] call _check;
A3UE_FPV_QA_startupRunning = false;
// Audit after cleanup so a missing branch cannot turn zero failures into PASS.
private _missing = _requiredCases select {!(_x in _caseResults)};
{[_x, "REQUIRED_CASE_NOT_REACHED"] call _skip;} forEach _missing;
private _passed = _failures == 0 && {_notRun == 0} && {_cases == count _requiredCases}
    && {count _caseResults == count _requiredCases};
private _status = ["FAIL", "PASS"] select _passed;
diag_log ["A3UE_FPV_QA_STARTUP_COVERAGE",_cases,count _requiredCases,_notRun,_missing];
diag_log ["A3UE_FPV_QA_STARTUP_END",_cases,_failures,count _requiredCases,_notRun,_status,
    "flight/player/Zeus/remote provenance/locality/HC NOT QUALIFIED"];
if (hasInterface) then {copyToClipboard str [_cases,_failures,count _requiredCases,_notRun,_status,
    "STARTUP_END: local startup only; retain tagged RPT"];};
_passed
