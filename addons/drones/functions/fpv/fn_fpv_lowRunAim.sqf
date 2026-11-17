// LOW_RUN flight (lowest line LL-1, design docs/internal/FPV_LowLine_Design_20261116.md), owner-local.
// attackNavigation calls it once per simulation instant while the pass is a low run. There is no new
// movement writer: it only supplies the TERMINAL_VECTOR writer's aim point, which the existing
// planner and integrator fly.
// The drone follows the latest survey's line: down the glide from the hand-off, skim height over open
// ground, over anything in its corridor and back down. About once a second a new survey, from the
// drone (kept on the line it weaves about) to the pilot's estimate of the target, replaces the line.
// Whatever it finds is flown: nothing declines, nothing rises one way.
//  DESCEND  on the glide: attack speed, braked to the skim speed by the level-out (attackLimits)
//  SKIM     past the glide's end and down on the line: the skim speed, the weave within weaveCap
//  SPRINT   from 60 m or 2.2 s to go: the commit. No more surveys; the attack-run speed; the final
//           blend to the pass's intent point, as in the dive.
// [uav, target, controllerIdentity, pass, navigation, estimate ASL, velocity estimate, time to go,
//  yaw deg, envelope, goal ASL] -> [aim ASL, velocity estimate for the planner], or [] when this
// pass is not (or no longer) low: the normal dive aim applies.
params [["_uav", objNull], ["_target", objNull], ["_controllerIdentity", []], ["_pass", createHashMap], ["_navigation", []],
	["_estimate", []], ["_velocityEstimate", [0, 0, 0]], ["_timeToGo", 99], ["_yaw", 0], ["_envelope", 1], ["_goal", []]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {[]};
if (isNull _uav || {isNull _target} || {!local _uav} || {count _estimate != 3} || {count _goal != 3}) exitWith {[]};
private _stage = [_uav, _target] call A3UE_fnc_fpv_lowRunStage;
if !(_stage in ["READY", "DESCEND", "SKIM", "SPRINT"]) exitWith {[]};
private _record = _uav getVariable "A3UE_FPV_lowRun";
private _result = _record get "result";
if (count _result < 8) exitWith {[]};
private _settings = call A3UE_fnc_fpv_lowRunSettings;
private _now = time;
private _uavPos = getPosASL _uav;
// Heights are worked out for the airframe's lowest point; the aim is for its position.
private _bottomZ = ((getPosWorld _uav) # 2) - (_uav getVariable ["A3UE_FPV_lowRunBelow", 0]);
private _aslOffset = (_uavPos # 2) - _bottomZ;
private _surface = {
	params ["_p"];
	private _z = getTerrainHeightASL [_p # 0, _p # 1];
	if (_z < 1) then {_z = [_p # 0, _p # 1] call A3UE_fnc_fpv_surfaceZ;};
	_z
};
private _clear = _bottomZ - ([_uavPos] call _surface);
private _velocity = velocity _uav;
private _speed = (vectorMagnitude [_velocity # 0, _velocity # 1, 0]) max 5;
private _targetPos = getPosASL _target;
private _range = _uavPos distance2D _estimate;

// Hand-off: the glide starts here, on the survey's slope (LR-1b/LR-1c: the drawn angle, steepened
// for a high arrival), from the line's own start.
if (_stage == "READY") then {
	private _origin = _result # 1;
	private _tan = _result # 4;
	_record set ["glideFrom", [_origin # 0, _origin # 1, _origin # 2, _tan]];
	_record set ["glideUsed", [_record get "glide", atan _tan] select (_tan > 0)];
	_record set ["handoffM", _range];
	_stage = "DESCEND";
	_record set ["stage", _stage];
};

// ---- A new survey about once a second, before the commit. From the drone, moved onto the line it
// weaves about while it is inside the corridor (LR-1d: a survey from the drifted position drew the
// line toward what lay beside it). While gliding it starts on the hand-off's glide line, with that
// slope, so the glide stays anchored however the airframe lags it.
private _here = [_uav, _uavPos] call A3UE_fnc_fpv_lowRunLineAt;
if (_stage in ["DESCEND", "SKIM"] && {count _here == 4}) then {
	private _start = [];
	if (count (_record get "check") == 0 && {_now < (_result # 0) || {_now - (_result # 0) >= (_settings get "recheck")}}) then {
		private _from = [_uavPos # 0, _uavPos # 1, _bottomZ];
		if (abs (_here # 2) <= (_settings get "weaveCap") + 1.5) then {
			private _lat = [(_here # 3) # 1, -((_here # 3) # 0), 0];
			_from = _from vectorDiff (_lat vectorMultiply (_here # 2));
			_from set [2, _bottomZ];
		};
		private _tan = 0;
		if (_stage == "DESCEND") then {
			private _glide = _record get "glideFrom";
			_tan = _glide # 3;
			_from set [2, ((_glide # 2) - _tan * ([_glide # 0, _glide # 1, 0] distance2D [_from # 0, _from # 1, 0])) max (([_from] call _surface) + (_record get "height"))];
		};
		_start = [_from, [_estimate # 0, _estimate # 1, _targetPos # 2], _tan];
	};
	if (([_uav, _target, _record, _settings, _start] call A3UE_fnc_fpv_lowRunCheck) == "DONE") then {
		_result = _record get "result";
		_here = [_uav, _uavPos] call A3UE_fnc_fpv_lowRunLineAt;
	};
};
if (count _here != 4) exitWith {[]};

// ---- The commit: from 60 m or 2.2 s out it sprints at attack speed and surveys no more.
if (_stage in ["DESCEND", "SKIM"] && {_range <= (_settings get "sprintM") || {_timeToGo <= (_settings get "sprintS")}}) then {
	_stage = "SPRINT";
	_record set ["stage", _stage];
	_record set ["check", createHashMap];
	_record set ["sprintAt", _now];
};

// ---- The aim. Direction: the pilot's estimate of the target, led like the planner leads it.
private _lead = (_range / ((vectorMagnitude _velocity) max 4)) min 1.5;
private _aimTarget = _estimate vectorAdd (_velocityEstimate vectorMultiply _lead);
private _toAim = [(_aimTarget # 0) - (_uavPos # 0), (_aimTarget # 1) - (_uavPos # 1), 0];
private _aimRange = vectorMagnitude _toAim;
private _los = if (_aimRange > 0.01) then {_toAim vectorMultiply (1 / _aimRange)} else {
	private _flat = [_velocity # 0, _velocity # 1, 0];
	if (vectorMagnitude _flat > 0.01) then {vectorNormalized _flat} else {[0, 1, 0]}
};
private _side = [_los # 1, -(_los # 0), 0];
// The weave: the same correction angles as the dive, sideways only (an up/down correction at 1-4 m
// flies into the ground), held inside the corridor the survey measured. An outward correction fades
// out over the last metre before weaveCap, judged on the drift 1.5 s ahead (LR-1d: the planned path
// answers a new course 1-1.5 s late, and the weave overran its room by 1-2 m).
private _cap = _settings get "weaveCap";
private _lat = [(_here # 3) # 1, -((_here # 3) # 0), 0];
private _ahead = (_here # 2) + 1.5 * (_velocity vectorDotProduct _lat);
if (_yaw * _ahead > 0) then {_yaw = _yaw * (((_cap - (abs _ahead)) max 0) min 1);};
private _course = vectorNormalized (_los vectorAdd (_side vectorMultiply (tan _yaw)));
// The carrot: 1.5 s and at least 20 m ahead; the target itself once it is closer than that (then
// the planner leads it, as in the dive, so the estimate goes unled).
private _distance = (1.5 * _speed) max 20;
private _atTarget = _aimRange <= _distance;
private _reach = [_distance, _aimRange max 1] select _atTarget;
private _carrot = [_estimate, _uavPos vectorAdd (_course vectorMultiply _distance)] select !_atTarget;
// The height: the line every 5 m out to the carrot, as a straight climb or descent from the
// airframe that clears all of it, at most 35 deg up and 30 deg down. A near miss over the head
// sprints at its own pass height over open ground, just over the head (from a 1 m or a 4 m skim the
// last second's blend alone is too short to bring the drone onto it), eased in at 1.5 m/s from the
// commit; over cover the line stands.
private _height = _record get "height";
private _passOver = -1;
if (_stage == "SPRINT" && {(_pass getOrDefault ["intent", ""]) == "OVER"}) then {
	private _t = (_now - (_record getOrDefault ["sprintAt", _now])) max 0;
	_passOver = ((((_goal # 2) - _aslOffset) - ([_estimate] call _surface)) max 1.0) min 4.5;
	_passOver = _height + (((_passOver - _height) min (1.5 * _t)) max (-1.5 * _t));
};
private _needs = [];
private _need = {
	params ["_d", "_p"];
	private _z = ([_uav, _p] call A3UE_fnc_fpv_lowRunLineAt) # 0;
	if (_passOver > 0) then {
		private _g = [_p] call _surface;
		if (_z <= _g + _height + 0.01) then {_z = _g + _passOver;};
	};
	_needs pushBack [_d, _z];
};
// Sampled 0.4-1.6 s ahead (a hop's top is flat for 10 m or more, so none falls between samples);
// closer samples would magnify every small rise ahead into a pull-up.
{
	private _d = _x * _speed;
	if (_d < _reach - 0.5) then {[_d, _uavPos vectorAdd (_course vectorMultiply _d)] call _need;};
} forEach [0.4, 0.8, 1.2, 1.6];
[_reach, _carrot] call _need;
private _want = -1e9;
{
	_x params ["_d", "_z"];
	_want = _want max (_bottomZ + (_z - _bottomZ) * (_reach / (_d max 0.5)));
} forEach _needs;
_want = (_want max (_bottomZ - 0.58 * _reach)) min (_bottomZ + 0.7 * _reach);
if (_atTarget) then {_want = _want max ((_estimate # 2) - _aslOffset);};
// The glide ends, and the skim begins, once the drone is past the glide's end and down on the line.
if (_stage == "DESCEND") then {
	private _glide = _record get "glideFrom";
	private _tan = (_glide # 3) max 0.05;
	// For the speed limit in attackLimits (LR-1b/LR-1c): the glide path left before the level-out,
	// which begins 1.5 s (at least 20 m) before the glide's end, flown at the skim speed.
	private _flare = (1.5 * (_record get "skim")) max 20;
	_record set ["descentLeft", ((((_result # 5) - (_here # 1)) - _flare) max 0) * (sqrt (1 + _tan * _tan))];
	if ((_here # 1) >= (_result # 5) && {_bottomZ <= (_here # 0) + 1}) then {
		_stage = "SKIM";
		_record set ["stage", _stage];
		_record set ["skimFrom", _range];
	};
};
// Smooth: the wanted height moves at most 20 m/s, so the planner always accepts the path.
private _wantAt = _record getOrDefault ["wantAt", -1];
if (_wantAt >= 0 && {_now > _wantAt} && {_now - _wantAt < 0.5}) then {
	private _step = 20 * (_now - _wantAt);
	private _previous = _record get "wantZ";
	_want = (_want max (_previous - _step)) min (_previous + _step);
};
_record set ["wantZ", _want];
_record set ["wantAt", _now];
private _weave = [_carrot # 0, _carrot # 1, _want + _aslOffset];
// The finish: the same final blend to the pass's intent point as the dive.
private _aim = (_weave vectorMultiply _envelope) vectorAdd (_goal vectorMultiply (1 - _envelope));
// Evidence for the RPT line: where the airframe first got within 5 m of the ground, and its lowest
// clearance while skimming (before the final blend).
if (_clear <= 5 && {(_record getOrDefault ["under5M", -1]) < 0}) then {_record set ["under5M", _range];};
if (_stage in ["SKIM", "SPRINT"] && {_envelope >= 0.999}) then {
	_record set ["minClear", (_record getOrDefault ["minClear", 1e9]) min _clear];
};
[_aim, [[0, 0, 0], +_velocityEstimate] select _atTarget]
