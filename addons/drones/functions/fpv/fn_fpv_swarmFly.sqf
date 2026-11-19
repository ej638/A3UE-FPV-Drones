// 1.0.9 friendly FPV swarm (SW-1d): one step of the swarm's own cruise (owner = server, one
// unscheduled slice, every frame under the frame director), for the flight in and every run-in.
// SW1c: Arma's helicopter AI overshot short run-ins by hundreds of metres, took 20-60 s to turn back,
// flew faster than its limit and twice flew away from its orders into an enemy SAM. So the swarm
// flies itself from launch until it circles, and in every run-in; the AI keeps the loiter ring and
// the way out. No trajectory planner: a heading, a speed and a climb rate.
// - Heading: turns towards the point at most "runTurn" deg/s (level turns only, never a loop), at a
//   horizontal speed that changes at most "accel" m/s2 towards the drone's own speed (SW-1e: each
//   drone flies at "runSpeed" times its style's factor). SW-1f (EJ after SW1e: "an abrupt turn"):
//   the turn rate builds at "turnAccel" deg/s2 and eases out onto the new heading, at most
//   "latAccel" m/s2 sideways at the speed flown; more than "brakeTurn" deg to turn and the drone
//   slows to "turnSpeed" m/s first, as a pilot brakes into a turn.
// - Height: the point's own, never below "floorAGL" over the ground under the drone or 2 s ahead of
//   it, at most "climb" m/s up or down.
// - Look-ahead, 10 Hz: one ray along the next 2 s of the path (swarmClear; the drone and its target
//   ignored). Something in the way (a mast, a tower, a hillside): climb hard for 2 s.
// - Writes: velocity every step; attitude through swarmPose (the D1 cadence, the nose down with speed),
//   the same writer as the dive, so nothing jumps when the dive begins (SW-1e).
// - The logical heading and speeds are kept between steps (never re-read from the airframe while it
//   flies); a step integrates at most 0.25 s; after a gap of more than 1 s (the AI or a dive flew in
//   between) it starts again from the airframe.
// Its record, A3UE_FPV_swarmFly: [lastAt, heading, horizontal speed, climb rate, path direction,
//   poseAt, poseFrame, attitude, aheadAt, climbUntil, turn rate (deg/s, counter-clockwise positive)].
// [uav, target (objNull: none), point ASL, settings, speed m/s (-1: "runSpeed")] -> nothing
params [["_uav", objNull], ["_target", objNull], ["_point", []], ["_settings", createHashMap], ["_limit", -1]];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {};
if !(_point isEqualType [] && {count _point == 3}) exitWith {};
if !(_limit isEqualType 0 && {finite _limit} && {_limit > 0}) then {_limit = _settings get "runSpeed";};
private _now = time;
private _fly = _uav getVariable ["A3UE_FPV_swarmFly", []];
if !(_fly isEqualType [] && {count _fly == 11} && {(_now - (_fly # 0)) <= 1} && {(_now - (_fly # 0)) >= 0}) then {
	private _velocity = velocity _uav;
	private _flat = [_velocity # 0, _velocity # 1, 0];
	private _heading = if (vectorMagnitude _flat > 1) then {vectorNormalized _flat} else {
		private _nose = vectorDir _uav;
		_nose = [_nose # 0, _nose # 1, 0];
		if (vectorMagnitude _nose > 0.01) then {vectorNormalized _nose} else {[0, 1, 0]}
	};
	private _path = if (vectorMagnitude _velocity > 1) then {vectorNormalized _velocity} else {+_heading};
	_fly = [_now, _heading, vectorMagnitude _flat, _velocity # 2, _path, -1, -10, [], _now, -1, 0];
	_uav setVariable ["A3UE_FPV_swarmFly", _fly];
};
_fly params ["_lastAt", "_heading", "_speed", "_vz", "_path", "_poseAt", "_poseFrame", "_attitude", "_aheadAt", "_climbUntil", "_rate"];
private _dt = ((_now - _lastAt) max 0) min 0.25;
// Same simulation instant (paused, just started, or already stepped this frame): nothing to integrate.
if (_dt <= 0) exitWith {};
private _pos = getPosASL _uav;

// Heading: a level turn towards the point (degrees, counter-clockwise positive). The rate that still
// eases out onto the heading (sqrt (2 a angle)), at most runTurn and latAccel / speed, reached at
// turnAccel; never past the heading. Far off it: brake to turnSpeed.
private _want = [(_point # 0) - (_pos # 0), (_point # 1) - (_pos # 1), 0];
private _turn = 0;
if (vectorMagnitude _want > 1) then {
	_want = vectorNormalized _want;
	_turn = (((_heading # 0) * (_want # 1)) - ((_heading # 1) * (_want # 0))) atan2 (_heading vectorDotProduct _want);
};
private _turnAccel = _settings get "turnAccel";
private _rateMax = (_settings get "runTurn") min (((_settings get "latAccel") / (_speed max 1)) * 57.2958);
private _rateWant = ((sqrt (2 * _turnAccel * (abs _turn))) min _rateMax) * ([1, -1] select (_turn < 0));
private _rateStep = _turnAccel * _dt;
_rate = _rate + (((_rateWant - _rate) max -_rateStep) min _rateStep);
private _apply = _rate * _dt;
if ((_apply * _turn) > 0 && {(abs _apply) > (abs _turn)}) then {_apply = _turn;};
if (_apply != 0) then {
	_heading = vectorNormalized [((_heading # 0) * (cos _apply)) - ((_heading # 1) * (sin _apply)), ((_heading # 0) * (sin _apply)) + ((_heading # 1) * (cos _apply)), 0];
};
if ((abs _turn) > (_settings get "brakeTurn")) then {_limit = _limit min (_settings get "turnSpeed");};
private _step = (_settings get "accel") * _dt;
_speed = _speed + (((_limit - _speed) max -_step) min _step);

// Height: the point's, clear of the ground here and 2 s ahead; hard up while something is in the way.
private _ahead = _pos vectorAdd (_heading vectorMultiply ((_speed max 10) * 2));
private _ground = ((getTerrainHeightASL [_pos # 0, _pos # 1]) max (getTerrainHeightASL [_ahead # 0, _ahead # 1])) max 0;
private _climb = _settings get "climb";
private _vzWant = (((((_point # 2) max (_ground + (_settings get "floorAGL"))) - (_pos # 2)) * 0.5) max -_climb) min _climb;
if (_now < _climbUntil) then {_vzWant = _climb * 1.5;};
_vz = _vz + (((_vzWant - _vz) max -_step) min _step);
private _velocity = (_heading vectorMultiply _speed) vectorAdd [0, 0, _vz];
private _newPath = if (vectorMagnitude _velocity > 0.5) then {vectorNormalized _velocity} else {+_heading};

// Look-ahead (10 Hz): the next 2 s of the path.
if (_now >= _aheadAt) then {
	_aheadAt = _now + 0.1;
	private _from = getPosWorld _uav;
	if (vectorMagnitude _velocity > 1) then {
		if (([_uav, _target, _from, _from vectorAdd (_velocity vectorMultiply 2)] call A3UE_fnc_fpv_swarmClear) isNotEqualTo []) then {
			_climbUntil = _now + 2;
		};
	};
};

// Writes: attitude through the shared writer (D1 cadence), velocity every step.
private _pose = [_uav, _path, _newPath, vectorMagnitude _velocity, _dt, [_poseAt, _poseFrame, _attitude]] call A3UE_fnc_fpv_swarmPose;
_poseAt = _pose # 0;
_poseFrame = _pose # 1;
_attitude = _pose # 2;
_uav setVelocity _velocity;
_uav setVariable ["A3UE_FPV_swarmFly", [_now, _heading, _speed, _vz, _newPath, _poseAt, _poseFrame, _attitude, _aheadAt, _climbUntil, _rate]];
