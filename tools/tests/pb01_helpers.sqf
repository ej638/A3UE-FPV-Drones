// Explicit disposable QA only. LOCAL is structural; TRACE observes genuine RPC provenance.
params [["_mode", "LOCAL"], ["_uav", objNull], ["_target", objNull]];
if (!isServer || {isRemoteExecuted} || {!canSuspend}) exitWith {false};
private _names = ["publishTelemetry","applyGuidance","runTerminal","runTerminalVector",
    "holdPattern","runLostTarget","clearTarget","detonateCompat","supportCreateMarker",
    "cacheLinkState","selectTarget","resolveImpactPoint","supportEngagementReason",
    "supportPassesSafetyRing","computeIntercept","shouldDetonateNow"];

if (_mode == "RESTORE" && {isNil "A3UE_PB01_trace"}) exitWith {false};
if (_mode == "RESTORE") exitWith {
    private _ok = true;
    {
        private _row = A3UE_PB01_trace get _x;
        if ((missionNamespace getVariable [_x,0]) isEqualTo (_row # 1)) then {
            missionNamespace setVariable [_x,_row # 0];
        } else {_ok = false;};
    } forEach keys A3UE_PB01_trace;
    diag_log ["PB01","TRACE_RESTORED",_ok];
    // Retire the frozen specimen through ordinary cleanup after capture export; do not resume it.
    _ok
};

// Fixed small observation; excludes tickets/tokens and full object/mission snapshots.
A3UE_PB01_snapshot = {
    params ["_u"];
    [getPosASL _u,vectorDir _u,vectorUp _u,velocity _u,
        ["A3UE_PB01_sentinel","A3UE_FPV_targetNetId","A3UE_FPV_mode",
         "A3UE_FPV_lastMoveUpdate","A3UE_FPV_lastTerminalMoveUpdate","A3UE_FPV_nextHoldUpdate",
         "A3UE_FPV_nextDetonationRequestAt","A3UE_FPV_terminalPoseSerial",
         "A3UE_FPV_cachedLinkState","A3UE_FPV_lastTargetScore","A3UE_FPV_lastLeadTime",
         "A3UE_FPV_lastDetonationReason","A3UE_FPV_lostTargetOriginASL"] apply {str (_u getVariable [_x,"ABSENT"])},
        (crew _u) apply {[_x checkAIFeature "PATH",_x checkAIFeature "FSM",_x checkAIFeature "AUTOCOMBAT"]},
        missionNamespace getVariable ["A3A_supportMarkerCount",-1],
        +(missionNamespace getVariable ["A3UE_FPV_supportTransientMarkers",[]]),
        count (missionNamespace getVariable ["A3UE_FPV_recentDetonations",[]]),
        ["A3A_resourcesDefenceOcc","A3A_resourcesAttackOcc","A3A_resourcesDefenceInv","A3A_resourcesAttackInv"] apply {missionNamespace getVariable [_x,-1]}]
};

if (_mode == "TRACE") exitWith {
    if (isNull _uav || {isNull _target} || {!local _uav}
        || {!([_uav] call A3UE_fnc_fpv_hasCurrentLifecycle)}
        || {!(_uav getVariable ["A3UE_FPV_managed",false])}
        || {[_uav] call A3UE_fnc_fpv_isExternallyControlled}) exitWith {diag_log ["PB01","TRACE_BLOCKED","SPECIMEN"];false};
    private _full = _names apply {"A3UE_fnc_fpv_" + _x};
    if ((_full findIf {private _f = missionNamespace getVariable [_x,0]; !(_f isEqualType {}) || {isFinal _f}}) >= 0
        || {!isNil "A3UE_PB01_trace"}) exitWith {diag_log ["PB01","TRACE_BLOCKED","BINDING"];false};
    // Stop just this real issued owner controller/fiber before fixed before/after observations.
    {_x params ["_key"];private _h = _uav getVariable [_key,scriptNull];if !(scriptDone _h) then {terminate _h;};}
        forEach [["A3UE_FPV_controllerHandle"],["A3UE_FPV_fiberTrailHandle"]];
    _uav enableSimulationGlobal false;
    A3UE_PB01_uav = _uav; A3UE_PB01_target = _target;
    publicVariable "A3UE_PB01_uav"; publicVariable "A3UE_PB01_target";
    // Valid movement/reset inputs on this frozen, current-ticket specimen.
    _uav setVariable ["A3UE_FPV_mode","TERMINAL_VECTOR"];
    _uav setVariable ["A3UE_FPV_targetNetId",netId _target];
    _uav setVariable ["A3UE_FPV_terminalVectorEnteredAt",time];
    _uav setVariable ["A3UE_FPV_lastKnownTargetPosASL",getPosASL _target];
    _uav setVariable ["A3UE_FPV_lastKnownTargetVel",velocity _target];
    _uav setVariable ["A3UE_FPV_lastKnownTargetTime",time];
    _uav setVariable ["A3UE_FPV_lostTargetExpireAt",time + 600];
    A3UE_PB01_trace = createHashMap;
    {
        private _original = missionNamespace getVariable _x;
        private _wrapper = compile format [
            'private _before = [A3UE_PB01_uav] call A3UE_PB01_snapshot;
            diag_log ["PB01","ENTRY","%1",clientOwner,remoteExecutedOwner,isRemoteExecuted,isRemoteExecutedJIP,canSuspend,call A3UE_fnc_fpv_helperAccess,call A3UE_fnc_fpv_lifecycleAccess];
            private _return = _this call ((A3UE_PB01_trace get "%1") # 0);
            diag_log ["PB01","RETURN","%1",_return,_before isEqualTo ([A3UE_PB01_uav] call A3UE_PB01_snapshot)];
            _return',_x];
        A3UE_PB01_trace set [_x,[_original,_wrapper]];
        missionNamespace setVariable [_x,_wrapper];
    } forEach _full;
    diag_log ["PB01","TRACE_ARMED",netId _uav,netId _target,owner _uav];
    true
};

if (_mode != "LOCAL" || {!(missionNamespace getVariable ["serverInitDone",false])}
    || {isNil "A3UE_FPV_supportTransientMarkers"}) exitWith {false};
// Synthetic private ticket isolates current/stale effect admission only; never print it.
private _u = createVehicle ["O_UAV_01_F",[50,50,100],[],0,"NONE"];
private _t = createVehicle ["O_UAV_01_F",[100,100,100],[],0,"NONE"];
_u enableSimulationGlobal false; _t enableSimulationGlobal false;
createVehicleCrew _u;
private _identity = [123456,clientOwner,1,1];
{
    _x params ["_k","_v"]; _u setVariable [_k,_v];
} forEach [["A3UE_FPV_managed",true],["A3UE_FPV_netId",netId _u],
    ["A3UE_FPV_controllerRunning",true],["A3UE_FPV_controllerGeneration",1],
    ["A3UE_FPV_controllerIdentity",_identity],["A3UE_FPV_lifecycleTicketIdentity",_identity],
    ["A3UE_FPV_lifecycleId",123456],["A3UE_FPV_lifecycleEpisode",1],
    ["A3UE_FPV_lifecycleTicket",[123456,1,"LOCAL_FIXTURE"]]];
private _fails = 0; private _count = 0;
private _check = {params ["_name","_ok"];_count = _count + 1;if (!_ok) then {_fails = _fails + 1;};diag_log ["PB01","LOCAL",_name,_ok];};
["current admission",[_u,_identity] call A3UE_fnc_fpv_canActuate] call _check;
["local telemetry",[_u,"A3UE_PB01_sentinel",true,0] call A3UE_fnc_fpv_publishTelemetry && {_u getVariable ["A3UE_PB01_sentinel",false]}] call _check;
["local guidance",[_u,getPosASL _t,createHashMap] call A3UE_fnc_fpv_applyGuidance] call _check;
["local terminal",[_u,_t,createHashMap] call A3UE_fnc_fpv_runTerminal] call _check;
["local hold",[_u,createHashMap] call A3UE_fnc_fpv_holdPattern] call _check;
_u setVariable ["A3UE_FPV_mode","TERMINAL_VECTOR"];
_u setVariable ["A3UE_FPV_targetNetId",netId _t];
_u setVariable ["A3UE_FPV_terminalVectorEnteredAt",time];
["local vector",[_u,_t,createHashMap,1,_identity] call A3UE_fnc_fpv_runTerminalVector] call _check;
_u setVariable ["A3UE_FPV_lastKnownTargetPosASL",getPosASL _t];
_u setVariable ["A3UE_FPV_lastKnownTargetTime",time];
_u setVariable ["A3UE_FPV_lostTargetExpireAt",time + 10];
[_u,createHashMap,false] call A3UE_fnc_fpv_runLostTarget;
["local lost guidance",(_u getVariable ["A3UE_FPV_lostTargetOriginASL",[]]) isNotEqualTo []] call _check;
{
    _x params ["_key","_bad","_good"];
    _u setVariable [_key,_bad];
    private _before = [_u] call A3UE_PB01_snapshot;
    private _controllerIdentity = _identity;
    private _results = [[_u,getPosASL _t] call A3UE_fnc_fpv_applyGuidance,
        [_u,_t] call A3UE_fnc_fpv_runTerminal,[_u] call A3UE_fnc_fpv_holdPattern,
        [_u,_t,createHashMap,1,_identity] call A3UE_fnc_fpv_runTerminalVector,
        [_u,_t] call A3UE_fnc_fpv_detonateCompat];
    [_key,!([_u,_identity] call A3UE_fnc_fpv_canActuate) && {! (true in _results)}
        && {_before isEqualTo ([_u] call A3UE_PB01_snapshot)}] call _check;
    // Harmless reset remains available while direct control/retirement suspends actuation.
    ["clear during " + _key,[_u] call A3UE_fnc_fpv_clearTarget] call _check;
    _u setVariable [_key,_good];
} forEach [["A3UE_FPV_controllerGeneration",2,1],
    ["A3UE_FPV_controllerIdentity",[123456,clientOwner,2,1],_identity],
    ["A3UE_FPV_cleanupPending",true,false],["A3UE_FPV_managed",false,true],
    ["A3UE_FPV_siteEpoch","QA",""],["bis_fnc_moduleRemoteControl_owner",99,objNull]];
// Old controller identity must stay stale even after receiver has a valid replacement ticket.
isNil {
    private _controllerIdentity = [123456,clientOwner,0,0];
    private _before = [_u] call A3UE_PB01_snapshot;
    ["stale inherited controller",!([_u,getPosASL _t] call A3UE_fnc_fpv_applyGuidance)
        && {_before isEqualTo ([_u] call A3UE_PB01_snapshot)}] call _check;
};
private _marker = ["PB01_LOCAL",[50,50,0]] call A3UE_fnc_fpv_supportCreateMarker;
["local server marker",_marker != "" && {markerShape _marker != ""}] call _check;
deleteMarker _marker;
A3UE_FPV_supportTransientMarkers = A3UE_FPV_supportTransientMarkers - [_marker];
private _groups = (crew _u) apply {group _x};
{deleteVehicle _x;} forEach crew _u; deleteVehicle _u; deleteVehicle _t;
{deleteGroup _x;} forEach _groups;
diag_log ["PB01","LOCAL_END",_count,_fails,"STRUCTURAL_ONLY; MP/flight/support NOT RUN"];
_fails == 0
