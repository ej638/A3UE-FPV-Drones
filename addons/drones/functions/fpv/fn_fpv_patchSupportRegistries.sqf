// Bounded server-local reconciliation. Foreign entries are never claimed by value.
params [["_mode", "INSTALL"]];
if (!isServer || {isRemoteExecuted} || {!(_mode in ["INSTALL", "CHECK", "RESTORE"])}) exitWith {false};
private _result = false;
isNil {
	private _ready = missionNamespace getVariable ["serverInitDone", false];
	private _reason = "";
	private _state = "UNSUPPORTED";
	if (!_ready) then {_state = "REGISTERED"; _reason = "WAITING_CAMPAIGN";};
	if (_ready && {_reason == ""}) then {
		if (isNil "Occupants" || {isNil "Invaders"} || {!(Occupants in [east, west, independent])}
			|| {!(Invaders in [east, west, independent])}) then {_reason = "INVALID_CAMPAIGN_SIDES";};
		if !(missionNamespace getVariable ["A3A_fnc_createSupport", 0] isEqualType {}
			&& {missionNamespace getVariable ["A3A_fnc_requestSupport", 0] isEqualType {}}) then {_reason = "MISSING_AU_SUPPORT_API";};
		{
			_x params ["_name", "_path"];
			private _cfg = configFile >> "CfgFunctions" >> "A3A" >> "A3UEFPVSupport" >> (_name select [8]);
			if !([_name, _path, _cfg, ["fpv_ai_drones"]] call A3UE_fnc_fpv_hookBindingMatches) then {_reason = "FPV_CALLBACK_CONFLICT"; _state = "CONFLICT";};
		} forEach [
			["A3A_fnc_SUP_FPV", "\fpv_ai_drones\functions\fpv\au_support\fn_SUP_FPV.sqf"],
			["A3A_fnc_SUP_FPVAvailable", "\fpv_ai_drones\functions\fpv\au_support\fn_SUP_FPVAvailable.sqf"]
		];
	};
	private _doctrine = missionNamespace getVariable ["A3UE_FPV_doctrine", createHashMap];
	private _reactiveEntry = _doctrine getOrDefault ["ReactiveSupport", createHashMap];
	if (_ready && {_reason == ""} && {count _reactiveEntry == 0}) then {_reason = "NO_REACTIVE_SUPPORT_DOCTRINE";};
	private _roleWeights = _reactiveEntry getOrDefault ["roleWeights", createHashMap];
	private _familyWeights = _reactiveEntry getOrDefault ["familyWeights", createHashMap];
	private _supportTuple = ["TARGET", 0.35, 0, 80];
	private _supportedRoles = ["AT", "AP", "RECON"];
	private _supportedFamilies = ["armafpv", "fpv_ua", "kvn"];

	private _isSidePatchEligible = {
		params ["_side"];

		private _eligible = false;

		{
			private _roleId = _x;
			if ((_roleWeights getOrDefault [_roleId, 0]) <= 0) then {
				continue;
			};

			{
				private _familyId = _x;
				if ((_familyWeights getOrDefault [_familyId, 0]) <= 0) then {
					continue;
				};

				private _uavClass = [_familyId, _roleId, _side, "ReactiveSupport"] call A3UE_fnc_fpv_selectClassForRole;
				if (_uavClass isEqualTo "") then {
					continue;
				};

				if !(isClass (configFile >> "CfgVehicles" >> _uavClass)) then {
					continue;
				};

				_eligible = true;
			} forEach _supportedFamilies;

			if (_eligible) exitWith {};
		} forEach _supportedRoles;

		_eligible
	};

	private _occEligible = if (isNil "Occupants") then {
		false
	} else {
		[Occupants] call _isSidePatchEligible
	};

	private _invEligible = if (isNil "Invaders") then {
		false
	} else {
		[Invaders] call _isSidePatchEligible
	};


	private _claims = missionNamespace getVariable ["A3UE_FPV_supportHookClaims", createHashMap];
	private _patched = [];
	private _reasons = [];
	{
		_x params ["_name", "_eligible", "_prefix"];
		private _registry = missionNamespace getVariable [_name, 0];
		private _claim = _claims getOrDefault [_name, createHashMap];
		private _valid = _registry isEqualType createHashMap;
		private _present = _valid && {"FPV" in _registry};
		private _value = if (_present) then {_registry get "FPV"} else {0};
		private _owned = _valid && {count _claim > 0}
			&& {_registry isEqualRef (_claim get "registry")}
			&& {_value isEqualType []} && {_value isEqualRef (_claim get "value")}
			&& {_value isEqualTo _supportTuple};
		private _rowState = _state;
		private _rowReason = _reason;
		private _provider = [["AU (empty FPV slot)", "FOREIGN_OR_UNKNOWN"] select _present, "A3UE"] select _owned;
		if (_valid && {_ready} && {_reason == ""}) then {
			// Validate stock tuple schema before extending this particular map.
			private _schemaOK = true;
			{
				if !(_y isEqualType [] && {count _y == 4}
					&& {(_y # 0) in ["TARGET", "AREA", "TROOPS"]}
					&& {(_y select [1]) isEqualTypeAll 0}) exitWith {_schemaOK = false;};
			} forEach _registry;
			if (!_schemaOK) then {_rowReason = "INVALID_SUPPORT_TUPLE_SCHEMA";};
		};
		if (!_valid && {_ready}) then {_rowReason = "LIVE_SUPPORT_TYPES_INVALID";};
		// Losing an owned slot in the SAME map is a conflict, not a rebuild.
		// A new empty map may be claimed; a populated replacement is foreign.
		if (count _claim > 0 && {!_owned} && {
			_present || {_valid && {_registry isEqualRef (_claim get "registry")}}
		}) then {_claim set ["conflict", true];};
		if ((_present && {!_owned}) || {_claim getOrDefault ["conflict", false]}) then {
			_rowState = "CONFLICT"; _rowReason = "FOREIGN_FPV_ENTRY_OR_OWNERSHIP_LOST";
		};
		private _active = false;
		if (_owned && {_mode == "RESTORE" || {!_eligible} || {_rowReason != ""}} && {_mode != "CHECK"}) then {
			// Claims record the prior absence; never delete somebody else's tuple.
			if !(isFinal _registry) then {_registry deleteAt "FPV";};
			if ("FPV" in _registry) then {_rowState = "UNSUPPORTED"; _rowReason = "SUPPORT_RESTORE_REJECTED";} else {
				_owned = false;
				_claims deleteAt _name;
				_provider = "AU (restored prior absence)";
			};
		};
		if (_rowReason == "" && {_valid}) then {
			_rowState = "READY"; _rowReason = "INACTIVE";
			if (!_eligible) then {_rowState = "UNSUPPORTED"; _rowReason = "NO_COMPATIBLE_VENDOR_FOR_SIDE";};
			if (_mode == "RESTORE") then {_rowState = "READY"; _rowReason = "RELEASED";};
			if (_eligible && {_mode != "RESTORE"}) then {
				if (!_owned && {_mode == "INSTALL"} && {!isFinal _registry}) then {
					private _installed = +_supportTuple;
					_registry set ["FPV", _installed, true];
					_owned = (_registry getOrDefault ["FPV", 0]) isEqualRef _installed;
					if (_owned) then {
						_claims set [_name, createHashMapFromArray [["registry", _registry], ["value", _installed], ["previousPresent", false]]];
					};
				};
				_active = _owned;
				if (_active) then {_rowState = "ACTIVE"; _rowReason = ""; _provider = "A3UE";} else {
					_rowReason = ["NOT_INSTALLED", "IMMUTABLE_SUPPORT_MAP"] select (isFinal _registry);
					if (isFinal _registry) then {_rowState = "UNSUPPORTED";};
				};
			};
		};
		missionNamespace setVariable [_prefix + "SupportPatchEligible", _eligible && {_ready} && {_reason == ""}];
		missionNamespace setVariable [_prefix + "SupportRegistryPatched", _active];
		[_name, _rowState, _rowReason, _provider, "FPV tuple / synchronous AU cost"] call A3UE_fnc_fpv_setHookStatus;
		_patched pushBack _active;
		if (_rowReason != "") then {_reasons pushBack [_name, _rowReason];};
	} forEach [["A3A_supportTypesOcc", _occEligible, "A3UE_FPV_occ"], ["A3A_supportTypesInv", _invEligible, "A3UE_FPV_inv"]];
	missionNamespace setVariable ["A3UE_FPV_supportHookClaims", _claims];
	_result = true in _patched;
	missionNamespace setVariable ["A3UE_FPV_supportHooksInstalled", _result];
	missionNamespace setVariable ["A3UE_FPV_supportRegistryPatched", _result];
	missionNamespace setVariable ["A3UE_FPV_supportInstallFailedReason", if (_reasons isEqualTo []) then {""} else {str _reasons}];
};
_result
