// 1.0.9 friendly FPV swarm (SW-1): validated settings in one hashmap, cached for 2 s because the
// lean dive reads it every frame. The swarm size is a CBA setting (SW-2, read through userSetting);
// the other tunables are unsupported mission variables (read live on the server). The rest is the
// fixed shape of a swarm.
// [] -> hashmap
private _cache = missionNamespace getVariable ["A3UE_FPV_swarmSettingsCache", []];
if (_cache isEqualType [] && {count _cache == 2} && {diag_tickTime < (_cache # 0)}) exitWith {_cache # 1};
private _number = {
	params ["_name", "_default", "_min", "_max"];
	private _value = missionNamespace getVariable [_name, _default];
	if !(_value isEqualType 0 && {finite _value}) then {_value = _default;};
	(_value max _min) min _max
};
private _settings = createHashMapFromArray [
	// Drones per swarm (EJ after SW1: 7) and the most anti-tank drones in one (EJ: only with vehicles
	// in the circle; 2, then 4 after SW1h: "we're seeing how strong the armor stands up to drones";
	// all of them with armour in the circle, SW-1j).
	["size", ["swarmSize"] call A3UE_fnc_fpv_userSetting],
	["maxAT", round (["A3UE_FPV_swarmMaxAT", 4, 0, 8] call _number)],
	// The commander's cost in AU's Supports menu (SW-2; EJ, 17 November: 1 support point + 500 money, no
	// airport needed). Shown by the menu, charged by the server (swarmCall).
	["costPoints", 1], ["costMoney", 500],
	// The call circle (m). Drones only take enemies inside it and chase them 50 m beyond.
	["radius", ["A3UE_FPV_swarmRadius", 300, 100, 600] call _number],
	["margin", 50],
	// Leave after this long without a dive (s; SW-1e, EJ after SW1d: "took forever to leave"; whatever
	// is left in the circle; SW-1g, EJ after SW1f: "loiter for a short time and leave ... a minute"),
	// or this long on station in all (s).
	["idleS", ["A3UE_FPV_swarmIdleS", 60, 20, 600] call _number],
	["stationS", ["A3UE_FPV_swarmStationS", 360, 60, 1200] call _number],
	// Reserved targets at least this far apart (m; SW-1f: 25, was 15: in SW1e 9 of 25 lost drones died
	// in a neighbour's blast in their own dive, men 15-20 m apart; SW-1j, EJ after SW1j: back to 15, "there's
	// still 2-3 left that were kind of close", with dives at targets within "tapRadius" "tapGap" s apart
	// so the neighbour's blast has gone off first); no target this close to a friendly (m).
	["spacing", ["A3UE_FPV_swarmSpacing", 15, 0, 50] call _number],
	["safety", ["A3UE_FPV_swarmSafety", 15, 0, 50] call _number],
	// Launch: this far out (m), "behindM" behind the caller (SW-1j, EJ after SW1i: "spawn behind the
	// commander and fly over his head"), or on the side of the nearest rebel-held place without one.
	// SW-1i: at most 750 m, so a SAM in the circle never gets a shot (Arma's long-range SAM launchers,
	// MIM-145 and S-750, do not fire inside 1000 m; in SW1h they shot down 17 drones, firing from
	// 1058-1276 m, after a 1500 m launch).
	["spawnMin", 600], ["spawnMax", 750], ["spawnHeight", 60], ["behindM", 200],
	// Launch order (SW-1g, EJ after SW1f: "fly in staggered, and spread out ... some trailing further
	// behind"): a lead group "launchGap" s apart, and the last third (rounded down) as a trailing group
	// that leaves "trailS" s after the first drone, also "launchGap" apart.
	["launchGap", 1.5], ["trailS", 14],
	// Station: arrival/loiter ring and height (m), loiter speed (m/s); free drones within "engage" of
	// the centre take targets. SW-1c: a tighter, quicker ring over the zone (EJ: SW1b's 200 m ring at
	// 14 m/s, 90 s a lap, was "so far away you dont even know they're there"). SW-1d: a loitering
	// drone more than "returnM" outside the ring is flown back; a drone flown in is "arriveM" from
	// its point of the ring when the AI takes it.
	["ring", 120], ["height", 70], ["loiterSpeed", 18], ["engage", 600], ["returnM", 150], ["arriveM", 40],
	// The swarm's own cruise (SW-1d; inbound and run-ins): speed (m/s), level turn rate (deg/s), climb
	// rate (m/s) and the least height over the ground under it and 2 s ahead (m).
	// Turns (SW-1f, EJ after SW1e: a drone "did an abrupt turn and came back"; SW-1e swung 180 degrees
	// at 75 deg/s and 25 m/s, 3.4 g from a standing start): the turn rate builds at "turnAccel"
	// deg/s2 and eases out, never more than "latAccel" m/s2 sideways at the speed flown, and a drone
	// more than "brakeTurn" deg off its heading slows to "turnSpeed" m/s, as a pilot brakes into a turn.
	["runSpeed", 22], ["runTurn", 75], ["climb", 6], ["floorAGL", 25],
	["turnAccel", 120], ["latAccel", 15], ["brakeTurn", 60], ["turnSpeed", 12],
	// Style (SW-1e, EJ after SW1d: the group came in "clustered" and lost most of its first pass;
	// "mix up some of the altitudes"): each drone draws once, at launch, a height offset (m, on the
	// way in, in its run-ins and its loiter), a side lane (m; SW-1f: where it launches, to the side of
	// the launch point, then a straight line in; SW-1e's swerve out into the lane and back in again
	// looked like "a crazy twist together"), a speed factor and a loiter ring offset (m), and circles
	// one way or the other. Lanes are shuffled; the rest go by launch order.
	["styleHeights", [0, 20, -15, 10, -20, 25, -5, 15]],
	["styleLanes", [0, -35, 35, -70, 70, -105, 105, -140]],
	["styleSpeeds", [1, 0.92, 1.08, 0.96, 1.04, 0.88, 1.12, 1]],
	["styleRings", [0, 25, -25, 40, -40, 15, -15, 45]],
	// Run-in (SW-1b steep top-attack; SW-1g, EJ after SW1f: "pick a target, not picky about obstacles,
	// and go for them"): the drone flies straight at its target at its own height and dives once the
	// target is "diveAngle" degrees below the horizon (about 80 m out from 70 m) and within
	// "diveFacing" degrees of the way it flies (a target behind it: it turns round first). No sight
	// or corridor check, no passes: cover on the dive line takes the blast. Dives start "stagger" s
	// apart. SW-1h: a man, gunner or static dived at "maxTries" times and still there (in a building,
	// in a tower) is left alone for "triesS" s by every swarm (SW1g: a tower gun took one drone in each
	// of three swarms, all lost on the tower). Vehicles never are: armour may take several hits.
	// SW-1i: dives at the same target start at least "tapGap" s apart, so the next drone sees what
	// the last hit did (the target gone: it takes another; EJ after SW1h). SW-1j: also dives at targets
	// within "tapRadius" m of each other (the old spacing).
	// SW-2b (session SW2): a target "overheadAngle" degrees or more below and within "overheadFacing" of
	// the way the drone flies dives at once (from overhead, steering at a point inside its own turning
	// circle, it circled for 46 s); one behind it is still turned round to first.
	["diveAngle", 40], ["diveFacing", 30], ["overheadAngle", 65], ["overheadFacing", 120], ["stagger", 0.6], ["tapGap", 3],
	["tapRadius", 25], ["maxTries", 2], ["triesS", 600],
	// SW-1l (EJ after SW1k): men on the stairs of these towers (and their ruins) are never targets, within
	// "stairM" m of the tower (Arma's patrol towers, about 7 m across; the Tanoa one named on its own).
	["stairTowers", ["Cargo_Patrol_base_F", "Land_Cargo_Patrol_V4_F", "Land_Cargo_Patrol_V1_ruins_F",
		"Land_Cargo_Patrol_V2_ruins_F", "Land_Cargo_Patrol_V3_ruins_F", "Land_Cargo_Patrol_V4_ruins_F"]], ["stairM", 6],
	// SW-1m (EJ after SW1l: "if there are really no other targets after a short time, a drone will pick and
	// dive on one of the seen but obstructed targets"): the men on the stairs become targets once no other
	// target has been left in the circle for "lastS" s (still at most "maxTries" dives each).
	["lastS", 10],
	// Lean dive: turn rate (deg/s), acceleration (m/s2), contact radius on a soldier (m).
	// Push-over (SW-1e, EJ: the dive "almost snaps"): the turn rate starts at "pushRate" deg/s and
	// grows "pushRamp" deg/s each second; the speed builds at "pushAccel" m/s2 plus gravity.
	["turnRate", 150], ["accel", 14], ["contact", 1.2],
	// Bank in the dive (deg; SW-1f, EJ after SW1e: "a crazy twist together when they started diving").
	["pushRate", 30], ["pushRamp", 150], ["pushAccel", 3], ["diveBank", 12],
	// Time limits (s): run-in, dive, inbound, leaving; a leaving drone is deleted this far from every player (m).
	["runInS", 75], ["diveS", 25], ["inboundS", 240], ["leaveS", 120], ["leaveClear", 1000],
	// Brain pass interval (s).
	["scanS", 1.5],
	// Dive speed (m/s) per family: [anti-personnel, anti-tank], the 1.0.x dive table.
	["speeds", createHashMapFromArray [["armafpv", [34, 32]], ["kvn", [30, 28]], ["fpv_ua", [28, 26]]]]
];
missionNamespace setVariable ["A3UE_FPV_swarmSettingsCache", [diag_tickTime + 2, _settings]];
_settings
