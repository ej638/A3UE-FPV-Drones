// Engine regression: cached physical contracts, pre-creation validation, real commit rejection.
// Disposable server-local AU MP range. Old/regressed code can create real explosions.
// Optional positive specimen is destroyed by the production commit; restart afterward.
params [["_positiveUav", objNull, [objNull]], ["_deliveryPos", [], [[]]], ["_target", objNull, [objNull]],
	["_probePosATL", [50, 50, 100], [[]]]];
if (!isServer || {isRemoteExecuted}) exitWith {diag_log "[A3UE FPV TEST V04] BLOCKED server-local required";};
private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) exitWith {diag_log "[A3UE FPV TEST V04] BLOCKED no enabled family; P0 smoke is separate";};
private _cases = 0;
private _failures = 0;
private _classesChecked = [];
private _expected = createHashMap;
private _createdOnFailure = [];
private _check = {
	params ["_case", "_ok"];
	_cases = _cases + 1;
	if (!_ok) then {_failures = _failures + 1;};
	diag_log format ["[A3UE FPV TEST V04] case=%1 pass=%2", _case, _ok];
};
// Capture every unexpected creation so a regressed spawner cannot leave untracked drones.
private _rejectSpawn = {
	params ["_spec"];
	private _uav = [_spec] call A3UE_fnc_fpv_spawnManagedDrone;
	if (isNull _uav) exitWith {true};
	_createdOnFailure pushBack [netId _uav, typeOf _uav, crew _uav, (crew _uav) apply {group _x}];
	[_uav] call A3UE_fnc_fpv_cleanupDrone;
	false
};
// Independent expected public identities: retain side, TI and endurance variants.
{
	_x params ["_prefix", "_sideKey", "_side"];
	{
		private _payload = _x;
		{
			private _ti = _x;
			_expected set [format ["%1_Crocus_%2%3", _prefix, _payload, _ti],
				["armafpv", _payload, ["R_TBG32V_F", "A3UE_FPV_AT"] select (_payload == "AT"),
				_sideKey, _side, "RADIO", ["THERMAL", "VISUAL"] select (_ti == "")]];
			{
				_expected set [format ["frtz_%1_KVN_%2%3%4", _prefix, _payload, _ti, _x],
					["kvn", _payload, ["R_TBG32V_F", "A3UE_FPV_AT"] select (_payload == "AT"),
					_sideKey, _side, "FIBER_VISUAL", ["THERMAL", "VISUAL"] select (_ti == "")]];
			} forEach ["", "_20KM", "_25KM"];
		} forEach ["", "_TI"];
	} forEach ["AT", "AP"];
	{
		_x params ["_suffix", "_payload", "_ammo"];
		_expected set [format ["%1_UAFPV_%2", _prefix, _suffix], ["fpv_ua", _payload, _ammo, _sideKey, _side, "RADIO", "VISUAL"]];
	} forEach [["IED_AP", "IED", "R_TBG32V_F"], ["OG7V_AP", "OG7V", "R_TBG32V_F"],
		["RKG_AP", "RKG", "R_TBG32V_F"], ["PG7VL_AT", "PG7VL", "A3UE_FPV_AT"], ["TBG7L_HE", "TBG7L", "UA_TBG7L_HE"]];
} forEach [["O", "east", east], ["B", "west", west], ["I", "independent", independent]];
isNil {
	{
		private _familyId = _x;
		{
			private _sideKey = _x;
			{
				private _role = _x;
				{
					private _class = _x;
					private _desc = [_class, _familyId, _role] call A3UE_fnc_fpv_getClassDescriptor;
					private _want = _expected getOrDefault [_class, []];
					[format ["catalog descriptor %1/%2", _class, _role], count _desc > 0 && {_want isNotEqualTo []}
						&& {(_desc get "physicalPayload") == (_want # 1)} && {(_desc get "sideKey") == _sideKey}
						&& {(_desc get "linkModel") == (_want # 5)} && {(_desc get "sensorProfile") == (_want # 6)}
						&& {_desc get "canDetonate"}] call _check;
					if (count _desc > 0 && {_want isNotEqualTo []}) then {
						private _ammo = _want # 2;
						[format ["physical ammo %1/%2", _class, _role], (_desc get "ammoClass") == _ammo] call _check;
					};
					_classesChecked pushBackUnique _class;
				} forEach _y;
			} forEach _y;
		} forEach (_y get "classesBySide");
	} forEach _catalog;
	["at least one catalog class checked", _classesChecked isNotEqualTo []] call _check;
	if (_classesChecked isEqualTo []) exitWith {};
	private _spec = createHashMapFromArray [["spawnPosATL", +_probePosATL], ["siteType", "Outpost"],
		["familyId", (_expected get (_classesChecked # 0)) # 0], ["payloadRole", "AP"], ["side", east], ["uavClass", "O_UAV_01_F"]];
	private _before = count (allMissionObjects "AllVehicles");
	["unrecognized existing UAV override rejected", [_spec] call _rejectSpawn] call _check;
	_spec set ["uavClass", 42];
	["malformed explicit override rejected", [_spec] call _rejectSpawn] call _check;
	{
		private _class = _x;
		private _want = _expected getOrDefault [_class, []];
		if (_want isEqualTo []) then {continue;};
		private _validRoles = ([_class, _want # 0] call A3UE_fnc_fpv_getClassDescriptor) getOrDefault ["taskRoles", []];
		if (_validRoles isEqualTo []) then {continue;};
		_spec set ["uavClass", _class];
		_spec set ["familyId", _want # 0];
		_spec set ["side", _want # 4];
		_spec set ["payloadRole", ["AT", "AP"] select ((_want # 1) in ["AT", "PG7VL"])];
		[format ["wrong task rejected %1", _class], [_spec] call _rejectSpawn] call _check;
		_spec set ["payloadRole", _validRoles # 0];
		_spec set ["side", if ((_want # 4) == east) then {west} else {east}];
		[format ["wrong side rejected %1", _class], [_spec] call _rejectSpawn] call _check;
		_spec set ["side", _want # 4];
		_spec set ["familyId", ["armafpv", "kvn"] select ((_want # 0) == "armafpv")];
		[format ["wrong family rejected %1", _class], [_spec] call _rejectSpawn] call _check;
	} forEach _classesChecked;
	["invalid overrides created no vehicle", count (allMissionObjects "AllVehicles") == _before] call _check;
	if ("fpv_ua" in _catalog) then {
		{
			_x params ["_prefix", "_side"];
			private _tbgClass = format ["%1_UAFPV_TBG7L_HE", _prefix];
			if (isClass (configFile >> "CfgVehicles" >> _tbgClass)) then {
				private _desc = [_tbgClass, "fpv_ua", "AP", _side] call A3UE_fnc_fpv_getClassDescriptor;
				[format ["TBG7L native-only ammo %1", _prefix], count _desc > 0
					&& {(_desc get "physicalPayload") == "TBG7L"} && {(_desc get "ammoCandidates") isEqualTo ["UA_TBG7L_HE"]}
					&& {(_desc get "ammoClass") == (["", "UA_TBG7L_HE"] select (isClass (configFile >> "CfgAmmo" >> "UA_TBG7L_HE")))}] call _check;
				// Simulated missing optional capability: test the real admission gate, no ammo fallback.
				if (count _desc > 0) then {
					private _ammo = _desc get "ammoClass";
					_desc set ["ammoClass", ""];
					_spec set ["familyId", "fpv_ua"]; _spec set ["payloadRole", "AP"]; _spec set ["side", _side]; _spec set ["uavClass", _tbgClass];
					[format ["missing TBG ammo declines before creation %1", _prefix], [_spec] call _rejectSpawn] call _check;
					_desc set ["ammoClass", _ammo];
				};
			};
			{
				private _class = format ["%1_UAFPV%2", _prefix, _x];
				if (!isClass (configFile >> "CfgVehicles" >> _class)) then {continue;};
				private _desc = [_class, "fpv_ua"] call A3UE_fnc_fpv_getClassDescriptor;
				[format ["non-suicide descriptor %1", _class], count _desc > 0 && {!(_desc get "canDetonate")}
					&& {(_desc get "ammoClass") == ""} && {(_desc get "taskRoles") isEqualTo []}] call _check;
				_spec set ["familyId", "fpv_ua"]; _spec set ["payloadRole", "AP"]; _spec set ["side", _side]; _spec set ["uavClass", _class];
				[format ["non-suicide spawn declined %1", _class], [_spec] call _rejectSpawn] call _check;
				private _u = createVehicle [_class, _probePosATL, [], 0, "NONE"];
				if (isNull _u) then {diag_log ["V04", "BLOCKED native specimen", _class]; _failures = _failures + 1; continue;};
				_u enableSimulationGlobal false;
				_u allowDamage false;
				_u setVariable ["A3UE_FPV_managed", true];
				_u setVariable ["A3UE_FPV_vendorId", "fpv_ua"];
				_u setVariable ["A3UE_FPV_payloadRole", "AP"];
				_u setVariable ["A3UE_FPV_netId", netId _u];
				// Real registration ensures the payload contract, not a missing lifetime, rejects this specimen.
				private _life = [_u, true] call A3UE_fnc_fpv_registerLifecycle;
				if (_life < 0) then {deleteVehicle _u; [format ["registered specimen %1", _class], false] call _check; continue;};
				private _strike = createHashMapFromArray [["uavNetId", netId _u], ["deliveryPosASL", getPosASL _u],
					["deliveryDir", [0, 1, 0]], ["deliveryUp", [0, 0, 1]], ["detonationReason", "DIRECT_CONTACT"], ["fallbackReason", "NONE"]];
				private _rows = count (missionNamespace getVariable ["A3UE_FPV_recentDetonations", []]);
				[format ["generic AP commit blocked %1", _class], !([_u, _life, _strike] call A3UE_fnc_fpv_commitDetonation)
					&& {!(_u getVariable ["A3UE_FPV_detonationCommitted", false])}
					&& {count (missionNamespace getVariable ["A3UE_FPV_recentDetonations", []]) == _rows}] call _check;
				{deleteVehicle _x} forEach crew _u;
				deleteVehicle _u;
			} forEach ["", "_NET", "_RPG18", "_AKS74"];
		} forEach [["O", east], ["B", west], ["I", independent]];
	};
};
diag_log ["V04", "UNEXPECTED_CREATION_CLEANUP", _createdOnFailure];
diag_log format ["[A3UE FPV TEST V04] CONTRACT END cases=%1 failures=%2 catalogClasses=%3; ENGINE INTEGRATION NOT QUALIFIED", _cases, _failures, count _classesChecked];
if (isNull _positiveUav) exitWith {};
private _want = _expected getOrDefault [typeOf _positiveUav, []];
if (_failures > 0 || {_want isEqualTo []} || {count _deliveryPos != 3}
	|| {!alive _positiveUav} || {!(_positiveUav getVariable ["A3UE_FPV_managed", false])}
	|| {[_positiveUav] call A3UE_fnc_fpv_isExternallyControlled}) exitWith {diag_log "[A3UE FPV TEST V04] BLOCKED positive prerequisites";};
private _positiveClass = typeOf _positiveUav;
private _expectedAmmo = _want # 2;
private _id = _positiveUav getVariable ["A3UE_FPV_netId", netId _positiveUav];
private _life = _positiveUav getVariable ["A3UE_FPV_lifecycleIdServer", -1];
private _role = _positiveUav getVariable ["A3UE_FPV_payloadRole", ""];
private _oldPhysical = _positiveUav getVariable ["A3UE_FPV_physicalPayload", ""];
private _oldAmmo = _positiveUav getVariable ["A3UE_FPV_ammoClass", ""];
_positiveUav setVariable ["A3UE_FPV_physicalPayload", "FORGED_PAYLOAD"];
_positiveUav setVariable ["A3UE_FPV_ammoClass", "FORGED_AMMO"];
private _strike = createHashMapFromArray [["uavNetId", _id], ["targetNetId", netId _target],
	["payloadRole", "AP"], ["physicalPayload", "FORGED_PAYLOAD"], ["ammoClass", "FORGED_AMMO"],
	["deliveryPosASL", +_deliveryPos], ["deliveryDir", [0, 1, 0]], ["deliveryUp", [0, 0, 1]], ["detonationReason", "DIRECT_CONTACT"], ["fallbackReason", "NONE"]];
private _accepted = [_positiveUav, _life, _strike] call A3UE_fnc_fpv_commitDetonation;
if (!_accepted) exitWith {
	_positiveUav setVariable ["A3UE_FPV_physicalPayload", _oldPhysical];
	_positiveUav setVariable ["A3UE_FPV_ammoClass", _oldAmmo];
	diag_log "[A3UE FPV TEST V04] BLOCKED positive commit; inspect site/support/safety; no positive PASS";
};
private _rows = (missionNamespace getVariable ["A3UE_FPV_recentDetonations", []]) select {
	(_x getOrDefault ["uavNetId", ""]) == _id && {(_x getOrDefault ["lifecycleId", -1]) == _life}
};
["one positive commit", count _rows == 1] call _check;
if (count _rows == 1) then {
	private _row = _rows # 0;
	["actual class selects physical payload", (_row get "physicalPayload") == (_want # 1) && {(_row get "uavClass") == _positiveClass}] call _check;
	["tactical role retained", (_row get "payloadRole") == _role] call _check;
	["forged ammo ignored", (_row get "ammoClass") == _expectedAmmo] call _check;
	diag_log ["V04", "POSITIVE_RECORD", _row];
};
diag_log format ["[A3UE FPV TEST V04] POSITIVE END cases=%1 failures=%2; ACTUAL EFFECT/CREDIT require V03 observers", _cases, _failures];
