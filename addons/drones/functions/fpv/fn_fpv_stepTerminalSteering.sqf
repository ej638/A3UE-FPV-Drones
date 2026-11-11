// Pure logical-frame integration: m/s, m/s^2, simulation seconds, rad/s.
params ["_direction", "_up", "_speed", "_angularRate", "_aim", "_targetSpeed",
	"_accel", "_decel", "_blend", "_blendMax", "_dt", ["_rateLimit", -1], ["_slewLimit", -1]];

private _validNumber = {_this isEqualType 0 && {finite _this} && {abs _this <= 1e6}};
private _validVector = {
	_this isEqualType [] && {count _this == 3} && {(_this findIf {!(_x call _validNumber)}) < 0}
};
if (([_direction,_up,_angularRate,_aim] findIf {!(_x call _validVector)}) >= 0
	|| {([_speed,_targetSpeed,_accel,_decel,_blend,_blendMax,_dt,_rateLimit,_slewLimit] findIf {!(_x call _validNumber)}) >= 0}) exitWith {[]};
if (_speed < 0 || {_targetSpeed < 0} || {_accel < 0} || {_decel < 0} || {_dt < 0} || {_dt > 0.25}
	|| {_blend < 0} || {_blend > _blendMax} || {_blendMax > 1}
	|| {vectorMagnitude _direction < 1e-6} || {vectorMagnitude _up < 1e-6} || {vectorMagnitude _aim < 1e-6}) exitWith {[]};
_direction = vectorNormalized _direction;
_aim = vectorNormalized _aim;
_up = _up vectorDiff (_direction vectorMultiply (_up vectorDotProduct _direction));
if (vectorMagnitude _up < 1e-6) exitWith {[]};
_up = vectorNormalized _up;
if (_dt == 0) exitWith {[_direction, _up, _speed, +_angularRate, 0, 0]};

// SQF acos/sin/cos use degrees. All stored rotation rates/angles use radians.
private _alignment = ((_direction vectorDotProduct _aim) max -1) min 1;
private _angle = (acos _alignment) * (pi / 180);
private _rateMax = pi * (-(ln (1 - (_blendMax min 0.999999))) / 0.02);
if (_rateLimit >= 0) then {_rateMax = _rateMax min _rateLimit;};
if (vectorMagnitude _angularRate > _rateMax + 1e-6) exitWith {[]};
private _slewMax = 2 * _rateMax / 0.02;
if (_slewLimit >= 0) then {_slewMax = _slewLimit;};
private _fraction = 1 - ((1 - (_blend min 0.999999)) ^ (_dt / 0.02));
private _tangent = _aim vectorDiff (_direction vectorMultiply _alignment);
if (vectorMagnitude _tangent < 1e-6) then {_tangent = +_up;};
private _axis = vectorNormalized (_direction vectorCrossProduct (vectorNormalized _tangent));
private _requestedRate = _axis vectorMultiply ((_angle * _fraction / _dt) min _rateMax);
private _rateDelta = _requestedRate vectorDiff _angularRate;
private _deltaMagnitude = vectorMagnitude _rateDelta;
if (_deltaMagnitude > _slewMax * _dt && {_deltaMagnitude > 0}) then {
	_rateDelta = _rateDelta vectorMultiply (_slewMax * _dt / _deltaMagnitude);
};
private _nextRate = _angularRate vectorAdd _rateDelta;
// Convex slew from an admitted stored rate preserves the magnitude envelope.
private _rateMagnitude = vectorMagnitude _nextRate;
if (_rateMagnitude > _rateMax && {_rateMagnitude > 0}) then {
	_nextRate = _nextRate vectorMultiply (_rateMax / _rateMagnitude);
	_rateMagnitude = _rateMax;
};
private _turnAngle = _rateMagnitude * _dt;
if (_turnAngle > 0) then {
	_axis = _nextRate vectorMultiply (1 / _rateMagnitude);
	private _cosTurn = cos (_turnAngle * (180 / pi));
	private _sinTurn = sin (_turnAngle * (180 / pi));
	private _rotate = {
		params ["_v"];
		((_v vectorMultiply _cosTurn) vectorAdd ((_axis vectorCrossProduct _v) vectorMultiply _sinTurn)) vectorAdd
			(_axis vectorMultiply ((_axis vectorDotProduct _v) * (1 - _cosTurn)))
	};
	_direction = vectorNormalized ([_direction] call _rotate);
	_up = [_up] call _rotate;
};
_up = vectorNormalized (_up vectorDiff (_direction vectorMultiply (_up vectorDotProduct _direction)));
private _deltaSpeed = ((_targetSpeed - _speed) max (-_decel * _dt)) min (_accel * _dt);
[_direction, _up, _speed + _deltaSpeed, _nextRate, _deltaSpeed / _dt, _turnAngle]
