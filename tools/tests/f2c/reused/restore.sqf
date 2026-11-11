// QA extraction: docs\experiments\crocus-at-policy-20261026\commands\09-restore-observer.sqf; scheduled local caller.

if (!isServer || {isRemoteExecuted} || {!canSuspend} || {!hasInterface}) exitWith {};
private _saved = missionNamespace getVariable ["A3UE_POLICY_savedObserver", []];
private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState", createHashMap];
if (count _saved != 7 || {(_saved # 0) != player} || {(_saved # 1) != netId player}
    || {!alive player} || {!local player} || {!isNull (objectParent player)}
    || {!isNull (missionNamespace getVariable ["A3UE_POLICY_target", objNull])}
    || {(missionNamespace getVariable ["A3UE_POLICY_crew", []]) findIf {!isNull _x} >= 0}
    || {(missionNamespace getVariable ["A3UE_POLICY_groups", []]) findIf {!isNull _x} >= 0}
    || {(count _cap > 0 && {!(_cap getOrDefault ["exported", false])})}
    || {((values (missionNamespace getVariable ["A3UE_FPV_QA_runs", createHashMap]))
        findIf {!(_x getOrDefault ["cleaned", false])}) >= 0}) exitWith {
    diag_log "Policy restoration BLOCKED: exact original observer and completed teardown/export required";
};
private _applied = false;
isNil {
    if (player != _saved # 0 || {netId player != _saved # 1} || {!alive player} || {!local player}
        || {!isNull (objectParent player)} || {player distance2D [4549,11526,0] > 3}
        || {isDamageAllowed player} || {!captive player}
        || {(missionNamespace getVariable ["A3UE_POLICY_savedObserver",[]]) isNotEqualTo _saved}
        || {player getVariable ["A3UE_F2RA_preparationTicket",""] != ((missionNamespace getVariable ["A3UE_F2RA",createHashMap]) getOrDefault ["ticket","-"])}) exitWith {};
player setPosATL (_saved # 2);
player setVectorDirAndUp [_saved # 3, _saved # 4];
player allowDamage (_saved # 5);
player setCaptive (_saved # 6);
    _applied = true;
};
if (!_applied) exitWith {diag_log ["F2R_PREP","RESTORE_MUTATION_FENCE"];};
private _rows = [["positionRestored", (getPosATL player) distance (_saved # 2) < 1],
    ["damageSettingRestored", isDamageAllowed player isEqualTo (_saved # 5)],
    ["captiveSettingRestored", captive player isEqualTo (_saved # 6)],
    ["position", getPosATL player], ["directionUp", [vectorDir player, vectorUp player]],
    ["captureActive", _cap getOrDefault ["active", false]],
    ["captureExported", _cap getOrDefault ["exported", true]],
    ["unretiredRuns", count ((values (missionNamespace getVariable ["A3UE_FPV_QA_runs", createHashMap]))
        select {!(_x getOrDefault ["cleaned", false])})]];
{diag_log ["CROCUS_CADENCE_RESTORE", _forEachIndex, _x];} forEach _rows;
if (((_rows # 0) # 1) && {((_rows # 1) # 1)} && {((_rows # 2) # 1)}) then {
    A3UE_POLICY_savedObserver = nil;
};
diag_log str _rows;
