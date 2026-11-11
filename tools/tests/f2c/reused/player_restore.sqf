// Exact dynamically recorded player identity; never pass a player to target cleanup.
params ["_s"];
private _saved = _s getOrDefault ["playerSaved",[]];
private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState",createHashMap];
if ([clientOwner,isServer,hasInterface,isRemoteExecuted,canSuspend] isNotEqualTo [2,true,true,false,true]
    || {!(_s getOrDefault ["ownedPlayer",false])} || {count _saved != 7}
    || {count _cap > 0 && {!(_cap getOrDefault ["exported",false])}}
    || {((values (missionNamespace getVariable ["A3UE_FPV_QA_runs",createHashMap])) findIf {!(_x getOrDefault ["cleaned",false])}) >= 0}) exitWith {false};
private _restored = false;
isNil {
    if (player != (_saved # 0) || {netId player != (_saved # 1)} || {!alive player} || {!local player}
        || {!isNull objectParent player} || {isDamageAllowed player} || {captive player}
        || {(_s getOrDefault ["playerSaved",[]]) isNotEqualTo _saved}
        || {player getVariable ["A3UE_F2RA_preparationTicket",""] != _s get "ticket"}) exitWith {};
    player setPosATL (_saved # 2); player setVectorDirAndUp [_saved # 3,_saved # 4];
    player allowDamage (_saved # 5); player setCaptive (_saved # 6);
    player setVariable ["A3UE_F2RA_preparationTicket",nil];
    _s set ["ownedPlayer",false]; _restored = true;
};
diag_log ["F2R_AUTO",1,_s get "ticket","PLAYER_RESTORED",diag_tickTime,[_restored,netId player,getPosATL player,isDamageAllowed player,captive player]];
_restored
