// One SCHEDULED writer; read-only EachFrame observation. No production frame driver.
params [["_options",createHashMap,[createHashMap]]];
private _speed = _options getOrDefault ["speed",28];
private _poseEvery = _options getOrDefault ["poseEveryFrames",4];
if (!(_speed isEqualType 0) || {!finite _speed} || {_speed < 5} || {_speed > 30}
    || {!(_poseEvery in [2,3,4,6,8])}) exitWith {
    diag_log ["A3UE_FPV_QA_MOTION_BLOCKED","ACTUATION","NOT RUN","speed 5..30; poseEveryFrames 2/3/4/6/8"];
    if (hasInterface) then {copyToClipboard str ["NOT RUN","INVALID_ACTUATION_OPTIONS"];};
};
A3UE_FPV_QA_motionAPI = compileScript ["scripts\ua_dive\motion_fixture.sqf"];
private _s = ["begin",["ACTUATION",_options,_thisScript]] call A3UE_FPV_QA_motionAPI;
if (count _s == 0) exitWith {};
private _record = {params ["_event","_data"]; ["record",[_event,_data]] call A3UE_FPV_QA_motionAPI;};
{
    private _turn = _x;
    {
        if (_s get "cancel") exitWith {};
        private _sequence = _x;
        private _spec = ["make"] call A3UE_FPV_QA_motionAPI;
        private _u = _spec get "u";
        if (!(_spec getOrDefault ["ready",false])) then {
            _s set ["notRun",1+(_s get "notRun")];
            ["CASE",[_sequence,_turn,"NOT RUN","READINESS_TIMEOUT_OR_ISOLATION"]] call _record;
        } else {
            // Suppress native path/FSM/target intent in every arm. MOVE and ANIM
            // stay enabled: disabling them can itself freeze vehicle movement.
            {private _unit = _x;
                {_unit disableAI _x;} forEach ["PATH","FSM","AUTOCOMBAT","TARGET","AUTOTARGET"];
                _unit enableAI "MOVE"; _unit enableAI "ANIM";
            } forEach crew _u;
            private _mask = ([_u]+crew _u) apply {["mask",[_x]] call A3UE_FPV_QA_motionAPI};
            private _disabled = crew _u findIf {!(_x checkAIFeature "MOVE") || {!(_x checkAIFeature "ANIM")}
                || {_x checkAIFeature "PATH"} || {_x checkAIFeature "FSM"} || {_x checkAIFeature "AUTOCOMBAT"}} < 0;
            if (!_disabled || {!( ["qualify",[_spec,"PHASE_BEFORE_WRITES"]] call A3UE_FPV_QA_motionAPI)}) then {
                _s set ["notRun",1+(_s get "notRun")];
                ["CASE",[_sequence,_turn,"NOT RUN",["AI_MOVEMENT_NOT_DISABLED","COMPATIBILITY_NOT_RUN"] select (_s get "cancel")]] call _record;
            } else {
                // Identical initial geometry; reset occurs before this phase only.
                _u setPosATL (_options get "originATL");
                _u setVectorDirAndUp [[0,1,0],[0,0,1]];
                _u setVelocity [0,0,0];
                _s set ["phase",[_sequence,_turn,netId _u]];
                _s set ["lastCommand",[]];
                _s set ["observations",0];
                _s set ["observationGapMax",0];
                _s set ["lastObservedAt",-1];
                _s set ["phaseDistance",0];
                _s set ["priorPosition",getPosASL _u];
                _s set ["phaseU",_u];
                _s set ["matchedMask",_mask];
                private _start = diag_tickTime;
                _s set ["phaseUntil",_start+3];
                ["PHASE_BEGIN",[_s get "phase",getPosASL _u,_speed,_poseEvery,_mask,
                    local _u,owner _u,simulationEnabled _u,isDamageAllowed _u,damage _u,
                    "velocity intent every >=20ms; turning 30 degrees/s in wall time; pose cadence in relative rendered frames"]] call _record;
                private _eh = addMissionEventHandler ["EachFrame", {
                    private _c = missionNamespace getVariable ["A3UE_FPV_QA_motionState",createHashMap];
                    if (!(_c getOrDefault ["active",false]) || {_c get "cancel"}) exitWith {};
                    private _u = _c get "phaseU";
                    if (diag_tickTime > (_c get "phaseUntil")) exitWith {};
                    private _cmd = _c get "lastCommand";
                    // Only an observation from a strictly LATER rendered frame is eligible.
                    if (count _cmd == 0 || {diag_frameNo <= (_cmd # 1)}) exitWith {};
                    private _pos = getPosASL _u;
                    private _vel = velocity _u;
                    private _at = diag_tickTime;
                    private _last = _c get "lastObservedAt";
                    if (_last >= 0) then {_c set ["observationGapMax",(_c get "observationGapMax") max (_at-_last)];};
                    _c set ["lastObservedAt",_at];
                    _c set ["phaseDistance",(_c get "phaseDistance")+(_pos vectorDistance (_c get "priorPosition"))];
                    _c set ["priorPosition",_pos];
                    _c set ["observations",1+(_c get "observations")];
                    ["record",["OBSERVE",[_c get "phase",_cmd # 2,_at-(_cmd # 0),diag_frameNo-(_cmd # 1),
                        _pos,_vel,diag_fps,diag_deltaTime,local _u,owner _u,simulationEnabled _u,
                        isDamageAllowed _u,damage _u]]] call A3UE_FPV_QA_motionAPI;
                }];
                _s set ["observer",_eh];
                private _lastPoseFrame = -100;
                private _issued = 0;
                private _ok = true;
                while {diag_tickTime < _start+3 && {!(_s get "cancel")}} do {
                    // Same masks/control/locality/simulation throughout; refuse any writer takeover.
                    private _currentMask = ([_u]+crew _u) apply {["mask",[_x]] call A3UE_FPV_QA_motionAPI};
                    if (!( ["safe",[_u]] call A3UE_FPV_QA_motionAPI)
                        || {_currentMask isNotEqualTo _mask} || {getPosATL _u # 2 < 20}
                        || {_u distance2D (_options get "originATL") > 150}) exitWith {_ok = false;};
                    private _heading = if (_turn) then {(diag_tickTime-_start)*30} else {0};
                    private _dir = [sin _heading,cos _heading,0];
                    private _velocity = _dir vectorMultiply _speed;
                    private _pose = _sequence == "POSE_VELOCITY" || {_sequence == "CADENCED_POSE" && {diag_frameNo-_lastPoseFrame >= _poseEvery}};
                    private _before = diag_tickTime;
                    isNil {
                        if (_pose) then {_u setVectorDirAndUp [_dir,[0,0,1]]; _lastPoseFrame = diag_frameNo;};
                        _u setVelocity _velocity;
                        _issued = _issued+1;
                        _s set ["lastCommand",[diag_tickTime,diag_frameNo,_issued]];
                        ["COMMAND",[_s get "phase",_issued,_before-(_s get "base"),_pose,_dir,_velocity,
                            velocity _u,"immediate readback, NOT movement evidence"]] call _record;
                    };
                    sleep .02;
                };
                removeMissionEventHandler ["EachFrame",_eh]; _s set ["observer",-1];
                ["qualify",[_spec,"PHASE_AFTER_WRITES"]] call A3UE_FPV_QA_motionAPI;
                private _n = _s get "observations";
                if (_n < 10 || {_issued < 10} || {_s get "observationGapMax" > .1}
                    || {_s get "cancel"}) then {_s set ["notRun",1+(_s get "notRun")];};
                private _restored = ["restore",_spec] call A3UE_FPV_QA_motionAPI;
                _ok = _ok && {_restored};
                _s set ["cases",1+(_s get "cases")];
                if (!_ok) then {_s set ["failures",1+(_s get "failures")];};
                ["PHASE_END",[_s get "phase",_issued,_n,_s get "phaseDistance",_s get "observationGapMax",_ok,
                    "coverage/safeguards only; physical motion comparison requires OBSERVE evidence"]] call _record;
            };
        };
        if (!( ["cleanup"] call A3UE_FPV_QA_motionAPI)) exitWith {_s set ["cancel",true]; _s set ["reason","CLEANUP_PENDING"];};
    } forEach ["VELOCITY_ONLY","POSE_VELOCITY","CADENCED_POSE"];
} forEach [false,true];
["finish"] call A3UE_FPV_QA_motionAPI;
