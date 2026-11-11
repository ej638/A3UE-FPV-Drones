private _s = missionNamespace getVariable ["A3UE_F2RA",createHashMap];
if (_s getOrDefault ["state",""] != "PREPARING" || {_s getOrDefault ["cancel",false]}) exitWith {diag_log ["F2R_PREP","WRAPPER_IDENTITY_OR_PHASE"]; false};
// QA extraction: docs\experiments\crocus-at-policy-20261026\commands\03-observer-range.sqf; scheduled local caller.

if (!isServer || {isRemoteExecuted} || {!canSuspend} || {!hasInterface}
    || {worldName != "vt7"} || {profileName != "EJ_FPV_QA"}
    || {isNull player} || {!alive player} || {!local player}
    || {!isNull (objectParent player)}
    || {(missionNamespace getVariable ["A3UE_POLICY_context", []]) isNotEqualTo [2,true,true,false,true]}
    || {missionNamespace getVariable ["A3UE_FPV_debug", false]}) exitWith {
    diag_log "Policy range BLOCKED: require qualified hosted QA context, on-foot observer, debug false";
};
private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState", createHashMap];
if ((count _cap > 0 && {!(_cap getOrDefault ["exported", false])})
    || {((values (missionNamespace getVariable ["A3UE_FPV_QA_runs", createHashMap]))
        findIf {!(_x getOrDefault ["cleaned", false])}) >= 0}
    || {!isNil "A3UE_POLICY_savedObserver"}) exitWith {
    diag_log "Policy range BLOCKED: existing QA state or saved observer; preserve and resolve it";
};
isNil {
A3UE_POLICY_savedObserver = [player, netId player, getPosATL player,
    vectorDir player, vectorUp player, isDamageAllowed player, captive player];
A3UE_POLICY_condition = missionNamespace getVariable ["A3UE_POLICY_condition", "production-policy-candidate"];
A3UE_FPV_QA_targetPos = if (_s get "activity" == "CONTROL") then {[4165.9,11428.3,0]} else {+((_s get "recipe") # 4)};
_s set ["observer",+A3UE_POLICY_savedObserver]; _s set ["ownedObserver",true];
player setVariable ["A3UE_F2RA_preparationTicket",_s get "ticket"];
player allowDamage false;
player setCaptive true;
player setPosATL [4549,11526,0];
};
private _rows = [["conditionLabelOnly", A3UE_POLICY_condition],
    ["observerSaved", [A3UE_POLICY_savedObserver # 1, A3UE_POLICY_savedObserver # 2,
        A3UE_POLICY_savedObserver # 5, A3UE_POLICY_savedObserver # 6]],
    ["observerNow", [getPosATL player, isDamageAllowed player, captive player]],
    ["targetPosition", A3UE_FPV_QA_targetPos],
    ["conditions", [+date, overcast, rain, fog, +wind, timeMultiplier, diag_fps]]];
{diag_log ["CROCUS_CADENCE_RANGE", _forEachIndex, _x];} forEach _rows;
diag_log str _rows;
