// 1.0.9 friendly FPV swarm: the lean dive, one step (owner = server, one unscheduled slice, every
// frame under the director). Design §3.4 / §4.2: no weave, no planned misses, no flip-back, no
// trajectory planner. One fuse ray and a few vector operations a step.
// - Steering: lead pursuit of the target's aim point, turning at most "turnRate" deg/s. The logical
//   direction and speed are kept between steps (never re-read from the airframe mid-dive); a step
//   integrates at most 0.25 s.
// - Push-over (SW-1e, EJ: it "almost snaps to the dive position"; a pilot "tilts the drone forwards
//   and it starts picking up speed as it dives"): the turn rate starts at "pushRate" deg/s and grows
//   "pushRamp" deg/s each second to "turnRate"; the speed builds at "pushAccel" m/s2 plus gravity
//   along the path (at most "accel") to the family's dive speed.
// - Writes: velocity every step; attitude through swarmPose, the same writer as the cruise (D1
//   cadence; the dive starts from the cruise's own pose and bank, so nothing jumps).
// - Fuse: within "contact" of the aim point, a predicted pass within it before the next step, or one
//   ray along this step touching anything (the target, ground, a tree, a wall: 1.0.8's any-contact
//   rule). The strike goes through detonateCompat and the server commit, like every managed drone:
//   one warhead, the right kill credit, settled once.
// - No look-ahead (SW-1g, EJ after SW1f: "not picky about obstacles, and go for them"; SW-1b's
//   BLOCKED pull-up and return made the drones fly round): cover on the dive line takes the blast,
//   through the any-contact fuse.
// - Break-off: target gone, a miss (6 m past the closest point), dive older than "diveS", or a
//   friendly within "safety" of the target (swarmSafe, once a second; "by=" says who). The drone
//   pulls up at 45 degrees for 1.2 s. After a miss, with the target still there, it comes back for it
//   once (a fresh run-in and gate, still flown by the swarm, SW-1d); otherwise it returns to the
//   swarm and the tick gives the AI back.
// [uav, identity, record, settings] -> [sleep, hot]
params [["_uav", objNull], ["_identity", []], ["_record", createHashMap], ["_settings", createHashMap]];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {[0.5, false]};
private _now = time;
private _dive = _uav getVariable ["A3UE_FPV_swarmDive", []];
if !(_dive isEqualType [] && {count _dive == 12}) exitWith {
	[_uav, 0, "DIVE_STATE"] call A3UE_fnc_fpv_swarmDrop;
	[0.25, false]
};
_dive params ["_enteredAt", "_lastAt", "_dir", "_speed", "_closest", "_poseAt", "_poseFrame", "_attitude", "_safetyAt", "_pullAt", "_targetId",
	"_breakWhy"];
private _dt = ((_now - _lastAt) max 0) min 0.25;
// Same simulation instant (paused, or already stepped this frame): nothing to integrate.
if (_dt <= 0) exitWith {[0.02, true]};

private _pos = getPosASL _uav;
private _pulling = _pullAt >= 0;
private _target = objNull;
private _aim = [];
private _targetVelocity = [0, 0, 0];
private _dist = -1;
private _desired = [];
private _limit = 0;
if (!_pulling) then {
	_target = [_uav] call A3UE_fnc_fpv_resolveTarget;
	private _why = "";
	if (isNull _target || {netId _target != _targetId}) then {_why = "TARGET_GONE";};
	if (_why == "" && {_now - _enteredAt > (_settings get "diveS")}) then {_why = "DIVE_TIMEOUT";};
	private _unsafe = "";
	if (_why == "" && {_now >= _safetyAt}) then {
		_safetyAt = _now + 1;
		_unsafe = [_record get "side", _target, _settings get "safety"] call A3UE_fnc_fpv_swarmSafe;
		if (_unsafe != "") then {
			_why = "FRIENDLY_NEAR";
			(_record get "hidden") set [_targetId, _now + 20];
			// SW-1h: called off for a friendly, not a try at the target (swarmTick counted it).
			private _tries = missionNamespace getVariable ["A3UE_FPV_swarmTries", createHashMap];
			private _tried = _tries getOrDefault [_targetId, [0, -1]];
			if ((_tried # 0) > 0) then {_tries set [_targetId, [(_tried # 0) - 1, _tried # 1]];};
		};
	};
	if (_why == "") then {
		_aim = aimPos _target;
		_targetVelocity = velocity _target;
		_dist = _pos vectorDistance _aim;
		_closest = _closest min _dist;
		if (_closest < 30 && {_dist > _closest + 6}) then {
			_why = "MISSED";
		} else {
			private _timeToGo = (_dist / (_speed max 10)) min 3;
			_desired = vectorNormalized ((_aim vectorAdd (_targetVelocity vectorMultiply _timeToGo)) vectorDiff _pos);
			private _speeds = (_settings get "speeds") getOrDefault [_uav getVariable ["A3UE_FPV_vendorId", ""], [28, 26]];
			_limit = _speeds select ((_uav getVariable ["A3UE_FPV_payloadRole", "AP"]) == "AT");
		};
	};
	if (_why != "") then {
		_pulling = true;
		_pullAt = _now;
		_breakWhy = _why;
		_record set ["breaks", 1 + (_record getOrDefault ["breaks", 0])];
		diag_log format ["[A3UE_FPV] swarm id=%1 event=BREAK drone=%2 target=%3 reason=%4 diveS=%5 closestM=%6 by=%7",
			_record get "id", netId _uav, _targetId, _why, (_now - _enteredAt) toFixed 1, round (_closest min 9999), _unsafe];
	};
};
// The pull-up ends. Missed with the target still there: come back for it once (the run-in starts
// again from the airframe as it is). Otherwise (or the second time) the target goes back to the
// swarm and the tick gives the AI back.
if (_pulling && {_now - _pullAt >= 1.2}) exitWith {
	private _still = objNull;
	if (_breakWhy == "MISSED") then {
		_still = [_uav] call A3UE_fnc_fpv_resolveTarget;
		if (!isNull _still && {netId _still != _targetId}) then {_still = objNull;};
	};
	if (!isNull _still && {(_uav getVariable ["A3UE_FPV_swarmRetries", 0]) < 1}) then {
		_uav setVariable ["A3UE_FPV_swarmRetries", 1 + (_uav getVariable ["A3UE_FPV_swarmRetries", 0])];
		_uav setVariable ["A3UE_FPV_swarmDive", []];
		_uav setVariable ["A3UE_FPV_swarmFly", []];
		_uav setVariable ["A3UE_FPV_swarmGoAt", _now];
		[_uav, "ATTACK"] call A3UE_fnc_fpv_swarmSetTask;
		_record set ["reattacks", 1 + (_record getOrDefault ["reattacks", 0])];
		diag_log format ["[A3UE_FPV] swarm id=%1 event=AGAIN drone=%2 target=%3 after=%4",
			_record get "id", netId _uav, _targetId, _breakWhy];
	} else {
		[_uav, 0, ""] call A3UE_fnc_fpv_swarmDrop;
	};
	[[0.05, false], [0.02, true]] select ((_uav getVariable ["A3UE_FPV_swarmTask", ""]) == "ATTACK")
};
if (_pulling) then {
	private _flat = [_dir # 0, _dir # 1, 0];
	_desired = if (vectorMagnitude _flat > 0.05) then {vectorNormalized ((vectorNormalized _flat) vectorAdd [0, 0, 1])} else {[0, 0, 1]};
	_limit = 15;
};

// Turn towards the desired direction, at most the push-over rate (then turnRate) * dt; the pull-up
// turns at the full rate.
private _cos = ((_dir vectorDotProduct _desired) max -1) min 1;
private _angle = acos _cos;
private _rateNow = _settings get "turnRate";
if (!_pulling) then {_rateNow = _rateNow min ((_settings get "pushRate") + ((_settings get "pushRamp") * (_now - _enteredAt)));};
private _maxTurn = _rateNow * _dt;
private _newDir = +_desired;
if (_angle > _maxTurn) then {
	private _axis = _dir vectorCrossProduct _desired;
	if (vectorMagnitude _axis < 1e-6) then {_axis = _dir vectorCrossProduct [0, 0, 1];};
	if (vectorMagnitude _axis < 1e-6) then {_axis = [1, 0, 0];};
	_axis = vectorNormalized _axis;
	_newDir = vectorNormalized ((_dir vectorMultiply (cos _maxTurn)) vectorAdd ((_axis vectorCrossProduct _dir) vectorMultiply (sin _maxTurn)));
};
// Speed: up at "pushAccel" plus gravity along the path (at most "accel"), down at "accel".
private _brake = (_settings get "accel") * _dt;
private _gain = if (_pulling) then {_brake} else {(((_settings get "pushAccel") + (9.81 * ((-(_newDir # 2)) max 0))) min (_settings get "accel")) * _dt};
private _newSpeed = _speed + (((_limit - _speed) max -_brake) min _gain);
private _velocity = _newDir vectorMultiply _newSpeed;

// Fuse (not while pulling up).
private _fuse = "";
private _impact = [];
if (!_pulling) then {
	private _contact = _settings get "contact";
	private _relative = _velocity vectorDiff _targetVelocity;
	private _relativeSpeed = vectorMagnitude _relative;
	if (_dist <= _contact) then {
		_fuse = "DIRECT_CONTACT";
		_impact = +_aim;
	} else {
		if (_relativeSpeed > 0.1) then {
			private _offset = _aim vectorDiff _pos;
			private _when = (_offset vectorDotProduct _relative) / (_relativeSpeed * _relativeSpeed);
			if (_when >= 0 && {_when <= (((_dt * 1.5) max 0.03) min 0.15)}) then {
				if ((vectorMagnitude (_offset vectorDiff (_relative vectorMultiply _when))) <= _contact) then {
					_fuse = "PREDICTED_IMPACT";
					_impact = _aim vectorAdd (_targetVelocity vectorMultiply _when);
				};
			};
		};
	};
	if (_fuse == "") then {
		// One ray along this step: anything in the way fires the fuse.
		private _reach = ((_newSpeed * 1.5 * _dt) max 1) min 4;
		private _from = getPosWorld _uav;
		private _to = _from vectorAdd (_newDir vectorMultiply _reach);
		private _crew = crew _uav;
		private _hits = lineIntersectsSurfaces [_from, _to, _uav, objNull, true, 3, "GEOM", "NONE"];
		private _index = _hits findIf {
			private _object = _x param [3, objNull];
			if (isNull _object) then {_object = _x param [2, objNull];};
			isNull _object || {!(_object in _crew) && {(objectParent _object) isNotEqualTo _uav}}
		};
		if (_index >= 0) then {
			private _hit = _hits # _index;
			private _object = _hit param [3, objNull];
			if (isNull _object) then {_object = _hit param [2, objNull];};
			if (!isNull _object && {_object isEqualTo _target || {(objectParent _object) isEqualTo _target}}) then {
				_fuse = "DIRECT_CONTACT";
				_impact = +(_hit # 0);
			} else {
				_fuse = "SURFACE_CONTACT";
				_uav setVariable ["A3UE_FPV_lastSurfaceContactASL", +(_hit # 0)];
			};
		} else {
			if ((getTerrainHeightASL [_to # 0, _to # 1]) < 0 && {(_to # 2) < 0.5}) then {
				_fuse = "SURFACE_CONTACT";
				_uav setVariable ["A3UE_FPV_lastSurfaceContactASL", +_to];
			};
		};
	};
};
private _struck = false;
if (_fuse != "") then {
	if (_impact isNotEqualTo []) then {
		private _class = _uav getVariable ["A3UE_FPV_swarmTargetClass", ""];
		_uav setVariable ["A3UE_FPV_terminalImpactMode", switch (true) do {
			case (_target isKindOf "Man"): {"DIRECT_BODY"};
			case (_class in ["STATIC", "SYSTEM"]): {"DIRECT_STATIC"};
			default {"DIRECT_HULL"};
		}];
		_uav setVariable ["A3UE_FPV_lastImpactValid", true];
		_uav setVariable ["A3UE_FPV_lastImpactPointASL", _impact];
		_uav setVariable ["A3UE_FPV_lastImpactTargetNetId", netId _target];
	} else {
		_uav setVariable ["A3UE_FPV_lastImpactValid", false];
	};
	// Fence the pack's own explode handler until the server commits (EN-02 contact fence).
	[_uav, "SET"] call A3UE_fnc_fpv_contactFence;
	[_uav, _target, _fuse, "NONE", _uav getVariable ["A3UE_FPV_targetRevision", 0]] call A3UE_fnc_fpv_detonateCompat;
	if (_uav getVariable ["A3UE_FPV_detonating", false]) then {
		_struck = true;
		_record set ["strikes", 1 + (_record getOrDefault ["strikes", 0])];
		diag_log format ["[A3UE_FPV] swarm id=%1 event=STRIKE drone=%2 role=%3 target=%4 class=%5 reason=%6 diveS=%7 speed=%8",
			_record get "id", netId _uav, _uav getVariable ["A3UE_FPV_payloadRole", ""], _targetId,
			_uav getVariable ["A3UE_FPV_swarmTargetClass", ""], _fuse, (_now - _enteredAt) toFixed 1, round _newSpeed];
	} else {
		// On the server the commit is synchronous: refused, so the pack's own backstop is back.
		[_uav, "RELEASE"] call A3UE_fnc_fpv_contactFence;
	};
};
if (_struck) exitWith {[0.25, false]};

// Writes: attitude through the shared writer (D1 cadence), velocity every step.
private _pose = [_uav, _dir, _newDir, _newSpeed, _dt, [_poseAt, _poseFrame, _attitude], _settings get "diveBank"] call A3UE_fnc_fpv_swarmPose;
_poseAt = _pose # 0;
_poseFrame = _pose # 1;
_attitude = _pose # 2;
_uav setVelocity _velocity;
_uav setVariable ["A3UE_FPV_swarmDive", [_enteredAt, _now, _newDir, _newSpeed, _closest, _poseAt, _poseFrame, _attitude, _safetyAt, _pullAt, _targetId,
	_breakWhy]];
[0.02, true]
