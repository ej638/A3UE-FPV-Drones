// F2C-L presentation attitude for the terminal pose writer (field finding FS-01).
// Pure math: no engine reads or writes. The logical steering basis is untouched,
// so trajectory, speed, fuse and contact are exactly the F2C values.
// Units: _rate rad/s (axis * magnitude), _speed m/s, _dt simulation seconds since
// the previous presentation write, bank and limits in degrees.
// The airframe up vector is rebuilt every write from the world horizon (no
// parallel transport, so roll cannot accumulate), plus a bounded coordinated-turn
// bank. A roll guard limits rotation about the nose so heading flips near
// vertical cannot snap the airframe.
// Returns [_up, [_heading2D, _bankDeg, _up]] or [] on invalid input.
params ["_dir", "_rate", "_speed", ["_previous", []], ["_dt", 0]];

private _validVector = {
	_this isEqualType [] && {count _this == 3}
		&& {(_this findIf {!(_x isEqualType 0) || {!finite _x} || {abs _x > 1e6}}) < 0}
};
if (!(_dir call _validVector) || {!(_rate call _validVector)} || {vectorMagnitude _dir < 1e-6}
	|| {!(_speed isEqualType 0)} || {!finite _speed} || {_speed < 0}
	|| {!(_dt isEqualType 0)} || {!finite _dt}) exitWith {[]};

private _bankMax = 30;
private _bankRate = 90;
private _rollGuardRate = 360;
private _dtUsed = (_dt max 0) min 0.25;
_dir = vectorNormalized _dir;

// Previous state is advisory; any malformed entry means a fresh, level start.
private _prevHeading = [];
private _prevBank = 0;
private _prevUp = [];
if (_previous isEqualType [] && {count _previous == 3}) then {
	_previous params [["_h", []], ["_b", 0], ["_u", []]];
	if (_h isEqualType [] && {count _h == 2} && {(_h findIf {!(_x isEqualType 0) || {!finite _x}}) < 0}
		&& {abs (((_h # 0) ^ 2 + (_h # 1) ^ 2) - 1) < 0.01}
		&& {_b isEqualType 0} && {finite _b} && {abs _b <= _bankMax + 0.001}
		&& {_u call _validVector} && {vectorMagnitude _u > 1e-6}) then {
		_prevHeading = +_h;
		_prevBank = _b;
		_prevUp = vectorNormalized _u;
	};
};

// Horizontal heading. Near vertical the heading is undefined: keep the last one.
private _horizontal = sqrt (((_dir # 0) ^ 2) + ((_dir # 1) ^ 2));
private _heading = switch (true) do {
	case (_horizontal >= 0.05): {[(_dir # 0) / _horizontal, (_dir # 1) / _horizontal]};
	case (_prevHeading isNotEqualTo []): {_prevHeading};
	case (_horizontal > 1e-9): {[(_dir # 0) / _horizontal, (_dir # 1) / _horizontal]};
	default {[0, 1]};
};
private _right = [_heading # 1, -(_heading # 0), 0];
private _levelUp = _right vectorCrossProduct _dir;
if (vectorMagnitude _levelUp < 1e-6) exitWith {[]};
_levelUp = vectorNormalized _levelUp;
_right = vectorNormalized (_dir vectorCrossProduct _levelUp);

// Coordinated-turn bank from the commanded lateral acceleration (rate x velocity).
private _lateral = _speed * ((_rate vectorCrossProduct _dir) vectorDotProduct _right);
private _bankTarget = ((_lateral atan2 9.81) max -_bankMax) min _bankMax;
private _bank = 0;
if (_prevUp isNotEqualTo []) then {
	private _bankStep = _bankRate * _dtUsed;
	_bank = _prevBank + (((_bankTarget - _prevBank) max -_bankStep) min _bankStep);
};
private _targetUp = (_levelUp vectorMultiply (cos _bank)) vectorAdd (_right vectorMultiply (sin _bank));

// Roll guard about the nose. Ordinary dives track the target exactly.
private _up = _targetUp;
if (_prevUp isNotEqualTo []) then {
	private _carried = _prevUp vectorDiff (_dir vectorMultiply (_prevUp vectorDotProduct _dir));
	if (vectorMagnitude _carried > 1e-6) then {
		_carried = vectorNormalized _carried;
		private _roll = ((_carried vectorCrossProduct _targetUp) vectorDotProduct _dir) atan2 (_carried vectorDotProduct _targetUp);
		private _rollStep = _rollGuardRate * _dtUsed;
		if (abs _roll > _rollStep) then {
			private _applied = (_roll max -_rollStep) min _rollStep;
			_up = (_carried vectorMultiply (cos _applied)) vectorAdd ((_dir vectorCrossProduct _carried) vectorMultiply (sin _applied));
		};
	};
};
_up = _up vectorDiff (_dir vectorMultiply (_up vectorDotProduct _dir));
if (vectorMagnitude _up < 1e-6) exitWith {[]};
_up = vectorNormalized _up;
[_up, [_heading, _bank, +_up]]
