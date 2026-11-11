// Site stock deployment pass (field findings FS-03/FS-04/FS-05). Server queue only.
// Spawns up to _count drones, spends only drones that actually spawned, defers
// drones with no clear standoff launch point (retried at most 3 times, 20 s apart;
// unspent stock stays with the site), and writes one Info-level siteDeploy line.
// _pass: "activation" or "retry". With _count == 0 it only writes the line.
params ["_markerX", "_siteType", "_profile", "_siteSide", "_familyId", "_count", "_entry", ["_pass", "activation"]];

if (!isServer || {isRemoteExecuted}) exitWith {0};
if !(_entry isEqualType createHashMap) exitWith {0};

private _spawned = [];
private _blocked = 0;
private _modes = [];
private _classes = [];
private _launchSlots = [];
private _nearest = -1;
if (_count > 0) then {
	// One bounded allPlayers pass per deployment, shared by every drone in it.
	private _threats = [_siteSide] call A3UE_fnc_fpv_standoffThreats;
	for "_index" from 1 to _count do {
		// F5-1b breadcrumb (server-local, read by A3UE_fnc_fpv_siteQueueProbe).
		missionNamespace setVariable ["A3UE_FPV_siteStage", ["drone", _markerX, diag_tickTime, _index, _count]];
		private _placement = createHashMapFromArray [["threats", _threats]];
		private _uav = [_markerX, _siteType, _profile, _siteSide, _familyId, _placement] call A3UE_fnc_fpv_managerSpawnDrone;
		private _distance = _placement getOrDefault ["nearestHostile", -1];
		if (_distance >= 0 && {_nearest < 0 || {_distance < _nearest}}) then {_nearest = _distance;};
		if (isNull _uav) then {
			if ((_placement getOrDefault ["reason", ""]) == "STANDOFF") then {_blocked = _blocked + 1;};
		} else {
			_spawned pushBack _uav;
			_modes pushBackUnique (_placement getOrDefault ["mode", "DIRECT"]);
			_classes pushBack (typeOf _uav);
			_launchSlots pushBack (_uav getVariable ["A3UE_FPV_launchSlot", 0]);
		};
	};
	if (_spawned isNotEqualTo []) then {
		["SPEND", _markerX, _siteSide, count _spawned] call A3UE_fnc_fpv_siteStock;
	};
	private _drones = _entry getOrDefault ["drones", []];
	_drones append _spawned;
	_entry set ["drones", _drones];

	private _retries = _entry getOrDefault ["deferRetries", 0];
	if (_pass == "retry") then {_retries = _retries + 1;};
	_entry set ["deferRetries", _retries];
	if (_blocked > 0 && {_retries < 3}) then {
		_entry set ["deferred", _blocked];
		_entry set ["deferRetryAt", time + 20];
	} else {
		_entry set ["deferred", 0];
		_entry set ["deferRetryAt", -1];
	};
	_entry set ["status", switch (true) do {
		case (_drones isNotEqualTo []): {"active"};
		case ((_entry get "deferred") > 0): {"deferred"};
		case (_blocked > 0): {"standoff_blocked"};
		default {"spawn_failed"};
	}];
};

missionNamespace setVariable ["A3UE_FPV_siteStage", ["deployLine", _markerX, diag_tickTime, count _spawned, _count]];
private _stock = (missionNamespace getVariable ["A3UE_FPV_siteStock", createHashMap]) getOrDefault [_markerX, createHashMap];
private _generation = ((missionNamespace getVariable ["A3UE_FPV_siteLifecycle", createHashMap]) getOrDefault [_markerX, createHashMap]) getOrDefault ["generation", -1];
diag_log format ["[A3UE_FPV] siteDeploy marker=%1 type=%2 side=%3 generation=%4 pass=%5 status=%6 family=%7 requested=%8 spawned=%9 deferred=%10 stock=%11/%12 placement=%13 nearestHostileM=%14 classes=%15 slots=%16",
	_markerX, _siteType, _siteSide, _generation, _pass, _entry getOrDefault ["status", ""], _familyId, _count, count _spawned,
	_entry getOrDefault ["deferred", 0], _stock getOrDefault ["remaining", -1], _stock getOrDefault ["max", -1],
	_modes, round _nearest, _classes, _launchSlots];
count _spawned
