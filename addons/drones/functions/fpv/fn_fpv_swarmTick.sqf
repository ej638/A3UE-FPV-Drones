// 1.0.9 friendly FPV swarm: one controller tick of a swarm drone. runController calls it for a drone
// with A3UE_FPV_swarmId, in one unscheduled slice; the pacer, the frame director, the lifecycle
// identity and the stop path are runController's own. Nothing here suspends.
// - The swarm brain (swarmPass) decides who attacks what; this tick only flies.
// - Who flies (SW-1d): the swarm itself on the way in, in every run-in (swarmFly) and in the dive
//   (swarmDive), stepped every frame by the director; Arma's AI on the loiter ring and the way out
//   (orders only when due). A loitering drone the AI lets wander off is flown back.
// - The run-in (SW-1g, EJ after SW1f: the passes and the picky target checks made the flight "crazy"):
//   straight at the target, and the dive at the steep gate. No passes, no sight or corridor checks.
// - Under direct player or Zeus control nothing is written and a run-in or dive is dropped (project rule).
// [uav, state, identity, generation] -> [sleep seconds, hot (the swarm flies it: stepped by the director)]
params [["_uav", objNull], ["_state", createHashMap], ["_identity", []], ["_generation", -1]];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {[0.5, false]};
private _now = time;
private _settings = call A3UE_fnc_fpv_swarmSettings;
private _record = (missionNamespace getVariable ["A3UE_FPV_swarms", createHashMap]) getOrDefault [_uav getVariable ["A3UE_FPV_swarmId", ""], createHashMap];
private _task = _uav getVariable ["A3UE_FPV_swarmTask", "INBOUND"];
// A drone never outlives its swarm except by a fault: retire it (server, the owner).
if (count _record == 0) exitWith {
	if (isServer) then {[_uav] call A3UE_fnc_fpv_cleanupDrone;};
	[1, false]
};
// Control changes go to the server's lifecycle record, as for every managed drone (signal epochs).
private _external = [_uav] call A3UE_fnc_fpv_isExternallyControlled;
if (_external isNotEqualTo (_uav getVariable ["A3UE_FPV_reportedControl", false])) then {
	_uav setVariable ["A3UE_FPV_reportedControl", _external];
	[_uav, "control", [_external]] call A3UE_fnc_fpv_sendLifecycle;
};
if (_external) exitWith {
	if (_task in ["ATTACK", "DIVE"]) then {[_uav, 0, "CONTROL"] call A3UE_fnc_fpv_swarmDrop;};
	[0.5, false]
};
if !([_uav, _identity] call A3UE_fnc_fpv_canActuate) exitWith {[0.5, false]};
// Who flies (SW-1d): the swarm in INBOUND, ATTACK and DIVE, the AI otherwise. Take the airframe
// from the AI, or give it back, when the task changes sides (or a release of control left it held).
private _lean = _task in ["INBOUND", "ATTACK", "DIVE"];
private _held = (_uav getVariable ["A3UE_FPV_nativeControl", []]) isNotEqualTo [];
if (!_lean && {_held}) then {
	[_uav, _identity, "RESTORE"] call A3UE_fnc_fpv_swarmControl;
	_state set ["swarmOrder", []];
};
if (_lean && {!_held} && {!([_uav, _identity, "TAKE"] call A3UE_fnc_fpv_swarmControl)}) exitWith {[0.5, false]};
// Targetable by enemy AI, as every managed drone (1 Hz).
if (_now >= (_state getOrDefault ["swarmTargetabilityAt", 0])) then {
	[_uav, _generation] call A3UE_fnc_fpv_applyTargetability;
	_state set ["swarmTargetabilityAt", _now + 1];
};

// One AI move order: on a new key (task or target), when the point moved more than _moved metres, or
// when the last order is older than _ttl seconds.
private _order = {
	params ["_posATL", "_height", "_speed", "_key", "_ttl", ["_moved", 15]];
	private _last = _state getOrDefault ["swarmOrder", []];
	if (_last isEqualType [] && {count _last == 3} && {(_last # 0) isEqualTo _key} && {_now < (_last # 2)}
		&& {((_last # 1) distance2D _posATL) <= _moved}) exitWith {};
	if ((_state getOrDefault ["swarmAiTask", ""]) != _task) then {
		// SW-1c: the AI only flies our orders. No danger reactions or targeting, and it never flees
		// (SW1b: drones were found 800 m from their orders, two still inbound at 38 m/s).
		_uav enableAI "ALL";
		{
			_x disableAI "FSM";
			_x disableAI "AUTOCOMBAT";
			_x disableAI "TARGET";
			_x disableAI "AUTOTARGET";
			(group _x) allowFleeing 0;
		} forEach (crew _uav);
		_uav setBehaviour "CARELESS";
		_uav setCombatMode "BLUE";
		_state set ["swarmAiTask", _task];
	};
	_uav flyInHeight _height;
	_uav forceSpeed _speed;
	_uav doMove [_posATL # 0, _posATL # 1, _height];
	_state set ["swarmOrder", [_key, +_posATL, _now + _ttl]];
};

private _result = [0.5, false];
private _center = _record get "center";
// SW-1e: this drone's style, drawn once at launch (swarmBrain): [height offset m, side lane m, speed
// factor, loiter ring offset m, circling direction]. Its height on the way in, in its run-ins and its
// loiter; its speed; its ring; and which way it circles. The lane is where it launched (SW-1f).
private _style = _uav getVariable ["A3UE_FPV_swarmStyle", []];
if !(_style isEqualType [] && {count _style == 5} && {(_style findIf {!(_x isEqualType 0) || {!finite _x}}) < 0}) then {_style = [0, 0, 1, 0, 1];};
private _height = (_settings get "height") + (((_style # 0) max -30) min 40);
private _pace = (_settings get "runSpeed") * (((_style # 2) max 0.7) min 1.3);
private _ring = (_settings get "ring") + (((_style # 3) max -60) min 80);
private _turnSign = [1, -1] select ((_style # 4) < 0);
private _cruiseAt = diag_tickTime;
switch (_task) do {
	case "DIVE": {
		private _at = diag_tickTime;
		_result = [_uav, _identity, _record, _settings] call A3UE_fnc_fpv_swarmDive;
		// Dive cost for the swarm's summary line (the director line has the total).
		private _cost = (diag_tickTime - _at) * 1000;
		private _perf = _record get "divePerf";
		_perf set [0, (_perf # 0) + 1];
		_perf set [1, (_perf # 1) + _cost];
		if (_cost > (_perf # 2)) then {_perf set [2, _cost];};
	};
	case "ATTACK": {
		_result = [0.05, false];
		private _target = [_uav] call A3UE_fnc_fpv_resolveTarget;
		private _dropped = "";
		private _hide = 0;
		private _detail = "";
		switch (true) do {
			case (isNull _target): {_dropped = "TARGET_GONE";};
			case (((getPosASL _target) distance2D _center) > ((_settings get "radius") + (_settings get "margin"))): {_dropped = "LEFT_AREA"; _hide = 30;};
			case (_now - (_uav getVariable ["A3UE_FPV_swarmTaskAt", _now]) > (_settings get "runInS")): {_dropped = "RUNIN_TIMEOUT"; _hide = 20;};
		};
		if (_dropped == "") then {
			private _aim = aimPos _target;
			private _pos = getPosASL _uav;
			private _flat = _pos distance2D _aim;
			private _below = ((_pos # 2) - (_aim # 2)) atan2 (_flat max 0.1);
			// SW-1g (EJ after SW1f: "pick a target, not picky about obstacles, and go for them"): the gate
			// is only the angle (the steep top-attack, SW-1b), the drone's turn (dive starts staggered)
			// and the target ahead of it, within "diveFacing" of the way it flies (behind it: it turns
			// round first, never a loop). No sight line, corridor or roof check and no passes: cover on
			// the dive line takes the blast (any-contact fuse). Then one safety check. The swarm already
			// holds the airframe (SW-1d).
			private _velocity = velocity _uav;
			private _heading = [_velocity # 0, _velocity # 1, 0];
			private _toTarget = [(_aim # 0) - (_pos # 0), (_aim # 1) - (_pos # 1), 0];
			// SW-2b (session SW2: the last-resort drone took a man at a ruin from 8 m off, 70 m up, and
			// circled him 6-12 m out for 46 s until the swarm left; a point inside the turning circle is
			// never ahead): nearly overhead ("overheadAngle" or more below) and not behind (within
			// "overheadFacing" of the way it flies), the push-over is short, so it dives. Behind it, it
			// still turns round first (never a loop). Straight below: dives.
			private _facing = (vectorMagnitude _heading) < 3 || {(vectorMagnitude _toTarget) <= 1} || {
				private _dot = (vectorNormalized _heading) vectorDotProduct (vectorNormalized _toTarget);
				_dot >= (cos (_settings get "diveFacing"))
					|| {_below >= (_settings get "overheadAngle") && {_dot >= (cos (_settings get "overheadFacing"))}}
			};
			// SW-1i: another drone of the swarm dived at this target less than "tapGap" s ago: hold the
			// dive (and slow, so it does not overfly) until that hit has landed; the target gone, the
			// drone takes another (EJ after SW1h). SW-1j: at a target within "tapRadius" of this one too,
			// so with targets only "spacing" 15 m apart a neighbour's blast does not catch a drone in its
			// own dive (SW1e at 15 m: 9 of 25 lost drones). One entry per target dived at, this swarm.
			private _taps = _record getOrDefault ["taps", createHashMap];
			private _targetId = netId _target;
			private _targetAt = getPosASL _target;
			private _lastTap = -1e9;
			{
				private _tap = _taps get _x;
				if (_x == _targetId || {((_tap # 1) distance2D _targetAt) < (_settings get "tapRadius")}) then {_lastTap = _lastTap max (_tap # 0);};
			} forEach (keys _taps);
			private _tapHeld = _now < (_lastTap + (_settings get "tapGap"));
			if (_now >= (_uav getVariable ["A3UE_FPV_swarmGoAt", 0]) && {!_tapHeld} && {_below >= (_settings get "diveAngle")} && {_facing}) then {
				// SW-1e: the swarm's own friendly check (swarmSafe: no enemy protects anyone, SW-1f).
				private _unsafe = [_record get "side", _target, _settings get "safety"] call A3UE_fnc_fpv_swarmSafe;
				if (_unsafe != "") then {
					_dropped = "FRIENDLY_NEAR"; _hide = 20; _detail = _unsafe;
				} else {
					// The dive goes on from the cruise as it is (SW-1e: its path, speed, pose and bank, so
					// nothing jumps); from the airframe if there is no fresh cruise.
					private _speed = vectorMagnitude _velocity;
					private _dir = if (_speed > 1) then {vectorNormalized _velocity} else {vectorDir _uav};
					private _pose = [-1, -10, []];
					private _fly = _uav getVariable ["A3UE_FPV_swarmFly", []];
					if (_fly isEqualType [] && {count _fly == 11} && {(_now - (_fly # 0)) <= 0.5} && {(_now - (_fly # 0)) >= 0}) then {
						_dir = +(_fly # 4);
						_speed = sqrt (((_fly # 2) ^ 2) + ((_fly # 3) ^ 2));
						_pose = [_fly # 5, _fly # 6, _fly # 7];
					};
					// [enteredAt, lastAt, dir, speed, closest, poseAt, poseFrame, attitude, safetyAt, pullAt,
					//  targetId, breakWhy]
					_uav setVariable ["A3UE_FPV_swarmDive", [_now, _now, _dir, _speed, 1e9, _pose # 0, _pose # 1, _pose # 2, _now + 1, -1, netId _target, ""]];
					_record set ["lastDiveAt", _now];
					_taps set [_targetId, [_now, _targetAt]];
					_record set ["taps", _taps];
					// SW-1h: dives per target, machine-wide, for "triesS" (swarmAssign leaves a man or a
					// static alone after "maxTries"). Counted here, so a drone that blows up on the cover
					// (the pack's own impact detonation, no STRIKE line) counts too. Expired entries go
					// once the map holds more than 100.
					private _tries = missionNamespace getVariable ["A3UE_FPV_swarmTries", createHashMap];
					if (count _tries > 100) then {
						{if (_now >= ((_tries get _x) # 1)) then {_tries deleteAt _x;};} forEach (keys _tries);
					};
					private _tried = _tries getOrDefault [netId _target, [0, -1]];
					if (_now >= (_tried # 1)) then {_tried = [0, -1];};
					_tries set [netId _target, [(_tried # 0) + 1, _now + (_settings get "triesS")]];
					missionNamespace setVariable ["A3UE_FPV_swarmTries", _tries];
					[_uav, "DIVE"] call A3UE_fnc_fpv_swarmSetTask;
					_result = [0.02, true];
					diag_log format ["[A3UE_FPV] swarm id=%1 event=DIVE drone=%2 target=%3 distM=%4 aboveM=%5 angle=%6 again=%7 try=%8 tapS=%9",
						_record get "id", netId _uav, netId _target, round _flat, round ((_pos # 2) - (_aim # 2)), round _below,
						_uav getVariable ["A3UE_FPV_swarmRetries", 0], (_tries get (netId _target)) # 0,
						if (_lastTap < -1e8) then {-1} else {(_now - _lastTap) toFixed 1}];
				};
			};
			if (_dropped == "" && {(_uav getVariable ["A3UE_FPV_swarmTask", ""]) == "ATTACK"}) then {
				// Straight at the target, at the drone's own height over its aim point (SW-1e style; from
				// its own launch lane, SW-1f, so the group comes in spread with no swerve). A moving target
				// is followed; one behind the drone is turned round to (swarmFly brakes into the turn).
				private _tPos = getPosASL _target;
				[_uav, _target, [_tPos # 0, _tPos # 1, (_aim # 2) + _height], _settings,
					[_pace, _pace min (_settings get "turnSpeed")] select _tapHeld] call A3UE_fnc_fpv_swarmFly;
				_result = [0.02, true];
			};
		};
		if (_dropped != "") then {[_uav, _hide, _dropped, _detail] call A3UE_fnc_fpv_swarmDrop;};
	};
	case "INBOUND": {
		// Straight to its own point of the ring (or back to the nearest one), "height" over the ground there.
		private _arrive = _uav getVariable ["A3UE_FPV_swarmArrive", _center];
		if (((getPosASL _uav) distance2D _arrive) <= (_settings get "arriveM")) then {
			[_uav, "LOITER"] call A3UE_fnc_fpv_swarmSetTask;
			_result = [0.05, false];
		} else {
			[_uav, objNull, [_arrive # 0, _arrive # 1, ((getTerrainHeightASL [_arrive # 0, _arrive # 1]) max 0) + _height], _settings, _pace] call A3UE_fnc_fpv_swarmFly;
			_result = [0.02, true];
		};
	};
	case "LOITER": {
		private _bearing = _center getDir (getPosASL _uav);
		private _out = ((getPosASL _uav) distance2D _center) - _ring;
		if (_out > (_settings get "returnM")) then {
			// SW-1d: the AI let it wander off (SW1c: 600-800 m out at up to 36 m/s for a minute, out of
			// sight of the zone). Fly it straight back to the nearest point of the ring; on the way it is
			// free to take a target.
			_uav setVariable ["A3UE_FPV_swarmArrive", _center getPos [_ring, _bearing]];
			[_uav, "INBOUND"] call A3UE_fnc_fpv_swarmSetTask;
			_record set ["returns", 1 + (_record getOrDefault ["returns", 0])];
			diag_log format ["[A3UE_FPV] swarm id=%1 event=RETURN drone=%2 outM=%3", _record get "id", netId _uav, round _out];
			_result = [0.05, false];
		} else {
			// Circle the area: every 5 s, a point 50 degrees further round its own ring, its own way
			// round, at its own height (SW-1e: not one conga line at one height).
			[_center getPos [_ring, _bearing + (50 * _turnSign)], _height, _settings get "loiterSpeed", "LOITER", 5, 1e9] call _order;
		};
	};
	case "LEAVE": {
		[_record get "exit", _height + 10, 25, "LEAVE", 10] call _order;
	};
};
// The swarm's own cruise (inbound and run-ins) for the summary line; the dive has its own.
if (_task in ["INBOUND", "ATTACK"] && {_result # 1}) then {
	private _cost = (diag_tickTime - _cruiseAt) * 1000;
	private _perf = _record getOrDefault ["cruisePerf", [0, 0, 0]];
	_perf set [0, (_perf # 0) + 1];
	_perf set [1, (_perf # 1) + _cost];
	if (_cost > (_perf # 2)) then {_perf set [2, _cost];};
	_record set ["cruisePerf", _perf];
};
_result
