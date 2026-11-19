// 1.0.9 friendly FPV swarm: the server's entry point. Design: docs/internal/FPV_Friendly_Swarm_Design_20261116.md.
// SW-1 accepts only calls from the server itself (the QA command on a hosted game, which the debug
// console may deliver as a remote call from owner 2, or a server script). SW-2 adds the commander's
// paid request from AU's Supports menu, checked by sender and charged here.
// - One swarm at a time, claimed in this unscheduled call.
// - Drone mix (EJ, 17 November): anti-tank drones only for crewed enemy vehicles in the circle at the
//   call (boats too since SW-1m), at most "maxAT" (all of them with armour, SW-1j); with none, the whole
//   swarm is anti-personnel.
// - Launch point: "spawnMin"-"spawnMax" from the centre, behind the requester (SW-1j), or on the side
//   of the nearest rebel-held place without one.
// [centre position, size (default: the setting), requester (optional: the unit calling it)] -> [true, swarm id] or [false, reason]
params [["_center", []], ["_size", -1], ["_requester", objNull]];
if (!isServer || {isRemoteExecutedJIP} || {isRemoteExecuted && {remoteExecutedOwner != 2}}) exitWith {[false, "AUTHORITY"]};
if !(_center isEqualType [] && {count _center >= 2}) exitWith {[false, "POSITION"]};
if (((_center select [0, 2]) findIf {!(_x isEqualType 0) || {!finite _x}}) >= 0) exitWith {[false, "POSITION"]};
_center = [_center # 0, _center # 1, 0];
if ((_center # 0) < 0 || {(_center # 1) < 0} || {(_center # 0) > worldSize} || {(_center # 1) > worldSize}) exitWith {[false, "POSITION"]};
private _settings = call A3UE_fnc_fpv_swarmSettings;
if !(_size isEqualType 0 && {finite _size} && {_size > 0}) then {_size = _settings get "size";};
_size = ((round _size) max 3) min 8;
private _side = if (isNil "teamPlayer") then {independent} else {teamPlayer};
private _sideKey = switch (_side) do {
	case west: {"west"};
	case east: {"east"};
	case independent: {"independent"};
	default {""};
};
if (_sideKey == "") exitWith {[false, "SIDE"]};

// Loaded families with drones for the rebel side, per role.
private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) then {_catalog = call A3UE_fnc_fpv_buildCompatCatalog;};
private _families = createHashMapFromArray [["AT", []], ["AP", []]];
{
	private _familyId = _x;
	private _roles = ((_catalog get _familyId) getOrDefault ["classesBySide", createHashMap]) getOrDefault [_sideKey, createHashMap];
	{
		if ((_roles getOrDefault [_x, []]) isNotEqualTo []) then {(_families get _x) pushBack _familyId;};
	} forEach ["AT", "AP"];
} forEach (keys _catalog);
if ((_families get "AP") isEqualTo [] && {(_families get "AT") isEqualTo []}) exitWith {[false, "NO_DRONE_PACK"]};

private _active = missionNamespace getVariable ["A3UE_FPV_swarmActive", ""];
// A claim whose swarm no longer exists (its script failed) does not block the next call.
if (_active != "" && {!(_active in (missionNamespace getVariable ["A3UE_FPV_swarms", createHashMap]))}) then {_active = "";};
if (_active != "") exitWith {[false, "SWARM_ACTIVE"]};
private _number = 1 + (missionNamespace getVariable ["A3UE_FPV_swarmCount", 0]);
missionNamespace setVariable ["A3UE_FPV_swarmCount", _number];
private _id = format ["swarm%1", _number];
missionNamespace setVariable ["A3UE_FPV_swarmActive", _id];

// Launch point (SW-1j, EJ after SW1i: "the drones spawn behind the commander and fly over his head on
// the way to the target ... your drone operators behind you further back on the lines are flying in"):
// on the line from the centre through the caller, "behindM" past him. Coming in over the caller's side,
// they take the targets on that side first (nearer ranks better, swarmAssign). A caller more than
// "spawnMax" - "behindM" out sees them launch between him and the target (SW-1i: never beyond
// "spawnMax", for the SAMs). A caller within 50 m of the centre (SW1j: EJ called the first base from
// 30 m, and they came from the far side): behind his back, the way he faces. Without a caller (a server
// script): on the side of the nearest rebel-held place (HQ, outposts, towns, airports).
private _home = [];
private _homeDistance = 1e9;
private _from = "HOME";
private _callerDistance = -1;
if (_requester isEqualType objNull && {alive _requester}) then {
	private _callerPos = getPosASL _requester;
	_callerDistance = _callerPos distance2D _center;
	_homeDistance = _callerDistance + (_settings get "behindM");
	if (_callerDistance >= 50) then {
		_home = _callerPos;
		_from = "CALLER";
	} else {
		_home = _center getPos [100, (getDir _requester) + 180];
		_from = "FACING";
	};
};
if (_home isEqualTo []) then {
	private _markers = ["Synd_HQ"];
	if (!isNil "markersX" && {!isNil "sidesX"}) then {
		_markers append (markersX select {(sidesX getVariable [_x, sideUnknown]) == _side});
	};
	{
		private _markerPos = getMarkerPos _x;
		if (_markerPos isNotEqualTo [0, 0, 0]) then {
			private _distance = _markerPos distance2D _center;
			if (_distance < _homeDistance) then {_homeDistance = _distance; _home = _markerPos;};
		};
	} forEach _markers;
};
private _bearing = if (_home isEqualTo []) then {random 360} else {_center getDir _home};
private _launchDistance = if (_home isEqualTo []) then {_settings get "spawnMax"} else {(_homeDistance max (_settings get "spawnMin")) min (_settings get "spawnMax")};
private _spawn = _center getPos [_launchDistance, _bearing];
private _exit = _center getPos [(_settings get "spawnMax") + 300, _bearing];

// The call area, shown to everyone while the swarm is up.
private _color = switch (_side) do {case west: {"ColorWEST"}; case east: {"ColorEAST"}; default {"ColorGUER"};};
private _area = format ["A3UE_FPV_%1_area", _id];
// Local setters, then one global call that sends each marker's whole state once.
createMarker [_area, _center];
_area setMarkerShapeLocal "ELLIPSE";
_area setMarkerSizeLocal [_settings get "radius", _settings get "radius"];
_area setMarkerBrushLocal "Border";
_area setMarkerColor _color;
private _label = format ["A3UE_FPV_%1_label", _id];
createMarker [_label, _center];
_label setMarkerTypeLocal "hd_objective";
_label setMarkerColorLocal _color;
_label setMarkerText (localize "STR_A3UE_FPV_SWARM_MARKER");

private _record = createHashMapFromArray [
	["id", _id], ["center", _center], ["side", _side], ["size", _size], ["spawn", _spawn], ["exit", _exit],
	["marker", _area], ["markers", [_area, _label]], ["requester", _requester],
	["phase", "INBOUND"], ["createdAt", time], ["arrivedAt", -1], ["lastTargetAt", -1], ["leaveAt", -1], ["leaveReason", ""],
	["drones", []], ["launched", 0], ["hidden", createHashMap], ["nextGoAt", 0],
	["strikes", 0], ["breaks", 0], ["drops", 0], ["returned", 0], ["reattacks", 0], ["divePerf", [0, 0, 0]]
];
// The mix, from what is in the circle now: one anti-tank drone per vehicle or autonomous system (the
// SAM and radar, SW-1h: each went at one AT hit in SW1h), and all "maxAT" with a tank or APC in the
// circle (SW-1j, EJ after SW1i: "they should get all 4 now. They are so strong, its taking up to 6
// drones to take 1 out ... if the vehicle does blow up, the remaining drones are freed up anyways";
// SW-1i counted armour three times). None without a vehicle.
private _seen = [_record, _settings] call A3UE_fnc_fpv_swarmScan;
private _vehicles = {(_x # 1) in ["ARMOR", "SYSTEM", "GUN", "VEHICLE"]} count _seen;
private _armor = {(_x # 1) == "ARMOR"} count _seen;
private _antiTank = (([(_settings get "maxAT") min _vehicles, _settings get "maxAT"] select (_armor > 0)) min _size) max 0;
if ((_families get "AT") isEqualTo []) then {_antiTank = 0;};
if ((_families get "AP") isEqualTo []) then {_antiTank = _size;};
private _roles = [];
for "_i" from 1 to _size do {_roles pushBack (["AP", "AT"] select (_i <= _antiTank));};

private _swarms = missionNamespace getVariable ["A3UE_FPV_swarms", createHashMap];
_swarms set [_id, _record];
missionNamespace setVariable ["A3UE_FPV_swarms", _swarms];
diag_log format ["[A3UE_FPV] swarm id=%1 event=CALLED center=%2 size=%3 at=%4 vehiclesSeen=%5 armor=%6 launchM=%7 bearing=%8 from=%9 callerM=%10 families=%11",
	_id, _center apply {round _x}, _size, _antiTank, _vehicles, _armor, round _launchDistance, round _bearing, _from, round _callerDistance, _families];
[_id, _roles, _families] spawn A3UE_fnc_fpv_swarmBrain;
[true, _id]
