// LT-2 coordinated attack. One board per machine (missionNamespace, never broadcast). For every
// target it lists the drones cleared to attack it (holders) and the drones waiting (queue).
// - At most A3UE_FPV_attackersPerTarget drones hold a target; the rest wait in overwatch.
// - A free slot goes to the closest waiting drone, but not before the follow-up delay that
//   starts when an attack ends (strike, shot down, miss, target dropped).
// - A cleared drone still far out gives its slot to a much closer one; a cleared drone that
//   stays close without diving gives way after A3UE_FPV_attackSlotTimeout.
// - Targets within A3UE_FPV_attackSpacing metres of each other share one attack at a time, so
//   one warhead does not take the drone attacking the man next to its target.
// The controller calls this once per TRACKING pass, inside its unscheduled tick. Work is linear
// in the drones on this one target. No world queries.
// [uav, target] -> ["ATTACK", index, holders] or ["WAIT", index, waiting]
params [["_uav", objNull], ["_target", objNull]];
// F5 / PB-01: an RPC from a client never mutates this machine's board (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {["ATTACK", 0, 1]};
private _settings = call A3UE_fnc_fpv_wingSettings;
private _limit = _settings # 2;
if (_limit <= 0 || {isNull _uav} || {isNull _target} || {!local _uav}) exitWith {["ATTACK", 0, 1]};
private _key = netId _target;
if (_key == "") exitWith {["ATTACK", 0, 1]};
// The resolved target changed without a clear (a man boarded a vehicle): leave the old record.
if !((_uav getVariable ["A3UE_FPV_wingTarget", ""]) in ["", _key]) then {[_uav, "TARGET_CHANGED"] call A3UE_fnc_fpv_attackRelease;};
private _board = missionNamespace getVariable ["A3UE_FPV_attackBoard", createHashMap];
if (count _board == 0) then {missionNamespace setVariable ["A3UE_FPV_attackBoard", _board];};
private _now = time;
private _record = _board getOrDefault [_key, createHashMap];
if (count _record == 0) then {
	// Sweep finished records when a new target arrives on a full board (bounded, rare).
	if (count _board >= 24) then {
		{
			private _old = _board get _x;
			if (((_old get "holders") isEqualTo []) && {(_old get "queue") isEqualTo []} && {_now > (_old get "nextGrantAt") + 30}) then {_board deleteAt _x;};
		} forEach (keys _board);
	};
	_record = createHashMapFromArray [["holders", []], ["queue", []], ["nextGrantAt", 0], ["grants", 0], ["target", _target]];
	_board set [_key, _record];
};
private _followUp = {(_settings # 3) + 0.5 * ((_record get "grants") mod 3)};
private _valid = {
	params ["_drone", ["_onKey", _key]];
	!isNull _drone && {alive _drone} && {local _drone} && {_drone getVariable ["A3UE_FPV_managed", false]}
		&& {!(_drone getVariable ["A3UE_FPV_detonating", false])}
		&& {_drone getVariable ["A3UE_FPV_controllerRunning", false]}
		&& {!(_drone getVariable ["A3UE_FPV_cleanupPending", false])}
		&& {(_drone getVariable ["A3UE_FPV_wingTarget", ""]) == _onKey}
		&& {(_drone getVariable ["A3UE_FPV_mode", ""]) in ["TRACKING", "TERMINAL_ATTACK", "TERMINAL_VECTOR"]}
};
// Blast spacing: is a target within the spacing under attack right now? Only live attackers
// count, so a finished record nobody asks about can never block this one, and a cleared drone
// that has not dived within the slot timeout stops counting (it cannot hold up its neighbours).
// The neighbour's follow-up delay does not count: a drone cleared now needs seconds to arrive.
private _spacing = _settings # 11;
private _neighbourBusy = {
	private _busy = false;
	if (_spacing > 0) then {
		{
			private _otherKey = _x;
			private _other = _board get _otherKey;
			private _otherTarget = _other getOrDefault ["target", objNull];
			if (_otherKey != _key && {!_busy} && {!isNull _otherTarget} && {(_otherTarget distance _target) <= _spacing}) then {
				_busy = ((_other get "holders") findIf {
					[_x # 0, _otherKey] call _valid
						&& {((_x # 0) getVariable ["A3UE_FPV_mode", ""]) != "TRACKING" || {_now - (_x # 1) <= (_settings # 8)}}
				}) >= 0;
			};
		} forEach (keys _board);
	};
	_busy
};
private _log = {
	params ["_event", "_drone"];
	diag_log format ["[A3UE_FPV] wing target=%1 event=%2 id=%3 rangeM=%4 attackers=%5 waiting=%6 nextInS=%7", _key, _event, netId _drone,
		round (_drone distance _target), count _holders, count _queue, (round ((((_record get "nextGrantAt") - _now) max 0) * 10)) / 10];
};
private _holders = _record get "holders";
private _queue = (_record get "queue") select {[_x] call _valid};
private _held = count _holders;
_holders = _holders select {[_x # 0] call _valid};
if (count _holders < _held) then {
	// An attack ended without a release: the drone struck or was shot down.
	_record set ["nextGrantAt", (_record get "nextGrantAt") max (_now + (call _followUp))];
	["ENDED", _uav] call _log;
};
private _holderIndex = _holders findIf {(_x # 0) isEqualTo _uav};
if (_holderIndex < 0 && {!(_uav in _queue)}) then {
	_queue pushBack _uav;
	_uav setVariable ["A3UE_FPV_wingTarget", _key];
};
if (_holderIndex >= 0) then {
	// Cleared but close and not diving (no clear line, no flyable plan): give way.
	private _entry = _holders # _holderIndex;
	if ((_uav getVariable ["A3UE_FPV_mode", ""]) == "TRACKING" && {(_uav distance _target) <= 250}) then {
		if ((_entry # 2) < 0) then {_entry set [2, _now];};
		if (_now - (_entry # 2) > (_settings # 8) && {_queue isNotEqualTo []}) then {
			_holders deleteAt _holderIndex;
			_queue pushBack _uav;
			_holderIndex = -1;
			// It stands back for as long again, so the slot goes to another drone.
			_uav setVariable ["A3UE_FPV_wingBackoffUntil", _now + (_settings # 8)];
			["TIMEOUT", _uav] call _log;
		};
	} else {
		_entry set [2, -1];
	};
} else {
	// Waiting: take the slot of a cleared drone that is still far out and much farther than this one.
	if (count _holders >= _limit) then {
		private _range = _uav distance _target;
		private _swap = _holders findIf {
			private _other = _x # 0;
			(_other getVariable ["A3UE_FPV_mode", ""]) == "TRACKING" && {(_other distance _target) > 250}
				&& {(_other distance _target) > _range + 150}
		};
		if (_swap >= 0) then {
			private _other = (_holders # _swap) # 0;
			_holders set [_swap, [_uav, _now, [-1, _now] select (_range <= 250)]];
			_queue = [_other] + (_queue - [_uav]);
			_holderIndex = _swap;
			["SWAP", _uav] call _log;
		};
	};
};
// Free slots go to the closest waiting drones once the follow-up delay has passed.
while {count _holders < _limit && {_queue isNotEqualTo []} && {_now >= (_record get "nextGrantAt")} && {!(call _neighbourBusy)}} do {
	private _eligible = _queue select {_now >= (_x getVariable ["A3UE_FPV_wingBackoffUntil", -1])};
	if (_eligible isEqualTo []) then {_eligible = _queue;};
	private _drone = _eligible # 0;
	private _bestRange = 1e9;
	{
		private _range = _x distance _target;
		if (_range < _bestRange) then {_bestRange = _range; _drone = _x;};
	} forEach _eligible;
	_queue = _queue - [_drone];
	// Entry: [drone, cleared at, close (inside 250 m) and not diving since; -1 = not close].
	_holders pushBack [_drone, _now, [-1, _now] select (_bestRange <= 250)];
	_record set ["grants", (_record get "grants") + 1];
	if (_drone isEqualTo _uav) then {_holderIndex = (count _holders) - 1;};
	["CLEARED", _drone] call _log;
};
_record set ["holders", _holders];
_record set ["queue", _queue];
if (_holderIndex >= 0) exitWith {["ATTACK", _holderIndex, count _holders]};
["WAIT", _queue find _uav, count _queue]
