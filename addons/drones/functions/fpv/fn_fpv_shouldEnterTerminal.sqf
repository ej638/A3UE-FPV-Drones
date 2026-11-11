// Planning activation only. The controller requires a feasible checked corridor before handoff.
params [["_uav",objNull],["_target",objNull],["_profile",createHashMap]];
if (isNull _uav || {isNull _target}) exitWith {false};
private _limits = [_profile] call A3UE_fnc_fpv_trajectoryLimits;
private _speed = (vectorMagnitude (velocity _uav)) max (_limits # 0);
private _height = abs ((getPosASL _uav # 2) - (getPosASL _target # 2));
private _budget = 2 * _speed * _speed / (_limits # 3) + _speed * _speed / (2 * (_limits # 2))
    + _height * _speed / (_limits # 4) + 2 * _speed;
private _inRange = (_uav distance _target) <= ((_budget max 180) min 350);
// F4-1 (owner-local, read-only): approach-profile gates, and a drone that has just flown
// past its target turns back under native tracking before it re-enters the dive.
private _settings = call A3UE_fnc_fpv_attackSettings;
if (!_inRange || {!(_settings # 0)}) exitWith {_inRange};
private _relative = (getPosASL _uav) vectorDiff (getPosASL _target);
private _horizontal = sqrt (((_relative # 0) ^ 2) + ((_relative # 1) ^ 2));
private _missAt = _uav getVariable ["A3UE_FPV_attackLastMissAt", -1];
if (_missAt isEqualType 0 && {_missAt >= 0} && {time >= _missAt} && {time - _missAt < 10}) then {
    private _velocity = velocity _uav;
    private _flat = [_velocity # 0, _velocity # 1, 0];
    if (vectorMagnitude _flat > 3 && {_horizontal > 1}
        && {((vectorNormalized _flat) vectorDotProduct (vectorNormalized [-(_relative # 0), -(_relative # 1), 0])) < 0.3}) then {
        _inRange = false;
    };
};
if (!_inRange) exitWith {false};
private _engagement = [_uav, _target, +(_uav getVariable ["A3UE_FPV_controllerIdentity", []]), false] call A3UE_fnc_fpv_attackEngagement;
private _gate = if (_engagement isEqualTo []) then {true} else {
    switch (_engagement # 1) do {
        // Still on the flank leg: only a target that has come close cuts it short.
        case "FLANK": {(_engagement # 3) != "LEG" || {(vectorMagnitude _relative) <= 90}};
        // High enough: start the dive where it is steep but flyable; not high: dive late.
        case "HIGH_DIVE": {
            if ((_relative # 2) >= 25) then {
                _horizontal <= (((_relative # 2) / (tan ((_engagement # 2) # 1))) + 20)
            } else {
                _horizontal <= 110
            }
        };
        default {true};
    }
};
if (!_gate) exitWith {false};
// F4-2: beyond 60 m the dive waits for a clear line, so the drone keeps closing at its transit
// height over trees or a crest; inside 60 m the existing cover rules decide.
if ((_settings # 11) && {_horizontal > 60}) exitWith {[_uav, _target] call A3UE_fnc_fpv_attackClearLine};
true
