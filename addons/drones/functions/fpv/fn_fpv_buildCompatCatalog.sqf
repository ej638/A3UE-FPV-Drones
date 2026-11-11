private _loaded = createHashMapFromArray [
	["armafpv", isClass (configFile >> "CfgPatches" >> "ArmaFPV_Data")],
	["fpv_ua", isClass (configFile >> "CfgPatches" >> "FPV_UA")],
	["kvn", isClass (configFile >> "CfgPatches" >> "frtz_KVN")]
];

private _catalog = createHashMap;

private _filterExistingClasses = {
	params ["_classNames"];

	_classNames select { isClass (configFile >> "CfgVehicles" >> _x) }
};

private _buildRoleMap = {
	params ["_roleSpecs"];

	private _roleMap = createHashMap;

	{
		_x params ["_roleId", "_classNames"];

		private _validClasses = [_classNames] call _filterExistingClasses;
		if (_validClasses isNotEqualTo []) then {
			_roleMap set [_roleId, _validClasses];
		};
	} forEach _roleSpecs;

	_roleMap
};

private _buildClassesBySide = {
	params ["_sideSpecs"];

	private _classesBySide = createHashMap;

	{
		_x params ["_sideKey", "_roleSpecs"];

		private _roleMap = [_roleSpecs] call _buildRoleMap;
		if (count _roleMap > 0) then {
			_classesBySide set [_sideKey, _roleMap];
		};
	} forEach _sideSpecs;

	_classesBySide
};

private _retranslatorClass = if (isClass (configFile >> "CfgVehicles" >> "FPV_Retranslator")) then {
	"FPV_Retranslator"
} else {
	""
};

private _jammerClasses = ["Sania", "Sania_with_tripod"] select {
	isClass (configFile >> "CfgVehicles" >> _x)
};

if (_loaded get "armafpv") then {
	private _classesBySide = [[
		["east", [
			["AT", ["O_Crocus_AT", "O_Crocus_AT_TI"]],
			["AP", ["O_Crocus_AP", "O_Crocus_AP_TI"]],
			["RECON", ["O_Crocus_AT_TI", "O_Crocus_AP_TI"]]
		]],
		["west", [
			["AT", ["B_Crocus_AT", "B_Crocus_AT_TI"]],
			["AP", ["B_Crocus_AP", "B_Crocus_AP_TI"]],
			["RECON", ["B_Crocus_AT_TI", "B_Crocus_AP_TI"]]
		]],
		["independent", [
			["AT", ["I_Crocus_AT", "I_Crocus_AT_TI"]],
			["AP", ["I_Crocus_AP", "I_Crocus_AP_TI"]],
			["RECON", ["I_Crocus_AT_TI", "I_Crocus_AP_TI"]]
		]]
	]] call _buildClassesBySide;

	if (count _classesBySide > 0) then {
		_catalog set ["armafpv", createHashMapFromArray [
			["patch", "ArmaFPV_Data"],
			["signalModel", "RADIO"],
			["nativeRecon", false],
			["retranslatorClass", _retranslatorClass],
			["jammerClasses", _jammerClasses],
			["classesBySide", _classesBySide]
		]];
	};
};

if (_loaded get "fpv_ua") then {
	private _classesBySide = [[
		["east", [
			["AT", ["O_UAFPV_PG7VL_AT"]],
			["AP", ["O_UAFPV_IED_AP", "O_UAFPV_RKG_AP", "O_UAFPV_OG7V_AP"]],
			["RECON", ["O_UAFPV_RKG_AP", "O_UAFPV_OG7V_AP"]]
		]],
		["west", [
			["AT", ["B_UAFPV_PG7VL_AT"]],
			["AP", ["B_UAFPV_IED_AP", "B_UAFPV_RKG_AP", "B_UAFPV_OG7V_AP"]],
			["RECON", ["B_UAFPV_RKG_AP", "B_UAFPV_OG7V_AP"]]
		]],
		["independent", [
			["AT", ["I_UAFPV_PG7VL_AT"]],
			["AP", ["I_UAFPV_IED_AP", "I_UAFPV_RKG_AP", "I_UAFPV_OG7V_AP"]],
			["RECON", ["I_UAFPV_RKG_AP", "I_UAFPV_OG7V_AP"]]
		]]
	]] call _buildClassesBySide;

	if (count _classesBySide > 0) then {
		_catalog set ["fpv_ua", createHashMapFromArray [
			["patch", "FPV_UA"],
			["signalModel", "RADIO"],
			["nativeRecon", false],
			["retranslatorClass", _retranslatorClass],
			["jammerClasses", _jammerClasses],
			["classesBySide", _classesBySide]
		]];
	};
};

if (_loaded get "kvn") then {
	private _classesBySide = [[
		["east", [
			["AT", ["frtz_O_KVN_AT", "frtz_O_KVN_AT_20KM", "frtz_O_KVN_AT_25KM"]],
			["AP", ["frtz_O_KVN_AP", "frtz_O_KVN_AP_20KM", "frtz_O_KVN_AP_25KM"]],
			["RECON", [
				"frtz_O_KVN_AT_TI", "frtz_O_KVN_AP_TI",
				"frtz_O_KVN_AT_TI_20KM", "frtz_O_KVN_AP_TI_20KM",
				"frtz_O_KVN_AT_TI_25KM", "frtz_O_KVN_AP_TI_25KM"
			]]
		]],
		["west", [
			["AT", ["frtz_B_KVN_AT", "frtz_B_KVN_AT_20KM", "frtz_B_KVN_AT_25KM"]],
			["AP", ["frtz_B_KVN_AP", "frtz_B_KVN_AP_20KM", "frtz_B_KVN_AP_25KM"]],
			["RECON", [
				"frtz_B_KVN_AT_TI", "frtz_B_KVN_AP_TI",
				"frtz_B_KVN_AT_TI_20KM", "frtz_B_KVN_AP_TI_20KM",
				"frtz_B_KVN_AT_TI_25KM", "frtz_B_KVN_AP_TI_25KM"
			]]
		]],
		["independent", [
			["AT", ["frtz_I_KVN_AT", "frtz_I_KVN_AT_20KM", "frtz_I_KVN_AT_25KM"]],
			["AP", ["frtz_I_KVN_AP", "frtz_I_KVN_AP_20KM", "frtz_I_KVN_AP_25KM"]],
			["RECON", [
				"frtz_I_KVN_AT_TI", "frtz_I_KVN_AP_TI",
				"frtz_I_KVN_AT_TI_20KM", "frtz_I_KVN_AP_TI_20KM",
				"frtz_I_KVN_AT_TI_25KM", "frtz_I_KVN_AP_TI_25KM"
			]]
		]]
	]] call _buildClassesBySide;

	if (count _classesBySide > 0) then {
		_catalog set ["kvn", createHashMapFromArray [
			["patch", "frtz_KVN"],
			["signalModel", "FIBER_VISUAL"],
			["nativeRecon", false],
			["retranslatorClass", ""],
			["jammerClasses", []],
			["classesBySide", _classesBySide]
		]];
	};
};

// Physical contracts are resolved once from the finite, supported class list.
// Task eligibility never changes the airframe's warhead or ammunition.
private _managedAtReady = isClass (configFile >> "CfgAmmo" >> "A3UE_FPV_AT") && {
	isClass (configFile >> "CfgAmmo" >> "A3UE_FPV_AT_Penetrator")
};
private _makeDescriptor = {
	params ["_class", "_familyId", "_sideKey", "_taskRoles", "_payload", "_linkModel", "_sensorProfile", "_canDetonate"];
	_canDetonate = _canDetonate && {_payload in ["AT", "AP", "PG7VL", "IED", "OG7V", "RKG", "TBG7L"]};
	private _ammoCandidates = if (!_canDetonate) then {[]} else {
		switch (_payload) do {
			case "AT";
			case "PG7VL": {["A3UE_FPV_AT"]};
			case "TBG7L": {["UA_TBG7L_HE"]};
			case "AP";
			case "IED";
			case "OG7V";
			case "RKG": {["R_TBG32V_F"]};
			default {[]};
		}
	};
	private _ammoClass = "";
	{if (isClass (configFile >> "CfgAmmo" >> _x) && {_x != "A3UE_FPV_AT" || {_managedAtReady}}) exitWith {_ammoClass = _x;};} forEach _ammoCandidates;
	createHashMapFromArray [
		["className", _class], ["familyId", _familyId], ["sideKey", _sideKey],
		["taskRoles", _taskRoles], ["physicalPayload", _payload],
		["canDetonate", _canDetonate], ["ammoCandidates", _ammoCandidates], ["ammoClass", _ammoClass],
		["linkModel", _linkModel], ["sensorProfile", _sensorProfile]
	]
};

{
	private _familyId = _x;
	private _family = _y;
	private _capabilities = createHashMap;
	private _descriptors = createHashMap;
	{
		private _sideKey = _x;
		{
			private _taskRole = _x;
			{
				private _class = _x;
				private _descriptor = _descriptors getOrDefault [_class, createHashMap];
				if (count _descriptor == 0) then {
					private _payload = ["AP", "AT"] select ("_AT" in _class);
					if (_familyId == "fpv_ua") then {_payload = (_class splitString "_") # 2;};
					_descriptor = [_class, _familyId, _sideKey, [], _payload,
						_family get "signalModel", ["VISUAL", "THERMAL"] select ("_TI" in _class), true] call _makeDescriptor;
					_descriptors set [_class, _descriptor];
					private _config = configFile >> "CfgVehicles" >> _class;
					_capabilities set [_class, createHashMapFromArray [
						["maxSpeed", getNumber (_config >> "maxSpeed")],
						["nominalEnduranceDistance", if (_familyId == "kvn") then {1000 * getNumber (_config >> "fuelCapacity")} else {0}]
					]];
				};
				(_descriptor get "taskRoles") pushBackUnique _taskRole;
			} forEach _y;
		} forEach _y;
	} forEach (_family get "classesBySide");

	// Descriptor-only UA additions: no automatic doctrine/pool expansion.
	// TBG7L permits a validated AP override only when its native ammo exists.
	// Non-suicide payloads have no managed task eligibility and no ammo fallback.
	if (_familyId == "fpv_ua") then {
		{
			_x params ["_sidePrefix", "_sideKey"];
			{
				_x params ["_suffix", "_payload", "_canDetonate"];
				private _class = if (_suffix == "") then {format ["%1_UAFPV", _sidePrefix]} else {format ["%1_UAFPV_%2", _sidePrefix, _suffix]};
				if (isClass (configFile >> "CfgVehicles" >> _class)) then {
					_descriptors set [_class, [_class, _familyId, _sideKey,
						if (_canDetonate) then {["AP"]} else {[]}, _payload, "RADIO", "VISUAL", _canDetonate] call _makeDescriptor];
				};
			} forEach [["TBG7L_HE", "TBG7L", true], ["", "EMPTY", false],
				["NET", "NET", false], ["RPG18", "RPG18", false], ["AKS74", "AKS74", false]];
		} forEach [["O", "east"], ["B", "west"], ["I", "independent"]];
	};
	_family set ["classCapabilities", _capabilities];
	_family set ["classDescriptors", _descriptors];
} forEach _catalog;

missionNamespace setVariable ["A3UE_FPV_loadedMods", _loaded];
missionNamespace setVariable ["A3UE_FPV_catalog", _catalog];

_catalog
