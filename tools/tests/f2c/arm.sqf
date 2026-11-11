// F2 correction activities only. Reuses the established ticket/dispatcher/cancellation protocol.
params [["_activity",""],["_ticket",""],["_argument",0]];
private _validTicket = _ticket isEqualType "" && {count _ticket >= 8} && {count _ticket <= 64}
    && {((toArray _ticket) findIf {!(_x in ([45,95] + [48,49,50,51,52,53,54,55,56,57] + [65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90] + [97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122]))}) < 0};
if (!_validTicket || {!(_activity in ["CLEAR","FOLIAGE","BUILDING","DISMOUNT_TRACKING","DISMOUNT_MANAGED","PARTIAL","CONTROL","cancel","recover"])}) exitWith {
    diag_log ["F2R_AUTO",1,_ticket,"REFUSED",diag_tickTime,["ARGUMENTS"]];
};
private _claimed = false;
isNil {
    private _old = missionNamespace getVariable ["A3UE_F2RA",createHashMap];
    if (_activity in ["cancel","recover"]) then {
        _claimed = count _old > 0 && {_old get "ticket" == _ticket} && {!(_old getOrDefault ["finished",false])};
    } else {
        private _used = missionNamespace getVariable ["A3UE_F2RA_used",[]];
        if ((count _old == 0 || {_old getOrDefault ["finished",false]}) && {!(_ticket in _used)} && {count _used < 10}) then {
            _used pushBack _ticket; A3UE_F2RA_used = _used;
            A3UE_F2RA = createHashMapFromArray [["ticket",_ticket],["activity",_activity],["state","QUEUED"],
                ["finished",false],["cancel",false],["queued",diag_tickTime],["ownedObserver",false]];
            _claimed = true;
        };
    };
};
if (!_claimed) exitWith {diag_log ["F2R_AUTO",1,_ticket,"DUPLICATE_OR_BUSY",diag_tickTime,[_activity]];};
// Same established one-shot EachFrame -> scheduled LOCAL route. Qualify actual execution there.
private _eh = addMissionEventHandler ["EachFrame", {
    removeMissionEventHandler ["EachFrame",_thisEventHandler];
    _thisArgs params ["_activity","_ticket","_argument"];
    private _handle = [_activity,_ticket,_argument] execVM "scripts\f2c\runner.sqf";
    if (_activity in ["CLEAR","FOLIAGE","BUILDING","DISMOUNT_TRACKING","DISMOUNT_MANAGED","PARTIAL","CONTROL"]) then {A3UE_F2RA set ["handle",_handle];};
},[_activity,_ticket,_argument]];
// Only queue admission expires here; this remote-origin watchdog never prepares a fixture.
[_eh,_ticket] spawn {
    params ["_eh","_ticket"];
    private _until = diag_tickTime + 12;
    waitUntil {sleep 0.5; diag_tickTime >= _until || {A3UE_F2RA get "state" != "QUEUED"}};
    if (A3UE_F2RA get "ticket" == _ticket && {A3UE_F2RA get "state" == "QUEUED"}) then {
        removeMissionEventHandler ["EachFrame",_eh];
        A3UE_F2RA set ["finished",true]; A3UE_F2RA set ["state","REFUSED"];
        diag_log ["F2R_AUTO",1,_ticket,"FINISH",diag_tickTime,["REFUSED","FRAME_ROUTE_TIMEOUT"]];
    };
};
