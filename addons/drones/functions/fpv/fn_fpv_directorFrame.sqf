// LT-2 frame director. One EachFrame handler per machine (installed by controllerState). It
// ticks the controllers of the drones that are attacking: cleared and closing on the target, or
// diving. Their steering, fuse and strike then run every frame, however late the script
// scheduler is. Every other drone stays with its scheduled script at a low rate.
// - A tick is the same code the scheduled script runs (runController with its state): one
//   controller, one movement writer, two pacers.
// - Work per frame is bounded: after A3UE_FPV_frameBudgetMs the remaining due drones wait one
//   frame and go first in the next (round robin, no starvation). At least one tick per frame.
// - A drone is ticked when its own controller says it is due, so nothing runs twice in a frame
//   and nothing runs while simulation time stands still (pause).
// Idle cost: one empty-array test and one clock compare per frame.
private _states = A3UE_FPV_directorStates;
private _perf = A3UE_FPV_perf;
if (_states isNotEqualTo []) then {
	private _settings = call A3UE_fnc_fpv_wingSettings;
	private _count = count _states;
	_perf set [4, (_perf # 4) + 1];
	if (_count > (_perf # 5)) then {_perf set [5, _count];};
	private _budget = (_settings # 1) / 1000;
	private _frameAt = diag_tickTime;
	private _now = time;
	private _first = (missionNamespace getVariable ["A3UE_FPV_directorCursor", 0]) mod _count;
	private _next = -1;
	private _ticked = 0;
	private _changed = false;
	for "_i" from 0 to (_count - 1) do {
		private _index = (_first + _i) mod _count;
		private _state = _states # _index;
		if (!(_settings # 0) || {!(_state get "running")} || {!(_state get "hot")}) then {
			// Not attacking any more (or the director was switched off): back to its script.
			_state set ["listed", false];
			_changed = true;
		} else {
			if (_now >= (_state get "dueAt")) then {
				if (_ticked > 0 && {diag_tickTime - _frameAt >= _budget}) then {
					if (_next < 0) then {_next = _index;};
				} else {
					private _at = diag_tickTime;
					[_state get "uav", _state get "generation", _state] call A3UE_fnc_fpv_runController;
					private _cost = diag_tickTime - _at;
					_perf set [0, (_perf # 0) + 1];
					_perf set [1, (_perf # 1) + _cost];
					if (_cost > (_perf # 2)) then {_perf set [2, _cost];};
					_ticked = _ticked + 1;
					if (!(_state get "running") || {!(_state get "hot")}) then {
						_state set ["listed", false];
						_changed = true;
					};
				};
			};
		};
	};
	if (_next >= 0) then {_perf set [3, (_perf # 3) + 1];};
	missionNamespace setVariable ["A3UE_FPV_directorCursor", _next max 0];
	private _frameCost = diag_tickTime - _frameAt;
	if (_frameCost > (_perf # 10)) then {_perf set [10, _frameCost];};
	if (_changed) then {A3UE_FPV_directorStates = _states select {_x get "listed"};};
};
if (diag_tickTime >= (missionNamespace getVariable ["A3UE_FPV_perfNextAt", 0])) then {call A3UE_fnc_fpv_perfReport;};
