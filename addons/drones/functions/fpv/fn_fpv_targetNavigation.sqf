// Current target geometry only: no sensing, memory lease or payload permission.
// [authority/intent key, simulation time, observation time, point ASL, velocity, pass reference ASL]
params ["_uav", "_target", "_controllerIdentity"];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {[]};
if (isNull _uav || {isNull _target} || {!alive _target}
    || {(_uav getVariable ["A3UE_FPV_targetNetId",""]) != netId _target}
    || {([_uav] call A3UE_fnc_fpv_resolveTarget) isNotEqualTo _target}) exitWith {[]};
private _vector = {_this isEqualType [] && {count _this == 3} && {(_this findIf {!(_x isEqualType 0) || {!finite _x} || {abs _x > 1e6}}) < 0}};
private _reference = getPosASL _target;
private _velocity = velocity _target;
if (!(_reference call _vector) || {!(_velocity call _vector)}) exitWith {[]};
private _offset = switch (true) do {
    case (_target isKindOf "Man"): {1.15};
    case (_target isKindOf "Air"): {0};
    case (_target isKindOf "StaticWeapon"): {0.9};
    default {1.2};
};
_reference = _reference vectorAdd [0,0,_offset];
private _point = +_reference;
private _impact = _uav getVariable ["A3UE_FPV_lastImpactPointASL",[]];
private _impactAt = _uav getVariable ["A3UE_FPV_lastImpactTelemetryAt",-1];
if (_uav getVariable ["A3UE_FPV_lastImpactValid",false]
    && {(_uav getVariable ["A3UE_FPV_lastImpactTargetNetId",""]) == netId _target}
    && {(_uav getVariable ["A3UE_FPV_terminalImpactMode","NONE"]) in ["DIRECT_BODY","DIRECT_HULL","DIRECT_STATIC","AIR_PROXIMITY"]}
    && {_impact call _vector} && {time >= _impactAt} && {time - _impactAt <= 0.25}) then {_point = +_impact;};
private _key = [+_controllerIdentity,_target,netId _target,
    [_uav getVariable ["A3UE_FPV_siteEpoch",""],_uav getVariable ["A3UE_FPV_siteMarker",""],_uav getVariable ["A3UE_FPV_siteSide",sideUnknown]],
    ["TARGET",_target,_uav getVariable ["A3UE_FPV_targetRevision",0]],_uav getVariable ["A3UE_FPV_supportName",""],_uav getVariable ["A3UE_FPV_rivalEventId",""]];
[_key,time,diag_tickTime,_point,_velocity,_reference]
