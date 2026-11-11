private _s = missionNamespace getVariable ["A3UE_F2RA",createHashMap];
if (_s getOrDefault ["state",""] != "PREPARING" || {_s getOrDefault ["cancel",false]}) exitWith {diag_log ["F2R_PREP","WRAPPER_IDENTITY_OR_PHASE"]; false};
// QA extraction: docs\experiments\crocus-at-policy-20261026\commands\04-target-setup.sqf; scheduled local caller.

if (!isServer || {isRemoteExecuted} || {worldName != "vt7"}) exitWith {};
if (!isNull (missionNamespace getVariable ["A3UE_FPV_QA_target", objNull])
    || {!isNull (missionNamespace getVariable ["A3UE_POLICY_target", objNull])}) exitWith {
    diag_log "Policy setup blocked: previous target remains";
};
if (isNil "A3UE_POLICY_savedObserver" || {profileName != "EJ_FPV_QA"}
    || {missionNamespace getVariable ["A3UE_FPV_debug", false]}
    || {isNil "A3UE_FPV_QA_dispatch"}
    || {!(missionNamespace getVariable ["serverInitDone", false])}
    || {!(missionNamespace getVariable ["A3UE_FPV_registrationComplete", false])}) exitWith {
    diag_log "Policy setup BLOCKED: fresh QA readiness/observer required";
};
private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState", createHashMap];
if ((count _cap > 0 && {!(_cap getOrDefault ["exported", false])})
    || {((values (missionNamespace getVariable ["A3UE_FPV_QA_runs", createHashMap]))
        findIf {!(_x getOrDefault ["cleaned", false])}) >= 0}) exitWith {
    diag_log "Policy setup BLOCKED: prior capture/run unfinished";
};
private _class = "O_Crocus_AT";
private _descriptor = [_class, "armafpv", "AT", east] call A3UE_fnc_fpv_getClassDescriptor;
if (!isClass (configFile >> "CfgVehicles" >> "I_MRAP_03_F")
    || {!(_descriptor getOrDefault ["canDetonate", false])}) exitWith {
    diag_log "Policy setup blocked: required target or drone class unavailable";
};
private _pos = missionNamespace getVariable ["A3UE_FPV_QA_targetPos", []];
if (count _pos != 3) exitWith {diag_log "Policy setup blocked: range position missing";};
private _nearby = (_pos nearEntities [["CAManBase", "LandVehicle", "Air", "Ship"], 150]) select {alive _x};
if (_nearby isNotEqualTo []) exitWith {diag_log "Policy setup blocked: occupied range";};
private _vehicle = objNull;
isNil {
_vehicle = createVehicle ["I_MRAP_03_F", _pos, [], 0, "CAN_COLLIDE"];
if (isNull _vehicle) exitWith {diag_log "Policy target creation failed";};
A3UE_POLICY_target = _vehicle;
A3UE_POLICY_targetId = netId _vehicle;
A3UE_POLICY_crew = [];
A3UE_POLICY_groups = [];
A3UE_POLICY_crewIds = [];
_s set ["aId",netId _vehicle];
_s set ["aRoster",[_vehicle,[],[],[]]];
};
if (isNull _vehicle) exitWith {};
_vehicle setDir 0;
_vehicle allowDamage true;
createVehicleCrew _vehicle;
private _until = diag_tickTime + 8;
waitUntil {sleep 0.05; !isNull driver _vehicle || {diag_tickTime >= _until}};
{
    A3UE_POLICY_crew pushBackUnique _x;
    private _group = group _x;
    A3UE_POLICY_groups pushBackUnique _group;
    _group deleteGroupWhenEmpty true;
    _group setCombatMode "BLUE";
    removeAllWeapons _x;
    _x setCaptive false;
    _x allowDamage true;
    _x setBehaviour "CARELESS";
    _x disableAI "PATH";
    _x disableAI "AUTOCOMBAT";
    _x disableAI "TARGET";
    _x disableAI "AUTOTARGET";
} forEach crew _vehicle;
_vehicle engineOn false;
A3UE_POLICY_crewIds = A3UE_POLICY_crew apply {netId _x};
A3UE_POLICY_class = _class;
A3UE_POLICY_baseline = [damage _vehicle, getAllHitPointsDamage _vehicle,
    A3UE_POLICY_crew apply {[netId _x, alive _x, damage _x]}];
A3UE_FPV_QA_origin = (getPosATL _vehicle) getPos [600, 0];
A3UE_FPV_QA_origin set [2, 45];
private _eligible = !isNull ([_vehicle, [east] call A3UE_fnc_fpv_getHostileSides] call A3UE_fnc_fpv_filterTarget);
private _result = [
    ["target", netId _vehicle], ["targetClass", typeOf _vehicle],
    ["alive", alive _vehicle], ["damageAllowed", isDamageAllowed _vehicle],
    ["damage", damage _vehicle], ["crewFields", ["id", "side", "alive", "damageAllowed", "captive", "damage"]],
    ["crew", (crew _vehicle) apply {[netId _x, str side group _x, alive _x, isDamageAllowed _x, captive _x, damage _x]}],
    ["droneClass", _class], ["ammo", _descriptor getOrDefault ["ammoClass", ""]],
    ["eligibleForEast", _eligible], ["launchATL", A3UE_FPV_QA_origin],
    ["crewStationaryBits", A3UE_POLICY_crew apply {[netId _x, _x checkAIFeature "PATH", _x checkAIFeature "AUTOCOMBAT", weapons _x]}]
];
{diag_log ["PB01", "POLICY_TARGET_READY", _forEachIndex, _x];} forEach _result;
diag_log str _result;
