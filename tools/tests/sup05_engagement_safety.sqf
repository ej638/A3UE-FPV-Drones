// STRUCTURAL engine fixture: real spatial/crew checks, synthetic visibility and membership.
// Disposable ready server-local AU campaign, recompile enabled; restart afterward.
// Never substitutes for actual AU routes, payload/flight or multiplayer evidence.
// Optional commit case needs an enabled FPV payload class; a safety regression can create a real explosion.
if (!isServer || {isRemoteExecuted}) exitWith {diag_log "[A3UE FPV TEST SUP-05] BLOCKED: server-local only";};
if (isFinal A3UE_fnc_fpv_isTargetObstructed) exitWith {diag_log "[A3UE FPV TEST SUP-05] BLOCKED: immutable visibility helper";};
private _side = Occupants;
private _hostiles = [_side] call A3UE_fnc_fpv_getHostileSides;
if (_hostiles isEqualTo []) exitWith {diag_log "[A3UE FPV TEST SUP-05] BLOCKED: no hostile side";};
private _savedVisibility = A3UE_fnc_fpv_isTargetObstructed;
private _savedRegistry = missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap];
private _groups = [_side, _hostiles # 0, civilian] apply {createGroup [_x, true]};
private _pos = [50000, 50000, 0];
private _request = _pos vectorAdd [500, 0, 0];
private _target = (_groups # 1) createUnit ["B_Soldier_F", _pos, [], 0, "NONE"];
private _friendly = (_groups # 0) createUnit ["B_Soldier_F", _request, [], 0, "NONE"];
private _civilian = (_groups # 2) createUnit ["C_man_1", _request, [], 0, "NONE"];
private _captive = (_groups # 1) createUnit ["B_Soldier_F", _request, [], 0, "NONE"];
private _replacement = (_groups # 1) createUnit ["B_Soldier_F", _pos vectorAdd [300, 0, 0], [], 0, "NONE"];
private _vehicle = createVehicle ["C_Offroad_01_F", _pos, [], 0, "NONE"];
private _uav = createVehicle ["B_UAV_01_F", _pos vectorAdd [0, 0, 40], [], 0, "NONE"];
private _objects = [_target, _friendly, _civilian, _captive, _replacement, _vehicle, _uav];
{_x enableSimulationGlobal false; _x allowDamage false;} forEach _objects;
private _plan = createHashMapFromArray [["safetyRadius", 40]];
private _cases = 0;
private _failures = 0;
private _blockedCases = 0;
private _assert = {
    params ["_case", "_ok"];
    _cases = _cases + 1;
    if (!_ok) then {_failures = _failures + 1;};
    diag_log format ["[A3UE FPV TEST SUP-05] STRUCTURAL case=%1 pass=%2", _case, _ok];
};
isNil {
    private _blocked = false;
    A3UE_fnc_fpv_isTargetObstructed = {createHashMapFromArray [["blocked", _blocked]]};
    _uav setVariable ["A3UE_FPV_managed", true];
    _uav setVariable ["A3UE_FPV_supportSafetyRadius", 40];
    _uav setVariable ["A3UE_FPV_supportSide", _side];
    _uav setVariable ["A3UE_FPV_targetSide", _hostiles # 0];
    _uav setVariable ["A3UE_FPV_targetNetId", netId _target];
    _uav setVariable ["A3UE_FPV_controllerGeneration", 1];
    ["clear actual target despite blocked request center", [_side, _target, _request, _plan] call A3UE_fnc_fpv_supportPassesSafetyRing] call _assert;
    _friendly setPosATL (_pos vectorAdd [3, 0, 0]);
    ["offset request cannot hide actual friendly", !([_side, _target, _request, _plan] call A3UE_fnc_fpv_supportPassesSafetyRing)] call _assert;
    ["initial protected engagement reason", ([_uav, _target, true] call A3UE_fnc_fpv_supportEngagementReason) == "UNSAFE_ENGAGEMENT"] call _assert;
    _friendly setPosATL _request;
    ["safe target permission", ([_uav, _target, true] call A3UE_fnc_fpv_supportEngagementReason) == ""] call _assert;
    _civilian setPosATL (_pos vectorAdd [4, 0, 0]);
    ["moving civilian blocks", !([_side, _target, _request, _plan] call A3UE_fnc_fpv_supportPassesSafetyRing)] call _assert;
    _civilian setPosATL _request;
    _captive setCaptive true;
    _captive setPosATL (_pos vectorAdd [5, 0, 0]);
    ["captive bystander protected", !([_side, _target, _request, _plan] call A3UE_fnc_fpv_supportPassesSafetyRing)] call _assert;
    _captive setPosATL _request;
    _target setCaptive true;
    ["captive target loses authorization", ([_uav, _target, true] call A3UE_fnc_fpv_supportEngagementReason) == "TARGET_CHANGED"] call _assert;
    _target setCaptive false;
    _target moveInDriver _vehicle;
    ["boarding invalidates old infantry identity", ([_uav, _target, true] call A3UE_fnc_fpv_supportEngagementReason) == "TARGET_CHANGED"] call _assert;
    ["resolver normalizes occupied vehicle", ([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _vehicle] call _assert;
    _uav setVariable ["A3UE_FPV_targetNetId", netId _vehicle];
    ["normalized vehicle can be authorized", ([_uav, _vehicle, true] call A3UE_fnc_fpv_supportEngagementReason) == ""] call _assert;
    _friendly moveInCargo _vehicle;
    ["hostile driver cannot hide friendly passenger", !([_side, _vehicle, _request, _plan] call A3UE_fnc_fpv_supportPassesSafetyRing)] call _assert;
    moveOut _friendly; _friendly setPosATL _request;
    moveOut _target; _target setPosATL _pos;
    ["empty target loses authorization", ([_uav, _vehicle, true] call A3UE_fnc_fpv_supportEngagementReason) == "TARGET_CHANGED"] call _assert;
    _uav setVariable ["A3UE_FPV_targetNetId", netId _replacement];
    _friendly setPosATL ((getPosATL _replacement) vectorAdd [2, 0, 0]);
    ["replacement is checked at its actual position", ([_uav, _replacement, true] call A3UE_fnc_fpv_supportEngagementReason) == "UNSAFE_ENGAGEMENT"] call _assert;
    _friendly setPosATL _request;
    ["safe replacement permission", ([_uav, _replacement, true] call A3UE_fnc_fpv_supportEngagementReason) == ""] call _assert;
    _uav setVariable ["A3UE_FPV_targetNetId", netId _target];
    _blocked = true;
    ["terminal visibility failure is explicit", ([_uav, _target, true] call A3UE_fnc_fpv_supportEngagementReason) == "NO_VISIBLE_TARGET"] call _assert;
    ["tracking can transit before visibility boundary", ([_uav, _target, false] call A3UE_fnc_fpv_supportEngagementReason) == ""] call _assert;
    _blocked = false;
    _uav setVariable ["A3UE_FPV_engagementPermissionCache", []];
    _friendly setPosATL (_pos vectorAdd [3, 0, 0]);
    private _smallPolicy = createHashMapFromArray [["safetyRadius", 1], ["side", _side], ["targetSide", _hostiles # 0]];
    [_uav, _target, false, [], false, _smallPolicy] call A3UE_fnc_fpv_supportEngagementReason;
    ["permission cache cannot cross policy radius", ([_uav, _target, false] call A3UE_fnc_fpv_supportEngagementReason) == "UNSAFE_ENGAGEMENT"] call _assert;
    _friendly setPosATL _request;
    ["missing target is never authorized", ([_uav, objNull, true] call A3UE_fnc_fpv_supportEngagementReason) == "TARGET_CHANGED"] call _assert;
    ["fresh delivery-position ring blocks offset payload", ([_uav, _target, true, _request] call A3UE_fnc_fpv_supportEngagementReason) == "UNSAFE_ENGAGEMENT"] call _assert;
    _friendly setPosATL (_pos vectorAdd [80, 0, 0]);
    _uav setVariable ["A3UE_FPV_safetyCandidateCache", []];
    [_side, _target, _pos, _plan, _uav] call A3UE_fnc_fpv_supportPassesSafetyRing;
    private _cache = _uav getVariable ["A3UE_FPV_safetyCandidateCache", []];
    _friendly setPosATL (_pos vectorAdd [4, 0, 0]);
    ["cached candidates use current position", !([_side, _target, _pos, _plan, _uav] call A3UE_fnc_fpv_supportPassesSafetyRing)] call _assert;
    ["cache hit retains discovery object", (_uav getVariable "A3UE_FPV_safetyCandidateCache") isEqualRef _cache] call _assert;
    _friendly setPosATL _request;
    _civilian setPosATL (_pos vectorAdd [4, 0, 0]);
    ["fresh final check catches entrant outside cached list", ([_uav, _target, true] call A3UE_fnc_fpv_supportEngagementReason) == "UNSAFE_ENGAGEMENT"] call _assert;
    _civilian setPosATL _request;
    _uav setVariable ["A3UE_FPV_controllerGeneration", 2];
    [_side, _target, _pos, _plan, _uav] call A3UE_fnc_fpv_supportPassesSafetyRing;
    ["ownership generation refreshes discovery", ((_uav getVariable "A3UE_FPV_safetyCandidateCache") # 5) == 2] call _assert;
    _target setPosATL (_pos vectorAdd [20, 0, 0]);
    [_side, _target, _pos, _plan, _uav] call A3UE_fnc_fpv_supportPassesSafetyRing;
    ["target movement refreshes discovery center", ((_uav getVariable "A3UE_FPV_safetyCandidateCache") # 1) isEqualTo getPosATL _target] call _assert;
    _target setPosATL _pos;
    _uav setVariable ["A3UE_FPV_engagementBlockedAt", serverTime - 16];
    ["elapsed hold cannot authorize a safe target", ([_uav, _target, true] call A3UE_fnc_fpv_supportEngagementReason) == "UNSAFE_ENGAGEMENT"] call _assert;
    _uav setVariable ["A3UE_FPV_engagementBlockedAt", -1];
    _uav setVariable ["A3UE_FPV_engagementAborted", true];
    ["aborted episode cannot restart after handoff", ([_uav, _target, true] call A3UE_fnc_fpv_supportEngagementReason) == "UNSAFE_ENGAGEMENT"] call _assert;
    _uav setVariable ["A3UE_FPV_engagementAborted", false];
    _uav setVariable ["A3UE_FPV_supportSafetyRadius", 0];
    ["explicit zero radius preserves non-avoidance policy", ([_uav, objNull, true] call A3UE_fnc_fpv_supportEngagementReason) == ""] call _assert;
    _uav setVariable ["A3UE_FPV_supportSafetyRadius", nil];
    ["site and Rivals drones do not acquire support policy", ([_uav, objNull, true] call A3UE_fnc_fpv_supportEngagementReason) == ""] call _assert;
    // This subcase needs a real supported payload class: vanilla rejects before safety.
    // Catalog/descriptor/registration/commit remain production functions.
    private _specimen = [];
    {
        private _family = _x;
        {
            private _desc = _y;
            private _roles = _desc getOrDefault ["taskRoles", []];
            if (_specimen isEqualTo [] && {_desc getOrDefault ["canDetonate", false]}
                && {(_desc getOrDefault ["ammoClass", ""]) != ""} && {_roles isNotEqualTo []}) then {
                _specimen = [_x, _family, _roles # 0];
            };
        } forEach (_y getOrDefault ["classDescriptors", createHashMap]);
    } forEach (missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap]);
    if (_specimen isEqualTo []) then {
        _blockedCases = _blockedCases + 1;
        diag_log "[A3UE FPV TEST SUP-05] BLOCKED commit recheck: enabled supported FPV class/ammo required; spatial cases remain separate";
    } else {
        private _commitUav = createVehicle [_specimen # 0, _pos vectorAdd [0,0,40], [], 0, "NONE"];
        _objects pushBack _commitUav;
        _commitUav enableSimulationGlobal false;
        _commitUav allowDamage false;
        _commitUav setVariable ["A3UE_FPV_managed", true];
        _commitUav setVariable ["A3UE_FPV_vendorId", _specimen # 1];
        _commitUav setVariable ["A3UE_FPV_payloadRole", _specimen # 2];
        _commitUav setVariable ["A3UE_FPV_targetNetId", netId _target];
        _commitUav setVariable ["A3UE_FPV_netId", netId _commitUav];
        private _name = format ["QA_SUP05_%1", diag_tickTime];
        private _life = [_commitUav, true, _name] call A3UE_fnc_fpv_registerLifecycle;
        if (_life < 0) then {
            ["registered supported commit specimen", false] call _assert;
        } else {
            private _entry = createHashMapFromArray [["status", "active"], ["side", _side], ["targetSide", _hostiles # 0],
                ["safetyRadius", 40], ["drones", [_commitUav]], ["droneNetIds", [netId _commitUav]]];
            A3UE_FPV_supportRegistry = createHashMapFromArray [[_name, _entry]];
            private _strike = createHashMapFromArray [["uavNetId", netId _commitUav], ["targetNetId", netId _target],
                ["deliveryPosASL", getPosASL _target], ["deliveryDir", [1, 0, 0]], ["deliveryUp", [0, 0, 1]],
                ["detonationReason", "DIRECT_CONTACT"], ["fallbackReason", "NONE"]];
            _friendly setPosATL (_pos vectorAdd [3, 0, 0]);
            private _accepted = [_commitUav, _life, _strike] call A3UE_fnc_fpv_commitDetonation;
            ["server rechecks held doctrine despite absent owner radius", !_accepted && {(_commitUav getVariable ["A3UE_FPV_engagementFailureReason", ""]) == "UNSAFE_ENGAGEMENT"}] call _assert;
            ["rejected proposal creates no success or outcome", alive _commitUav && {!(_commitUav getVariable ["A3UE_FPV_detonationCommitted", false])}
                && {(_entry get "status") == "active"} && {!("droneOutcomes" in _entry)}] call _assert;
            // Detach synthetic membership before restoring the original campaign registry.
            private _record = A3UE_FPV_lifecycles get str _life;
            _record set ["managed", false]; _record set ["support", ""];
            [_life, "retire"] call A3UE_fnc_fpv_endLifecycle;
            A3UE_FPV_lifecycles deleteAt str _life;
        };
    };
    A3UE_fnc_fpv_isTargetObstructed = _savedVisibility;
    A3UE_FPV_supportRegistry = _savedRegistry;
    // Remove managed tag to avoid lifecycle bookkeeping on synthetic membership.
    _uav setVariable ["A3UE_FPV_managed", false];
};
{deleteVehicle _x;} forEach _objects;
{deleteGroup _x;} forEach _groups;
private _result = ["PASS", "BLOCKED"] select (_blockedCases > 0);
if (_failures > 0) then {_result = "FAIL";};
diag_log format ["[A3UE FPV TEST SUP-05] END result=%1 cases=%2 failures=%3; STRUCTURAL ONLY blocked=%4; restart", _result, _cases, _failures, _blockedCases];
