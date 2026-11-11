// LT-2 evidence line, written by the director every 10 s (A3UE_FPV_perfLog) or 60 s, and only
// when a controller ran in that window. It measures what the earlier runs had to infer:
// - director: frames with attacking drones, most at once, ticks, mean and longest tick, longest
//   frame, frames that ran out of budget;
// - scheduled controllers: how many, wake-ups and ticks, and how late the script scheduler woke
//   them (mean and longest), which is the scheduler lag every other mission script sees too;
// - target scans done and the machine's FPS.
// Costs are sums of diag_tickTime differences: the mean stays right when the clock gets coarse
// late in a long session, single values (longest tick) do not.
// One line per window, no per-frame or per-drone logging.
private _perf = A3UE_FPV_perf;
private _now = diag_tickTime;
private _window = _now - (_perf # 11);
missionNamespace setVariable ["A3UE_FPV_perfNextAt", _now + ([60, 10] select ((call A3UE_fnc_fpv_wingSettings) # 10))];
A3UE_FPV_controllerStates = (missionNamespace getVariable ["A3UE_FPV_controllerStates", []]) select {
	(_x get "running") && {alive (_x get "uav")}
};
private _scans = missionNamespace getVariable ["A3UE_FPV_scanCount", 0];
if ((_perf # 0) + (_perf # 6) > 0) then {
	private _ms = {(round (_this * 100000)) / 100};
	diag_log format ["[A3UE_FPV] director windowS=%1 fps=%2 controllers=%3 | attackFrames=%4 attackersMax=%5 ticks=%6 meanMs=%7 maxMs=%8 frameMaxMs=%9 overBudget=%10 | scheduled wakes=%11 ticks=%12 lateMeanMs=%13 lateMaxMs=%14 | scans=%15",
		round _window, round diag_fps, count A3UE_FPV_controllerStates,
		_perf # 4, _perf # 5, _perf # 0, ((_perf # 1) / ((_perf # 0) max 1)) call _ms, (_perf # 2) call _ms, (_perf # 10) call _ms, _perf # 3,
		_perf # 6, _perf # 9, ((_perf # 7) / ((_perf # 6) max 1)) call _ms, (_perf # 8) call _ms, _scans];
};
missionNamespace setVariable ["A3UE_FPV_scanCount", 0];
{_perf set [_x, 0];} forEach [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
_perf set [11, _now];
