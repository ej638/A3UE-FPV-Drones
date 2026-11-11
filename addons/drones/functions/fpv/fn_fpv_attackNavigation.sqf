// F4-1 pilot model on the terminal aim point. Wraps the existing navigation tuple: only
// the steering point (#3) and its velocity (#4) change. Key (#0), clocks (#1, #2) and the
// true target reference (#5, used for pass and miss distances) are returned unchanged.
// - Pilot reaction: the target is re-sampled every 0.25-0.4 s and dead-reckoned between
//   samples, so a late change of direction is seen late (earned dodges, no dice).
// - Correction weave: the aim is rotated by a sampled, converging yaw/pitch error.
// - Outcome intent: in the final window the aim blends to the pass intent point.
// Disabled, not terminal, air target or no current pass: the input tuple, unchanged.
// [uav, target, controllerIdentity, navigation] -> navigation
params [["_uav", objNull], ["_target", objNull], ["_controllerIdentity", []], ["_navigation", []]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {_navigation};
if (!(_navigation isEqualType []) || {count _navigation != 6}) exitWith {_navigation};
private _settings = call A3UE_fnc_fpv_attackSettings;
if (!(_settings # 0) || {(_uav getVariable ["A3UE_FPV_mode", ""]) != "TERMINAL_VECTOR"} || {_target isKindOf "Air"}) exitWith {_navigation};
// F4-2 flip in progress (attackReversal): pull up ahead of the drone, then turn over the top
// straight onto the target. No weave, intent or lift until the return pass begins.
private _flip = _uav getVariable ["A3UE_FPV_attackReversal", createHashMap];
if ((_settings # 10) && {_flip isEqualType createHashMap} && {(_flip getOrDefault ["phase", ""]) in ["PULL", "OVER"]}
	&& {(_flip getOrDefault ["key", []]) isEqualTo [+_controllerIdentity, netId _target,
		_uav getVariable ["A3UE_FPV_targetRevision", 0], _uav getVariable ["A3UE_FPV_terminalVectorEnteredAt", -1]]}) exitWith {
	if ((_flip get "phase") == "PULL") then {
		[_navigation # 0, _navigation # 1, _navigation # 2,
			((getPosASL _uav) vectorAdd ((_flip get "heading") vectorMultiply 6)) vectorAdd [0, 0, 30], [0, 0, 0], _navigation # 5]
	} else {
		[_navigation # 0, _navigation # 1, _navigation # 2, +(_navigation # 5), +(_navigation # 4), _navigation # 5]
	}
};
private _pass = [_uav, _target, _controllerIdentity, _settings] call A3UE_fnc_fpv_attackPass;
if (count _pass == 0) exitWith {_navigation};
private _now = time;
// One evaluation per simulation instant: repeated calls within one tick agree exactly.
if ((_pass get "memoAt") == _now && {(_pass get "memoKey") isEqualTo (_navigation # 0)}) exitWith {+(_pass get "memo")};
private _uavPos = getPosASL _uav;
private _uavVelocity = velocity _uav;
private _livePos = getPosASL _target;
private _liveVelocity = _navigation # 4;
private _error = [0, 0, 0];
private _velocityEstimate = +_liveVelocity;
if (_settings # 3) then {
	private _sampledAt = _pass get "sampleAt";
	if (_sampledAt < 0 || {_now >= (_pass get "nextSampleAt")} || {_now < _sampledAt} || {_now - _sampledAt > 1}) then {
		private _rng = ((1597 * (_pass get "rng")) + 51) mod 4096;
		_pass set ["rng", _rng];
		_pass set ["sampleAt", _now];
		_pass set ["samplePos", +_livePos];
		_pass set ["sampleVel", +_liveVelocity];
		_pass set ["nextSampleAt", _now + 0.25 + 0.15 * (_rng / 4096)];
	};
	private _estimate = (_pass get "samplePos") vectorAdd ((_pass get "sampleVel") vectorMultiply (_now - (_pass get "sampleAt")));
	_error = _estimate vectorDiff _livePos;
	if (vectorMagnitude _error > 8) then {_error = (vectorNormalized _error) vectorMultiply 8;};
	_velocityEstimate = +(_pass get "sampleVel");
};
private _base = (_navigation # 3) vectorAdd _error;
// With the contact fuse, a resolved ground solution is flown at rather than overflown.
private _groundSolution = false;
if ((_settings # 6) && {(_uav getVariable ["A3UE_FPV_terminalImpactMode", "NONE"]) == "GROUND_NEAR_TARGET"}
	&& {_uav getVariable ["A3UE_FPV_lastImpactValid", false]}
	&& {(_uav getVariable ["A3UE_FPV_lastImpactTargetNetId", ""]) == netId _target}) then {
	private _impact = _uav getVariable ["A3UE_FPV_lastImpactPointASL", []];
	private _impactAt = _uav getVariable ["A3UE_FPV_lastImpactTelemetryAt", -1];
	if (_impact isEqualType [] && {count _impact == 3} && {_now >= _impactAt} && {_now - _impactAt <= 0.25}) then {
		_base = _impact vectorAdd _error;
		_groundSolution = true;
	};
};
private _toBase = _base vectorDiff _uavPos;
private _flat = [_toBase # 0, _toBase # 1, 0];
private _flatRange = vectorMagnitude _flat;
private _frame = _pass get "frame";
// Line-of-sight frame; frozen inside 8 m so it cannot flip while passing the target.
if (_flatRange >= 8 || {_frame isEqualTo []}) then {
	private _los = [0, 1, 0];
	if (_flatRange > 0.01) then {_los = _flat vectorMultiply (1 / _flatRange);} else {
		private _heading = [_uavVelocity # 0, _uavVelocity # 1, 0];
		if (vectorMagnitude _heading > 0.01) then {_los = vectorNormalized _heading;};
	};
	_frame = [_los, [_los # 1, -(_los # 0), 0]];
	_pass set ["frame", _frame];
};
_frame params ["_los", "_side"];
private _range = vectorMagnitude _toBase;
private _closing = if (_range > 0.01) then {((_uavVelocity vectorDiff _velocityEstimate) vectorDotProduct _toBase) / _range} else {0};
private _timeToGo = if (_closing > 1) then {_range / _closing} else {99};
private _window = _pass get "envelope";
private _offset = [_pass get "segTimes", _pass get "segYaw", _pass get "segPitch", 0.35,
	_now - (_pass get "start"), _timeToGo, _settings # 2, _window # 0, _window # 1] call A3UE_fnc_fpv_attackAimOffset;
_offset params ["_yaw", "_pitch", "_envelope"];
private _lateral = _flatRange * (tan _yaw);
private _vertical = _flatRange * (tan _pitch);
if (_vertical < 0) then {
	// A downward correction never takes the aim below 0.6 m above the terrain.
	private _room = (_base # 2) - ((getTerrainHeightASL [_base # 0, _base # 1]) + 0.6);
	_vertical = _vertical max ((-_room) min 0);
};
private _weave = (_base vectorAdd (_side vectorMultiply _lateral)) vectorAdd [0, 0, _vertical];
private _feet = _livePos vectorAdd _error;
private _goal = +_base;
if (!_groundSolution) then {
	switch (_pass get "intent") do {
		case "GROUND_SHORT": {
			_goal = _feet vectorAdd (_los vectorMultiply (-(_pass get "groundDist")));
			_goal set [2, getTerrainHeightASL [_goal # 0, _goal # 1]];
		};
		case "GROUND_SIDE": {
			_goal = _feet vectorAdd (_side vectorMultiply ((_pass get "groundSide") * (_pass get "groundDist")));
			_goal set [2, getTerrainHeightASL [_goal # 0, _goal # 1]];
		};
		case "OVER": {
			// Near miss: just over the head (TOP) or just beside it (SIDE), 1.5-3 m beyond along
			// the drone's own heading, so the pass carries on instead of descending behind it.
			private _ahead = [_uavVelocity # 0, _uavVelocity # 1, 0];
			_ahead = if (vectorMagnitude _ahead > 1) then {vectorNormalized _ahead} else {_los};
			_goal = ((_feet vectorAdd [0, 0, 1.85 + (_pass get "overClear")]) vectorAdd (_ahead vectorMultiply (_pass get "overLead")))
				vectorAdd ([-(_ahead # 1), _ahead # 0, 0] vectorMultiply (_pass getOrDefault ["overSide", 0]));
		};
	};
};
private _aim = (_weave vectorMultiply _envelope) vectorAdd (_goal vectorMultiply (1 - _envelope));
// F4-2 obstacle lift: the pilot hops over a tree, building or crest in the dive path. A look
// along the velocity (2.5 s, short of the target, 10 Hz) finds the first obstacle that is not
// the target's own surroundings (objects within 12 m and the ground within 30 m of it stay with
// the cover and fuse rules); the aim then goes 5 m over its top until the drone is past it.
if (_settings # 11) then {
	if (_now >= (_pass getOrDefault ["liftNextAt", -1]) || {_now < (_pass getOrDefault ["liftCheckedAt", -1])}) then {
		_pass set ["liftCheckedAt", _now];
		_pass set ["liftNextAt", _now + 0.1];
		private _speed = vectorMagnitude _uavVelocity;
		private _targetRange = _uavPos vectorDistance (_navigation # 5);
		private _look = ((_speed * 2.5) min (_targetRange - 10)) min 80;
		if (_speed > 5 && {_look > 8} && {_targetRange > 25}) then {
			private _dir = _uavVelocity vectorMultiply (1 / _speed);
			private _found = [_uav, _target, _uavPos, _uavPos vectorAdd (_dir vectorMultiply _look), false, true] call A3UE_fnc_fpv_obstacleProbe;
			if (_found isNotEqualTo []) then {
				private _hitPos = _found # 0;
				if (((_hitPos distance2D (_navigation # 5)) > ([12, 30] select (isNull (_found # 2))))
					&& {(_uavPos vectorDistance _hitPos) < (_targetRange - 8)}) then {
					private _flatDir = [_dir # 0, _dir # 1, 0];
					if (vectorMagnitude _flatDir > 0.01) then {_flatDir = vectorNormalized _flatDir;};
					private _lift = _hitPos vectorAdd (_flatDir vectorMultiply 6);
					_lift set [2, (_found # 1) + 5];
					if ((_pass getOrDefault ["lift", []]) isEqualTo []) then {_pass set ["lifts", (_pass getOrDefault ["lifts", 0]) + 1];};
					_pass set ["lift", _lift];
					_pass set ["liftUntil", _now + 3];
				};
			};
		};
	};
	private _lift = _pass getOrDefault ["lift", []];
	if (_lift isNotEqualTo []) then {
		if (_now >= (_pass getOrDefault ["liftUntil", -1])
			|| {((_lift vectorDiff _uavPos) vectorDotProduct [_uavVelocity # 0, _uavVelocity # 1, 0]) <= 0}) then {
			_pass set ["lift", []];
		} else {
			_aim = +_lift;
			_velocityEstimate = [0, 0, 0];
		};
	};
};
// Pass statistics against the true target, for the RPT summary only. The closest approach is
// taken on the straight segment between samples (about 3 m apart at dive speed), so a near
// miss reports how close it really came, not the nearest sample.
private _relative = _uavPos vectorDiff (_navigation # 5);
private _distance = vectorMagnitude _relative;
private _previous = _pass getOrDefault ["previousRelative", []];
if (_previous isNotEqualTo [] && {(_now - (_pass getOrDefault ["previousAt", -1])) <= 0.5} && {_now > (_pass getOrDefault ["previousAt", -1])}) then {
	private _segment = _relative vectorDiff _previous;
	private _length2 = _segment vectorDotProduct _segment;
	if (_length2 > 1e-6) then {
		private _u = (((-(_previous vectorDotProduct _segment)) / _length2) max 0) min 1;
		_distance = _distance min (vectorMagnitude (_previous vectorAdd (_segment vectorMultiply _u)));
	};
};
_pass set ["previousRelative", _relative];
_pass set ["previousAt", _now];
if (_distance < (_pass get "closest")) then {_pass set ["closest", _distance];};
_pass set ["maxSpeed", (_pass get "maxSpeed") max (vectorMagnitude _uavVelocity)];
private _result = [_navigation # 0, _navigation # 1, _navigation # 2, _aim, _velocityEstimate, _navigation # 5];
_pass set ["memoAt", _now];
_pass set ["memoKey", +(_navigation # 0)];
_pass set ["memo", +_result];
_result
