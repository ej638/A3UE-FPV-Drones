// Pure curve/direct continuation within the existing writer. SI, simulation dt.
// Returns [integrator step, desired direction, desired speed, used continuation].
params ["_state", "_follow", "_position", "_point", "_velocity", "_actualSpeed", "_limits", "_dt"];
private _direction = _state # 3;
private _speed = _state # 5;
private _rate = _state # 6;
private _continuation = _follow isEqualTo [];
private _direct = {
    private _range = _position vectorDistance _point;
    private _lead = ((_range / (_speed max 4)) min 1.5) min (25 / ((vectorMagnitude _velocity) max 0.01));
    private _delta = (_point vectorAdd (_velocity vectorMultiply _lead)) vectorDiff _position;
    // Coincident point: retain finite travel for this instant; fuse is independent.
    if (vectorMagnitude _delta < 0.01) exitWith {[+_direction,_speed]};
    private _aim = vectorNormalized _delta;
    // Project requested descent, never clip the inherited real velocity/attitude.
    private _zLimit = ((_limits # 4) / (_speed max (_limits # 0) max 1)) min 1;
    if (abs (_aim # 2) > _zLimit) then {
        private _horizontal = [_aim # 0,_aim # 1,0];
        if (vectorMagnitude _horizontal < 1e-6) then {_horizontal = [_direction # 0,_direction # 1,0];};
        if (vectorMagnitude _horizontal < 1e-6) then {_horizontal = [1,0,0];};
        _aim = (vectorNormalized _horizontal) vectorMultiply (sqrt (1 - _zLimit * _zLimit));
        _aim set [2, (if ((_delta # 2) < 0) then {-1} else {1}) * _zLimit];
    };
    private _angle = (acos (((_direction vectorDotProduct _aim) max -1) min 1)) * pi / 180;
    private _wanted = (_limits # 0) min (((_limits # 3) / (_angle max 0.01)) max 4);
    // Inherited descent/overspeed converges by the authored deceleration, not a snap.
    _wanted = _wanted min ((_limits # 4) / ((abs (_direction # 2)) max (abs (_aim # 2)) max 0.01));
    [_aim,_wanted]
};
private _drive = if (_continuation) then {call _direct} else {[_follow # 0,_follow # 1]};
private _integrate = {
    private _storedRate = vectorMagnitude _rate;
    private _speedForTurn = if (_storedRate > 1e-6) then {(_limits # 3) / _storedRate} else {1e5};
    private _wanted = (_drive # 1) min (_actualSpeed + (_limits # 9)) min _speedForTurn;
    private _ceiling = _speed max (_speed + (((_wanted - _speed) max (-(_limits # 2) * _dt)) min ((_limits # 1) * _dt)));
    private _rateLimit = ((_limits # 5) min ((_limits # 3) / (_ceiling max 1))) max (_storedRate min ((_limits # 5) + 1e-6));
    private _step = [_direction,_state # 4,_speed,_rate,_drive # 0,_wanted,
        _limits # 1,_limits # 2,0.18,0.35,_dt,_rateLimit,_limits # 6] call A3UE_fnc_fpv_stepTerminalSteering;
    [_step,+(_drive # 0),_wanted,_continuation]
};
private _result = call _integrate;
// A feasible curve can become unfollowable after real drift. Converge with the same
// integrator instead of refusing every tick above the provisional descent ceiling.
if (!_continuation && {!((_result # 0) isEqualTo [])}
    && {abs ((_result # 0 # 0 # 2) * (_result # 0 # 2)) > (_limits # 4) + 0.1}) then {
    _continuation = true;
    _drive = call _direct;
    _result = call _integrate;
};
_result
