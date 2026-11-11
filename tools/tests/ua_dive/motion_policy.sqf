// Narrow inspected-preset admission. Read-only vendor/config/registry inspection.
params ["_action", ["_arg", []]];
// Diagnostic identity only. Admission uses exact reviewed source/body equality.
private _fingerprint = {params ["_text"]; [count _text]};
// The initializer's two reviewed paths are selected by immutable class config.
// Overrides may agree with that path, but cannot switch paths or add capacity.
private _cargoStatic = {
    params ["_policy"];
    if (!("ACE_CARGO_EMPTY" in (_policy get "conditions"))) exitWith {[]};
    private _class = (_policy get "classes") # 0;
    private _profiles = _policy get "cargoProfiles";
    private _index = _profiles findIf {(_x # 0) == _class};
    if (_index < 0) exitWith {["CARGO_CONFIG_UNQUALIFIED",_class]};
    (_profiles # _index) params ["","_path","_has","_space"];
    private _cfg = configFile >> "CfgVehicles" >> _class;
    if (!isNumber (_cfg >> "ace_cargo_hasCargo") || {getNumber (_cfg >> "ace_cargo_hasCargo") != _has}
        || {!isNumber (_cfg >> "ace_cargo_space")} || {getNumber (_cfg >> "ace_cargo_space") != _space}
        || {configProperties [_cfg >> "ace_cargo" >> "cargo","isClass _x",true] isNotEqualTo []}) exitWith {
        ["CARGO_CONFIG_UNQUALIFIED",_class,_path,"hasCargo/space/configuredCargo differs"]
    };
    []
};
private _cargoState = {
    params ["_policy","_u","_objects",["_mass",-1]];
    if (!("ACE_CARGO_EMPTY" in (_policy get "conditions"))) exitWith {[]};
    private _profiles = _policy get "cargoProfiles";
    private _class = if (isNull _u) then {(_policy get "classes") # 0} else {typeOf _u};
    private _index = _profiles findIf {(_x # 0) == _class};
    if (_index < 0) exitWith {["CLASS"]};
    (_profiles # _index) params ["","_path","_has","_space"];
    private _override = _u getVariable "ace_cargo_hasCargo";
    if (!isNil "_override" && {!(_override isEqualType true) || {_override != (_has == 1)}}) exitWith {[_path,"HAS_CARGO_OVERRIDE"]};
    private _capacity = _u getVariable ["ace_cargo_space",_space];
    if (!(_capacity isEqualType 0) || {_capacity != _space}) exitWith {[_path,"SPACE_OVERRIDE"]};
    private _init = _u getVariable ["ace_cargo_initVehicle",false];
    if (!(_init isEqualType true) || {_has == 0 && {_init}}) exitWith {[_path,"INIT_STATE"]};
    if (!isNil {_u getVariable "ace_cargo_canLoad"} || {!isNil {_u getVariable "ace_cargo_size"}}
        || {(_u getVariable ["ace_cargo_setSpaceRemoveJip",false]) isNotEqualTo false}) exitWith {[_path,"LOADABILITY_OR_SETSPACE_OVERRIDE"]};
    if (!isNull _u && {_mass >= 0} && {getMass _u != _mass}) exitWith {[_path,"MASS_CHANGED"]};
    // Include retained crew/containers at cleanup. Never delete cargo to pass.
    _objects = +_objects;
    _objects = _objects select {!isNull _x};
    private _at = 0;
    while {_at < count _objects && {count _objects <= 32}} do {
        {_objects pushBackUnique (_x # 1);} forEach everyContainer (_objects # _at);
        _at = _at+1;
    };
    if (count _objects > 32) exitWith {[_path,"CONTAINER_BOUND"]};
    private _bad = _objects findIf {
        (_x getVariable ["ace_cargo_loaded",[]]) isNotEqualTo []
            || {attachedObjects _x isNotEqualTo []} || {!isNull attachedTo _x}
            || {getVehicleCargo _x isNotEqualTo []} || {!isNull isVehicleCargo _x}
    };
    if (_bad >= 0) exitWith {[_path,"LOADED_OR_ATTACHED_RESOURCE",typeOf (_objects # _bad),netId (_objects # _bad)]};
    private _preview = missionNamespace getVariable ["ace_cargo_itemPreviewObject",objNull];
    if (!(_preview isEqualType objNull)) exitWith {[_path,"PREVIEW_TYPE"]};
    if ((missionNamespace getVariable ["ace_cargo_interactionVehicle",objNull]) in _objects
        || {(missionNamespace getVariable ["ace_cargo_selectedItem",objNull]) in _objects}
        || {!isNull _preview}
        || {(missionNamespace getVariable ["ace_cargo_deployPFH",-1]) isNotEqualTo -1}) exitWith {[_path,"CARGO_INTERACTION_OR_DEPLOYMENT"]};
    []
};
if (_action == "cargoCleanup") exitWith {
    _arg params ["_policy","_u","_owned",["_mass",-1]];
    private _detail = [_policy,_u,_owned,_mass] call _cargoState;
    if (_detail isEqualTo []) then {[]} else {["COMPATIBILITY_CONDITION",typeOf _u,netId _u,"ACE_CARGO_EMPTY",_detail]}
};
private _prep = missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap];
private _reason = [];
private _until = if (_action == "inventory") then {_prep getOrDefault ["deadline",diag_tickTime]} else {diag_tickTime+30};
private _steps = 0;
private _budget = {
    _steps = _steps+1;
    if (_steps > 200000 && {_action == "inventory"}) then {_reason = ["PREPARATION_WORK_LIMIT"];};
    if (_action == "inventory") then {
        if (_prep getOrDefault ["cancel",false]) then {_reason = ["PREPARATION_CANCELLED"];};
        if (diag_tickTime >= _until && {_reason isEqualTo []}) then {_reason = ["POLICY_ADMISSION_DEADLINE"];};
        if (_steps mod 128 == 0 && {canSuspend}) then {sleep .001;};
    };
    _reason isEqualTo []
};
private _registryText = {
    params ["_registered"];
    if (!(_registered isEqualType []) || {count _registered > 128}) exitWith {"<REGISTRY_LIMIT_OR_TYPE>"};
    private _bad = _registered findIf {
        !(call _budget) || {!(_x isEqualType [])} || {count _x != 3}
            || {!((_x # 0) isEqualType {})} || {count str (_x # 0) > 20000}
            || {!((_x # 1) isEqualType true)} || {!((_x # 2) isEqualType [])}
            || {count (_x # 2) > 128} || {(_x # 2) findIf {!(_x isEqualType "") || {count _x > 128}} >= 0}
    };
    if (_bad >= 0) exitWith {"<REGISTRY_SHAPE_OR_LENGTH>"};
    str _registered
};
private _unmatchedIdentity = {
    params ["_text"];
    // A known #line path is a source label, never evidence of body equality.
    // Arbitrary prefixes, bodies and unreviewed path text are never exported.
    private _index = _pins findIf {_text find (""""+(_x # 1)+"""") >= 0};
    if (_index < 0) exitWith {["UNIDENTIFIED"]};
    private _pin = _pins # _index;
    ["SOURCE_LABEL_ONLY",(_pin # 1) select [0,160],(_pin # 3) select [0,80]]
};
// Engine regex scans ordinary code spans; SQF iterates only strings/comments.
// A temporary control-character separator preserves identifier token boundaries.
// Input collision is refused; quoted contents never pass through these replacements.
private _canons = createHashMap;
private _canonBytes = 0;
private _canonical = {
    params ["_text"];
    if (count _text > 20000) exitWith {_reason = ["CODE_LENGTH_LIMIT",count _text]; ""};
    if (!(call _budget)) exitWith {""};
    private _cached = _canons get _text;
    if (!isNil "_cached") exitWith {_cached};
    private _plain = {
        params ["_code"];
        if (_code find toString [1] >= 0) exitWith {_reason = ["CODE_SEPARATOR_COLLISION"]; ""};
        (toLower _code) regexReplace ["([a-z0-9_])[\x00-\x20]+(?=[a-z0-9_])/g","$1"+toString [1]]
            regexReplace ["[\x00\x02-\x20]/g",""] regexReplace ["\x01/g"," "]
    };
    private _lexemes = _text regexFind ["""(?:""""|[^""])*""|'(?:''|[^'])*'|#line[^\n]*|//[^\n]*|/\*[\s\S]*?\*//g"];
    private _out = [];
    private _parts = [];
    private _at = 0;
    {
        if (!(call _budget)) exitWith {};
        private _token = _x # 0 # 0;
        private _offset = _x # 0 # 1;
        _parts pushBack (_text select [_at,_offset-_at]);
        if ((_token select [0,1]) in ["""","'"]) then {
            _out pushBack ([(_parts joinString "")] call _plain);
            _parts = [];
            if ((_token select [0,1]) == "'") then {
                _token = """"+((_token select [1,count _token-2]) regexReplace ["''/g","'"] regexReplace ["""/g",""""""])+"""";
            };
            _out pushBack _token;
        } else {_parts pushBack " ";};
        _at = _offset+count _token;
    } forEach _lexemes;
    if (!(call _budget)) exitWith {""};
    _parts pushBack (_text select [_at]);
    _out pushBack ([(_parts joinString "")] call _plain);
    private _result = _out joinString "";
    if (_reason isNotEqualTo []) exitWith {""};
    if (count _canons < 512 && {_canonBytes+count _text+count _result <= 1000000}) then {
        _canons set [_text,_result]; _canonBytes = _canonBytes+count _text+count _result;
    };
    _result
};
if (_action == "conditions") exitWith {
    _arg params ["_policy","_u",["_mass",-1]];
    private _failure = [];
    private _crew = crew _u;
    private _unknown = ([_u]+_crew) findIf {!(typeOf _x in (_policy get "classes"))};
    if (_unknown >= 0) exitWith {["UNQUALIFIED_CREATED_CLASS",typeOf (([_u]+_crew) # _unknown),netId (([_u]+_crew) # _unknown)]};
    {
        private _condition = _x;
        private _bad = false;
        private _subject = _u;
        private _detail = [];
        switch _condition do {
            case "UNARMED_CREW": {
                private _idx = _crew findIf {primaryWeapon _x != "" || {handgunWeapon _x != ""} || {secondaryWeapon _x != ""}
                    || {currentWeapon _x != ""} || {!isNil {_x getVariable "WBK_AI_BIC"}}};
                _bad = _idx >= 0;
                if (_bad) then {_subject = _crew # _idx; _detail = [primaryWeapon _subject,handgunWeapon _subject,secondaryWeapon _subject,currentWeapon _subject];};
            };
            case "CONSCIOUS_CREW": {
                private _idx = _crew findIf {lifeState _x in ["INCAPACITATED","DEAD","DEAD-RESPAWN","DEAD-SWITCHING"]
                    || {_x getVariable ["ACE_isUnconscious",false]} || {(toLower animationState _x) find "unconscious" >= 0}};
                _bad = _idx >= 0;
                if (_bad) then {_subject = _crew # _idx; _detail = [lifeState _subject,animationState _subject,_subject getVariable ["ACE_isUnconscious",false]];};
            };
            case "NO_CAPTIVE_STATE": {
                private _idx = _crew findIf {_x getVariable ["ace_captives_isHandcuffed",false]
                    || {_x getVariable ["ace_captives_isSurrendering",false]}
                    || {_x getVariable ["ace_captives_handcuffAnimEHID",-1] != -1}
                    || {_x getVariable ["ace_captives_surrenderAnimEHID",-1] != -1}};
                _bad = _idx >= 0;
                if (_bad) then {_subject = _crew # _idx;};
            };
            case "MUTE_UNDEFINED": {_bad = _crew findIf {(_x getVariable ["ace_common_muteUnitReasons",[]]) isNotEqualTo []} >= 0;};
            case "NO_RALLYPOINT": {_bad = ["ACE_Rallypoint_West","ACE_Rallypoint_East","ACE_Rallypoint_Independent"] findIf {
                !isNull (missionNamespace getVariable [_x,objNull])} >= 0;};
            case "RADIO_OFF": {_bad = _u getVariable ["klpq_musicRadio_radioIsOn",false]
                || {_u getVariable ["klpq_musicRadio_loudRadioIsOn",false]}
                || {!isNull (_u getVariable ["klpq_musicRadio_hiddenRadio",objNull])};};
            case "LASER_OFF": {_bad = _u getVariable ["ace_markinglaser_laserMode",0] != 0;};
            case "LST_OFF": {_bad = _u getVariable ["ace_laser_laserSpotTrackerOn",false];};
            case "IS_UAV": {_bad = !unitIsUAV _u;};
            case "ACE_CARGO_EMPTY": {
                _detail = [_policy,_u,[_u]+_crew,_mass] call _cargoState;
                _bad = _detail isNotEqualTo [];
            };
            case "EMPTY_CARGO": {
                private _objects = [_u]+_crew;
                private _index = 0;
                while {_index < count _objects && {count _objects <= 32}} do {
                    { _objects pushBackUnique (_x # 1); } forEach everyContainer (_objects # _index);
                    _index = _index+1;
                };
                _bad = count _objects > 32 || {_objects findIf {magazineCargo _x isNotEqualTo [] || {weaponCargo _x isNotEqualTo []}} >= 0};
            };
            case "NO_FRIES": {_bad = !isNull (_u getVariable ["ace_fastroping_FRIES",objNull]);};
            case "NO_PYLONS": {}; // Immutable config is read only at qualification boundaries.
            case "NO_SUPPLY": {_bad = getAmmoCargo _u > 0 || {_u getVariable ["ace_rearm_isSupplyVehicle",false]};};
            case "FCS_DISABLED": {}; // Immutable turret config is checked only at qualification boundaries.
            case "UA_PG7VL": {_bad = typeOf _u != "O_UAFPV_PG7VL_AT"
                || {!((_u getVariable ["UA_FPV_PayloadType",""]) in ["","PG7VL"])};};
            case "KVN_EXACT_VARIANT": {_bad = typeOf _u != "frtz_O_KVN_AT_20KM";};
            default {
                // Even zero is defined and sendEffects will replay its callbacks.
                private _prefix = ["ace_common","cba_statuseffects"] select (_condition == "CBA_EFFECTS_UNDEFINED");
                private _map = missionNamespace getVariable [_prefix+"_statusEffects",0];
                private _keys = if (_map isEqualType createHashMap) then {keys _map} else {[]};
                _keys sort true;
                _bad = !(_map isEqualType createHashMap) || {count _keys > 64}
                    || {_keys isNotEqualTo (_policy getOrDefault [_prefix,[]])};
                if (!_bad) then {
                    {
                        private _unit = _x;
                        private _idx = _keys findIf {!isNil {_unit getVariable (_prefix+"_effect_"+_x)}};
                        if (_idx >= 0) exitWith {
                            _bad = true; _subject = _unit;
                            private _name = _keys # _idx;
                            private _value = _unit getVariable (_prefix+"_effect_"+_name);
                            _detail = [_prefix,_name,if (_value isEqualType 0) then {_value} else {typeName _value}];
                        };
                    } forEach ([_u]+_crew);
                };
            };
        };
        if (_bad) exitWith {_failure = ["COMPATIBILITY_CONDITION",typeOf _subject,netId _subject,_condition,_detail];};
    } forEach (_policy get "conditions");
    _failure
};
if (_action in ["revalidate","precreate"]) exitWith {
    _arg params ["_policy","_u",["_mass",-1]];
    private _failure = [_policy] call _cargoStatic;
    if (_failure isEqualTo [] && {_action != "precreate"}) then {_failure = ["conditions",[_policy,_u,_mass]] call A3UE_FPV_QA_motionPolicy;};
    if (_failure isNotEqualTo []) exitWith {_failure};
    if ("FCS_DISABLED" in (_policy get "conditions") && {allTurrets _u findIf {
        private _cfg = [configOf _u,_x] call CBA_fnc_getTurret;
        getNumber (_cfg >> "ace_fcs_Enabled") == 1
    } >= 0}) exitWith {["COMPATIBILITY_CONDITION",typeOf _u,netId _u,"FCS_DISABLED"]};
    private _cfg = configOf _u;
    if ("NO_FRIES" in (_policy get "conditions") && {getNumber (_cfg >> "ace_fastroping_enabled") == 2}) exitWith {
        ["COMPATIBILITY_CONDITION",typeOf _u,netId _u,"NO_FRIES"]
    };
    if ("NO_PYLONS" in (_policy get "conditions") && {isClass (_cfg >> "Components" >> "TransportPylonsComponent")}) exitWith {
        ["COMPATIBILITY_CONDITION",typeOf _u,netId _u,"NO_PYLONS"]
    };
    if ("NO_SUPPLY" in (_policy get "conditions") && {getNumber (_cfg >> "ace_rearm_defaultSupply") > 0
        || {getNumber (_cfg >> "transportAmmo") > 0} || {isClass (_cfg >> "ACE_Actions" >> "ACE_MainActions" >> "ace_rearm_takeAmmo")}}) exitWith {
        ["COMPATIBILITY_CONDITION",typeOf _u,netId _u,"NO_SUPPLY"]
    };
    private _changed = (_policy get "bindings") findIf {
        private _actual = missionNamespace getVariable [_x # 0,0];
        !(_actual isEqualType {}) || {str _actual isNotEqualTo (_x # 1)}
    };
    if (_changed >= 0) exitWith {["FUNCTION_CHANGED",(_policy get "bindings") # _changed # 0]};
    private _registry = (_policy get "registries") findIf {
        ([missionNamespace getVariable [_x # 0,[]]] call _registryText) isNotEqualTo (_x # 1)
    };
    if (_registry >= 0) exitWith {["REGISTRY_CHANGED",(_policy get "registries") # _registry # 0]};
    if (_action == "precreate") exitWith {[]};
    if ("ACE_CARGO_EMPTY" in (_policy get "conditions") && {typeOf _u != "B_UAV_01_F"}
        && {(_u getVariable ["ace_cargo_initVehicle",false]) isNotEqualTo true}) exitWith {
        ["COMPATIBILITY_CONDITION",typeOf _u,netId _u,"ACE_CARGO_EMPTY",["ENABLED_EMPTY","NATIVE_INIT_PENDING"]]
    };
    private _reason = [];
    if (_policy get "cba") then {
        {
            private _unit = _x;
            if (!(typeOf _unit in (_policy get "classes"))) exitWith {_reason = ["UNQUALIFIED_CREATED_CLASS",typeOf _unit,netId _unit];};
            if (!(_unit getVariable ["cba_xeh_isProcessed",false]) || {!(_unit getVariable ["cba_xeh_isInitialized",false])}) exitWith {
                _reason = ["CBA_OBJECT_NOT_INITIALIZED",typeOf _unit,netId _unit];
            };
            {
                private _event = _x;
                private _actual = _unit getVariable ["cba_xeh_"+_event,[]];
                private _wanted = (_policy get "objectCallbacks") get (toLower typeOf _unit+":"+_event);
                if (!(_actual isEqualType []) || {count _actual > 128}
                    || {(_actual apply {str _x}) isNotEqualTo _wanted}) exitWith {
                    _reason = ["OBJECT_CALLBACKS_CHANGED",typeOf _unit,netId _unit,_event];
                };
            } forEach ["init","initpost","local"];
            if (_reason isNotEqualTo []) exitWith {};
        } forEach ([_u]+crew _u);
    };
    _reason
};
if (_action != "inventory") exitWith {createHashMap};
private _data = call compileScript ["scripts\ua_dive\motion_policy_data.sqf"];
_data params ["_version","_dispatchPins","_callbacks","_pins","_dynamic","_identity","_cargoProfiles"];
private _old = missionNamespace getVariable ["A3UE_FPV_QA_motionMaterial",createHashMap];
if ((_old getOrDefault ["identity",""]) != _identity) then {_old = createHashMap;};
// Transactional copies: nothing from a failed/partial audit is published.
private _sources = +(_old getOrDefault ["sources",createHashMap]);
// File-patched providers are mutable: re-read every reviewed source/dependency.
// Do not change the user's patching setting to obtain reuse.
private _mountedImmutable = !isFilePatchingEnabled;
_prep set ["mountedImmutable",_mountedImmutable];
_prep set ["kind",["CACHE_AVAILABLE","COLD"] select (count _old == 0)];
private _bodies = +(_old getOrDefault ["bodies",createHashMap]);
private _dynamicBodies = +(_old getOrDefault ["dynamic",createHashMap]);
private _dynamicTexts = +(_old getOrDefault ["dynamicTexts",createHashMap]);
_canons = +(_old getOrDefault ["canons",createHashMap]);
_canonBytes = _old getOrDefault ["canonBytes",0];
private _stats = [0,0,0,0,0,0]; // source verified/reused, body verified/reused, inline verified/reused
private _costs = [0,0,0]; // source equality, function bodies, dynamic expected bodies
_prep set ["phase","INVENTORY"]; _prep set ["identity",_identity];
_prep set ["counts",_stats]; _prep set ["costs",_costs];
if (count _pins > 128 || {count _callbacks > 32} || {count _dynamic > 32}) exitWith {
    createHashMapFromArray [["ok",false],["reason",["POLICY_DATA_LIMIT"]],["rows",[]],["version",_version]]
};
private _p = createHashMapFromArray [["version",_version],["ok",false],["reason",[]],["rows",[]],
    ["cargoProfiles",_cargoProfiles],
    ["conditions",[]],["bindings",[]],["registries",[]],["objectCallbacks",createHashMap],["classes",[]],
    ["cba",isClass (configFile >> "CfgPatches" >> "cba_xeh")],["admissionStarted",diag_tickTime]];
_prep set ["phase","CONFIG_REGISTRY"];
private _rows = _p get "rows";
private _addRow = {
    params ["_row"];
    if (count _rows >= 256 || {diag_tickTime >= _until}) exitWith {
        if (_reason isEqualTo []) then {_reason = ["INVENTORY_LIMIT_OR_DEADLINE",count _rows];};
    };
    _rows pushBack _row;
};
private _verified = [];
private _registryBytes = 0;
private _verifyPin = {
    params ["_id"];
    if (_id in _verified || {_reason isNotEqualTo []}) exitWith {};
    _verified pushBack _id;
    private _pin = _pins # parseNumber _id;
    _pin params ["_pinID","_path","_expected","_name","_span","_deps"];
    {[_x] call _verifyPin;} forEach _deps;
    if (!(call _budget)) exitWith {};
    _prep set ["item",_path]; _prep set ["phase","SOURCE"];
    private _sourceAt = diag_tickTime;
    private _lf = "";
    private _start = 0;
    private _sourceReused = _mountedImmutable && {_sources getOrDefault [_id,false]};
    if (!_sourceReused) then {
        private _source = loadFile _path;
        if (count _source > 1000000) exitWith {_reason = ["SOURCE_LENGTH_LIMIT",_path];};
        _lf = _source regexReplace ["\r/g",""];
        private _checked = _lf;
        if (_span isNotEqualTo []) then {
            private _markerAt = _lf find (_span # 0);
            if (_markerAt < 0) then {_reason = ["SOURCE_SPAN_MISSING",_path];} else {
                _start = _markerAt+count (_span # 0);
                _checked = _lf select [_start,_span # 1];
            };
        };
        private _expectedLF = (_pin # 6) joinString toString [10];
        if (_checked isNotEqualTo _expectedLF && {_reason isEqualTo []}) then {_reason = ["SOURCE_UNQUALIFIED",_path,_name,count _expectedLF,count _checked];};
        if (_reason isEqualTo [] && {call _budget}) then {_sources set [_id,true]; _stats set [0,(_stats # 0)+1];};
    } else {_stats set [1,(_stats # 1)+1];};
    _costs set [0,(_costs # 0)+diag_tickTime-_sourceAt];
    [["SOURCE",_path,_name,_expected,_sourceReused,["REFUSED","EXACT_LF_MATCH_OR_VERIFIED_MOUNT"] select (_reason isEqualTo [])]] call _addRow;
    _prep set ["progress",count _verified];
    if (_reason isNotEqualTo [] || {_name == ""}) exitWith {};
    _prep set ["phase","FUNCTION_BODY"];
    private _bodyAt = diag_tickTime;
    private _loaded = missionNamespace getVariable [_name,0];
    if (!(_loaded isEqualType {})) exitWith {_reason = ["FUNCTION_MISSING",_path,_name];};
    private _raw = str _loaded;
    private _saved = _bodies getOrDefault [_id,[]];
    if (_saved isNotEqualTo [] && {_raw isEqualTo (_saved # 0)}) then {
        _stats set [3,(_stats # 3)+1];
    } else {
        private _forms = if (_saved isEqualTo []) then {[]} else {_saved # 1};
        if (_forms isEqualTo []) then {
            private _text = if (_span isEqualTo []) then {preprocessFileLineNumbers _path} else {
                private _reviewed = (_pin # 6) joinString toString [10];
                _reviewed select [1,count _reviewed-2]
            };
            if (count _text > 20000) then {_reason = ["FUNCTION_LENGTH_LIMIT",_path,_name];} else {
                // Only the three existing inspected header forms; compile, never call.
                private _headers = ["",format ["private _fnc_scriptNameParent = if (isNil '_fnc_scriptName') then {'%1'} else {_fnc_scriptName}; private _fnc_scriptName = '%1'; scriptName _fnc_scriptName;",_name],
                    format ["private _fnc_scriptNameParent = if (isNil '_fnc_scriptName') then {'%1'} else {_fnc_scriptName}; scriptName '%1';",_name]];
                // Exact engine comparison normally avoids canonicalizing any expected form.
                _forms = _headers apply {str compile (_x+_text)};
            };
        };
        if (_forms findIf {_raw isEqualTo _x} < 0 && {_reason isEqualTo []}) then {
            private _body = [_raw] call _canonical;
            if (_forms findIf {([_x] call _canonical) isEqualTo _body} < 0 && {_reason isEqualTo []}) then {
                _reason = ["FUNCTION_BODY_UNQUALIFIED",_path,_name];
            };
        };
        if (_reason isEqualTo [] && {call _budget}) then {_bodies set [_id,[_raw,_forms]]; _stats set [2,(_stats # 2)+1];};
    };
    _costs set [1,(_costs # 1)+diag_tickTime-_bodyAt];
    if (!(call _budget)) exitWith {};
    (_p get "bindings") pushBackUnique [_name,str _loaded];
};
private _review = {
    params ["_path","_body","_native"];
    private _index = _callbacks findIf {(_x # 1) == _path && {(_x # 2) isEqualTo _body}};
    if (_index < 0) exitWith {["UNKNOWN_CALLBACK",_path,[_body] call _fingerprint]};
    private _row = _callbacks # _index;
    {[_x] call _verifyPin;} forEach (_row # 4);
    {(_p get "conditions") pushBackUnique _x;} forEach (_row # 3);
    if (_native && {!(_p get "cba")} && {_row # 0 == "ua_native"}) then {_reason = ["UA_REQUIRES_NATIVE_CBA_SERVICE",_path];};
    _reason
};
private _class = _arg;
private _dynamicBody = {
    params ["_d"];
    _d params ["_id","_baseClass","_event","_path","_marker","_function"];
    // Qualify this origin and shared dependencies before deriving/caching a body.
    [(_d # 6) # 0] call _verifyPin;
    if (!(call _budget)) exitWith {""};
    private _cached = _dynamicBodies get _id;
    if (!isNil "_cached") exitWith {_stats set [5,(_stats # 5)+1]; _cached};
    if (!(call _budget)) exitWith {""};
    private _dynamicAt = diag_tickTime;
    _prep set ["phase","DYNAMIC_BODY"]; _prep set ["item",_id];
    private _body = "";
    if (_function != "") then {
        private _f = missionNamespace getVariable [_function,0];
        if (_f isEqualType {}) then {_body = [str _f] call _canonical;};
    } else {
        private _text = _dynamicTexts get _path;
        if (isNil "_text") then {
            _text = [preprocessFileLineNumbers _path] call _canonical;
            if (_reason isEqualTo []) then {_dynamicTexts set [_path,_text];};
        };
        private _at = _text find _marker;
        if (_at >= 0) then {
            private _start = _at+count _marker;
            private _depth = 0;
            private _quoted = false;
            private _a = toArray _text;
            private _i = _start;
            while {_i < count _a && {_i-_start < 20000} && {call _budget}} do {
                private _c = _a # _i;
                if (_c == 34) then {
                    if (_quoted && {_a param [_i+1,-1] == 34}) then {_i = _i+1;} else {_quoted = !_quoted;};
                } else {
                    if (!_quoted) then {if (_c == 123) then {_depth = _depth+1;}; if (_c == 125) then {_depth = _depth-1;};};
                };
                _i = _i+1;
                if (_depth == 0) exitWith {_body = _text select [_start,_i-_start];};
            };
        };
    };
    if (_function == "" && {_body != ""} && {call _budget}) then {_dynamicBodies set [_id,_body]; _stats set [4,(_stats # 4)+1];};
    _costs set [2,(_costs # 2)+diag_tickTime-_dynamicAt];
    _body
};
private _cfg = configFile >> "CfgVehicles" >> _class;
private _classes = [_class];
private _crew = getText (_cfg >> "crew");
if (_crew != "") then {_classes pushBackUnique _crew;};
private _turrets = {
    params ["_node",["_depth",0]];
    {
        if (count _classes > 8 || {_depth > 16} || {!(call _budget)}) exitWith {_reason = ["TURRET_SCAN_LIMIT"];};
        private _gunner = getText (_x >> "gunnerType");
        if (_gunner != "") then {_classes pushBackUnique _gunner;};
        [_x >> "Turrets",_depth+1] call _turrets;
    } forEach ("true" configClasses _node);
};
[_cfg >> "Turrets"] call _turrets;
_p set ["classes",_classes];
if (count _classes > 8 || {_classes findIf {!isClass (configFile >> "CfgVehicles" >> _x)} >= 0}) then {
    _reason = ["CREW_CONFIG_UNQUALIFIED",_classes select [0,8]];
    _classes = _classes select [0,8]; _p set ["classes",_classes];
};
if (_p get "cba") then {
    {[_x] call _verifyPin;} forEach _dispatchPins;
    // These two functions are generated by the inspected preInit, not named files.
    {
        _x params ["_name","_body","_event"];
        private _actual = missionNamespace getVariable [_name,0];
        private _forms = [_body,"scriptName 'XEH:"+_event+"';"+_body] apply {[str compile _x] call _canonical};
        if (!(_actual isEqualType {}) || {!(([str _actual] call _canonical) in _forms)}) then {_reason = ["CBA_FORWARDER_UNQUALIFIED",_name];};
        (_p get "bindings") pushBack [_name,str _actual];
    } forEach [["cba_xeh_fnc_init","(_this select 0) call CBA_fnc_initEvents; (_this select 0) call CBA_fnc_init","Init"],
        ["cba_xeh_fnc_local","{call _x} forEach ((_this select 0) getVariable 'cba_xeh_Local')","Local"]];
    private _machine = missionNamespace getVariable ["SLX_XEH_MACHINE",[]];
    if (count _machine < 9 || {!(_machine # 8)}) then {_reason = ["CBA_POSTINIT_PENDING"];} ;
};
{
    if (!(call _budget)) exitWith {};
    private _specClass = _x;
    _prep set ["phase","CONFIG_REGISTRY"]; _prep set ["item",_specClass];
    // Effective inherited native EH leaves; unknown native init/local is never skipped.
    private _nativeScan = {
        params ["_node",["_depth",0]];
        if (_depth > 16 || {count _rows >= 256} || {diag_tickTime >= _until}) exitWith {
            if (_reason isEqualTo []) then {_reason = ["NATIVE_SCAN_LIMIT",_specClass,str _node];};
        };
        {
            if (!(call _budget)) exitWith {};
            if (isClass _x) then {[_x,_depth+1] call _nativeScan;} else {
                if (toLower configName _x in ["init","initpost","postinit","local"] && {isText _x}) then {
                    private _body = getText _x;
                    private _decision = "EMPTY";
                    if (_body != "") then {
                        private _forward = _body in ["call cba_xeh_fnc_init","call cba_xeh_fnc_local"];
                        if (_forward && {_p get "cba"}) then {_decision = "INSPECTED_FORWARDER";} else {
                            private _path = "native/"+toLower configName _x;
                            private _issue = [_path,_body,true] call _review;
                            _decision = ["REVIEWED_CONDITIONAL","REFUSED"] select (_issue isNotEqualTo []);
                            if (_issue isNotEqualTo [] && {_reason isEqualTo []}) then {_reason = _issue+[_specClass,str _x];};
                        };
                    };
                    [[_specClass,"NATIVE",str _x,[_body] call _fingerprint,_decision]] call _addRow;
                };
            };
        } forEach configProperties [_node,"true",true];
    };
    [configFile >> "CfgVehicles" >> _specClass >> "EventHandlers"] call _nativeScan;
    private _chain = [];
    private _node = configFile >> "CfgVehicles" >> _specClass;
    while {isClass _node && {count _chain < 64}} do {_chain pushBack configName _node; _node = inheritsFrom _node;};
    if (isClass _node) then {_reason = ["INHERITANCE_LIMIT",_specClass];};
    {
        if (!(call _budget)) exitWith {};
        _x params ["_route","_event","_entry"];
        private _candidates = [];
        {
            if (!(call _budget)) exitWith {};
            private _base = _x;
            {
                if (!(call _budget)) exitWith {};
                private _ancestor = _x;
                {
                    if (!(call _budget)) exitWith {};
                    private _eh = _x;
                    private _allow = !isNumber (_eh >> "scope") || {getNumber (_eh >> "scope") != 0};
                    private _excluded = getArray (_eh >> "exclude");
                    if (isText (_eh >> "exclude")) then {_excluded pushBack getText (_eh >> "exclude");};
                    private _applicable = (_allow || {_specClass == _ancestor}) && {_excluded findIf {_specClass isKindOf _x} < 0};
                    private _respawn = getNumber (_eh >> "onRespawn") == 1 && {_event != "local"};
                    if (isClass _eh) then {
                        {if (isText _x || {isNumber _x} || {isArray _x}) then {
                            if (!(toLower configName _x in [_entry,"client"+_entry,"server"+_entry])) then {
                                [[_specClass,_event,str _x,"METADATA","NOT_EXECUTABLE"]] call _addRow;
                            };
                        };} forEach configProperties [_eh];
                    };
                    {
                        _x params ["_field","_role"];
                        private _leaf = if (isClass _eh) then {_eh >> _field} else {_eh};
                        if (isText _leaf && {(isClass _eh) || {_role == "all"}}) then {
                            private _body = getText _leaf;
                            if (count _body > 20000) exitWith {_reason = ["CONFIG_CALLBACK_LENGTH_LIMIT",str _leaf];};
                            private _roleActive = _role == "all" || {_role == "client" && {!isDedicated}} || {_role == "server" && {isServer}};
                            private _path = _route+"/"+_ancestor+"/"+configName _eh;
                            if (isClass _eh) then {_path = _path+"/"+_field;};
                            private _code = _body+";";
                            if (_respawn) then {_code = _code+"(_this select 0) addEventHandler ['Respawn', "+str _code+"];";};
                            private _rowIndex = count _rows;
                            [[_specClass,_event,str _leaf,[_body] call _fingerprint,
                                ["INACTIVE_SCOPE_EXCLUDE_ROLE","CONFIG_CANDIDATE"] select (_applicable && {_roleActive}),_role,_respawn]] call _addRow;
                            if (_applicable && {_roleActive} && {_body != ""}) then {
                                if (_rowIndex < 256) then {_candidates pushBack [[str compile _code] call _canonical,_path,_body,_rowIndex];};
                            };
                        };
                    } forEach [[_entry,"all"],["client"+_entry,"client"],["server"+_entry,"server"]];
                } forEach configProperties [_base >> _route >> _ancestor];
            } forEach _chain;
        } forEach [configFile,campaignConfigFile,missionConfigFile];
        private _wanted = [];
        if (_p get "cba") then {
            {
                if (!(call _budget)) exitWith {};
                private _ancestor = _x;
                private _var = "cba_xeh_"+_event+":"+_ancestor;
                private _registered = missionNamespace getVariable [_var,[]];
                if (!(_registered isEqualType []) || {count _registered > 128}) then {_reason = ["REGISTRY_LIMIT_OR_TYPE",_specClass,_var];} else {
                    private _registryRaw = [_registered] call _registryText;
                    if ((_registryRaw select [0,1]) == "<") exitWith {_reason = ["REGISTRY_SHAPE_OR_LENGTH",_specClass,_var];};
                    if ((_p get "registries") findIf {(_x # 0) == _var} < 0) then {
                        _registryBytes = _registryBytes+count _registryRaw;
                        if (_registryBytes > 1000000) then {_reason = ["REGISTRY_STORAGE_LIMIT",_specClass,_var];} else {
                            (_p get "registries") pushBack [_var,_registryRaw];
                        };
                    };
                    {
                        if (!(call _budget)) exitWith {};
                        private _registrationIndex = _forEachIndex;
                        if (!(_x isEqualType []) || {count _x != 3}) then {_reason = ["REGISTRY_SHAPE",_specClass,_var];} else {
                            _x params ["_code","_inherit","_exclude"];
                            if (!(_code isEqualType {}) || {!(_inherit isEqualType true)} || {!(_exclude isEqualType [])}) then {_reason = ["REGISTRY_SHAPE",_specClass,_var];} else {
                                if ((_inherit || {_specClass == _ancestor}) && {_exclude findIf {_specClass isKindOf _x} < 0}) then {
                                    private _codeText = str _code;
                                    if (count _codeText > 20000) exitWith {_reason = ["CALLBACK_LENGTH_LIMIT",_specClass,_var,count _codeText];};
                                    private _canon = [_codeText] call _canonical;
                                    _wanted pushBack _codeText;
                                    private _match = _candidates findIf {(_x # 0) isEqualTo _canon};
                                    if (_match < 0) then {
                                        private _dyn = _dynamic findIf {(_x # 1) == _ancestor && {(_x # 2) == _event}
                                            && {fileExists (_x # 3)} && {([_x] call _dynamicBody) isEqualTo _canon}};
                                        if (_dyn < 0) then {
                                            private _identity = [_codeText] call _unmatchedIdentity;
                                            private _unmatched = [_specClass,_var,_registrationIndex,_identity,[count _codeText]];
                                            if ((_prep getOrDefault ["unmatched",[]]) isEqualTo []) then {_prep set ["unmatched",_unmatched];};
                                            if (_reason isEqualTo []) then {_reason = ["UNKNOWN_DYNAMIC_CALLBACK"]+_unmatched;};
                                            [[_specClass,_event,_var,[count _codeText],"REFUSED_DYNAMIC",_registrationIndex,_identity]] call _addRow;
                                        } else {
                                            private _d = _dynamic # _dyn;
                                            {[_x] call _verifyPin;} forEach (_d # 6);
                                            {(_p get "conditions") pushBackUnique _x;} forEach (_d # 7);
                                            [[_specClass,_event,_var,_d # 3,_d # 0,["REFUSED","REVIEWED_DYNAMIC"] select (_reason isEqualTo []),_registrationIndex]] call _addRow;
                                        };
                                    } else {
                                        private _candidate = _candidates # _match;
                                        private _issue = [_candidate # 1,_candidate # 2,false] call _review;
                                        (_rows # (_candidate # 3)) set [4,["REVIEWED_CONDITIONAL","REFUSED"] select (_issue isNotEqualTo [])];
                                        if (_issue isNotEqualTo [] && {_reason isEqualTo []}) then {
                                            private _unmatched = [_specClass,_var,_registrationIndex,["CONFIG_CANDIDATE",(_candidate # 1) select [0,160]],[count _codeText]];
                                            _prep set ["unmatched",_unmatched]; _reason = _issue+_unmatched;
                                        };
                                    };
                                };
                            };
                        };
                    } forEach _registered;
                };
            } forEach _chain;
        };
        (_p get "objectCallbacks") set [toLower _specClass+":"+_event,_wanted];
    } forEach [["Extended_Init_EventHandlers","init","init"],["Extended_InitPost_EventHandlers","initpost","init"],
        ["Extended_Local_EventHandlers","local","local"]];
} forEach _classes;
{
    private _prefix = _x;
    if ((["ACE_EFFECTS_UNDEFINED","CBA_EFFECTS_UNDEFINED"] # _forEachIndex) in (_p get "conditions")) then {
        private _effects = missionNamespace getVariable [_prefix+"_statusEffects",0];
        if (!(_effects isEqualType createHashMap) || {count _effects > 64}) then {_reason = ["STATUS_REGISTRY_UNQUALIFIED",_prefix];} else {
            private _keys = keys _effects;
            _keys sort true;
            _p set [_prefix,_keys];
            private _ready = missionNamespace getVariable [["ace_common_settingsInitFinished","cba_settings_ready"] # _forEachIndex,false];
            if (!_ready) then {_reason = ["STATUS_SETTINGS_PENDING",_prefix];};
        };
    };
} forEach ["ace_common","cba_statuseffects"];
if (count _rows > 256) then {_reason = ["INVENTORY_LIMIT",count _rows]; _p set ["rows",_rows select [0,256]];};
if (_reason isEqualTo [] && {call _budget}) then {
    _prep set ["phase","FINAL_BINDINGS_REGISTRIES"];
    private _issue = ["precreate",[_p,objNull]] call A3UE_FPV_QA_motionPolicy;
    if (_issue isNotEqualTo []) then {_reason = _issue;};
};
if (_reason isEqualTo [] && {call _budget}) then {
    // All reviewed immutable material is owned by this mission/process, one policy
    // identity only. Partial transactions are discarded. Live state is not cached.
    _p set ["material",createHashMapFromArray [
        ["identity",_identity],["sources",_sources],["bodies",_bodies],["dynamic",_dynamicBodies],["dynamicTexts",_dynamicTexts],
        ["canons",_canons],["canonBytes",_canonBytes]]];
};
_p set ["reason",_reason];
_p set ["ok",_reason isEqualTo []];
_p set ["admissionSeconds",diag_tickTime-(_p get "admissionStarted")];
_costs pushBack (0 max ((_p get "admissionSeconds")-(_costs # 0)-(_costs # 1)-(_costs # 2)));
_p set ["counts",_stats]; _p set ["costs",_costs];
_prep set ["kind",if ((_stats # 1)+(_stats # 3)+(_stats # 5) == 0) then {"COLD"} else {
    ["INCREMENTAL","WARM_REVALIDATION"] select ((_stats # 0)+(_stats # 2)+(_stats # 4) == 0)
}];
_p
