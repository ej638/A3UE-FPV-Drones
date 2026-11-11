// Sole finalizer. All deletion is behind exact retained-roster/locality/control checks.
params ["_s","_result"];
private _ticket = _s get "ticket";
private _log = {params ["_event",["_data",[]]]; diag_log ["F2R_AUTO",1,_ticket,_event,diag_tickTime,_data];};
private _claimed = false;
isNil {if !(_s getOrDefault ["finalizing",false]) then {_s set ["finalizing",true]; _claimed = true;};};
if (!_claimed) exitWith {};
_s set ["result",_result]; [_s,"FINALIZING"] call compileScript ["scripts\f2r\state.sqf"];
private _status = call {
    if (!isServer || {isRemoteExecuted} || {!canSuspend}) exitWith {"CONTEXT"};
    private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState",createHashMap];
    private _id = _s getOrDefault ["runId",""];
    if (_id != "" && {_s getOrDefault ["captureNonce",""] != ""}
        && {_cap getOrDefault ["nonce",""] != _s get "captureNonce"}) exitWith {"CAPTURE_IDENTITY_CHANGED"};
    if (_id != "") then {
        if (_cap getOrDefault ["id",""] != _id) exitWith {};
        if (_cap getOrDefault ["active",false]) then {["stop","",[],60,"manual"] call compileScript ["scripts\ua_dive\capture.sqf"];};
        private _until = diag_tickTime + 45;
        waitUntil {sleep 0.5; _cap getOrDefault ["exported",false] || {diag_tickTime >= _until}};
    };
    if (_id != "" && {(_cap getOrDefault ["id",""] != _id) || {!(_cap getOrDefault ["exported",false])}}) exitWith {"EXPORT_UNRESOLVED"};
    private _run = _s getOrDefault ["run",createHashMap];
    if (count _run > 0) then {
        private _droneId = _s getOrDefault ["droneId",""];
        private _life = _s getOrDefault ["life",-1];
        private _record = (missionNamespace getVariable ["A3UE_FPV_lifecycles",createHashMap]) getOrDefault [str _life,createHashMap];
        private _recent = (missionNamespace getVariable ["A3UE_FPV_recentDetonations",[]]) select {
            _x getOrDefault ["uavNetId",""] == _droneId && {_x getOrDefault ["lifecycleId",-2] == _life}
        };
        ["OUTCOME",[_id,_droneId,_life,
            ["phase","outcome","closedAt","lateUntil"] apply {_record getOrDefault [_x,"ABSENT"]},
            _recent apply {private _r = _x; ["uavNetId","lifecycleId","ammoClass","payloadEventId","targetNetId","committedAt","detonationReason","fallbackReason","projectilePosASL"] apply {_r getOrDefault [_x,"ABSENT"]}}]] call _log;
        [_s,"OBSERVING_RETENTION"] call compileScript ["scripts\f2r\state.sqf"];
        // Reuse the retention observer's exact roster/closedAt evidence. No 610-second worker.
        // +10 is natural only before the explicit teardown marker below. Late absence is unknown.
        private _closed = _record getOrDefault ["closedAt",-1];
        if (_closed >= 0) then {
            private _until = diag_tickTime + 12;
            waitUntil {sleep 0.25; serverTime >= _closed + 10 || {diag_tickTime >= _until}};
        };
        private _retentionEvent = if (_s getOrDefault ["manualRetireAt",-1] < 0) then {"NATURAL_RETENTION"} else {"POST_TEARDOWN_RETENTION"};
        [_retentionEvent,[_id,_droneId,_life,serverTime,_closed,
            (_run get "drones") apply {isNull _x},(_run get "crew") apply {isNull _x},(_run get "groups") apply {isNull _x},
            (_s getOrDefault ["controllerHandles",[]]) apply {scriptDone _x},markerShape (_run get "marker")]] call _log;
    };
    {
        private _prefix = _x;
        private _target = missionNamespace getVariable [_prefix + "target",objNull];
        private _ids = missionNamespace getVariable [_prefix + "crewIds",[]];
        private _baseline = missionNamespace getVariable [_prefix + "baseline",[]];
        private _hits = getAllHitPointsDamage _target;
        ["EFFECTS",[missionNamespace getVariable [_prefix + "targetId",""],isNull _target,alive _target,damage _target,
            getPosASL _target,"HITPOINTS_SEPARATE",
            (missionNamespace getVariable [_prefix + "crew",[]]) apply {[_ids param [_forEachIndex,""],isNull _x,alive _x,damage _x]},
            [_baseline param [0,-1],_baseline param [2,[]]]]] call _log;
        private _oldHits = _baseline param [1,[]];
        {
            ["TARGET_HITPOINT",[missionNamespace getVariable [_prefix + "targetId",""],_forEachIndex,_x,
                (_oldHits param [2,[]]) param [_forEachIndex,-1],(_hits param [2,[]]) param [_forEachIndex,-1]]] call _log;
        } forEach ((_oldHits param [0,[]]) select [0,32]);
    } forEach ((if (_s getOrDefault ["aId",""] != "") then {["A3UE_POLICY_"]} else {[]})
        + (if (_s getOrDefault ["bId",""] != "") then {["A3UE_F2R_B_"]} else {[]}));
    [_s,"TEARDOWN"] call compileScript ["scripts\f2r\state.sqf"];
    if (count _run > 0 && {!(_run getOrDefault ["cleaned",false])}) then {
        private _crew = _run get "crew";
        private _crewIds = _s getOrDefault ["crewIds",[]];
        private _expectedIds = if (_s getOrDefault ["droneId",""] == "") then {[]} else {[_s get "droneId"]};
        private _safeRoster = {
            [+(_run get "drones"),+(_run get "crew"),+(_run get "groups"),+(_run get "ids"),_run get "marker"] isEqualTo (_s getOrDefault ["runRoster",[]])
            && {(_crew findIf {!isNull _x && {!local _x || {isPlayer _x} || {!(netId _x in _crewIds)}
                || {!isNull (objectParent _x) && {!(objectParent _x in (_run get "drones"))}}}}) < 0}
            && {((_run get "groups") findIf {!isNull _x && {!local _x || {(units _x findIf {!(_x in _crew)}) >= 0}}}) < 0}
        };
        private _safe = call _safeRoster && {(_run get "ids") isEqualTo _expectedIds}
            && {count _crew == count _crewIds}
            && {((_run get "drones") findIf {!isNull _x && {!local _x || {isPlayer _x}
                || {netId _x != _s get "droneId"} || {_x getVariable ["A3UE_FPV_lifecycleId",-2] != _s get "life"}
                || {[_x] call A3UE_fnc_fpv_isExternallyControlled}}}) < 0}
            && {(_crew findIf {!isNull _x && {!local _x || {isPlayer _x} || {!(netId _x in _crewIds)}}}) < 0}
            && {((_run get "groups") findIf {!isNull _x && {!local _x || {(units _x findIf {!(_x in _crew)}) >= 0}}}) < 0}
            && {((_run get "drones") findIf {!isNull _x && {(crew _x findIf {!(_x in _crew)}) >= 0}}) < 0};
        if (_safe) then {
            _s set ["manualRetireAt",serverTime];
            ["EXPLICIT_TEARDOWN",[_s get "runId",serverTime]] call _log;
            // Existing production retirement, preserving a real control change at owner deletion.
            // Do not use legacy control.sqf's default false preserveControl argument here.
            isNil {
                if !(call _safeRoster) exitWith {};
                {
                    if (!isNull _x && {local _x} && {netId _x == _s get "droneId"}
                        && {_x getVariable ["A3UE_FPV_lifecycleId",-2] == _s get "life"}
                        && {!([_x] call A3UE_fnc_fpv_isExternallyControlled)}) then {[_x,true] call A3UE_fnc_fpv_cleanupDrone;};
                } forEach (_run get "drones");
            };
            private _until = diag_tickTime + 20;
            waitUntil {sleep 0.25; ((_run get "drones") findIf {!isNull _x}) < 0 || {diag_tickTime >= _until}};
            isNil {
                if (((_run get "drones") findIf {!isNull _x}) >= 0 || {!(call _safeRoster)}) exitWith {};
                {if (!isNull _x) then {deleteVehicle _x;};} forEach _crew;
                {if (!isNull _x && {local _x} && {units _x isEqualTo []}) then {deleteGroup _x;};} forEach (_run get "groups");
                if ((_crew findIf {!isNull _x}) < 0 && {((_run get "groups") findIf {!isNull _x}) < 0}) then {
                    deleteMarkerLocal (_run get "marker"); _run set ["cleaned",true];
                };
            };
        };
    };
    if (count _run > 0 && {!(_run getOrDefault ["cleaned",false])}) exitWith {"EXACT_RUN_OWNERSHIP_OR_CONTROL"};
    // The original target cleanup helpers independently recheck exact IDs, occupants and groups.
    if (_s getOrDefault ["aId",""] != "") then {
        if ((missionNamespace getVariable ["A3UE_POLICY_targetId",""]) == _s get "aId"
            && {[missionNamespace getVariable ["A3UE_POLICY_target",objNull],missionNamespace getVariable ["A3UE_POLICY_crew",[]],missionNamespace getVariable ["A3UE_POLICY_crewIds",[]],missionNamespace getVariable ["A3UE_POLICY_groups",[]]] isEqualTo (_s get "aRoster")}) then {
            call compileScript ["scripts\f2r\target_cleanup_a.sqf"];
        };
    };
    if (_s getOrDefault ["bId",""] != "") then {
        if ((missionNamespace getVariable ["A3UE_F2R_B_targetId",""]) == _s get "bId"
            && {[missionNamespace getVariable ["A3UE_F2R_B_target",objNull],missionNamespace getVariable ["A3UE_F2R_B_crew",[]],missionNamespace getVariable ["A3UE_F2R_B_crewIds",[]],missionNamespace getVariable ["A3UE_F2R_B_groups",[]]] isEqualTo (_s get "bRoster")}) then {
            call compileScript ["scripts\f2r\target_cleanup_b.sqf"];
        };
    };
    private _left = ["A3UE_POLICY_","A3UE_F2R_B_"] findIf {
        !isNull (missionNamespace getVariable [_x + "target",objNull])
            || {((missionNamespace getVariable [_x + "crew",[]]) findIf {!isNull _x}) >= 0}
            || {((missionNamespace getVariable [_x + "groups",[]]) findIf {!isNull _x}) >= 0}
    };
    if (_left >= 0) exitWith {"EXACT_TARGET_OWNERSHIP"};
    if (_s getOrDefault ["ownedPlayer",false]) then {
        [_s] call compileScript ["scripts\f2r\player_restore.sqf"];
    };
    if (_s getOrDefault ["ownedPlayer",false]) exitWith {"PLAYER_IDENTITY_OR_PREPARATION_CHANGED"};
    if (_s getOrDefault ["ownedObserver",false]) then {
        private _saved = _s get "observer";
        if ((missionNamespace getVariable ["A3UE_POLICY_savedObserver",[]]) isEqualTo _saved
            && {player == _saved # 0} && {netId player == _saved # 1} && {alive player} && {local player}
            && {isNull (objectParent player)} && {player distance2D [4549,11526,0] <= 3}
            && {!isDamageAllowed player} && {captive player}
            && {player getVariable ["A3UE_F2RA_preparationTicket",""] == _ticket}) then {
            call compileScript ["scripts\f2r\restore.sqf"];
            if (isNil "A3UE_POLICY_savedObserver") then {
                player setVariable ["A3UE_F2RA_preparationTicket",nil]; _s set ["ownedObserver",false];
            };
        };
    };
    if (_s getOrDefault ["ownedObserver",false]) exitWith {"OBSERVER_IDENTITY_OR_PREPARATION_CHANGED"};
    A3UE_FPV_QA_phaseCue = _s getOrDefault ["previousPhaseCue",false];
    A3UE_FPV_QA_observedTargets = +(_s getOrDefault ["previousObservedTargets",[]]);
    "RESTORED"
};
_s set ["finalizing",false];
[_s,if (_status == "RESTORED") then {"STOPPED"} else {"NEEDS_RECOVERY"}] call compileScript ["scripts\f2r\state.sqf"];
_s set ["finished",_status == "RESTORED"];
["FINISH",[_result,_status,_s get "state"]] call _log;
