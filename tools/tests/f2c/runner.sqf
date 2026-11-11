params ["_activity","_ticket",["_argument",0]];
private _fieldActivity = _activity in ["CLEAR","DISMOUNT_TRACKING","DISMOUNT_MANAGED","PARTIAL","CONTROL"];
private _s = missionNamespace getVariable ["A3UE_F2RA",createHashMap];
private _log = {params ["_event",["_data",[]]]; diag_log ["F2R_AUTO",1,_ticket,_event,diag_tickTime,_data];};
if (count _s == 0 || {_s get "ticket" != _ticket} || {_s getOrDefault ["finished",false]}) exitWith {};
private _context = [clientOwner,isServer,hasInterface,isRemoteExecuted,canSuspend];
if (_context isNotEqualTo [2,true,true,false,true]) exitWith {
    ["CONTEXT",_context] call _log;
    _s set ["state","REFUSED"]; _s set ["finished",true];
    ["FINISH",["REFUSED","ACTUAL_EXECUTION_CONTEXT"]] call _log;
};
if (_activity == "recover") exitWith {
    if (_s get "state" == "NEEDS_RECOVERY" && {scriptDone (_s getOrDefault ["handle",scriptNull])}) then {[_s,_s getOrDefault ["result","INTERRUPTED"]] call compileScript ["scripts\f2r\finish.sqf"];};
};
if (_activity == "cancel") exitWith {_s set ["cancel",true]; ["CANCEL_REQUEST",[]] call _log;};
if (_s get "state" != "QUEUED") exitWith {["DUPLICATE_OR_BUSY",[_activity]] call _log;};
[_s,"PREFLIGHT"] call compileScript ["scripts\f2r\state.sqf"];
["CONTEXT",_context] call _log;
["SESSION",[profileName,worldName,getMissionPath "",missionName,diag_fps]] call _log;
// Watch interruption separately. Never claim completion or delete under uncertain ownership.
[_s] spawn {
    params ["_s"];
    private _deadline = diag_tickTime + 300;
    waitUntil {sleep 1; _s getOrDefault ["finished",false] || {scriptDone (_s get "handle")} || {diag_tickTime >= _deadline}};
    if !(_s getOrDefault ["finished",false]) then {
        _s set ["cancel",true];
        private _ticket = _s get "ticket";
        diag_log ["F2R_AUTO",1,_ticket,"INTERRUPTED",diag_tickTime,["NO_SUCCESS"]];
        private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState",createHashMap];
        if (_cap getOrDefault ["id",""] == _s getOrDefault ["runId","-"] && {_cap getOrDefault ["active",false]}) then {
            ["stop","",[],60,"manual"] call compileScript ["scripts\ua_dive\capture.sqf"];
        };
        if (scriptDone (_s get "handle")) then {
            [_s,"INTERRUPTED"] call compileScript ["scripts\f2r\finish.sqf"];
        } else {
            _s set ["state","NEEDS_RECOVERY"];
            diag_log ["F2R_AUTO",1,_ticket,"FINISH",diag_tickTime,["NEEDS_RECOVERY","WORKER_STILL_RUNNING"]];
        };
    };
};
private _state = {params ["_name"]; [_s,_name] call compileScript ["scripts\f2r\state.sqf"];};
private _wait = {
    params ["_predicate","_seconds"];
    private _until = diag_tickTime + _seconds;
    waitUntil {sleep 0.25; call _predicate || {_s get "cancel"} || {diag_tickTime >= _until}};
    !( _s get "cancel") && {call _predicate}
};
private _mark = {params ["_event",["_data",[]]];
    if (!isNil "A3UE_FPV_QA_sink") then {[objNull,"MARK",["F2R_AUTO",_ticket,_event,_data]] call A3UE_FPV_QA_sink;};
};
private _result = call {
    if (_s get "cancel") exitWith {"CANCELLED"};
    if (profileName != "EJ_FPV_QA" || {worldName != "vt7"} || {isNull player} || {!alive player}
        || {!local player} || {!isNull (objectParent player)} || {missionNamespace getVariable ["A3UE_FPV_debug",false]}
        || {!(missionNamespace getVariable ["serverInitDone",false])} || {!(missionNamespace getVariable ["A3UE_FPV_registrationComplete",false])}
        || {count (missionNamespace getVariable ["A3UE_FPV_catalog",createHashMap]) != 3}
        || {count (missionNamespace getVariable ["A3UE_FPV_doctrine",createHashMap]) != 12}
        || {diag_fps < 40} || {diag_fps > 50}) exitWith {"REFUSED_READINESS_PROFILE_WORLD_FPS"};
    if (!isNil "A3UE_POLICY_savedObserver" || {!isNull (missionNamespace getVariable ["A3UE_POLICY_target",objNull])}
        || {!isNull (missionNamespace getVariable ["A3UE_F2R_B_target",objNull])}
        || {!isNull (missionNamespace getVariable ["A3UE_FPV_QA_target",objNull])}
        || {missionNamespace getVariable ["A3UE_POLICY_zeusLaunchQueued",false]}) exitWith {"REFUSED_OLD_PREPARATION"};
    private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState",createHashMap];
    if ((count _cap > 0 && {!(_cap getOrDefault ["exported",false])})
        || {((values (missionNamespace getVariable ["A3UE_FPV_QA_runs",createHashMap])) findIf {!(_x getOrDefault ["cleaned",false])}) >= 0}
        || {(missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap]) getOrDefault ["active",false]}
        || {!((missionNamespace getVariable ["A3UE_FPV_QA_motionState",createHashMap]) getOrDefault ["finished",true])}) exitWith {"REFUSED_BUSY_OR_EXPORT"};
    private _curator = getAssignedCuratorLogic player;
    if (isNull _curator || {isNil "BIS_fnc_moduleRemoteControl"} || {(actionKeys "curatorInterface") isEqualTo []}) exitWith {"REFUSED_CURATOR_ROUTE"};
    if ((["targetNavigation","trajectorySteering","prepareTrajectory","runTerminalVector","terminalSteeringStatus"] findIf {isNil ("A3UE_fnc_fpv_" + _x)}) >= 0) exitWith {"REFUSED_FUNCTIONS"};
    private _recipe = missionNamespace getVariable ["A3UE_F2RA_recipe",call compileScript ["scripts\f2r\recipe.sqf"]];
    if (!_fieldActivity) then {
        private _check = [_recipe,true] call compileScript ["scripts\f2r\layout.sqf"];
        if !(_check # 0) then {_recipe = []; ["REFUSED",_check] call _log;};
    };
    if (_recipe isEqualTo []) exitWith {"REFUSED_RECIPE"};
    _s set ["recipe",_recipe];
    A3UE_POLICY_context = _context;
    A3UE_FPV_QA_dispatch = {
        params ["_arguments","_script"];
        addMissionEventHandler ["EachFrame",{removeMissionEventHandler ["EachFrame",_thisEventHandler]; _thisArgs params ["_arguments","_script"]; if (!isRemoteExecuted) then {_arguments execVM _script;};},[_arguments,_script]];
    };
    if (_activity in ["FOLIAGE","BUILDING"]) exitWith {[_s,_recipe] call compileScript ["scripts\f2c\player.sqf"];};
    ["PREPARING"] call _state;
    call compileScript ["scripts\f2r\observer.sqf"];
    if (isNil "A3UE_POLICY_savedObserver") exitWith {"REFUSED_OBSERVER"};
    player setVariable ["A3UE_F2RA_preparationTicket",_ticket];
    _s set ["ownedObserver",true]; _s set ["observer",+A3UE_POLICY_savedObserver];
    if (_s get "cancel") exitWith {"CANCELLED"};
    A3UE_FPV_QA_targetPos = if (_fieldActivity) then {if (_activity == "CONTROL") then {[4165.9,11428.3,0]} else {[4165.9,11478.3,0]}} else {+(_recipe # 4)};
    A3UE_F2RA_bPosition = +(_recipe # 10);
    call compileScript ["scripts\f2r\target_a.sqf"];
    private _a = missionNamespace getVariable ["A3UE_POLICY_target",objNull];
    if (isNull _a) exitWith {"REFUSED_TARGET_A"};
    _s set ["aId",netId _a]; _s set ["aRoster",[_a,+A3UE_POLICY_crew,+A3UE_POLICY_crewIds,+A3UE_POLICY_groups]];
    if (_s get "cancel") exitWith {"CANCELLED"};
    _a setDir (if (_fieldActivity) then {0} else {_recipe # 5});
    private _b = objNull;
    _s set ["bId",""];
    _curator addCuratorEditableObjects [[_a],false];
    // Full original target/crew/observer guards, at the launch boundary for both targets.
    private _validTarget = {
        params ["_t","_id","_crew","_ids"];
        !isNull _t && {alive _t} && {local _t} && {typeOf _t == "I_MRAP_03_F"} && {netId _t == _id}
            && {isDamageAllowed _t} && {!captive _t} && {damage _t == 0} && {abs (getPosATL _t # 2) < 0.5}
            && {count _crew == 2} && {count _ids == 2} && {count crew _t == 2}
            && {(_crew findIf {isNull _x || {!alive _x} || {!local _x} || {isPlayer _x} || {!(netId _x in _ids)}
                || {objectParent _x != _t} || {side group _x != independent} || {!isDamageAllowed _x} || {captive _x} || {damage _x != 0}}) < 0}
    };
    if (_s get "cancel") exitWith {"CANCELLED"};
    if (!([_a,_s get "aId",A3UE_POLICY_crew,A3UE_POLICY_crewIds] call _validTarget)
        || {!isNull _b && {!([_b,_s get "bId",A3UE_F2R_B_crew,A3UE_F2R_B_crewIds] call _validTarget)}}
        || {player != (A3UE_POLICY_savedObserver # 0)} || {netId player != (A3UE_POLICY_savedObserver # 1)}
        || {isDamageAllowed player} || {!captive player} || {player distance2D [4549,11526,0] > 3}
        || {(getAssignedCuratorLogic player) != _curator}) exitWith {"REFUSED_LAUNCH_GUARDS"};
    private _roster = [_a,_b] + A3UE_POLICY_crew + (missionNamespace getVariable ["A3UE_F2R_B_crew",[]]);
    private _points = if (_fieldActivity) then {[getPosATL _a,(getPosATL _a) getPos [250,90]]} else {[_recipe # 4,_recipe # 6,_recipe # 8,_recipe # 10]};
    if ((_points findIf {((_x nearEntities [["CAManBase","LandVehicle","Air","Ship"],150]) findIf {alive _x && {!(_x in _roster)}}) >= 0}) >= 0) exitWith {"REFUSED_RANGE_ISOLATION"};
    // QA geometry only: the measured 45m north approach hides A behind an intervening tree.
    // 75m had a clear initial VIEW/terrain probe. Recheck actual original A before any drone exists.
    private _launchAltitude = if (_fieldActivity) then {45} else {75};
    private _initialView = true;
    if (!_fieldActivity) then {
        A3UE_FPV_QA_origin set [2,_launchAltitude];
        private _from = ATLToASL A3UE_FPV_QA_origin;
        private _to = aimPos _a;
        private _hits = lineIntersectsSurfaces [_from,_to,objNull,_a,true,1,"VIEW","NONE"];
        _hits = _hits select {(_x # 2) != _a && {objectParent (_x # 2) != _a}};
        private _terrain = terrainIntersectASL [_from,_to];
        _initialView = !_terrain && {_hits isEqualTo []};
        ["INITIAL_A_VIEW",[_launchAltitude,_from,_to,_initialView,_terrain,
            _hits apply {[str (_x # 2),_x # 0]}]] call _log;
    };
    if (!_initialView) exitWith {"REFUSED_INITIAL_A_VIEW"};
    A3UE_FPV_QA_phaseCue = true; A3UE_FPV_QA_observedTargets = [_a,_b] select {!isNull _x};
    A3UE_POLICY_role = "AP"; A3UE_POLICY_site = "Outpost"; A3UE_POLICY_class = "O_Crocus_AP";
    ["LAUNCHING"] call _state;
    private _run = [createHashMapFromArray [["class","O_Crocus_AP"],["role","AP"],["count",1],["siteType","Outpost"],
        ["target",_a],["originATL",A3UE_FPV_QA_origin],["altitude",_launchAltitude],["bearing",0],["range",600],
        ["spacing",15],["duration",90],["seed",true],["instrument",true]]] call compileScript ["scripts\f2r\fixture.sqf"];
    if (isNil "_run" || {!(_run isEqualType createHashMap)} || {count _run == 0}) exitWith {"REFUSED_FACTORY"};
    A3UE_POLICY_run = _run get "id";
    _s set ["runId",_run get "id"]; _s set ["run",_run];
    _s set ["runRoster",[+(_run get "drones"),+(_run get "crew"),+(_run get "groups"),+(_run get "ids"),_run get "marker"]];
    private _u = (_run get "drones") param [0,objNull];
    _s set ["droneId",netId _u];
    _s set ["life",_u getVariable ["A3UE_FPV_lifecycleId",-1]];
    _s set ["crewIds",(_run get "crew") apply {netId _x}];
    if (isNull _u || {count (_run get "drones") != 1}) exitWith {"FAILED_PARTIAL_FACTORY"};
    private _ready = [{alive _u && {local _u} && {[_u] call A3UE_fnc_fpv_hasCurrentLifecycle}
        && {_u getVariable ["A3UE_FPV_controllerRunning",false]}
        && {(_u getVariable ["A3UE_FPV_startedGeneration",-1]) == (_u getVariable ["A3UE_FPV_controllerGeneration",-2])}
        && {!(scriptDone (_u getVariable ["A3UE_FPV_controllerHandle",scriptNull]))}},15] call _wait;
    _s set ["life",_u getVariable ["A3UE_FPV_lifecycleId",-1]];
    _s set ["crewIds",(_run get "crew") apply {netId _x}];
    _s set ["controllerHandles",["A3UE_FPV_controllerHandle","A3UE_FPV_fiberTrailHandle","A3UE_FPV_claimRetryHandle"] apply {_u getVariable [_x,scriptNull]}];
    private _c = missionNamespace getVariable ["A3UE_FPV_QA_captureState",createHashMap];
    ["ADMITTED",[_s get "runId",_c getOrDefault ["nonce",""],netId _u,_s get "life",_s get "aId",_s get "bId",_ready,_activity,getMissionPath "",_recipe]] call _log;
    ["ADMITTED",[_activity,netId _u,_s get "life",_s get "aId",_s get "bId"]] call _mark;
    if (!_ready) exitWith {"TIMED_OUT_CONTROLLER_READY"};
    _curator addCuratorEditableObjects [[_u] + (_run get "crew"),false];
    ["CAPTURING"] call _state;
    private _valid = {!isNull _u && {alive _u} && {local _u} && {netId _u == _s get "droneId"}
        && {_u getVariable ["A3UE_FPV_lifecycleId",-2] == _s get "life"}
        && {!(_u getVariable ["A3UE_FPV_detonationCommitted",false])} && {[_u] call A3UE_fnc_fpv_hasCurrentLifecycle}
        && {!([_u] call A3UE_fnc_fpv_isExternallyControlled)} && {!isNull _a} && {alive _a} && {local _a}
        && {netId _a == _s get "aId"} && {driver _a in A3UE_POLICY_crew}
        && {!(_s get "cancel")} && {_c getOrDefault ["active",false]}};
    if (_activity == "CONTROL") then {
        (driver _a) enableAI "PATH"; _a limitSpeed 15; _a doMove ((getPosATL _a) getPos [250,90]);
        ["MOVING_ORDER",[getPosATL _a,(getPosATL _a) getPos [250,90],15]] call _mark;
    };
    if (_activity in ["DISMOUNT_TRACKING","DISMOUNT_MANAGED","PARTIAL"]) then {
        private _wanted = if (_activity == "DISMOUNT_TRACKING") then {"TRACKING"} else {"TERMINAL_VECTOR"};
        private _admitted = [{!(call _valid) || {_u getVariable ["A3UE_FPV_mode",""] == _wanted
            && {_u getVariable ["A3UE_FPV_targetNetId",""] == netId _a}
            && {_wanted == "TRACKING" || {_u getVariable ["A3UE_FPV_terminalSteeringActive",false]}}
            && {_u distance _a > 150}}},50] call _wait;
        private _stimulated = false;
        isNil {
            if (_admitted && {call _valid} && {_u getVariable ["A3UE_FPV_mode",""] == _wanted}
                && {_u getVariable ["A3UE_FPV_targetNetId",""] == netId _a} && {_u distance _a > 150}
                && {count crew _a == 2} && {(A3UE_POLICY_crew findIf {isNull _x || {!alive _x} || {!local _x}
                    || {isPlayer _x} || {objectParent _x != _a} || {!(netId _x in A3UE_POLICY_crewIds)}}) < 0}) then {
                private _leaving = if (_activity == "PARTIAL") then {A3UE_POLICY_crew - [driver _a]} else {+A3UE_POLICY_crew};
                ["DISMOUNT_BEFORE",[_wanted,netId _a,(crew _a) apply {netId _x},_u distance _a,_u getVariable ["A3UE_FPV_targetRevision",0]]] call _mark;
                {unassignVehicle _x; moveOut _x;} forEach _leaving;
                ["DISMOUNT_ISSUED",[_activity,_leaving apply {netId _x}]] call _mark;
                _stimulated = true;
            };
        };
        if (!_stimulated) then {["DISMOUNT_NOT_OBSERVED",[_wanted]] call _mark;};
    };
    private _until = diag_tickTime + 100;
    private _nextSense = 0;
    while {_c getOrDefault ["active",false] && {!(_s get "cancel")} && {diag_tickTime < _until}} do {
        if (diag_tickTime >= _nextSense && {!isNull _u}) then {
            _nextSense = diag_tickTime + 0.5;
            ["TARGET_ELIGIBILITY",[netId _a,(crew _a) apply {[netId _x,alive _x]},
                A3UE_POLICY_crew apply {[netId _x,netId objectParent _x,alive _x,captive _x]},
                _u getVariable ["A3UE_FPV_targetNetId",""],netId ([_u] call A3UE_fnc_fpv_resolveTarget),
                _u getVariable ["A3UE_FPV_targetRevision",0],_u getVariable ["A3UE_FPV_mode",""],
                _u getVariable ["A3UE_FPV_navigationContinuation",false]]] call _mark;
        };
        sleep 0.25;
    };
    private _ended = !(_s get "cancel") && {!(_c getOrDefault ["active",false])};
    if (!_ended) exitWith {if (_s get "cancel") then {"CANCELLED"} else {"TIMED_OUT_CAPTURE"}};
    ["EXPORTING"] call _state;
    private _exported = [{_c getOrDefault ["exported",false]},45] call _wait;
    if (!_exported) exitWith {if (_s get "cancel") then {"CANCELLED"} else {"TIMED_OUT_EXPORT"}};
    private _rows = _c get "rows"; private _last = _rows # (count _rows - 1);
    if (_last # 5 == "END" && {_last # 12 # 5 == "duration"}) then {"FIXTURE_COMPLETE"} else {"INCOMPLETE_EARLY_END"}
};
[_s,_result] call compileScript ["scripts\f2r\finish.sqf"];
