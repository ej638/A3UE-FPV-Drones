// Existing controller only: bounded scheduled planning, then original-identity atomic cache commit.
params ["_uav", "_target", "_profile", "_generation", "_controllerIdentity"];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {[-2,"ACCESS"]};
if (isNull _uav || {isNull _target} || {!([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate)}) exitWith {[-2,"AUTHORITY"]};
private _keyNow = {
    [+_controllerIdentity,_target,_uav getVariable ["A3UE_FPV_targetNetId",""],
        [_uav getVariable ["A3UE_FPV_siteEpoch",""],_uav getVariable ["A3UE_FPV_siteMarker",""],_uav getVariable ["A3UE_FPV_siteSide",sideUnknown]],
        ["TARGET",_target,_uav getVariable ["A3UE_FPV_targetRevision",0]],
        _uav getVariable ["A3UE_FPV_supportName",""],_uav getVariable ["A3UE_FPV_rivalEventId",""]]
};
private _navigation = [_uav,_target,_controllerIdentity] call A3UE_fnc_fpv_targetNavigation;
if (_navigation isEqualTo []) exitWith {[-2,"TARGET_CHANGED"]};
// F4-1 pilot model moves only the steering point/velocity; the key is unchanged.
_navigation = [_uav,_target,_controllerIdentity,_navigation] call A3UE_fnc_fpv_attackNavigation;
private _key = _navigation # 0;
private _mode = _uav getVariable ["A3UE_FPV_mode",""];
private _before = _uav getVariable ["A3UE_FPV_trajectory",[]];
private _at = time;
private _observed = diag_tickTime;
private _lastAttempt = _uav getVariable ["A3UE_FPV_trajectoryAttemptAt",-1];
private _surface = +(_navigation # 3);
private _cached = count _before == 7 && {(_before # 0) isEqualTo _key}
    && {_at >= (_before # 1)} && {_at - (_before # 1) < 0.2}
    && {_observed >= (_before # 2)} && {_observed - (_before # 2) <= 0.5}
    && {(_surface vectorDistance (_before # 4)) <= 8};
if (_cached) exitWith {[1,"CACHED",_before,_lastAttempt,_key]};
// Changed intent is immediately ineligible; never reuse a plan from another target revision.
if (_lastAttempt >= 0 && {_at >= _lastAttempt} && {_at - _lastAttempt < 0.2}) exitWith {[0,"PLAN_DUE",_before,_lastAttempt,_key]};
// Reserve before queries. Even a preempted/rejected plan cannot increase query cadence.
private _reserved = false;
isNil {
    if ([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate
        && {(_uav getVariable ["A3UE_FPV_mode",""]) == _mode}
        && {(call _keyNow) isEqualTo _key}
        && {(_uav getVariable ["A3UE_FPV_trajectory",[]]) isEqualTo _before}
        && {(_uav getVariable ["A3UE_FPV_trajectoryAttemptAt",-1]) == _lastAttempt}) then {
        _uav setVariable ["A3UE_FPV_trajectoryAttemptAt",_at];
        _reserved = true;
    };
};
if (!_reserved) exitWith {[-2,"STALE"]};
private _limits = [_profile] call A3UE_fnc_fpv_trajectoryLimits;
// F4-2 flip envelope (pull-up and over the top); unchanged outside a flip.
_limits = [_uav,_target,_controllerIdentity,_profile,_limits] call A3UE_fnc_fpv_attackLimits;
private _position = getPosASL _uav;
private _velocity = velocity _uav;
private _speed = vectorMagnitude _velocity;
private _direction = if (_speed >= 0.01) then {vectorNormalized _velocity} else {vectorDir _uav};
private _steering = _uav getVariable ["A3UE_FPV_terminalSteeringState",[]];
if (_mode == "TERMINAL_VECTOR" && {count _steering == 12}) then {
    private _stateKey = _steering # 0;
    if (count _stateKey == 9
        && {[_stateKey # 0,_stateKey # 1,_stateKey # 2,_stateKey # 4,_stateKey # 6,_stateKey # 7,_stateKey # 8] isEqualTo _key}
        && {([_steering,_stateKey,_at,_observed,(missionNamespace getVariable ["A3UE_FPV_loadTolerantDive", true]) isNotEqualTo false]
            call A3UE_fnc_fpv_terminalSteeringStatus) # 0 in ["STEP","DUPLICATE","LATE"]}) then {
        _direction = +(_steering # 3);
        _speed = _speed max (_steering # 5);
    };
};
private _surfaceVelocity = +(_navigation # 4);
private _plan = [_position,_direction,_speed,_surface,_surfaceVelocity,_limits] call A3UE_fnc_fpv_planTrajectory;
// Commitment permits navigation through occlusion. Payload geometry is evaluated
// separately; no object/terrain/clearance query can veto this target-derived plan.
private _result = [-2,"STALE"];
isNil {
    if (!([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate)
        || {!([_uav,_generation] call A3UE_fnc_fpv_hasCurrentLifecycle)}
        || {(_uav getVariable ["A3UE_FPV_controllerGeneration",-1]) != _generation}
        || {!alive _target} || {objectFromNetId (netId _target) isNotEqualTo _target}
        || {(_uav getVariable ["A3UE_FPV_targetNetId",""]) != netId _target}
        || {(_uav getVariable ["A3UE_FPV_mode",""]) != _mode}
        || {!((call _keyNow) isEqualTo _key)}
        || {!((_uav getVariable ["A3UE_FPV_trajectory",[]]) isEqualTo _before)}
        || {(_uav getVariable ["A3UE_FPV_trajectoryAttemptAt",-1]) != _at}
        || {!((_uav getVariable ["A3UE_FPV_terminalSteeringState",[]]) isEqualTo _steering)}
        || {([_uav] call A3UE_fnc_fpv_resolveTarget) isNotEqualTo _target}
        || {time < _at} || {time - _at > 0.1} || {diag_tickTime < _observed} || {diag_tickTime - _observed > 0.5}
        || {(_uav getVariable ["A3UE_FPV_linkModel","RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState","OK"]) == "EW_DENIED"}}) exitWith {};
    private _committed = if (_plan # 0) then {[_key,_at,_observed,_position,_surface,_surfaceVelocity,_plan]} else {[]};
    _uav setVariable ["A3UE_FPV_navigation",_navigation];
    _uav setVariable ["A3UE_FPV_trajectory",_committed];
    _uav setVariable ["A3UE_FPV_trajectoryReason",_plan # 7];
    _result = [if (_plan # 0) then {1} else {-1},_plan # 7,_committed,_at,_key];
};
_result
