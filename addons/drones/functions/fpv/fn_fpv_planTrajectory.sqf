// Pure quadratic corridor and conservative interval envelope. SI throughout.
// Return [admitted, points[9], speedCaps[9], length, endpoint, leadTime, maxCurvature, reason].
params ["_position", "_direction", "_speed", "_surface", "_targetVelocity", "_limits"];
private _bad = {params ["_why"]; [false,[],[],0,[],0,0,_why]};
private _number = {_this isEqualType 0 && {finite _this} && {abs _this <= 1e6}};
private _vector = {_this isEqualType [] && {count _this == 3} && {(_this findIf {!(_x call _number)}) < 0}};
if (([_position,_direction,_surface,_targetVelocity] findIf {!(_x call _vector)}) >= 0
    || {!(_speed call _number)} || {_speed < 0}
    || {!(_limits isEqualType [])} || {count _limits != 10}
    || {(_limits findIf {!(_x call _number) || {_x <= 0}}) >= 0}) exitWith {["INPUT"] call _bad};
if (vectorMagnitude _direction < 1e-6) exitWith {["DIRECTION"] call _bad};
_direction = vectorNormalized _direction;
_limits params ["_cruise", "_accel", "_decel", "_lateral", "_descent", "_turn"];
private _range = _position vectorDistance _surface;
if (_range < 0.1) exitWith {["AT_SURFACE"] call _bad};
// Finite target-relative lead; tends continuously to zero at contact.
private _targetSpeed = vectorMagnitude _targetVelocity;
private _lead = ((_range / (_speed max 4)) min 1.5) min (25 / (_targetSpeed max 0.01));
private _end = _surface vectorAdd (_targetVelocity vectorMultiply _lead);
private _chord = _end vectorDiff _position;
private _distance = vectorMagnitude _chord;
if (_distance < 0.1) exitWith {["AT_SURFACE"] call _bad};
private _forward = _direction vectorDotProduct (vectorNormalized _chord);
if (_forward <= 0.15) exitWith {["SETUP_HEADING"] call _bad};
// Half-chord handle gives an exactly straight path for aligned entry. No height overlay.
private _control = _position vectorAdd (_direction vectorMultiply (_distance * 0.5));
private _d0 = (_control vectorDiff _position) vectorMultiply 2;
private _d1 = (_end vectorDiff _control) vectorMultiply 2;
private _dd = _d1 vectorDiff _d0;
private _dd2 = _dd vectorDotProduct _dd;
private _cross = vectorMagnitude (_d0 vectorCrossProduct _d1);
private _points = [];
private _caps = [];
private _physicalCaps = [];
private _length = 0;
private _maxCurvature = 0;
private _valid = true;
for "_i" from 0 to 8 do {
    private _t = _i / 8;
    private _a = 1 - _t;
    private _p = ((_position vectorMultiply (_a * _a)) vectorAdd (_control vectorMultiply (2 * _a * _t))) vectorAdd (_end vectorMultiply (_t * _t));
    if (_i > 0) then {_length = _length + (_p vectorDistance (_points # (_i - 1)));};
    _points pushBack _p;
    _caps pushBack _cruise;
    _physicalCaps pushBack 1e5;
};
for "_i" from 0 to 7 do {
    private _lo = _i / 8;
    private _hi = (_i + 1) / 8;
    private _closest = if (_dd2 > 1e-8) then {((-(_d0 vectorDotProduct _dd) / _dd2) max _lo) min _hi} else {_lo};
    private _minDerivative = vectorMagnitude (_d0 vectorAdd (_dd vectorMultiply _closest));
    if (_minDerivative < 0.01) then {_valid = false;} else {
        // For a quadratic, |B' cross B''| is constant: this bounds the ENTIRE interval.
        private _curvature = _cross / (_minDerivative ^ 3);
        _maxCurvature = _maxCurvature max _curvature;
        private _maxVertical = (abs ((_d0 vectorAdd (_dd vectorMultiply _lo)) # 2)) max (abs ((_d0 vectorAdd (_dd vectorMultiply _hi)) # 2));
        private _slope = (_maxVertical / _minDerivative) min 1;
        private _cap = 1e5;
        if (_curvature > 1e-6) then {_cap = (sqrt (_lateral / _curvature)) min (_turn / _curvature);};
        if (_slope > 1e-6) then {_cap = _cap min (_descent / _slope);};
        { _caps set [_x, (_caps # _x) min _cap]; _physicalCaps set [_x, (_physicalCaps # _x) min _cap]; } forEach [_i, _i + 1];
    };
};
if (!_valid || {(selectMin _caps) < 4}) exitWith {["CURVATURE_OR_DESCENT"] call _bad};
// Braking reachability, using polyline length (<= true arc length, hence conservative).
for "_i" from 7 to 0 step -1 do {
    private _ds = (_points # _i) vectorDistance (_points # (_i + 1));
    _caps set [_i, (_caps # _i) min (sqrt ((_caps # (_i + 1)) ^ 2 + 2 * _decel * _ds))];
    _physicalCaps set [_i, (_physicalCaps # _i) min (sqrt ((_physicalCaps # (_i + 1)) ^ 2 + 2 * _decel * _ds))];
};
// Overspeed above cruise can decelerate; overspeed above geometric feasibility cannot.
if (_speed > (_physicalCaps # 0) + 0.25) exitWith {["ENTRY_SPEED"] call _bad};
[true,_points,_caps,_length,_end,_lead,_maxCurvature,"FEASIBLE"]
