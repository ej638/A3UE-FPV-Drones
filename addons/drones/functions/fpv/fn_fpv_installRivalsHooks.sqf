// Atomic capture/verify/rollback. Never recapture wrappers or fight a later provider.
params [["_mode", "INSTALL"]];
if (!isServer || {isRemoteExecuted} || {!(_mode in ["INSTALL", "CHECK", "RESTORE"])}) exitWith {false};
private _installed = false;
isNil {
	private _names = ["SCRT_fnc_rivals_selectAndExecuteEvent", "SCRT_fnc_rivals_encounter_uavFlyby"];
	private _wrappers = [A3UE_fnc_fpv_rivalsSelectAndExecuteEvent, A3UE_fnc_fpv_rivalsUavFlyby];
	private _originalNames = ["A3UE_FPV_originalRivalsSelectAndExecuteEvent", "A3UE_FPV_originalRivalsUavFlyby"];
	private _claim = missionNamespace getVariable ["A3UE_FPV_rivalsHookClaim", createHashMap];
	private _captured = count _claim > 0;
	private _effective = _names apply {missionNamespace getVariable [_x, 0]};
	private _owned = [false, false];
	if (_captured) then {
		_owned = [(_effective # 0) isEqualTo (_claim get "selector"), (_effective # 1) isEqualTo (_claim get "handler")];
	};
	private _state = "REGISTERED";
	private _reason = "WAITING_CAMPAIGN";
	private _provider = "AU/SCRT";
	private _ready = missionNamespace getVariable ["serverInitDone", false];
	if (_ready) then {_state = "UNSUPPORTED"; _reason = "";};
	if (_captured && {!(_claim getOrDefault ["released", false])} && {false in _owned}) then {
		_claim set ["conflict", true];
	};
	if (_captured && {(_originalNames apply {missionNamespace getVariable [_x, 0]}) isNotEqualTo (_claim get "originals")}) then {
		_claim set ["conflict", true];
	};
	if (_claim getOrDefault ["conflict", false]) then {_state = "CONFLICT"; _reason = "RIVAL_BINDING_OWNERSHIP_LOST"; _provider = "FOREIGN_OR_UNKNOWN";};
	private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
	private _hasFamily = (keys _catalog) findIf {
		private _sides = (_catalog get _x) getOrDefault ["classesBySide", createHashMap];
		count (_sides getOrDefault ["east", createHashMap]) > 0
	} >= 0;
	if (_ready && {_reason == ""} && {!_hasFamily}) then {_reason = "NO_COMPATIBLE_RIVAL_VENDOR";};
	if (_ready && {_reason == ""}) then {
		if !(missionNamespace getVariable ["A3A_fnc_scheduler", 0] isEqualType {}
			&& {missionNamespace getVariable ["A3A_faction_riv", 0] isEqualType createHashMap}
			&& {(A3A_faction_riv getOrDefault ["vehiclesRivalsUavs", 0]) isEqualType []}) then {_reason = "INVALID_RIVAL_API_OR_FACTION_SCHEMA";};
		{
			_x params ["_name", "_path"];
			private _cfg = configFile >> "CfgFunctions" >> "A3UE" >> "FPV" >> (_name select [9]);
			if !([_name, _path, _cfg, ["fpv_ai_drones"]] call A3UE_fnc_fpv_hookBindingMatches) then {_reason = "A3UE_WRAPPER_CONFLICT"; _state = "CONFLICT";};
		} forEach [
			["A3UE_fnc_fpv_rivalsSelectAndExecuteEvent", "\fpv_ai_drones\functions\fpv\fn_fpv_rivalsSelectAndExecuteEvent.sqf"],
			["A3UE_fnc_fpv_rivalsUavFlyby", "\fpv_ai_drones\functions\fpv\fn_fpv_rivalsUavFlyby.sqf"]
		];
	};
	if (_ready && {_reason == ""} && {!_captured || {_claim getOrDefault ["released", false]}}) then {
		{
			private _name = _x;
			private _leaf = _name select [9]; // SCRT_fnc_ prefix
			private _path = "\x\A3A\addons\scrt\Rivals\fn_" + _leaf + ".sqf";
			private _meta = _name call BIS_fnc_functionMeta;
			private _cfg = configFile >> "CfgFunctions" >> "SCRT" >> "Rivals" >> _leaf;
			private _sources = configSourceAddonList _cfg;
			if (toLower (_meta param [0, ""]) != toLower _path
				|| {(_sources select {toLower _x != "a3a_scrt"}) isNotEqualTo []}
				|| {!([_name, _path, _cfg, ["a3a_scrt"]] call A3UE_fnc_fpv_hookBindingMatches)}) then {
				_state = "CONFLICT"; _reason = "FOREIGN_OR_INCOMPATIBLE_RIVAL_PROVIDER";
				_provider = str [_meta param [0, ""], _sources];
			};
		} forEach _names;
	};
	if (_reason == "" && {false in _owned}) then {
		if !(_effective isEqualTypeAll {}) then {_reason = "MISSING_RIVAL_FUNCTION";} else {
			if ((_effective findIf {isFinal _x}) >= 0) then {_reason = "IMMUTABLE_RIVAL_FUNCTION";};
		};
		if ((_wrappers findIf {isFinal _x}) >= 0) then {_reason = "IMMUTABLE_A3UE_WRAPPER";};
	};
	// Rollback/release only the wrappers captured in our claim, never a foreign replacement.
	if (_captured && {_mode != "CHECK"} && {_mode == "RESTORE" || {_reason != ""}}) then {
		{
			if (_owned # _forEachIndex && {!isFinal (_effective # _forEachIndex)}) then {
				missionNamespace setVariable [_x, (_claim get "originals") # _forEachIndex];
			};
		} forEach _names;
		_claim set ["released", true];
		if ((missionNamespace getVariable [_names # 0, 0]) isEqualTo (_claim get "selector")
			|| {(missionNamespace getVariable [_names # 1, 0]) isEqualTo (_claim get "handler")}) then {
			_state = "UNSUPPORTED"; _reason = "RIVAL_RESTORE_REJECTED";
		};
		_owned = [false, false];
	};
	if (_mode == "RESTORE" && {_reason == ""}) then {_state = "READY"; _reason = "RELEASED";};
	if (_reason == "") then {
		if (false in _owned && {_mode == "INSTALL"}) then {
			// First capture and both assignments share this unscheduled transaction (R03).
			if (!_captured) then {
				{missionNamespace setVariable [_x, _effective # _forEachIndex];} forEach _originalNames;
				_claim = createHashMapFromArray [["selector", _wrappers # 0], ["handler", _wrappers # 1], ["originals", +_effective]];
			};
			{missionNamespace setVariable [_x, _wrappers # _forEachIndex];} forEach _names;
			_owned = [(missionNamespace getVariable [_names # 0, 0]) isEqualTo (_wrappers # 0),
				(missionNamespace getVariable [_names # 1, 0]) isEqualTo (_wrappers # 1)];
			if (false in _owned) then {
				_state = "UNSUPPORTED"; _reason = "RIVAL_ASSIGNMENT_REJECTED";
				{if (_owned # _forEachIndex) then {missionNamespace setVariable [_x, _effective # _forEachIndex];};} forEach _names;
				_claim set ["released", true];
			} else {_claim set ["released", false];};
		};
		_installed = !(false in _owned) && {_mode != "RESTORE"} && {_reason == ""};
		if (_installed) then {_state = "ACTIVE"; _provider = "A3UE over captured AU/SCRT";} else {
			if (_reason == "") then {_state = "READY"; _reason = "NOT_INSTALLED";};
		};
	};
	missionNamespace setVariable ["A3UE_FPV_rivalsHookClaim", _claim];
	missionNamespace setVariable ["A3UE_FPV_rivalsHooksInstalled", _installed];
	["rivals", _state, _reason, _provider, "Server-local UAVGRENADE bindings / scheduler / captured fallback; HC dispatch unqualified"] call A3UE_fnc_fpv_setHookStatus;
};
_installed
