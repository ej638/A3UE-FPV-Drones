// 1.0.9 friendly FPV swarm: the swarm's own scheduled script on the server (spawned by swarmRequest).
// It launches the drones and runs one brain pass (swarmPass, in one unscheduled slice) every "scanS"
// seconds until the swarm is done. One script per swarm, one swarm at a time.
// SW-1g (EJ after SW1f: "fly in staggered, and spread out ... some trailing further behind"): a lead
// group "launchGap" s apart, then the last third (rounded down) as a trailing group "trailS" s after
// the first drone. The brain already runs while the trailing group waits (the lead group attacks at
// once); a swarm that leaves before then never launches them.
// [id, roles, families by role] -> nothing
params [["_id", ""], ["_roles", []], ["_families", createHashMap]];
if (!isServer || {isRemoteExecutedJIP} || {isRemoteExecuted && {remoteExecutedOwner != 2}}) exitWith {};
private _record = (missionNamespace getVariable ["A3UE_FPV_swarms", createHashMap]) getOrDefault [_id, createHashMap];
if (count _record == 0) exitWith {};
private _settings = call A3UE_fnc_fpv_swarmSettings;
private _center = _record get "center";
private _spawn = _record get "spawn";
private _bearing = _center getDir _spawn;
private _count = count _roles;
// SW-1e: each drone its own place in the group, drawn once here (never per frame): side lanes
// shuffled (SW-1f: its launch point); height, speed and loiter ring by launch order; every other
// drone circles the other way.
private _lanes = [];
for "_i" from 0 to (_count - 1) do {_lanes pushBack _i;};
for "_i" from (_count - 1) to 1 step -1 do {
	private _j = floor random (_i + 1);
	private _swap = _lanes # _i;
	_lanes set [_i, _lanes # _j];
	_lanes set [_j, _swap];
};
private _pick = {
	params ["_table", "_index", "_default"];
	private _value = (_settings get _table) param [_index, _default];
	[_default, _value] select (_value isEqualType 0 && {finite _value})
};
private _launch = {
	params ["_index"];
	private _role = _roles # _index;
	private _pool = _families getOrDefault [_role, []];
	if (_pool isNotEqualTo []) then {
		private _family = selectRandom _pool;
		// [height offset m, side lane m, speed factor, loiter ring offset m, circling direction]
		private _style = [
			["styleHeights", _index, 0] call _pick,
			["styleLanes", _lanes # _index, 0] call _pick,
			["styleSpeeds", _index, 1] call _pick,
			["styleRings", _index, 0] call _pick,
			[1, -1] select (_index mod 2)
		];
		// Each drone arrives at its own point of its ring, on the near side. SW-1f: it launches in its
		// own lane, "lane" m to the side of the launch point, and flies straight in from there.
		private _arrive = _center getPos [(_settings get "ring") + (_style # 3), _bearing + ((_index - ((_count - 1) / 2)) * 25)];
		private _lane = (((_style # 1) max -200) min 200);
		private _from = _spawn getPos [abs _lane, _bearing + ([90, -90] select (_lane < 0))];
		// Never out over the sea from a launch point on land (a coast): that drone keeps the launch point.
		if (surfaceIsWater _from && {!surfaceIsWater _spawn}) then {_from = +_spawn;};
		private _spec = createHashMapFromArray [
			["spawnPosATL", [_from # 0, _from # 1, _settings get "spawnHeight"]],
			["searchAnchorMarker", _record get "marker"],
			["siteType", "FriendlySwarm"],
			["profileId", "friendly_swarm"],
			["side", _record get "side"],
			["targetSide", sideUnknown],
			["familyId", _family],
			["payloadRole", _role],
			["launchDir", _spawn getDir _center],
			["vehicleInitMode", "DIRECT_BOOTSTRAP"],
			["initialMode", "IDLE"],
			["uavVars", [
				["A3UE_FPV_swarmId", _id, true],
				["A3UE_FPV_swarmTask", "INBOUND"],
				["A3UE_FPV_swarmTaskAt", time],
				["A3UE_FPV_swarmArrive", _arrive],
				["A3UE_FPV_swarmStyle", _style]
			]]
		];
		private _uav = _spec call A3UE_fnc_fpv_spawnManagedDrone;
		if (isNull _uav) then {
			diag_log format ["[A3UE_FPV] swarm id=%1 event=SPAWN_FAILED family=%2 role=%3", _id, _family, _role];
		} else {
			(_record get "drones") pushBack _uav;
			_record set ["launched", 1 + (_record get "launched")];
			// HQ says it once, with the whole swarm (the trailing group is on its way too).
			if ((_record get "launched") == 1) then {
				["STR_A3UE_FPV_SWARM_LAUNCHED", [_count]] remoteExecCall ["A3UE_fnc_fpv_swarmNotify", _record get "side"];
			};
			// SW-1c evidence: SW1b lost 5 drones to an enemy SAM, far from their orders. Rare, one line each.
			_uav addEventHandler ["IncomingMissile", {
				params ["_uav", "_ammo", "_vehicle"];
				diag_log format ["[A3UE_FPV] swarm id=%1 event=MISSILE drone=%2 task=%3 ammo=%4 from=%5 fromM=%6 pos=%7",
					_uav getVariable ["A3UE_FPV_swarmId", ""], netId _uav, _uav getVariable ["A3UE_FPV_swarmTask", ""], _ammo,
					typeOf _vehicle, round (_uav distance _vehicle), (getPosATL _uav) apply {round _x}];
			}];
			// SW-1j evidence: SW1i lost 8 of 16 drones to tower machine guns (droneLost gives only the
			// class). Which one (its id, against the RESERVE lines), from how far. One line per loss;
			// not its own warhead (SW1j: the drone's own crew is the killer then).
			_uav addEventHandler ["Killed", {
				params ["_uav", "_killer"];
				if (!isNull _killer && {(vehicle _killer) != _uav}) then {
					diag_log format ["[A3UE_FPV] swarm id=%1 event=SHOT drone=%2 task=%3 target=%4 by=%5 byClass=%6 byM=%7 aglM=%8",
						_uav getVariable ["A3UE_FPV_swarmId", ""], netId _uav, _uav getVariable ["A3UE_FPV_swarmTask", ""],
						_uav getVariable ["A3UE_FPV_targetNetId", ""], netId _killer, typeOf _killer, round (_uav distance _killer),
						round ((getPosATL _uav) # 2)];
				};
			}];
			// Only the server flies a swarm drone: no UAV terminal may connect to it (EJ, 17 November).
			[_uav] remoteExecCall ["A3UE_fnc_fpv_swarmLock", 0, _uav];
			diag_log format ["[A3UE_FPV] swarm id=%1 event=LAUNCH drone=%2 class=%3 family=%4 role=%5",
				_id, netId _uav, typeOf _uav, _family, _role];
		};
	};
};
// Launch times (s after the first drone): the lead group, then the trailing third.
private _trail = floor (_count / 3);
private _lead = _count - _trail;
private _times = [];
for "_i" from 0 to (_count - 1) do {
	_times pushBack ([_i * (_settings get "launchGap"), (_settings get "trailS") + ((_i - _lead) * (_settings get "launchGap"))] select (_i >= _lead));
};
_record set ["launching", true];
private _startAt = time;
private _next = 0;
private _passAt = 0;
while {(_record get "phase") != "DONE"} do {
	if (_record get "launching") then {
		// Launch whatever is due, while the swarm is still coming or on station.
		while {_next < _count && {(_record get "phase") in ["INBOUND", "ON_STATION"]} && {time >= _startAt + (_times # _next)}} do {
			[_next] call _launch;
			_next = _next + 1;
		};
		if (_next >= _count || {!((_record get "phase") in ["INBOUND", "ON_STATION"])}) then {
			_record set ["launching", false];
			if ((_record get "launched") == 0) then {
				// Nothing flew: the next pass closes the swarm with this reason.
				_record set ["phase", "LEAVING"];
				_record set ["leaveReason", "NO_LAUNCH"];
			};
		};
	};
	if (time >= _passAt) then {
		isNil {[_record, call A3UE_fnc_fpv_swarmSettings] call A3UE_fnc_fpv_swarmPass;};
		_passAt = time + ((call A3UE_fnc_fpv_swarmSettings) get "scanS");
	};
	private _wake = _passAt;
	if ((_record get "launching") && {_next < _count}) then {_wake = _wake min (_startAt + (_times # _next));};
	sleep (((_wake - time) max 0.05) min 1.5);
};
