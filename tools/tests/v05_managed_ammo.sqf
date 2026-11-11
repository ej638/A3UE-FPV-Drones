// Read-only engine regression: merged managed AT contract and cached selection.
// Run locally after AU readiness, once per process/cold-start preset/mod order.
// Physical effects, native coexistence and actual AU routes require the V05 card.
if (isRemoteExecuted) exitWith {diag_log "[A3UE FPV TEST V05] BLOCKED local execution required";};
private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
private _cases = 0;
private _failures = 0;
private _atClasses = [];
private _check = {
    params ["_case", "_ok"];
    _cases = _cases + 1;
    if (!_ok) then {_failures = _failures + 1;};
    diag_log format ["[A3UE FPV TEST V05] case=%1 pass=%2", _case, _ok];
};
private _contracts = [
    ["A3UE_FPV_AT", "M_Vorona_HEAT", [
        ["explosive", 0.8], ["hit", 150], ["htMax", 1800], ["htMin", 60],
        ["indirectHit", 25], ["indirectHitRange", 3.5], ["warheadName", "TandemHEAT"],
        ["submunitionAmmo", "A3UE_FPV_AT_Penetrator"], ["submunitionDirectionType", "SubmunitionModelDirection"],
        ["submunitionInitSpeed", 1000], ["submunitionParentSpeedCoef", 0],
        ["submunitionInitialOffset", [0, 0, -0.1]], ["submunitionConeType", ["random", 1]],
        ["submunitionConeAngle", 0], ["submunitionConeAngleHorizontal", 0],
        ["triggerTime", -1], ["triggerDistance", -1], ["triggerOnImpact", 1],
        ["fuseDistance", 0], ["deleteParentWhenTriggered", 0], ["timeToLive", 5]
    ]],
    ["A3UE_FPV_AT_Penetrator", "ammo_Penetrator_Vorona", [
        ["hit", 480], ["indirectHit", 0], ["indirectHitRange", 0],
        ["warheadName", "TandemHEAT"], ["timeToLive", 1]
    ]]
];
{
    _x params ["_class", "_base", "_fields"];
    private _cfg = configFile >> "CfgAmmo" >> _class;
    [format ["owned class/base %1", _class], isClass _cfg && {configName (inheritsFrom _cfg) == _base}] call _check;
    {
        _x params ["_field", "_expected"];
        private _entry = _cfg >> _field;
        private _actual = if (_expected isEqualType []) then {getArray _entry} else {
            if (_expected isEqualType "") then {getText _entry} else {getNumber _entry}
        };
        private _ok = if (_expected isEqualType 0) then {isNumber _entry && {abs (_actual - _expected) < 0.0001}} else {
            if (_expected isEqualType []) then {isArray _entry && {_actual isEqualTo _expected}} else {isText _entry && {_actual == _expected}}
        };
        [format ["merged %1/%2 actual=%3", _class, _field, _actual], _ok] call _check;
    } forEach _fields;
} forEach _contracts;
// Capture inherited physical fields for comparison; a declaration dump is not a merged config.
private _captureFields = ["simulation", "model", "hit", "indirectHit", "indirectHitRange", "explosive", "caliber",
    "explosionEffects", "CraterEffects", "effectsMissile", "effectsMissileInit", "soundHit", "soundFly",
    "warheadName", "timeToLive", "fuseDistance", "initTime", "thrust", "thrustTime", "airFriction", "typicalSpeed",
    "submunitionAmmo", "submunitionDirectionType", "submunitionInitSpeed", "submunitionParentSpeedCoef",
    "submunitionInitialOffset", "submunitionConeType", "submunitionConeAngle", "submunitionConeAngleHorizontal",
    "triggerTime", "triggerDistance", "triggerOnImpact", "deleteParentWhenTriggered"];
{
    private _class = _x;
    private _cfg = configFile >> "CfgAmmo" >> _class;
    private _fields = _captureFields apply {
        private _entry = _cfg >> _x;
        [_x, if (isArray _entry) then {getArray _entry} else {
            if (isText _entry) then {getText _entry} else {if (isNumber _entry) then {getNumber _entry} else {"ABSENT"}}
        }]
    };
    diag_log ["A3UE FPV TEST V05", "MERGED", _class, isClass _cfg, configName (inheritsFrom _cfg), _fields];
} forEach ["A3UE_FPV_AT", "A3UE_FPV_AT_Penetrator", "FPV_RPG42_AT", "FPV_RPG42_AT_Penetrator",
    "M_Vorona_HEAT", "ammo_Penetrator_Vorona"];
{
    private _familyId = _x;
    {
        private _class = _x;
        private _desc = _y;
        if !((_desc get "physicalPayload") in ["AT", "PG7VL"]) then {continue;};
        _atClasses pushBackUnique _class;
        {
            private _role = _x;
            private _resolved = [_class, _familyId, _role] call A3UE_fnc_fpv_getClassDescriptor;
            [format ["owned AT selection %1/%2/%3", _familyId, _class, _role], count _resolved > 0
                && {(_resolved get "ammoClass") == "A3UE_FPV_AT"}
                && {(_resolved get "ammoCandidates") isEqualTo ["A3UE_FPV_AT"]}] call _check;
        } forEach (_desc get "taskRoles");
    } forEach (_y get "classDescriptors");
} forEach _catalog;
diag_log format ["[A3UE FPV TEST V05] END cases=%1 failures=%2 atClasses=%3 families=%4; physical/native/AU evidence NOT RUN",
    _cases, _failures, count _atClasses, keys _catalog];
if (_atClasses isEqualTo []) then {diag_log "[A3UE FPV TEST V05] NO AT SAMPLES: valid P0 config-only check, P1-P7 BLOCKED";};
