// Two explicit foliage/building activities; shared runner preflight, capture, cancellation and finalizer.
// No automated visibility/control stimulus and no vehicle-driving extension.
params ["_s","_recipe"];
private _ticket = _s get "ticket";
private _activity = _s get "activity";
private _log = {params ["_event",["_data",[]]]; diag_log ["F2R_AUTO",1,_ticket,_event,diag_tickTime,_data];};
if ([clientOwner,isServer,hasInterface,isRemoteExecuted,canSuspend] isNotEqualTo [2,true,true,false,true]
    || {!(_activity in ["FOLIAGE","BUILDING"])} || {profileName != "EJ_FPV_QA"} || {worldName != "vt7"}
    || {!alive player} || {!local player} || {!isNull objectParent player}
    || {!isNil "A3UE_FPV_QA_playerCoverSaved"} || {!isNil "A3UE_FPV_QA_playerCoverRun"}
    || {(["targetNavigation","trajectorySteering","resolveTarget"] findIf {isNil ("A3UE_fnc_fpv_" + _x)}) >= 0}) exitWith {"REFUSED_PLAYER_CONTEXT"};
private _start = +(_recipe # 4);
private _sides = [east] call A3UE_fnc_fpv_getHostileSides;
// Existing repeat admission: don't delete/hide campaign alternatives to manufacture a test.
private _others = (_start nearEntities [["CAManBase","LandVehicle","Air","Ship"],800]) select {
    alive _x && {_x != player} && {!isNull ([_x,_sides] call A3UE_fnc_fpv_filterTarget)}
};
if (_others isNotEqualTo []) exitWith {
    ["REFUSED_ALTERNATIVES",[count _others,(_others select [0,32]) apply {[netId _x,typeOf _x,_x distance2D _start]}]] call _log;
    "REFUSED_RANGE_ALTERNATIVES"
};
[_s,"PREPARING"] call compileScript ["scripts\f2r\state.sqf"];
private _claimed = false;
isNil {
    if (!(_s get "cancel") && {!(_s getOrDefault ["ownedPlayer",false])}
        && {alive player} && {local player} && {isNull objectParent player}) then {
        _s set ["playerSaved",[player,netId player,getPosATL player,vectorDir player,vectorUp player,isDamageAllowed player,captive player]];
        _s set ["previousObservedTargets",+(missionNamespace getVariable ["A3UE_FPV_QA_observedTargets",[]])];
        _s set ["previousPhaseCue",missionNamespace getVariable ["A3UE_FPV_QA_phaseCue",false]];
        _s set ["ownedPlayer",true]; player setVariable ["A3UE_F2RA_preparationTicket",_ticket];
        player allowDamage false; player setCaptive false;
        player setPosATL _start; player setDir (_recipe # 5);
        A3UE_FPV_QA_observedTargets = [player]; A3UE_FPV_QA_phaseCue = true;
        _claimed = true;
    };
};
if (!_claimed) exitWith {"REFUSED_PLAYER_CLAIM"};
private _saved = _s get "playerSaved";
private _origin = _start vectorAdd [0,600,75]; _origin set [2,75];
// Same approved launch column; one prelaunch ray, no per-frame QA geometry probes.
private _from = ATLToASL _origin; private _to = aimPos player;
private _hits = lineIntersectsSurfaces [_from,_to,objNull,player,true,1,"VIEW","NONE"];
private _terrain = terrainIntersectASL [_from,_to];
if (_terrain || {_hits isNotEqualTo []}) exitWith {"REFUSED_INITIAL_PLAYER_VIEW"};
if (player != (_saved # 0) || {netId player != (_saved # 1)} || {!alive player}
    || {!local player} || {!isNull objectParent player} || {isDamageAllowed player} || {captive player}
    || {_s get "cancel"}) exitWith {"REFUSED_PLAYER_LAUNCH_IDENTITY"};
[_s,"LAUNCHING"] call compileScript ["scripts\f2r\state.sqf"];
private _run = [createHashMapFromArray [["class","O_Crocus_AP"],["role","AP"],["target",player],["count",1],
    ["originATL",_origin],["altitude",75],["duration",90],["seed",true],["instrument",true]]]
    call compileScript ["scripts\ua_dive\launch.sqf"];
if (isNil "_run" || {!(_run isEqualType createHashMap)} || {count _run == 0}) exitWith {"REFUSED_PLAYER_FACTORY"};
_s set ["runId",_run get "id"]; _s set ["run",_run];
_s set ["runRoster",[+(_run get "drones"),+(_run get "crew"),+(_run get "groups"),+(_run get "ids"),_run get "marker"]];
private _u = (_run get "drones") param [0,objNull];
_s set ["droneId",netId _u]; _s set ["life",_u getVariable ["A3UE_FPV_lifecycleId",-1]];
_s set ["crewIds",(_run get "crew") apply {netId _x}];
if (isNull _u || {count (_run get "drones") != 1}) exitWith {"FAILED_PARTIAL_PLAYER_FACTORY"};
private _until = diag_tickTime + 15;
waitUntil {sleep 0.1; _s get "cancel" || {diag_tickTime >= _until}
    || {[_u] call A3UE_fnc_fpv_hasCurrentLifecycle && {_u getVariable ["A3UE_FPV_controllerRunning",false]}}};
private _ready = alive _u && {local _u} && {[_u] call A3UE_fnc_fpv_hasCurrentLifecycle}
    && {_u getVariable ["A3UE_FPV_controllerRunning",false]}
    && {!(scriptDone (_u getVariable ["A3UE_FPV_controllerHandle",scriptNull]))};
_s set ["life",_u getVariable ["A3UE_FPV_lifecycleId",-1]];
_s set ["controllerHandles",[ _u getVariable ["A3UE_FPV_controllerHandle",scriptNull] ]];
private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState",createHashMap];
_s set ["captureNonce",_cap getOrDefault ["nonce",""]];
["ADMITTED",[_run get "id",_s get "captureNonce",netId _u,_s get "life",netId player,"",_ready,_activity,getMissionPath "",_recipe]] call _log;
if (!_ready) exitWith {"TIMED_OUT_PLAYER_CONTROLLER"};
(getAssignedCuratorLogic player) addCuratorEditableObjects [[_u] + (_run get "crew"),false];
[_s,"CAPTURING"] call compileScript ["scripts\f2r\state.sqf"];
["PLAYER_ACTIVITY",[_activity,"After PLAYER_SELECTED, move behind foliage or the approved barn for the selected activity. Remain hidden if unspent. No automatic next case.",_recipe # 6,_recipe # 8]] call _log;
private _mark = {params ["_event","_data"]; [objNull,"MARK",["F2R_AUTO",_ticket,_event,_data]] call A3UE_FPV_QA_sink;};
private _selected = false; private _nextSample = 0;
_until = diag_tickTime + 95;
while {_cap getOrDefault ["active",false] && {!(_s get "cancel")} && {diag_tickTime < _until}} do {
    if (player != (_saved # 0) || {netId player != (_saved # 1)} || {!local player} || {!alive player}
        || {!isNull objectParent player} || {player distance2D _start > 150}
        || {isDamageAllowed player} || {captive player}) exitWith {_s set ["cancel",true];};
    if (diag_tickTime >= _nextSample) then {
        _nextSample = diag_tickTime + 0.5;
        private _locked = !isNull _u && {_u getVariable ["A3UE_FPV_targetNetId",""] == netId player};
        private _legal = !isNull _u && {([_u] call A3UE_fnc_fpv_resolveTarget) isEqualTo player};
        if (!_selected && {_locked} && {_legal}) then {
            _selected = true; ["A_SELECTED",[netId _u,netId player]] call _mark;
            ["PLAYER_SELECTED",["Begin only the selected foliage/building activity now."]] call _log;
        };
        private _hits = if (!isNull _u) then {lineIntersectsSurfaces [getPosASL _u,aimPos player,_u,player,true,1,"VIEW","NONE"]} else {[]};
        ["COMMITMENT_PLAYER",[getPosASL player,_locked,_legal,_u getVariable ["A3UE_FPV_mode",""],
            _u getVariable ["A3UE_FPV_targetRevision",0],_u getVariable ["A3UE_FPV_navigationContinuation",false],
            _hits apply {[netId (_x # 2),typeOf (_x # 2),_x # 0,(getModelInfo (_x # 2)) param [1,""]]}]] call _mark;
    };
    sleep 0.25;
};
if (_s get "cancel") exitWith {"CANCELLED"};
if (_cap getOrDefault ["active",false]) exitWith {"TIMED_OUT_PLAYER_CAPTURE"};
[_s,"EXPORTING"] call compileScript ["scripts\f2r\state.sqf"];
_until = diag_tickTime + 45;
waitUntil {sleep 0.25; _cap getOrDefault ["exported",false] || {_s get "cancel"} || {diag_tickTime >= _until}};
if !(_cap getOrDefault ["exported",false]) exitWith {"INCOMPLETE_PLAYER_EXPORT"};
private _rows = _cap get "rows"; private _last = _rows # (count _rows - 1);
if (_last # 5 == "END" && {_last # 12 # 5 == "duration"}) then {"FIXTURE_COMPLETE"} else {"INCOMPLETE_EARLY_END"}
