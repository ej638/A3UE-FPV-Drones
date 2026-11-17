// LOW_RUN survey (lowest line LL-1, design docs/internal/FPV_LowLine_Design_20261116.md), owner-local.
// One survey measures the lowest safe line to the target: before the hand-off (a glide from the
// hand-off point H, then along the ground) and about once a second while low (from the drone). It
// never blocks: whatever is in the way is flown over, and the drone comes back down after it.
// Resumable and bounded: each call does a few units of work (one unit is about 25 microseconds: a
// short ray, a fifth of a ground station) and carries on next tick. Nothing in it suspends (LT-2).
// Phases: GROUND (every 5 m on the centre line and both corridor edges) -> OBJECTS (map objects,
// people, animals and vehicles, in 40 m steps) -> RAYS (five lines at the line's height, 25 m
// segments: what the map list misses) -> DONE.
// The line, every 5 m: the height of the airframe's lowest point. Skim height over the highest ground
// across the corridor (half-width weaveCap + 1.5 m), and `over` (0.7 m) over anything in it; climbing
// at most 15 deg before an obstacle and coming down at most 30 deg after it; and, from a glide start,
// never below the glide from the origin.
// Never flown over: an enemy soldier (contact with him is a hit), the target and its vehicle, anything
// within 2 m of the target (the bush or wall it stands at is the fuse's), something the line passes
// under (a bridge), and a power-line wire by its box (the box runs from the ground to the top of the
// span, engine session 1d; a cable that really is at the line's height is met by the rays).
// [uav, target, record, settings, start] -> "IDLE" | "RUNNING" | "DONE"
//   start: [] continues the survey in progress; [originASL, targetASL, glideTan] starts a new one.
//     originASL is the airframe's lowest point at the start; glideTan > 0 means the line first
//     glides down from there at that slope.
// On completion the record's "result" becomes
//   [completedAt, originASL, targetASL, plan, glideTan, lowS, hopTop, hopBy]
//   plan: the line's heights (ASL) at s = 0, 5, 10, ... m along, the last one at the target end;
//   lowS: where the glide meets the line under it (0 without a glide); hopTop/hopBy: the tallest
//   thing the line flies over (metres above its ground) and its model or class ("" when none).
params [["_uav", objNull], ["_target", objNull], ["_record", createHashMap], ["_settings", createHashMap], ["_start", []]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {"IDLE"};
if (isNull _uav || {isNull _target} || {!(_record isEqualType createHashMap)}) exitWith {"IDLE"};
private _clock = diag_tickTime;
private _now = time;
private _survey = _record getOrDefault ["check", createHashMap];
if (_start isNotEqualTo []) then {
	_start params ["_origin", "_targetAt", ["_glide", 0]];
	private _flat = [(_targetAt # 0) - (_origin # 0), (_targetAt # 1) - (_origin # 1), 0];
	private _range = vectorMagnitude _flat;
	private _dir = if (_range > 0.01) then {_flat vectorMultiply (1 / _range)} else {[0, 1, 0]};
	// The line ends 0.5 m short of the target: what lies beyond it does not matter.
	private _length = (_range - 0.5) max 1;
	private _side = side group effectiveCommander _uav;
	if (_side == sideUnknown) then {_side = side _uav;};
	_survey = createHashMapFromArray [
		["phase", "GROUND"], ["ms", 0], ["origin", +_origin], ["target", +_targetAt],
		["dir", _dir], ["lat", [_dir # 1, -(_dir # 0), 0]], ["length", _length], ["glide", _glide max 0],
		["h", _record getOrDefault ["height", 1]], ["half", (_settings get "weaveCap") + 1.5],
		["n", (ceil (_length / 5)) + 1], ["i", 0], ["ground", []], ["base", []], ["by", []], ["plan", []], ["low", 0],
		["k", 0], ["seen", []], ["line", 0], ["seg", 0],
		["hostile", [_side, _uav getVariable ["A3UE_FPV_targetSide", sideUnknown]] call A3UE_fnc_fpv_getHostileSides]
	];
	_record set ["check", _survey];
};
if (count _survey == 0) exitWith {"IDLE"};

private _budget = _settings get "checkUnits";
private _units = 0;
private _origin = _survey get "origin";
private _targetAt = _survey get "target";
private _dir = _survey get "dir";
private _lat = _survey get "lat";
private _length = _survey get "length";
private _half = _survey get "half";
private _h = _survey get "h";
private _n = _survey get "n";
private _over = _settings get "over";
private _stationS = {params ["_i"]; (5 * _i) min _length};
private _point = {params ["_s", ["_off", 0]]; (_origin vectorAdd (_dir vectorMultiply _s)) vectorAdd (_lat vectorMultiply _off)};
// The ground the drone must clear: land, or the sea surface plus its wave margin.
private _surface = {
	params ["_p"];
	private _z = getTerrainHeightASL [_p # 0, _p # 1];
	if (_z < 1) then {_z = [_p # 0, _p # 1] call A3UE_fnc_fpv_surfaceZ;};
	_z
};
// The model of a map object, else the class: for the RPT line.
private _nameOf = {
	params ["_object"];
	private _model = (getModelInfo _object) param [0, ""];
	[_model, typeOf _object] select (_model isEqualTo "")
};
// The line's height at s along (linear between stations).
private _planAt = {
	params ["_s"];
	private _plan = _survey get "plan";
	private _i = ((floor (_s / 5)) max 0) min (_n - 1);
	private _j = (_i + 1) min (_n - 1);
	private _s0 = [_i] call _stationS;
	private _s1 = [_j] call _stationS;
	private _u = if (_s1 > _s0) then {(((_s - _s0) / (_s1 - _s0)) max 0) min 1} else {0};
	(_plan # _i) + ((_plan # _j) - (_plan # _i)) * _u
};
// Fly over [alongMin, alongMax] at topZ + over (named for the RPT line).
private _raise = {
	params ["_a0", "_a1", "_top", "_object"];
	private _base = _survey get "base";
	private _by = _survey get "by";
	private _z = _top + _over;
	for "_i" from (((floor ((_a0 - 1) / 5)) max 0) min (_n - 1)) to (((ceil ((_a1 + 1) / 5)) max 0) min (_n - 1)) do {
		if (_z > (_base # _i)) then {
			_base set [_i, _z];
			_by set [_i, _object];
		};
	};
};
// The line from the base heights: the slope limits both ways, then the glide.
private _replan = {
	private _env = +(_survey get "base");
	private _descent = _settings get "descent";
	private _climb = _settings get "climb";
	for "_i" from 1 to (_n - 1) do {
		_env set [_i, (_env # _i) max ((_env # (_i - 1)) - _descent * (([_i] call _stationS) - ([_i - 1] call _stationS)))];
	};
	for "_i" from (_n - 2) to 0 step -1 do {
		_env set [_i, (_env # _i) max ((_env # (_i + 1)) - _climb * (([_i + 1] call _stationS) - ([_i] call _stationS)))];
	};
	private _glide = _survey get "glide";
	private _plan = +_env;
	private _low = 0;
	if (_glide > 0) then {
		_low = _n - 1;
		for "_i" from 0 to (_n - 1) do {_plan set [_i, (_env # _i) max ((_origin # 2) - _glide * ([_i] call _stationS))];};
		for "_i" from 0 to (_n - 1) do {
			if ((_plan # _i) <= (_env # _i) + 0.01) exitWith {_low = _i;};
		};
	};
	_survey set ["plan", _plan];
	_survey set ["low", _low];
};

private _phase = _survey get "phase";
// ---- GROUND: the highest ground across the corridor every 5 m, skim height over it.
if (_phase == "GROUND") then {
	private _i = _survey get "i";
	private _ground = _survey get "ground";
	private _base = _survey get "base";
	private _by = _survey get "by";
	while {_i < _n && {_units < _budget}} do {
		private _s = [_i] call _stationS;
		private _g = (([[_s] call _point] call _surface) max ([[_s, -_half] call _point] call _surface)) max ([[_s, _half] call _point] call _surface);
		_ground pushBack _g;
		_base pushBack (_g + _h);
		_by pushBack objNull;
		_i = _i + 1;
		_units = _units + 0.25;
	};
	_survey set ["i", _i];
	if (_i >= _n) then {
		call _replan;
		_survey set ["phase", "OBJECTS"];
	};
};

// ---- OBJECTS: people, animals and vehicles by position; map objects (trees, bushes, buildings,
// walls, fences, rocks, ...) by their box. 40 m steps.
if ((_survey get "phase") == "OBJECTS" && {_units < _budget}) then {
	private _k = _survey get "k";
	private _steps = (ceil (_length / 40)) max 1;
	private _types = ["TREE", "SMALL TREE", "BUSH", "BUILDING", "HOUSE", "CHURCH", "CHAPEL", "CROSS", "ROCK", "ROCKS",
		"BUNKER", "FORTRESS", "FOUNTAIN", "VIEW-TOWER", "LIGHTHOUSE", "QUAY", "FUELSTATION", "HOSPITAL", "FENCE", "WALL",
		"HIDE", "BUSSTOP", "TRANSMITTER", "STACK", "RUIN", "TOURISM", "WATERTOWER", "POWER LINES", "RAILWAY",
		"POWERSOLAR", "POWERWAVE", "POWERWIND", "SHIPWRECK"];
	private _seen = _survey get "seen";
	private _hostile = _survey get "hostile";
	private _targetParent = objectParent _target;
	while {_k < _steps && {_units < _budget}} do {
		private _queryAt = [(20 + 40 * _k) min _length] call _point;
		{
			private _unit = _x;
			if (_unit isNotEqualTo _uav && {_unit isNotEqualTo _target} && {_unit isNotEqualTo _targetParent} && {!(_unit in _seen)}) then {
				_seen pushBack _unit;
				private _at = getPosASL _unit;
				private _rel = [(_at # 0) - (_origin # 0), (_at # 1) - (_origin # 1), 0];
				private _along = _rel vectorDotProduct _dir;
				private _isMan = (_unit isKindOf "Man") && {!(_unit isKindOf "Animal")};
				private _box = boundingBoxReal _unit;
				// LR-1d: an animal counts at its own size (engine session 1c: a rabbit as a 1.9 m man).
				private _reach = [((abs ((_box # 0) # 0)) max (abs ((_box # 1) # 0))) max ((abs ((_box # 0) # 1)) max (abs ((_box # 1) # 1))), 0.6] select _isMan;
				private _free = ((abs (_rel vectorDotProduct _lat)) - _reach) max 0;
				if (_along >= -_reach && {_along <= _length + _reach} && {_free < _half}
					&& {((_at distance2D _targetAt) - _reach) > 2}
					&& {!_isMan || {alive _unit && {!((side group _unit) in _hostile)}}}) then {
					private _top = [((getPosWorld _unit) # 2) + ((_box # 1) # 2), (_at # 2) + 1.9] select _isMan;
					[_along - _reach, _along + _reach, _top, _unit] call _raise;
				};
			};
		} forEach (_queryAt nearEntities [["Man", "LandVehicle", "Ship", "StaticWeapon", "Air"], 30]);
		private _objects = nearestTerrainObjects [[_queryAt # 0, _queryAt # 1], _types, 30, false, true];
		_units = _units + 5;
		{
			private _object = _x;
			if !(_object in _seen) then {
				_seen pushBack _object;
				_units = _units + 0.1;
				private _box = boundingBoxReal _object;
				private _min = _box # 0;
				private _max = _box # 1;
				private _center = getPosWorld _object;
				private _yAxis = vectorDir _object;
				private _zAxis = vectorUp _object;
				private _xAxis = _yAxis vectorCrossProduct _zAxis;
				private _alongs = [];
				private _lats = [];
				{
					private _corner = (_center vectorAdd (_xAxis vectorMultiply (_x # 0))) vectorAdd (_yAxis vectorMultiply (_x # 1));
					private _rel = [(_corner # 0) - (_origin # 0), (_corner # 1) - (_origin # 1), 0];
					_alongs pushBack (_rel vectorDotProduct _dir);
					_lats pushBack (_rel vectorDotProduct _lat);
				} forEach [[_min # 0, _min # 1], [_min # 0, _max # 1], [_max # 0, _min # 1], [_max # 0, _max # 1]];
				private _a0 = selectMin _alongs;
				private _a1 = selectMax _alongs;
				private _l0 = selectMin _lats;
				private _l1 = selectMax _lats;
				private _free = if (_l0 <= 0 && {_l1 >= 0}) then {0} else {(abs _l0) min (abs _l1)};
				private _radius = ((abs (_min # 0)) max (abs (_max # 0))) max ((abs (_min # 1)) max (abs (_max # 1)));
				if (_a1 >= 0 && {_a0 <= _length} && {_free < _half} && {((_center distance2D _targetAt) - _radius) > 2}
					&& {!("wire" in (toLower ([_object] call _nameOf)))}) then {
					// Highest and lowest points, conservative for a leaning object.
					private _tilt = ((abs (_min # 0)) max (abs (_max # 0))) * (abs (_xAxis # 2)) + ((abs (_min # 1)) max (abs (_max # 1))) * (abs (_yAxis # 2));
					private _top = (_center # 2) + (_max # 2) * (_zAxis # 2) + _tilt;
					private _bottom = (_center # 2) + (_min # 2) * (_zAxis # 2) - _tilt;
					// Passed under (a bridge): its underside is well above the line all the way across it.
					if (_bottom <= (([_a0 max 0] call _planAt) max ([_a1 min _length] call _planAt)) + 1.5) then {
						[_a0, _a1, _top, _object] call _raise;
					};
				};
			};
		} forEach _objects;
		_k = _k + 1;
	};
	_survey set ["k", _k];
	if (_k >= _steps) then {
		call _replan;
		_survey set ["phase", "RAYS"];
	};
};

// ---- RAYS: five lines across the corridor at the line's height minus 0.3 m, 25 m segments. They
// catch what the map list misses: site sandbags, parked vehicles, wrecks, people, objects without a
// map type, a cable that really hangs at that height.
if ((_survey get "phase") == "RAYS" && {_units < _budget}) then {
	private _offsets = [0, -_half / 2, _half / 2, -_half, _half];
	private _segments = (ceil (_length / 25)) max 1;
	private _line = _survey get "line";
	private _seg = _survey get "seg";
	private _hostile = _survey get "hostile";
	private _targetParent = objectParent _target;
	while {_line < 5 && {_units < _budget}} do {
		private _off = _offsets # _line;
		private _s0 = 25 * _seg;
		private _s1 = (25 * (_seg + 1)) min _length;
		private _from = [_s0, _off] call _point;
		_from set [2, ([_s0] call _planAt) - 0.3];
		private _to = [_s1, _off] call _point;
		_to set [2, ([_s1] call _planAt) - 0.3];
		_units = _units + 1;
		{
			private _object = _x param [3, objNull];
			if (isNull _object) then {_object = _x param [2, objNull];};
			private _at = +(_x # 0);
			private _along = ([(_at # 0) - (_origin # 0), (_at # 1) - (_origin # 1), 0]) vectorDotProduct _dir;
			// The ground is the GROUND phase's; the target, its own vehicle and the last 2 m are the fuse's.
			if (!isNull _object && {_object isNotEqualTo _target} && {_object isNotEqualTo _targetParent} && {(_length + 0.5) - _along > 2}) then {
				if ((_object isKindOf "Man") && {!(_object isKindOf "Animal")}) then {
					if (alive _object && {!((side group _object) in _hostile)}) then {[_along - 0.6, _along + 0.6, ((getPosASL _object) # 2) + 1.9, _object] call _raise;};
				} else {
					// Its top, from a ray down at the point it was met.
					private _top = _at # 2;
					private _down = lineIntersectsSurfaces [[_at # 0, _at # 1, ((_at # 2) max (_from # 2)) + 40], [_at # 0, _at # 1, ([_at] call _surface) - 0.5],
						_uav, _target, true, 1, "VIEW", "GEOM"];
					_units = _units + 1;
					if (_down isNotEqualTo []) then {_top = (((_down # 0) # 0) # 2) max _top;};
					[_along - 1, _along + 1, _top, _object] call _raise;
				};
			};
		} forEach (lineIntersectsSurfaces [_from, _to, _uav, _target, true, 4, "VIEW", "GEOM"]);
		_seg = _seg + 1;
		if (_seg >= _segments) then {_seg = 0; _line = _line + 1;};
	};
	_survey set ["line", _line];
	_survey set ["seg", _seg];
	if (_line >= 5) then {
		call _replan;
		_survey set ["phase", "DONE"];
	};
};

private _slice = (diag_tickTime - _clock) max 0;
_survey set ["ms", (_survey get "ms") + _slice];
// For the RPT line: the most expensive single call (the per-frame cost) and the most expensive survey.
_record set ["sliceMsMax", (_record getOrDefault ["sliceMsMax", 0]) max (1000 * _slice)];
if ((_survey get "phase") != "DONE") exitWith {"RUNNING"};
private _ms = 1000 * (_survey get "ms");
_record set ["surveys", (_record getOrDefault ["surveys", 0]) + 1];
_record set ["surveyMsMax", (_record getOrDefault ["surveyMsMax", 0]) max _ms];
// The tallest thing the line flies over (not under the glide), for the RPT line.
private _plan = _survey get "plan";
private _base = _survey get "base";
private _ground = _survey get "ground";
private _by = _survey get "by";
private _hopTop = 0;
private _hopBy = objNull;
for "_i" from 0 to (_n - 1) do {
	private _object = _by # _i;
	if (!isNull _object && {(_plan # _i) <= (_base # _i) + 0.01}) then {
		private _tall = ((_base # _i) - _over) - (_ground # _i);
		if (_tall > _hopTop) then {_hopTop = _tall; _hopBy = _object;};
	};
};
private _hopName = if (isNull _hopBy) then {""} else {[_hopBy] call _nameOf};
if (_hopTop > (_record getOrDefault ["hopTop", 0])) then {
	_record set ["hopTop", _hopTop];
	_record set ["hopBy", _hopName];
};
_record set ["result", [_now, +_origin, +_targetAt, +_plan, _survey get "glide", [_survey get "low"] call _stationS, _hopTop, _hopName]];
_record set ["check", createHashMap];
"DONE"
