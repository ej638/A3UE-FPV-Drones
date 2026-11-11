// UAV-free engine interface checks; separate from cold/warm timing qualification.
params [["_class","B_UAV_01_F"]];
if (isRemoteExecuted || {!isServer} || {!canSuspend}) exitWith {
    if (hasInterface) then {copyToClipboard str ["NOT RUN","PREPARATION_CHECK_CONTEXT"];};
};
private _prior = missionNamespace getVariable ["A3UE_FPV_QA_motionMaterial",createHashMap];
private _serial = missionNamespace getVariable ["A3UE_FPV_QA_motionSerial",0];
private _worker = ["start",_class] execVM "scripts\ua_dive\motion_prepare.sqf";
private _until = diag_tickTime+2;
private _state = createHashMap;
waitUntil {
    sleep .001;
    _state = missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap];
    _state getOrDefault ["active",false] || {scriptDone _worker} || {diag_tickTime >= _until}
};
if (!(_state getOrDefault ["active",false]) || {(_state getOrDefault ["worker",scriptNull]) isNotEqualTo _worker}) exitWith {
    private _result = ["NOT RUN","PREPARATION_CHECK_NOT_RESERVED: preserve refusal/status; no cancellation sent"];
    diag_log ["A3UE_FPV_QA_MOTION_PREP_INTERFACE",_result];
    if (hasInterface) then {copyToClipboard str _result;};
};
private _ack = ["phase",_state get "phase","progress",_state get "progress","ready",_state get "ready"];
// A second preparation is deterministically attempted against the active lock.
private _second = ["start",_class] call compileScript ["scripts\ua_dive\motion_prepare.sqf"];
private _refused = count _second == 0 && {
    ((missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap]) get "worker") isEqualTo _worker
};
["cancel"] call compileScript ["scripts\ua_dive\motion_prepare.sqf"];
_until = diag_tickTime+32;
waitUntil {sleep .1; !(_state get "active") || {diag_tickTime >= _until}};
private _cancelled = !(_state get "active") && {!(_state get "ready")} && {_state get "exported"}
    && {(_state get "reason") # 0 in ["PREPARATION_CANCELLED","PREPARATION_CANCELLED_OR_DEADLINE_DURING_EXPORT"]};
private _unchanged = _prior isEqualTo (missionNamespace getVariable ["A3UE_FPV_QA_motionMaterial",createHashMap]);
private _noFixture = _serial == (missionNamespace getVariable ["A3UE_FPV_QA_motionSerial",0]);
private _result = ["PREPARATION_INTERFACE_ONLY",_refused && {_cancelled} && {_unchanged} && {_noFixture},
    _ack,["busyRefused",_refused],["cancelledUnlocked",_cancelled],["successfulMaterialUnchanged",_unchanged],
    ["fixtureSerialUnchanged",_noFixture],_state get "reason","no AI/motion/cleanup/performance PASS"];
diag_log ["A3UE_FPV_QA_MOTION_PREP_INTERFACE",_result];
if (hasInterface) then {copyToClipboard str _result;};
