// 1.0.9 friendly FPV swarm: one brain pass (server, one unscheduled slice, every "scanS" seconds).
// Phases: INBOUND -> ON_STATION -> LEAVING -> DONE.
// - INBOUND: on station when the first drone is within "engage" of the centre. Leaves if none gets
//   there within "inboundS" (a stuck launch).
// - ON_STATION: when a drone is free, one scan and the reservations (swarmAssign). Leaves when no
//   dive has started for "idleS" (SW-1e; whatever is left in the circle; SW-1g: 60 s) or after
//   "stationS" on station in all, never while a drone dives.
// - LEAVING: every drone not diving flies out; each is retired once 1 km from every player, at the
//   exit point, or "leaveS" after the swarm started leaving.
// - DONE: no drones left. Markers removed, the swarm closed, one summary line.
// [record, settings] -> phase after the pass
params [["_record", createHashMap], ["_settings", createHashMap]];
if !(call A3UE_fnc_fpv_lifecycleAccess) exitWith {"DONE"};
private _now = time;
private _id = _record get "id";
private _center = _record get "center";
private _engage = _settings get "engage";
private _drones = (_record get "drones") select {!isNull _x && {alive _x} && {_x getVariable ["A3UE_FPV_managed", false]}};
_record set ["drones", _drones];

private _leave = {
	params ["_reason"];
	_record set ["phase", "LEAVING"];
	_record set ["leaveAt", _now];
	_record set ["leaveReason", _reason];
	diag_log format ["[A3UE_FPV] swarm id=%1 event=LEAVING reason=%2 drones=%3 strikes=%4", _id, _reason, count _drones, _record get "strikes"];
	["STR_A3UE_FPV_SWARM_LEAVING", []] remoteExecCall ["A3UE_fnc_fpv_swarmNotify", _record get "side"];
};

// Done once nothing is left flying and nothing is still to be launched (SW-1g: the trailing group).
if (_drones isEqualTo [] && {!(_record getOrDefault ["launching", false])}) then {
	if ((_record get "phase") != "LEAVING") then {_record set ["leaveReason", "SPENT"];};
	_record set ["phase", "DONE"];
};

if ((_record get "phase") == "INBOUND") then {
	if ((_drones findIf {((getPosASL _x) distance2D _center) <= _engage}) >= 0) then {
		_record set ["phase", "ON_STATION"];
		_record set ["arrivedAt", _now];
		_record set ["lastTargetAt", _now];
		diag_log format ["[A3UE_FPV] swarm id=%1 event=ON_STATION drones=%2 inboundS=%3", _id, count _drones, round (_now - (_record get "createdAt"))];
		["STR_A3UE_FPV_SWARM_ON_STATION", []] remoteExecCall ["A3UE_fnc_fpv_swarmNotify", _record get "side"];
	} else {
		if (_now - (_record get "createdAt") > (_settings get "inboundS")) then {["INBOUND_TIMEOUT"] call _leave;};
	};
};

if ((_record get "phase") == "ON_STATION") then {
	private _busy = {(_x getVariable ["A3UE_FPV_swarmTask", ""]) in ["ATTACK", "DIVE"]} count _drones;
	private _free = {(_x getVariable ["A3UE_FPV_swarmTask", ""]) in ["INBOUND", "LOITER"]} count _drones;
	private _candidates = [];
	// Scan only when a drone is free.
	if (_free > 0) then {_candidates = [_record, _settings] call A3UE_fnc_fpv_swarmScan;};
	if (_busy > 0 || {_candidates isNotEqualTo []}) then {_record set ["lastTargetAt", _now];};
	if (_free > 0 && {_candidates isNotEqualTo []}) then {[_record, _candidates, _settings] call A3UE_fnc_fpv_swarmAssign;};
	private _anyDiving = (_drones findIf {(_x getVariable ["A3UE_FPV_swarmTask", ""]) == "DIVE"}) >= 0;
	// SW-1e (EJ after SW1d: "took forever to leave"): idle is no dive started for "idleS", whatever is
	// still in the circle (SW1d swarm 3 circled covered and protected targets for six minutes). A
	// run-in under way is dropped when the swarm leaves.
	private _lastDive = (_record getOrDefault ["lastDiveAt", -1]) max (_record get "arrivedAt");
	switch (true) do {
		case (!_anyDiving && {_now - _lastDive >= (_settings get "idleS")}): {["IDLE"] call _leave;};
		case (!_anyDiving && {_now - (_record get "arrivedAt") >= (_settings get "stationS")}): {["TIME"] call _leave;};
	};
};

if ((_record get "phase") == "LEAVING") then {
	private _players = allPlayers select {!(_x isKindOf "HeadlessClient_F")};
	private _exit = _record get "exit";
	{
		private _uav = _x;
		private _task = _uav getVariable ["A3UE_FPV_swarmTask", ""];
		if (_task != "DIVE") then {
			if (_task != "LEAVE") then {
				if (_task == "ATTACK") then {[_uav, 0, ""] call A3UE_fnc_fpv_swarmDrop;};
				[_uav, "LEAVE"] call A3UE_fnc_fpv_swarmSetTask;
			} else {
				private _pos = getPosASL _uav;
				private _clear = (_players findIf {(_x distance2D _pos) < (_settings get "leaveClear")}) < 0;
				if (_clear || {(_pos distance2D _exit) <= 150} || {_now - (_record get "leaveAt") >= (_settings get "leaveS")}) then {
					_record set ["returned", 1 + (_record get "returned")];
					[_uav] call A3UE_fnc_fpv_cleanupDrone;
					diag_log format ["[A3UE_FPV] swarm id=%1 event=RETIRED drone=%2 clear=%3", _id, netId _uav, _clear];
				};
			};
		};
	} forEach _drones;
};

// SW-1c evidence (only with A3UE_FPV_perfLog): every 5 s, where each drone is and what it does:
// [drone, task, metres from the centre, metres from its target (-1: none), speed m/s, height m].
if ((missionNamespace getVariable ["A3UE_FPV_perfLog", false]) isEqualTo true && {(_record get "phase") != "DONE"}
	&& {_now >= (_record getOrDefault ["trackAt", 0])}) then {
	_record set ["trackAt", _now + 5];
	private _rows = _drones apply {
		private _target = objectFromNetId (_x getVariable ["A3UE_FPV_targetNetId", ""]);
		[netId _x, _x getVariable ["A3UE_FPV_swarmTask", ""], round ((getPosASL _x) distance2D _center),
			if (isNull _target) then {-1} else {round ((getPosASL _x) distance2D (getPosASL _target))},
			round (vectorMagnitude (velocity _x)), round ((getPosATL _x) # 2)]
	};
	diag_log format ["[A3UE_FPV] swarm id=%1 event=TRACK phase=%2 drones=%3", _id, _record get "phase", _rows];
};
if ((_record get "phase") == "DONE") then {
	{deleteMarker _x;} forEach (_record get "markers");
	(missionNamespace getVariable ["A3UE_FPV_swarms", createHashMap]) deleteAt _id;
	if ((missionNamespace getVariable ["A3UE_FPV_swarmActive", ""]) == _id) then {missionNamespace setVariable ["A3UE_FPV_swarmActive", ""];};
	private _perf = _record get "divePerf";
	private _cruise = _record getOrDefault ["cruisePerf", [0, 0, 0]];
	private _launched = _record get "launched";
	diag_log format ["[A3UE_FPV] swarm id=%1 event=DONE reason=%2 launched=%3 strikes=%4 returned=%5 lost=%6 breaks=%7 drops=%8 diveSteps=%9 diveMeanMs=%10 diveMaxMs=%11 durationS=%12 again=%13 cruiseSteps=%14 cruiseMeanMs=%15 cruiseMaxMs=%16 flownBack=%17",
		_id, _record get "leaveReason", _launched, _record get "strikes", _record get "returned",
		(_launched - (_record get "strikes") - (_record get "returned")) max 0, _record get "breaks", _record get "drops",
		_perf # 0, ((_perf # 1) / ((_perf # 0) max 1)) toFixed 3, (_perf # 2) toFixed 3, round (_now - (_record get "createdAt")), _record getOrDefault ["reattacks", 0],
		_cruise # 0, ((_cruise # 1) / ((_cruise # 0) max 1)) toFixed 3, (_cruise # 2) toFixed 3, _record getOrDefault ["returns", 0]];
};
_record get "phase"
