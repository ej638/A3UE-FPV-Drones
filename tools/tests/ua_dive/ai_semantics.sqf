// Disposable native/unmanaged control. PASS is fixture coverage, not an AI hypothesis.
params [["_options",createHashMap,[createHashMap]]];
A3UE_FPV_QA_motionAPI = compileScript ["scripts\ua_dive\motion_fixture.sqf"];
private _s = ["begin",["AI_SEMANTICS",_options,_thisScript]] call A3UE_FPV_QA_motionAPI;
if (count _s == 0) exitWith {};
private _record = {params ["_event","_data"]; ["record",[_event,_data]] call A3UE_FPV_QA_motionAPI;};
private _snapshot = {
    params ["_label","_u"];
    ["MASK",[_label,netId _u,typeOf _u,local _u,owner _u,simulationEnabled _u,isDamageAllowed _u,
        ([_u]+crew _u) apply {[netId _x,["mask",[_x]] call A3UE_FPV_QA_motionAPI]}]] call _record;
};
{
    if (_s get "cancel") exitWith {};
    private _case = _x;
    private _spec = ["make"] call A3UE_FPV_QA_motionAPI;
    private _u = _spec get "u";
    if (!(_spec getOrDefault ["ready",false])) then {
        _s set ["notRun",1+(_s get "notRun")];
        ["CASE",[_case,"NOT RUN","READINESS_TIMEOUT_OR_ISOLATION"]] call _record;
    } else {
        private _ops = switch (_case) do {
            case "CURRENT": {["DISABLE_CREW","ENABLE_VEHICLE_ALL"]};
            case "ENABLE_FIRST": {["ENABLE_VEHICLE_ALL","DISABLE_CREW"]};
            default {["ENABLE_CREW_FEATURES","DISABLE_CREW","ENABLE_CREW_FEATURES"]};
        };
        private _ok = true;
        {
            private _op = _x;
            if (_s get "cancel") exitWith {};
            if (!( ["qualify",[_spec,_case+"/"+_op+"/before"]] call A3UE_FPV_QA_motionAPI)) exitWith {};
            if (!( ["safe",[_u]] call A3UE_FPV_QA_motionAPI)) exitWith {_ok = false;};
            [_case+"/"+_op+"/before",_u] call _snapshot;
            isNil {
                if (_op == "ENABLE_VEHICLE_ALL") then {_u enableAI "ALL";} else {
                    {private _unit = _x; {
                        if (_op == "DISABLE_CREW") then {_unit disableAI _x;} else {_unit enableAI _x;};
                    } forEach ["PATH","FSM","AUTOCOMBAT"];} forEach crew _u;
                };
                [_case+"/"+_op+"/immediate",_u] call _snapshot;
            };
            if (_op != "ENABLE_VEHICLE_ALL") then {
                private _expected = _op != "DISABLE_CREW";
                private _matched = crew _u findIf {
                    (_x checkAIFeature "PATH") != _expected || {(_x checkAIFeature "FSM") != _expected}
                        || {(_x checkAIFeature "AUTOCOMBAT") != _expected}
                } < 0;
                _ok = _ok && {_matched};
                ["API_CHECK",[_case,_op,_matched]] call _record;
            };
            // Later observation detects initialization/intervening changes; finite 0.2s.
            sleep .2;
            if (!( ["qualify",[_spec,_case+"/"+_op+"/delayed"]] call A3UE_FPV_QA_motionAPI)) exitWith {};
            [_case+"/"+_op+"/delayed",_u] call _snapshot;
        } forEach _ops;
        private _restored = ["restore",_spec] call A3UE_FPV_QA_motionAPI;
        _ok = _ok && {_restored};
        if (_s get "cancel") then {_s set ["notRun",1+(_s get "notRun")];} else {_s set ["cases",1+(_s get "cases")];};
        if (!_ok) then {_s set ["failures",1+(_s get "failures")];};
        private _status = if (_ok && {_s get "cancel"}) then {"NOT RUN"} else {["FAIL","PASS"] select _ok};
        ["CASE",[_case,_status,"vehicle ALL propagation is observed, never assumed"]] call _record;
    };
    if (!( ["cleanup"] call A3UE_FPV_QA_motionAPI)) exitWith {_s set ["cancel",true]; _s set ["reason","CLEANUP_PENDING"];};
} forEach ["CURRENT","ENABLE_FIRST","CREW_ONLY"];
["finish"] call A3UE_FPV_QA_motionAPI;
