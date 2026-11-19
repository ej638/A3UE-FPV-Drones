// 1.0.9 friendly FPV swarm: reservations, one target per drone (the brain, on the server, in one
// unscheduled slice). A drone's reservation is its own target while it attacks or dives, so the
// board can never disagree with the drones.
// - Every free drone (inbound or loitering, within "engage" of the centre) takes the best target
//   nobody holds, at least "spacing" from every held target, and goes at once. Dive starts are
//   staggered by "stagger" seconds so they don't all land in the same frame.
// - Anti-tank drones prefer armour, then armed vehicles, autonomous systems (SAM, radar), other
//   vehicles, statics, machine gunners, men. Anti-personnel drones prefer crewed static weapons, then
//   machine gunners, other men, armed then other soft vehicles, and never take armour or an
//   autonomous system (SW-1f, EJ after SW1e: "manned machine guns" first; SW-1h, EJ after SW1g: the
//   SAM and radar shrugged off AP hits). Nearer is better.
// - Anti-tank drones stay on armour or a system until it is gone (SW-1h double tap; SW-1i, EJ after
//   SW1h: "the AT drones can keep going for the high value targets until they are no longer a valid
//   target"; an APC took six AT drones): any number may hold one. Their dives go in "tapGap" s apart
//   (swarmTick), so each sees what the last did; with the target gone they take another.
// - Anti-tank drones choose first in a pass (SW1h: in swarm 7 both took men with the APC in the
//   circle; an anti-personnel drone's man next to it is the likely block, through spacing).
// - Each reservation is checked once for friendlies near the target (swarmSafe; no enemy, wounded or
//   surrendered, protects anyone) and for a roof over it (swarmClear, one short ray, remembered 20 s;
//   at most 12 a pass). The roof only orders the targets (SW-1g, EJ after SW1f: "not picky about
//   obstacles"): open ones first, a crewed static weapon under a roof (a tower or bunker gun) after
//   the open guns and machine gunners but before the open men (SW-1f), anyone else under a roof last.
//   Nothing is refused for cover and nobody waits: the best target there is gets taken at once.
// - A man, gunner or static dived at "maxTries" times and still there (inside a building, in a
//   tower) is left alone for "triesS" s by every swarm (SW-1h; SW-1g counted only this swarm's
//   STRIKE lines, so a drone that blew up on the tower never counted). Vehicles are never left alone.
// - Last resort (SW-1m, EJ after SW1l: "all the 'real' targets are taken care of by the drones or
//   players first, and these guys in known obstructed locations can be cleaned up"): a man on a patrol
//   tower's stairs (swarmScan) is taken only once no other target (alive, in the circle, not tried
//   out) has been left for "lastS" s. Then he is an ordinary target, with the same tries.
// [record, candidates (swarmScan), settings] -> number of new reservations
params [["_record", createHashMap], ["_candidates", []], ["_settings", createHashMap]];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {0};
if (_candidates isEqualTo []) exitWith {0};
private _now = time;
private _center = _record get "center";
private _side = _record get "side";
private _hidden = _record get "hidden";
private _engage = _settings get "engage";
private _spacing = _settings get "spacing";
private _safety = _settings get "safety";
// Dives per target, machine-wide (swarmTick counts them): [count, until].
private _tries = missionNamespace getVariable ["A3UE_FPV_swarmTries", createHashMap];
private _maxTries = _settings get "maxTries";
private _triedOut = {
	params ["_id", "_class"];
	private _tried = _tries getOrDefault [_id, [0, -1]];
	!(_class in ["ARMOR", "SYSTEM", "GUN", "VEHICLE"]) && {(_tried # 0) >= _maxTries} && {_now < (_tried # 1)}
};
// SW-1m: the last resort opens "lastS" s after the first pass with no other target left; any other
// target closes it again.
private _real = {!(_x param [3, false]) && {!([netId (_x # 0), _x # 1] call _triedOut)}} count _candidates;
private _lastFrom = _record getOrDefault ["lastResortFrom", -1];
if (_real > 0) then {_lastFrom = -1;} else {if (_lastFrom < 0) then {_lastFrom = _now;};};
_record set ["lastResortFrom", _lastFrom];
private _lastOpen = _lastFrom >= 0 && {_now - _lastFrom >= (_settings get "lastS")};
private _priority = createHashMapFromArray [
	["AT", createHashMapFromArray [["ARMOR", 0], ["GUN", 0.5], ["SYSTEM", 0.75], ["VEHICLE", 1], ["STATIC", 3], ["MG", 4], ["MAN", 5]]],
	["AP", createHashMapFromArray [["STATIC", 0], ["MG", 0.5], ["MAN", 1], ["GUN", 3], ["VEHICLE", 4]]]
];
private _held = [];
private _free = [];
{
	private _uav = _x;
	if (alive _uav && {_uav getVariable ["A3UE_FPV_managed", false]}) then {
		private _task = _uav getVariable ["A3UE_FPV_swarmTask", ""];
		if (_task in ["ATTACK", "DIVE"]) then {
			private _heldTarget = objectFromNetId (_uav getVariable ["A3UE_FPV_targetNetId", ""]);
			if (!isNull _heldTarget) then {_held pushBack [netId _heldTarget, getPosASL _heldTarget];};
		} else {
			if (_task in ["INBOUND", "LOITER"] && {((getPosASL _uav) distance2D _center) <= _engage}
				&& {_uav getVariable ["A3UE_FPV_controllerRunning", false]}
				&& {!([_uav] call A3UE_fnc_fpv_isExternallyControlled)}) then {_free pushBack _uav;};
		};
	};
} forEach (_record get "drones");
if (_free isEqualTo []) exitWith {0};
// Anti-tank drones choose first (SW-1i), then the drones closest to the centre.
private _order = [];
{
	_order pushBack [((getPosASL _x) distance2D _center) + ([1e5, 0] select ((_x getVariable ["A3UE_FPV_payloadRole", "AP"]) == "AT")), _forEachIndex];
} forEach _free;
_order sort true;
_free = _order apply {_free # (_x # 1)};
private _traces = 12;
// Roof answers per target, [covered, valid until] (SW-1c; machine-local, never broadcast).
private _roofs = _record getOrDefault ["roofs", createHashMap];
_record set ["roofs", _roofs];
private _assigned = 0;
private _goAt = (_record getOrDefault ["nextGoAt", _now]) max _now;
// SW-1e evidence: why free drones took nothing (target id -> what protects it).
private _waitUnsafe = createHashMap;
// SW-1i evidence: armour and systems in the circle this pass (an anti-tank drone that takes a man
// with heavy=1 found the armour blocked: spacing, friendlies or its roof).
private _heavy = {(_x # 1) in ["ARMOR", "SYSTEM"]} count _candidates;
{
	private _uav = _x;
	private _role = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];
	if !(_role in ["AT", "AP"]) then {_role = "AP";};
	private _table = _priority get _role;
	private _from = getPosASL _uav;
	private _ranked = [];
	{
		_x params ["_target", "_class", "_pos", ["_last", false]];
		private _id = netId _target;
		// Free and spaced from every other held target; armour or a system stays open to every
		// anti-tank drone until it is gone (SW-1i).
		private _spaced = (_held findIf {(_x # 0) != _id && {((_x # 1) distance2D _pos) < _spacing}}) < 0
			&& {((_held findIf {(_x # 0) == _id}) < 0) || {_role == "AT" && {_class in ["ARMOR", "SYSTEM"]}}};
		if (_class in _table && {!_last || {_lastOpen}} && {_spaced} && {alive _target} && {_now >= (_hidden getOrDefault [_id, -1])}
			&& {!([_id, _class] call _triedOut)}) then {
			// A target known to be under a roof ranks after every open one (SW-1c); SW-1f: a static
			// gun under a roof only after the open guns and machine gunners.
			private _roof = _roofs getOrDefault [_id, [false, -1]];
			private _covered = (_roof # 0) && {_now < (_roof # 1)};
			private _late = [0, [10, 0.75] select (_class == "STATIC")] select _covered;
			_ranked pushBack [(_table get _class) + ((_from distance2D _pos) / 300) + _late, _forEachIndex];
		};
	} forEach _candidates;
	_ranked sort true;
	private _choice = objNull;
	private _fallback = objNull;
	private _covered = false;
	{
		(_candidates # (_x # 1)) params ["_target", "_class", "_pos"];
		private _usable = true;
		private _roofed = false;
		private _unsafe = [_side, _target, _safety] call A3UE_fnc_fpv_swarmSafe;
		if (_unsafe != "") then {
			_hidden set [netId _target, _now + 10];
			_waitUnsafe set [netId _target, _unsafe];
			_usable = false;
		};
		// A roof over the target (inside a building, a tower post, the cargo HQ): one ray 30 m up,
		// remembered for 20 s. A newly found roof puts the target behind the open ones here (the next
		// pass ranks it so); kept as the fallback. Out of rays: next pass.
		if (_usable) then {
			private _id = netId _target;
			private _roof = _roofs getOrDefault [_id, [false, -1]];
			if (_now >= (_roof # 1)) then {
				if (_traces > 0) then {
					_traces = _traces - 1;
					private _aim = aimPos _target;
					_roof = [([_uav, _target, _aim, _aim vectorAdd [0, 0, 30]] call A3UE_fnc_fpv_swarmClear) isNotEqualTo [], _now + 20];
					_roofs set [_id, _roof];
				} else {
					_roof = [];
				};
			};
			if (_roof isEqualTo []) then {
				_usable = false;
			} else {
				if (_roof # 0) then {
					if (_class == "STATIC") then {
						_roofed = true;
					} else {
						if (isNull _fallback) then {_fallback = _target;};
						_usable = false;
					};
				};
			};
		};
		if (_usable) exitWith {_choice = _target; _covered = _roofed;};
	} forEach (_ranked select [0, 5]);
	// Nothing open: the target under a roof, at once (SW-1g; SW-1c made the drone circle first). The
	// dive goes in at the steep angle and the cover takes the blast if it is in the way.
	if (isNull _choice && {!isNull _fallback}) then {
		_choice = _fallback;
		_covered = true;
	};
	if (!isNull _choice) then {
		private _entry = (_candidates select {(_x # 0) isEqualTo _choice}) # 0;
		private _class = _entry # 1;
		_uav setVariable ["A3UE_FPV_targetNetId", netId _choice, true];
		_uav setVariable ["A3UE_FPV_targetRevision", 1 + (_uav getVariable ["A3UE_FPV_targetRevision", 0]), true];
		_uav setVariable ["A3UE_FPV_swarmGoAt", _goAt];
		_uav setVariable ["A3UE_FPV_swarmTargetClass", _class];
		_uav setVariable ["A3UE_FPV_swarmRetries", 0];
		[_uav, "ATTACK"] call A3UE_fnc_fpv_swarmSetTask;
		_held pushBack [netId _choice, getPosASL _choice];
		_goAt = _goAt + (_settings get "stagger");
		_assigned = _assigned + 1;
		diag_log format ["[A3UE_FPV] swarm id=%1 event=RESERVE drone=%2 role=%3 target=%4 class=%5 distM=%6 goInS=%7 covered=%8 heavy=%9 last=%10",
			_record get "id", netId _uav, _role, netId _choice, _class,
			round (_from distance2D (getPosASL _choice)), ((_uav getVariable ["A3UE_FPV_swarmGoAt", _now]) - _now) toFixed 1, [0, 1] select _covered, _heavy,
			[0, 1] select (_entry param [3, false])];
	};
} forEach _free;
_record set ["nextGoAt", _goAt];
// SW-1e evidence: free drones, targets in the circle and no reservation (SW1d: three minutes of
// circling with no line saying why). At most every 15 s.
if (_assigned == 0 && {_now >= (_record getOrDefault ["waitAt", 0])}) then {
	_record set ["waitAt", _now + 15];
	// SW-1h: what the candidates are (SW1g: an anti-personnel swarm waited a minute on two of them).
	private _kinds = createHashMap;
	{_kinds set [_x # 1, 1 + (_kinds getOrDefault [_x # 1, 0])];} forEach _candidates;
	// SW-1m: the men on the stairs among them, and when the last resort opens (s; -1: other targets left).
	diag_log format ["[A3UE_FPV] swarm id=%1 event=WAIT free=%2 candidates=%3 unsafe=%4 triedOut=%5 classes=%6 why=%7 stairs=%8 lastInS=%9",
		_record get "id", count _free, count _candidates, count _waitUnsafe,
		{[netId (_x # 0), _x # 1] call _triedOut} count _candidates,
		((keys _kinds) apply {format ["%1:%2", _x, _kinds get _x]}) joinString ",",
		if (count _waitUnsafe > 0) then {(values _waitUnsafe) # 0} else {""},
		{_x param [3, false]} count _candidates,
		[round (((_settings get "lastS") - (_now - _lastFrom)) max 0), -1] select (_lastFrom < 0)];
};
_assigned
