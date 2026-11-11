// Shared bounded QA infrastructure. No production function replacement.
params ["_action", ["_arg", []]];
private _s = missionNamespace getVariable ["A3UE_FPV_QA_motionState", createHashMap];
if (_action != "status" && {isRemoteExecuted || {!isServer}}) exitWith {false};
if (_action == "record") exitWith {
    _arg params ["_event","_data"];
    private _rows = _s get "rows";
    if (count _rows >= 12000 && {_event != "END"}) exitWith {_s set ["cancel",true]; _s set ["reason","BUFFER_LIMIT"];};
    _rows pushBack [count _rows+1,_event,diag_tickTime-(_s get "base"),diag_frameNo-(_s get "frameBase"),_data];
};
private _features = ["TARGET","AUTOTARGET","MOVE","ANIM","FSM","AIMINGERROR","SUPPRESSION",
    "CHECKVISIBLE","COVER","AUTOCOMBAT","PATH","MINEDETECTION","LIGHTS","NVG","RADIOPROTOCOL",
    "WEAPONAIM","FIREWEAPON","TEAMSWITCH","HEARING"];
private _mask = {params ["_unit"]; _features apply {_unit checkAIFeature _x}};
private _record = {
    params ["_event", "_data"];
    private _rows = _s get "rows";
    if (count _rows >= 12000 && {_event != "END"}) exitWith {_s set ["cancel", true]; _s set ["reason", "BUFFER_LIMIT"];};
    _rows pushBack [count _rows + 1, _event, diag_tickTime - (_s get "base"),
        diag_frameNo - (_s get "frameBase"), _data];
};
private _compatibilityFailure = {
    params ["_u","_issue","_point"];
    private _specs = (_s get "specimens") select {(_x get "u") == _u};
    if (_specs isNotEqualTo []) then {
        private _unsafe = (_issue # 0) in ["FUNCTION_CHANGED","REGISTRY_CHANGED","OBJECT_CALLBACKS_CHANGED","UNQUALIFIED_CREATED_CLASS"]
            || {_issue # 0 == "CARGO_CONFIG_UNQUALIFIED"}
            || {_issue # 0 == "COMPATIBILITY_CONDITION" && {(_issue # 3) in ["UNARMED_CREW","CONSCIOUS_CREW","NO_CAPTIVE_STATE","CBA_EFFECTS_UNDEFINED","ACE_EFFECTS_UNDEFINED","RADIO_OFF","LASER_OFF","LST_OFF","NO_FRIES","ACE_CARGO_EMPTY"]}};
        if (_unsafe) then {(_specs # 0) set ["foreignUnsafe",true];};
    };
    if (!(_s get "cancel")) then {
        ["ADMISSION_REFUSED",[_point,typeOf _u,netId _u,_issue,"NOT RUN"]] call _record;
        _s set ["reason",format ["COMPATIBILITY_NOT_RUN: %1",_issue]];
    };
    _s set ["cancel",true];
    false
};
private _safe = {
    params ["_u"];
    !isNull _u && {alive _u} && {local _u} && {owner _u == clientOwner}
        && {simulationEnabled _u} && {isEngineOn _u} && {isDamageAllowed _u} && {damage _u == 0}
        && {!(_u getVariable ["A3UE_FPV_managed", false])}
        && {!(_u getVariable ["A3UE_FPV_controllerRunning", false])}
        && {scriptDone (_u getVariable ["A3UE_FPV_controllerHandle", scriptNull])}
        && {scriptDone (_u getVariable ["A3UE_FPV_claimRetryHandle", scriptNull])}
        && {(_u getVariable ["A3UE_FPV_controllerGeneration",-1]) < 0}
        && {!([_u] call A3UE_fnc_fpv_isExternallyControlled)}
        && {allPlayers findIf {getConnectedUAV _x == _u} < 0}
        && {crew _u isNotEqualTo []}
        && {crew _u findIf {!local _x || {!local group _x} || {owner _x != clientOwner} || {!alive _x} || {isPlayer _x}} < 0}
        && {private _specs = (_s get "specimens") select {(_x get "u") == _u};
            _specs isNotEqualTo [] && {
                private _spec = _specs # 0;
                crew _u isEqualTo (_spec get "crew")
                    && {crew _u findIf {!(group _x in (_spec get "groups"))} < 0}
                    && {(_spec get "groups") findIf {units _x findIf {!(_x in (_spec get "crew"))} >= 0} < 0}
            }}
        && {private _spec = ((_s get "specimens") select {(_x get "u") == _u}) # 0;
            private _issue = ["conditions",[_s get "policy",_u,_spec getOrDefault ["cargoMass",-1]]] call A3UE_FPV_QA_motionPolicy;
            if (_issue isEqualTo []) then {true} else {[_u,_issue,"BOUNDED_STATE_GUARD"] call _compatibilityFailure}}
};
switch (_action) do {
    case "begin": {
        _arg params ["_kind", "_options", "_worker"];
        private _blocked = {
            params ["_why"];
            diag_log ["A3UE_FPV_QA_MOTION_BLOCKED", _kind, "NOT RUN", _why];
            if (hasInterface) then {copyToClipboard str ["NOT RUN", _why];};
            createHashMap
        };
        if (isRemoteExecuted || {!canSuspend} || {!isServer}
            || {!(missionNamespace getVariable ["A3UE_FPV_registrationComplete", false])}
            || {missionNamespace getVariable ["A3UE_FPV_debug", false]}) exitWith {["CONTEXT_OR_INITIALIZATION"] call _blocked};
        private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState", createHashMap];
        private _runs = missionNamespace getVariable ["A3UE_FPV_QA_runs", createHashMap];
        if (count _s > 0 && {!(_s getOrDefault ["finished", false])}
            || {(missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap]) getOrDefault ["active",false]}
            || {count _cap > 0 && {!(_cap getOrDefault ["exported", false])}}
            || {missionNamespace getVariable ["A3UE_FPV_QA_startupRunning", false]}
            || {values _runs findIf {!(_x getOrDefault ["cleaned", false])} >= 0}) exitWith {["FIXTURE_CAPTURE_EXPORT_OR_ROSTER_BUSY"] call _blocked};
        private _origin = _options getOrDefault ["originATL", []];
        private _class = _options getOrDefault ["class", "B_UAV_01_F"];
        if (!(_origin isEqualType []) || {!(_class isEqualType "")}
            || {!(_class in ["B_UAV_01_F","O_UAFPV_PG7VL_AT","frtz_O_KVN_AT_20KM"])}
            || {!isClass (configFile >> "CfgVehicles" >> _class)}
            || {count _origin != 3} || {_origin findIf {!(_x isEqualType 0) || {!finite _x}} >= 0}
            || {_origin # 2 < 40} || {_origin # 2 > 150}) exitWith {["CLASS_OR_GEOMETRY: exact controls, ATL altitude 40..150"] call _blocked};
        if (vehicles findIf {_x getVariable ["A3UE_FPV_managed", false] && {_x distance2D _origin < 1000}} >= 0
            || {allPlayers findIf {_x distance2D _origin < 350} >= 0}
            || {nearestObjects [_origin,["Air","LandVehicle","Man","Ship"],200] isNotEqualTo []}) exitWith {["RANGE_NOT_ISOLATED"] call _blocked};
        // Loaded native init must be the inspected non-movement initializer.
        private _initName = switch (_class) do {case "O_UAFPV_PG7VL_AT": {"UA_fnc_fpv_droneInit"}; case "frtz_O_KVN_AT_20KM": {"DB_kvn_fnc_fpv_droneInit"}; default {""};};
        private _native = toLower str (missionNamespace getVariable [_initName, {}]);
        if (_initName != "" && {(_native find "disableai") < 0
            || {(_native find "setvelocity") >= 0} || {(_native find "setpos") >= 0}
            || {(_native find "setvector") >= 0}}) exitWith {["UNINSPECTED_NATIVE_INITIALIZER"] call _blocked};
        if (!fileExists "scripts\ua_dive\motion_prepare.sqf" || {!fileExists "scripts\ua_dive\motion_policy.sqf"} || {!fileExists "scripts\ua_dive\motion_policy_data.sqf"}) exitWith {
            ["QA_POLICY_HELPERS_MISSING"] call _blocked
        };
        private _policy = ["admit",_class,_worker] call compileScript ["scripts\ua_dive\motion_prepare.sqf"];
        if (count _policy == 0) exitWith {createHashMap};
        // Scheduler time spent preparing cannot qualify a subsequently occupied range.
        if (vehicles findIf {_x getVariable ["A3UE_FPV_managed", false] && {_x distance2D _origin < 1000}} >= 0
            || {allPlayers findIf {_x distance2D _origin < 350} >= 0}
            || {nearestObjects [_origin,["Air","LandVehicle","Man","Ship"],200] isNotEqualTo []}) exitWith {["RANGE_NOT_ISOLATED_AFTER_PREPARATION"] call _blocked};
        diag_log ["A3UE_FPV_QA_MOTION_ADMISSION_SUMMARY",_policy get "version",_class,_policy get "ok",
            _policy get "reason",count (_policy get "rows"),_policy get "admissionSeconds"];
        if (!(_policy get "ok")) exitWith {
            // Bounded synchronous records only for a refused explicit command.
            {diag_log ["A3UE_FPV_QA_MOTION_ADMISSION",_policy get "version",_x];} forEach (_policy get "rows");
            [_policy get "reason"] call _blocked
        };
        private _serial = 1 + (missionNamespace getVariable ["A3UE_FPV_QA_motionSerial", 0]);
        if (_serial > 10) exitWith {["TEN_FIXTURES: preserve evidence/restart mission"] call _blocked};
        missionNamespace setVariable ["A3UE_FPV_QA_motionSerial", _serial];
        private _admitted = false;
        isNil {
        private _latest = missionNamespace getVariable ["A3UE_FPV_QA_motionState",createHashMap];
        private _latestCap = missionNamespace getVariable ["A3UE_FPV_QA_captureState",createHashMap];
        if (count _latest > 0 && {!(_latest getOrDefault ["finished",false])}
            || {(missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap]) getOrDefault ["active",false]}
            || {count _latestCap > 0 && {!(_latestCap getOrDefault ["exported",false])}}
            || {missionNamespace getVariable ["A3UE_FPV_QA_startupRunning",false]}
            || {values (missionNamespace getVariable ["A3UE_FPV_QA_runs",createHashMap]) findIf {!(_x getOrDefault ["cleaned",false])} >= 0}) exitWith {};
        _s = createHashMapFromArray [["id",format ["MOTION-%1-%2-%3",clientOwner,diag_frameNo toFixed 0,_serial]],
            ["kind",_kind],["options",_options],["base",diag_tickTime],["frameBase",diag_frameNo],
            ["rows",[]],["specimens",[]],["cancel",false],["reason",""],["failures",0],
            ["notRun",0],["cases",0],["required",[6,3] select (_kind == "AI_SEMANTICS")],["finished",false],["exported",false],["active",true],
            ["observer",-1],["worker",_worker],["deadline",diag_tickTime+120],["finalizing",false],["policy",_policy]];
        missionNamespace setVariable ["A3UE_FPV_QA_motionState", _s];
        _admitted = true;
        };
        if (!_admitted) exitWith {["ADMISSION_RACE_BUSY"] call _blocked};
        ["BEGIN",[_kind,_class,_origin,productVersion,_s get "base",(_s get "frameBase") toFixed 0,
            _features,_policy get "version","one scheduled writer; EachFrame observes BEFORE any later command; no physics-step assumption"]] call _record;
        { ["ADMISSION",_x] call _record; } forEach (_policy get "rows");
        ["ADMISSION_CONDITIONS",[_policy get "classes",_policy get "conditions"]] call _record;
        // Independent bounded supervisor handles cancellation, script error and deadline.
        [_s] spawn {
            params ["_state"];
            waitUntil {
                sleep .1;
                _state get "finished" || {_state get "finalizing"} || {_state get "cancel"}
                    || {scriptDone (_state get "worker")} || {diag_tickTime >= (_state get "deadline")}
            };
            if (_state get "finished" || {_state get "finalizing"}) exitWith {};
            if (!(_state get "cancel")) then {_state set ["reason","WORKER_ERROR_OR_DEADLINE"];};
            _state set ["cancel",true];
            sleep .2;
            if (_state get "finalizing" || {_state get "finished"}) exitWith {};
            // Only the QA entry script is ever terminated, never a foreign controller.
            private _worker = _state get "worker";
            if (!scriptDone _worker) then {terminate _worker;};
            ["finish"] call A3UE_FPV_QA_motionAPI;
        };
        _s
    };
    case "record": {_arg call _record;};
    case "safe": {
        private _ok = _arg call _safe;
        if (!_ok && {!(_s get "cancel")}) then {
            private _u = _arg # 0;
            ["ISOLATION_GUARD",["NOT RUN",typeOf _u,netId _u,local _u,owner _u,
                [_u] call A3UE_fnc_fpv_isExternallyControlled,crew _u apply {[typeOf _x,netId _x,local _x,isPlayer _x]},
                "control/locality/controller/crew/engine/simulation/damage prerequisites"]] call _record;
            _s set ["reason","ISOLATION_GUARD_NOT_RUN"]; _s set ["cancel",true];
        };
        _ok
    };
    case "qualify": {
        _arg params ["_spec","_point"];
        private _u = _spec get "u";
        private _issue = ["revalidate",[_s get "policy",_u,_spec getOrDefault ["cargoMass",-1]]] call A3UE_FPV_QA_motionPolicy;
        if (_issue isNotEqualTo []) exitWith {[_u,_issue,_point] call _compatibilityFailure};
        ["ADMISSION_CHECK",[_point,typeOf _u,netId _u,"QUALIFIED_CONDITIONS",
            crew _u apply {[typeOf _x,netId _x,primaryWeapon _x,handgunWeapon _x,secondaryWeapon _x,currentWeapon _x,
                lifeState _x,animationState _x]},(_s get "policy") get "conditions"]] call _record;
        if ("ACE_CARGO_EMPTY" in ((_s get "policy") get "conditions")) then {
            ["CARGO_CHECK",[_point,typeOf _u,netId _u,
                ["DISABLED","ENABLED_EMPTY"] select (getNumber (configOf _u >> "ace_cargo_hasCargo") == 1),
                isNil {_u getVariable "ace_cargo_hasCargo"},_u getVariable ["ace_cargo_hasCargo",false],
                _u getVariable ["ace_cargo_space",getNumber (configOf _u >> "ace_cargo_space")],
                _u getVariable ["ace_cargo_initVehicle",false],count (_u getVariable ["ace_cargo_loaded",[]]),
                count attachedObjects _u,count getVehicleCargo _u,getMass _u,_spec get "cargoMass"]] call _record;
        };
        true
    };
    case "mask": {_arg call _mask};
    case "make": {
        private _options = _s get "options";
        private _class = _options getOrDefault ["class","B_UAV_01_F"];
        private _u = objNull;
        private _spec = createHashMapFromArray [["u",_u],["crew",[]],["groups",[]],["masks",[]],["created",diag_tickTime],["hooks",[]]];
        private _preIssue = ["precreate",[_s get "policy",objNull]] call A3UE_FPV_QA_motionPolicy;
        if (_preIssue isNotEqualTo []) exitWith {[_u,_preIssue,"BEFORE_CREATE_NO_SPECIMEN"] call _compatibilityFailure; _spec};
        (_s get "specimens") pushBack _spec;
        private _issue = [];
        // Retain ownership atomically, even if the QA worker is cancelled at creation.
        isNil {
            _u = createVehicle [_class, _options get "originATL", [], 0, "FLY"];
            _spec set ["u",_u];
            if (!isNull _u) then {
                _spec set ["cargoMass",getMass _u];
                createVehicleCrew _u;
                {(_spec get "crew") pushBackUnique _x; (_spec get "groups") pushBackUnique group _x;} forEach crew _u;
                _issue = ["conditions",[_s get "policy",_u,_spec get "cargoMass"]] call A3UE_FPV_QA_motionPolicy;
            };
        };
        if (isNull _u) exitWith {_s set ["notRun",1+(_s get "notRun")]; _spec};
        if (_issue isNotEqualTo []) exitWith {[_u,_issue,"ACTUAL_CREATED_STATE"] call _compatibilityFailure; _spec};
        ["CREATED",[netId _u,typeOf _u,local _u,owner _u,diag_tickTime-(_spec get "created"),
            ([_u]+crew _u) apply {[netId _x,local _x,owner _x,[_x] call _mask]},
            _u getVariable ["UA_FPV_DroneInitStarted",false],_u getVariable ["UA_FPV_PayloadType",""]]] call _record;
        _u engineOn true;
        // Observe contact without replacing native callbacks or changing return values.
        private _contact = _u addEventHandler ["EpeContactStart", {
            params ["_object1","_object2","_selection1","_selection2","_force"];
            private _c = missionNamespace getVariable ["A3UE_FPV_QA_motionState",createHashMap];
            if (!(_c getOrDefault ["active",false])) exitWith {};
            ["record",["CONTACT",[netId _object1,netId _object2,_force]]] call A3UE_FPV_QA_motionAPI;
            _c set ["cancel",true]; _c set ["reason","CONTACT_INVALIDATES_COMPARISON"];
        }];
        (_spec get "hooks") pushBack ["EpeContactStart",_contact];
        private _until = diag_tickTime+10;
        private _stableAt = -1;
        private _prior = [];
        private _ready = false;
        waitUntil {
            sleep .1;
            // Retain only the atomic creation roster. Later crew are foreign.
            private _masks = ([_u] + crew _u) apply {[_x] call _mask};
            private _nativeReady = switch (_class) do {
                case "O_UAFPV_PG7VL_AT": {_u getVariable ["UA_FPV_DroneInitStarted",false]
                    && {_u getVariable ["UA_FPV_PayloadType",""] == "PG7VL"}
                    && {!(_u getVariable ["UA_FPV_TakeoffProtectionActive",false])}};
                case "frtz_O_KVN_AT_20KM": {[_u,0] call A3UE_fnc_fpv_hasCurrentLifecycle
                    && {scriptDone (_u getVariable ["A3UE_FPV_nativeClaimRetry",scriptNull])}
                    && {!(_u checkAIFeature "PATH")}};
                default {true};
            };
            private _ok = [_u] call _safe && {_nativeReady} && {typeOf _u == _class}
                && {diag_tickTime-(_spec get "created") >= 2} && {getPosATL _u # 2 >= 30};
            if (!_ok || {_masks isNotEqualTo _prior}) then {_stableAt = diag_tickTime;};
            _prior = _masks;
            _ready = _ok && {_stableAt >= 0} && {diag_tickTime-_stableAt >= 1};
            ["READINESS",[netId _u,typeOf _u,diag_tickTime-(_spec get "created"),local _u,owner _u,
                crew _u apply {[netId _x,local _x,owner _x,alive _x]},_masks,_nativeReady,
                _u getVariable ["UA_FPV_PayloadType",""],_u getVariable ["UA_FPV_TakeoffProtectionActive",false],
                _u getVariable ["A3UE_FPV_nativeGeneration",-1],_ok,_ready]] call _record;
            _ready || {diag_tickTime >= _until} || {_s get "cancel"} || {isNull _u}
        };
        _spec set ["ready",_ready];
        if (_ready) then {_ready = ["qualify",[_spec,"POST_READINESS"]] call A3UE_FPV_QA_motionAPI; _spec set ["ready",_ready];};
        _spec set ["masks",([_u]+(_spec get "crew")) apply {[_x,[_x] call _mask]}];
        ["READY",[netId _u,["NOT RUN","READY"] select _ready,diag_tickTime-(_spec get "created")]] call _record;
        _spec
    };
    case "restore": {
        private _spec = _arg;
        private _u = _spec get "u";
        if (!isNull _u && {!([_u] call _safe)}) exitWith {false};
        {
            _x params ["_unit","_values"];
            if (!isNull _unit && {local _unit}) then {
                {if (_values # _forEachIndex) then {_unit enableAI _x;} else {_unit disableAI _x;};} forEach _features;
            };
        } forEach (_spec get "masks");
        private _ok = (_spec get "masks") findIf {!isNull (_x # 0) && {([_x # 0] call _mask) isNotEqualTo (_x # 1)}} < 0;
        ["RESTORE",[netId _u,_ok,(_spec get "masks") apply {[netId (_x # 0),[_x # 0] call _mask]}]] call _record;
        _ok
    };
    case "cleanup": {
        private _ok = true;
        {
            isNil {
            private _spec = _x;
            private _u = _spec get "u";
            if (!isNull _u) then {
                private _issue = ["precreate",[_s get "policy",_u]] call A3UE_FPV_QA_motionPolicy;
                if (_issue isEqualTo []) then {_issue = ["conditions",[_s get "policy",_u,_spec getOrDefault ["cargoMass",-1]]] call A3UE_FPV_QA_motionPolicy;};
                if (_issue isNotEqualTo []) then {[_u,_issue,"CLEANUP_OWNERSHIP_CHECK"] call _compatibilityFailure;};
            };
            private _cargoIssue = ["cargoCleanup",[_s get "policy",_u,[_u]+(_spec get "crew"),_spec getOrDefault ["cargoMass",-1]]] call A3UE_FPV_QA_motionPolicy;
            if (_cargoIssue isNotEqualTo []) then {
                _spec set ["foreignUnsafe",true];
                [_u,_cargoIssue,"CLEANUP_CARGO_OWNERSHIP_CHECK"] call _compatibilityFailure;
            };
            private _owned = [_u]+(_spec get "crew");
            private _controlled = !isNull _u && {[_u] call A3UE_fnc_fpv_isExternallyControlled
                || {allPlayers findIf {getConnectedUAV _x == _u} >= 0}};
            private _foreign = !isNull _u && {_u getVariable ["A3UE_FPV_managed",false]
                || {_u getVariable ["A3UE_FPV_controllerRunning",false]}
                || {!scriptDone (_u getVariable ["A3UE_FPV_controllerHandle",scriptNull])}
                || {!scriptDone (_u getVariable ["A3UE_FPV_claimRetryHandle",scriptNull])}
                || {(_u getVariable ["A3UE_FPV_controllerGeneration",-1]) >= 0}
                || {crew _u findIf {!(_x in (_spec get "crew")) || {!(group _x in (_spec get "groups"))}} >= 0}
                || {(_spec get "groups") findIf {!isNull _x && {!local _x || {units _x findIf {!(_x in (_spec get "crew"))} >= 0}}} >= 0}};
            if (_controlled || {_foreign} || {_spec getOrDefault ["foreignUnsafe",false]}
                || {_owned findIf {!isNull _x && {!local _x || {isPlayer _x}}} >= 0}) then {
                _ok = false;
                ["CLEANUP_PENDING",[netId _u,"CONTROL_LOCALITY_OR_FOREIGN_CALLBACK_CREW: no foreign termination/deletion",_s get "reason"]] call _record;
            } else {
                // Restore only tested feature masks. Native handlers remain installed.
                if (!isNull _u && {_spec getOrDefault ["ready",false]} && {[_u] call _safe}) then {
                    if (!( ["restore",_spec] call A3UE_FPV_QA_motionAPI)) then {
                        _s set ["failures",1+(_s get "failures")];
                    };
                };
                private _ids = _owned apply {netId _x};
                private _groupIds = (_spec get "groups") apply {str _x};
                if (!isNull _u) then {{_u removeEventHandler _x;} forEach (_spec get "hooks");};
                {if (!isNull _x) then {deleteVehicle _x;};} forEach (_spec get "crew");
                if (!isNull _u) then {deleteVehicle _u;};
                {if (!isNull _x && {local _x} && {units _x isEqualTo []}) then {deleteGroup _x;};} forEach (_spec get "groups");
                private _gone = _owned findIf {!isNull _x} < 0 && {(_spec get "groups") findIf {!isNull _x} < 0};
                _ok = _ok && {_gone};
                ["CLEANUP",[_ids,_gone,(_spec get "crew") apply {isNull _x},(_spec get "groups") apply {isNull _x},_groupIds]] call _record;
            };
            };
        } forEach (_s get "specimens");
        _ok
    };
    case "finish": {
        if (count _s == 0 || {_s get "finished"} || {_s get "finalizing"}) exitWith {false};
        _s set ["finalizing",true];
        _s set ["active",false];
        if ((_s get "observer") >= 0) then {removeMissionEventHandler ["EachFrame",_s get "observer"]; _s set ["observer",-1];};
        private _cleaned = ["cleanup"] call A3UE_FPV_QA_motionAPI;
        if (!(_s get "cancel") && {_s get "notRun" == 0} && {_s get "cases" != (_s get "required")}) then {
            _s set ["failures",1+(_s get "failures")]; _s set ["reason","MISSING_CASE_COVERAGE"];
        };
        _s set ["notRun",(_s get "notRun") max ((_s get "required")-(_s get "cases"))];
        private _status = if (!_cleaned || {_s get "failures" > 0} || {_s get "reason" == "BUFFER_LIMIT"}
            || {_s get "reason" == "WORKER_ERROR_OR_DEADLINE"}) then {"FAIL"} else {
            ["PASS","NOT RUN"] select (_s get "cancel" || {_s get "notRun" > 0} || {_s get "cases" == 0})
        };
        private _result = [_s get "id",_s get "kind",_status,_s get "cases",_s get "failures",_s get "notRun",_cleaned,_s get "reason"];
        ["END",_result] call _record;
        private _serialize = {
            params ["_value"];
            if (_value isEqualType 0) exitWith {_value toFixed 6};
            if (_value isEqualType []) exitWith {"["+((_value apply {[_x] call _serialize}) joinString ",")+"]"};
            str _value
        };
        // Detached writer/observer; only deferred bounded RPT output, no flight logging.
        {
            private _wire = [_x] call _serialize;
            private _parts = ceil (count _wire/256);
            for "_part" from 0 to (_parts-1) do {
                diag_log text ([["A3UE_FPV_QA_MOTION_PART",_s get "id",clientOwner,_x # 0,_part,_parts,
                    _wire select [_part*256,256]]] call _serialize);
            };
            if (_forEachIndex mod 100 == 99) then {sleep .01;};
        } forEach (_s get "rows");
        diag_log ["A3UE_FPV_QA_MOTION_EXPORT_DONE",_result,count (_s get "rows")];
        _s set ["exported",true];
        _s set ["finished",_cleaned];
        _s set ["finalizing",false];
        if (hasInterface) then {copyToClipboard str _result;};
        _cleaned
    };
    case "cancel": {
        if (count _s > 0 && {!(_s get "finished")}) then {_s set ["cancel",true]; _s set ["reason","USER_CANCEL"];};
        if (hasInterface) then {copyToClipboard "Motion QA cancellation requested; wait for END/export/cleanup";};
    };
    case "status": {
        if (hasInterface) then {copyToClipboard str [_s getOrDefault ["id",""],_s getOrDefault ["active",false],
            _s getOrDefault ["finished",false],_s getOrDefault ["exported",false],_s getOrDefault ["reason",""]];};
    };
};
