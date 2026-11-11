// Pure profile boundary. Existing authored speeds/acceleration are km/h and km/h/s.
params [["_profile", createHashMap]];
// LT-2: inside one controller tick (one drone, one profile) the limits are worked out once
// (tick memo; a dive pass asked for them three times). Callers only read the array;
// attackLimits copies it before changing anything. Outside a tick every call is live.
if (!isNil "_fpvTick" && {"trajectoryLimits" in _fpvTick}) exitWith {_fpvTick get "trajectoryLimits"};
private _family = _profile getOrDefault ["familyId", ""];
private _familyLimits = switch (_family) do {
    case "armafpv": {[24,10,12,0.8]};
    case "kvn": {[22,9,10,0.75]};
    default {[20,8,9,0.7]};
};
private _read = {
    params ["_name", "_fallback"];
    private _value = [_profile, _name, _fallback] call A3UE_fnc_fpv_profileValue;
    if (!(_value isEqualType 0) || {!finite _value} || {_value <= 0} || {_value > 1000}) then {_value = _fallback;};
    _value / 3.6
};
// F4-1 committed attack run (E3 on the current writer): a per-family/role dive envelope,
// blended by A3UE_FPV_attackSpeedScale (0 = F2C-L ceilings, 1 = reviewed table, max 1.5).
// The master switch A3UE_FPV_attackRun = false restores the F2C-L boundary exactly.
private _scale = missionNamespace getVariable ["A3UE_FPV_attackSpeedScale", 1];
if (!(_scale isEqualType 0) || {!finite _scale}) then {_scale = 1;};
_scale = (_scale max 0) min 1.5;
if !((missionNamespace getVariable ["A3UE_FPV_attackRun", true]) isEqualTo true) then {_scale = 0;};
private _limits = call {
if (_scale <= 0) exitWith {
// cruise, acceleration, deceleration, lateral acceleration, descent, turn, rate slew,
// lookahead seconds, clearance metres, actual-speed lag allowance (all SI).
[(_familyLimits # 0) min (["trackingSpeed",90] call _read) min (["terminalVectorMaxSpeed",120] call _read),
    ["terminalVectorAccel",24] call _read, ["terminalVectorDecel",30] call _read,
    _familyLimits # 1, _familyLimits # 2, _familyLimits # 3, 3, 0.6, 3,
    ["terminalVectorSpeedLagTolerance",6] call _read]
};
// Dive speed AP/AT (m/s; provisional F3-design targets, judged by eye), lateral
// acceleration (m/s^2), descent (m/s), turn (rad/s), committed acceleration (m/s^2).
// The dive may exceed the approach (trackingSpeed); the airframe/doctrine terminal cap stays.
private _at = (_profile getOrDefault ["roleId", ""]) == "AT";
private _attack = switch (_family) do {
    case "armafpv": {[[34,32] select _at, 14, 24, 1.0, 12]};
    case "kvn": {[[30,28] select _at, 11, 21, 0.85, 9]};
    default {[[28,26] select _at, 12, 19.6, 0.9, 10]};
};
private _blend = {params ["_from", "_to"]; _from + (_to - _from) * _scale};
[([_familyLimits # 0, _attack # 0] call _blend) min (["terminalVectorMaxSpeed",120] call _read),
    (["terminalVectorAccel",24] call _read) max ((_attack # 4) * (_scale min 1)),
    ["terminalVectorDecel",30] call _read,
    [_familyLimits # 1, _attack # 1] call _blend, [_familyLimits # 2, _attack # 2] call _blend,
    [_familyLimits # 3, _attack # 3] call _blend, 3, 0.6, 3,
    ["terminalVectorSpeedLagTolerance",6] call _read]
};
if (!isNil "_fpvTick") then {_fpvTick set ["trajectoryLimits", _limits];};
_limits
