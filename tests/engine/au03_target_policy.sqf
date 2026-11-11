// Copy into a disposable AU mission as au03_target_policy.sqf.
// Server Exec: [] spawn {[] execVM "au03_target_policy.sqf";};
// This fixture temporarily changes one directional side relation; do not save.
params [];

if (!isServer) exitWith {diag_log "[AU03 TEST] BLOCKED: server required";};
if (isNil "Occupants" || {isNil "Invaders"} || {isNil "teamPlayer"}) exitWith {
	diag_log "[AU03 TEST] BLOCKED: AU sides required";
};
private _sides = [Occupants, Invaders, teamPlayer];
if (count (_sides arrayIntersect _sides) != 3 || {_sides findIf {!(_x in [west, east, independent])} >= 0}) exitWith {
	diag_log "[AU03 TEST] BLOCKED: three distinct combat sides required";
};
if (isNil "A3UE_fnc_fpv_filterTarget") exitWith {diag_log "[AU03 TEST] BLOCKED: updated addon required";};

private _oldRelation = Occupants getFriend Invaders;
private _objects = [];
private _groups = [];
private _rows = [];
private _blocked = "";
private _expect = {
	params ["_name", "_pass"];
	_rows pushBack [_name, _pass];
};
diag_log format ["[AU03 TEST] BEGIN sides=%1 relation=%2", _sides, _oldRelation];

try {
	Occupants setFriend [Invaders, 0];
	private _allowed = [Occupants, Invaders] call A3UE_fnc_fpv_getHostileSides;
	["opposing faction allowed", _allowed isEqualTo [Invaders]] call _expect;
	["civilian context rejected", ([Occupants, civilian] call A3UE_fnc_fpv_getHostileSides) isEqualTo []] call _expect;
	["own-side context rejected", ([Occupants, Occupants] call A3UE_fnc_fpv_getHostileSides) isEqualTo []] call _expect;
	["malformed context rejected", ([Occupants, "invalid"] call A3UE_fnc_fpv_getHostileSides) isEqualTo []] call _expect;
	private _context = [createHashMapFromArray [["context", "MajorAttackSupport"], ["targetSide", Invaders]], {
		["attack", createHashMap] call A3UE_fnc_fpv_getSupportContext
	}] call A3UE_fnc_fpv_withSupportContext;
	["wrapper carries objective faction", (_context getOrDefault ["targetSide", sideUnknown]) == Invaders] call _expect;
	private _invalid = ["attack", createHashMapFromArray [["targetSide", "invalid"]]] call A3UE_fnc_fpv_getSupportContext;
	["malformed normalization stays rejected", ([Occupants, _invalid getOrDefault ["targetSide", sideUnknown]] call A3UE_fnc_fpv_getHostileSides) isEqualTo []] call _expect;

	// Use a quiet, flat inland patch outside all active sites for scanner isolation.
	private _pos = missionNamespace getVariable ["AU03_testPosATL", []];
	if !(_pos isEqualType [] && {count _pos == 3}) then {throw "Set AU03_testPosATL to an isolated flat inland [x,y,0]";};
	if (_pos isEqualTo [0,0,0] || {surfaceIsWater _pos}) then {throw "Fixture marker must resolve to an inland position";};
	if ((nearestObjects [_pos, ["Man", "LandVehicle", "Air", "Ship", "StaticWeapon"], 300, true]) isNotEqualTo []) then {
		throw "Fixture area is occupied";
	};
	private _newUnit = {
		params ["_side", "_offset"];
		private _grp = createGroup [_side, true];
		_groups pushBack _grp;
		private _unit = _grp createUnit ["B_Soldier_F", _pos vectorAdd _offset, [], 0, "NONE"];
		if (isNull _unit) then {throw "Unit creation failed";};
		_objects pushBack _unit;
		_unit disableAI "ALL";
		_unit allowDamage false;
		_unit
	};
	private _pilot = [Occupants, [0,0,0]] call _newUnit;
	private _enemy = [Invaders, [20,0,0]] call _newUnit;
	private _rebel = [teamPlayer, [5,0,0]] call _newUnit;
	private _civilian = [civilian, [10,0,0]] call _newUnit;
	private _uav = createVehicle ["B_UAV_01_F", _pos vectorAdd [0,0,10], [], 0, "NONE"];
	private _vehicle = createVehicle ["C_Offroad_01_F", _pos vectorAdd [25,0,0], [], 0, "NONE"];
	_objects append [_uav, _vehicle];
	if (isNull _uav || {isNull _vehicle}) then {throw "Vehicle creation failed";};
	_pilot moveInDriver _uav;
	if (driver _uav != _pilot || {side group _pilot != Occupants}) then {throw "Probe crew setup failed";};
	_uav setVariable ["A3UE_FPV_managed", true];
	_uav setVariable ["A3UE_FPV_targetSide", Invaders];
	_uav setVariable ["A3UE_FPV_targetNetId", netId _enemy];
	private _profile = createHashMapFromArray [["searchRadius", 100], ["localSearchRadius", 100]];
	["civilian excluded", isNull ([_civilian, _allowed] call A3UE_fnc_fpv_filterTarget)] call _expect;
	["nearby rebel excluded by objective", isNull ([_rebel, _allowed] call A3UE_fnc_fpv_filterTarget)] call _expect;
	["explicit-side scanner", ([_uav, _profile] call A3UE_fnc_fpv_selectTarget) isEqualTo _enemy] call _expect;
	["seed revalidation agrees", ([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _enemy] call _expect;

	// Candidate caches and the stored target ID remain populated during the switch.
	Occupants setFriend [Invaders, 0.6];
	["alliance threshold", ([Occupants, Invaders] call A3UE_fnc_fpv_getHostileSides) isEqualTo []] call _expect;
	["cached scanner drops ally", isNull ([_uav, _profile] call A3UE_fnc_fpv_selectTarget)] call _expect;
	["stored target drops ally", isNull ([_uav] call A3UE_fnc_fpv_resolveTarget)] call _expect;
	private _before = [A3A_supportCount, +A3A_activeSupports, +A3A_supportStrikes, count (missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap])];
	private _plan = [Occupants, objNull, 500, createHashMapFromArray [["context", "MajorAttackSupport"], ["targetSide", Invaders]], "attack"] call A3UE_fnc_fpv_resolveSupportPackage;
	["allied plan rejected", !(_plan getOrDefault ["ok", true]) && {(_plan getOrDefault ["failure", ""]) == "NO_HOSTILE_TARGET_SIDE"}] call _expect;
	["planning allocates no support", _before isEqualTo [A3A_supportCount, +A3A_activeSupports, +A3A_supportStrikes, count (missionNamespace getVariable ["A3UE_FPV_supportRegistry", createHashMap])]] call _expect;
	Occupants setFriend [Invaders, 0];
	["hostility restoration", ([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _enemy] call _expect;
	_uav setVariable ["A3UE_FPV_targetSide", sideUnknown];
	["unrestricted site accepts opposing faction", ([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _enemy] call _expect;
	_uav setVariable ["A3UE_FPV_targetSide", Invaders];
	_enemy setCaptive true;
	["captive scanner excluded", isNull ([_uav, _profile] call A3UE_fnc_fpv_selectTarget)] call _expect;
	["captive current target excluded", isNull ([_uav] call A3UE_fnc_fpv_resolveTarget)] call _expect;
	_enemy setCaptive false;
	_enemy moveInDriver _vehicle;
	if (driver _vehicle != _enemy) then {throw "Occupied vehicle setup failed";};
	["boarding resolves vehicle", ([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _vehicle] call _expect;
	_uav setVariable ["A3UE_FPV_targetNetId", netId _vehicle];
	moveOut _enemy;
	if (crew _vehicle isNotEqualTo []) then {throw "Empty vehicle setup failed";};
	["empty vehicle rejected", isNull ([_uav] call A3UE_fnc_fpv_resolveTarget)] call _expect;
	_uav setVariable ["A3UE_FPV_targetSide", Occupants];
	["unsupported scanner context", isNull ([_uav, _profile] call A3UE_fnc_fpv_selectTarget)] call _expect;
	_uav setVariable ["A3UE_FPV_targetSide", Invaders];
	_uav setVariable ["A3UE_FPV_targetNetId", netId _enemy];
	deleteVehicle _enemy;
	["deleted target rejected", isNull ([_uav] call A3UE_fnc_fpv_resolveTarget)] call _expect;
} catch {
	_blocked = str _exception;
};

Occupants setFriend [Invaders, _oldRelation];
{if (!isNull _x) then {deleteVehicle _x;};} forEach _objects;
{if (!isNull _x) then {deleteGroup _x;};} forEach _groups;
private _result = if (_blocked != "") then {"BLOCKED"} else {
	["PASS", "FAIL"] select (_rows isEqualTo [] || {_rows findIf {!(_x # 1)} >= 0})
};
diag_log format ["[AU03 TEST] END result=%1 checked=%2 rows=%3 blocked=%4 restored=%5", _result, count _rows, _rows, _blocked, Occupants getFriend Invaders];
