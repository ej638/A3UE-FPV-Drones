// STRUCTURAL SUP-01 regression in a disposable, ready AU 12.0.3 campaign.
// Run locally on the server: [] execVM "scripts\sup01_rivals_mode.sqf";
// Production effective selector/availability; captured stock and scheduler are spies.
// No actual AU dispatch, vehicles, network calls or engine-route qualification.
if (!isServer || {isRemoteExecuted} || {!(missionNamespace getVariable ["serverInitDone", false])}
	|| {getText (configFile >> "CfgPatches" >> "A3A_core" >> "versionStr") != "12.0.3"}
	|| {!(missionNamespace getVariable ["A3UE_FPV_rivalsHooksInstalled", false])}
	|| {SCRT_fnc_rivals_selectAndExecuteEvent isNotEqualTo A3UE_fnc_fpv_rivalsSelectAndExecuteEvent}
	|| {SCRT_fnc_rivals_encounter_uavFlyby isNotEqualTo A3UE_fnc_fpv_rivalsUavFlyby}) exitWith {
	diag_log "[A3UE FPV TEST SUP-01] BLOCKED: local ready server and effective Rivals wrappers required";
};
isNil {
	private _variables = ["gameMode", "A3A_faction_riv", "A3UE_FPV_catalog",
		"A3UE_FPV_originalRivalsSelectAndExecuteEvent", "A3A_fnc_scheduler",
		"areRivalsDiscovered", "areRivalsDefeated", "inactivityLevelRivals",
		"isRivalEventInProgress", "rivalEventCooldown"];
	if (_variables findIf {
		private _value = missionNamespace getVariable [_x, 0];
		(_value isEqualTypeAny [{}, createHashMap]) && {isFinal _value}
	} >= 0) exitWith {diag_log "[A3UE FPV TEST SUP-01] BLOCKED: immutable fixture bindings";};
	private _saved = _variables apply {[_x, !isNil _x, missionNamespace getVariable [_x, 0]]};
	private _failures = [];
	private _cases = 0;
	private _assert = {
		params ["_case", "_pass"];
		_cases = _cases + 1;
		if (!_pass) then {_failures pushBack _case;};
		diag_log ["A3UE FPV TEST SUP-01", "STRUCTURAL", _case, _pass];
	};
	private _stockCalls = [];
	private _dispatches = [];
	A3UE_FPV_originalRivalsSelectAndExecuteEvent = {_stockCalls pushBack +_this;};
	A3A_fnc_scheduler = {_dispatches pushBack +_this;};
	// Synthetic capability isolates mode/state eligibility from vendor discovery.
	private _catalog = createHashMapFromArray [["armafpv", createHashMapFromArray [
		["classesBySide", createHashMapFromArray [["east", createHashMapFromArray [["AP", ["O_UAV_01_F"]]]]]]
	]]];
	A3UE_FPV_catalog = _catalog;
	areRivalsDiscovered = true;
	areRivalsDefeated = false;
	inactivityLevelRivals = 2;
	rivalEventCooldown = 123;
	gameMode = 3;
	// Cover both selector branches, reroll entry, and preservation of existing state.
	{
		private _stock = _x;
		A3A_faction_riv = createHashMapFromArray [["vehiclesRivalsUavs", _stock]];
		{
			private _inProgress = _x;
			{
				isRivalEventInProgress = _inProgress;
				_stockCalls = []; _dispatches = [];
				[_x] call SCRT_fnc_rivals_selectAndExecuteEvent;
				[format ["MODE3_STOCK%1_BUSY%2_EXCLUDE%3", count _stock, _inProgress, _x],
					_stockCalls isEqualTo [] && {_dispatches isEqualTo []}
					&& {isRivalEventInProgress isEqualTo _inProgress} && {rivalEventCooldown == 123}] call _assert;
			} forEach [0, 200];
		} forEach [false, true];
	} forEach [[], ["O_UAV_01_F"]];
	["MODE3_MANAGED_UNAVAILABLE", !([] call A3UE_fnc_fpv_rivalsEventAvailable)] call _assert;
	private _events = [100, 200, 300, 400, 500, 600];
	private _handlers = ["SCRT_fnc_rivals_encounter_carDemo", "SCRT_fnc_rivals_encounter_uavFlyby",
		"SCRT_fnc_rivals_encounter_rovingMortar", "SCRT_fnc_rivals_encounter_heliRaid",
		"SCRT_fnc_rivals_encounter_OccVsRivalsSkirmish", "SCRT_fnc_rivals_encounter_policeVsRivalsskirmish"];
	{
		gameMode = _x;
		A3A_faction_riv = createHashMapFromArray [["vehiclesRivalsUavs", []]];
		[format ["MODE%1_MANAGED_AVAILABLE", gameMode], [] call A3UE_fnc_fpv_rivalsEventAvailable] call _assert;
		{
			private _exclude = _x;
			_stockCalls = []; _dispatches = [];
			isRivalEventInProgress = false;
			[_exclude] call SCRT_fnc_rivals_selectAndExecuteEvent;
			private _selected = _handlers find ((_dispatches param [0, [[], ""]]) # 1);
			[format ["MODE%1_ONE_DISPATCH_EXCLUDE%2", gameMode, _exclude],
				_stockCalls isEqualTo [] && {count _dispatches == 1} && {isRivalEventInProgress}
				&& {_selected >= 0} && {(_events # _selected) != _exclude}
				&& {(_dispatches # 0 # 0) isEqualTo []} && {rivalEventCooldown == 123}] call _assert;
		} forEach ([0] + _events);
		A3A_faction_riv = createHashMapFromArray [["vehiclesRivalsUavs", ["O_UAV_01_F"]]];
		_stockCalls = []; _dispatches = []; isRivalEventInProgress = false;
		[200] call SCRT_fnc_rivals_selectAndExecuteEvent;
		[format ["MODE%1_STOCK_DELEGATES_ONCE", gameMode], _stockCalls isEqualTo [[200]]
			&& {_dispatches isEqualTo []} && {!isRivalEventInProgress}] call _assert;
		A3A_faction_riv = createHashMapFromArray [["vehiclesRivalsUavs", []]];
		{
			_x params ["_name", "_discovered", "_defeated", "_level", "_hasCatalog"];
			areRivalsDiscovered = _discovered; areRivalsDefeated = _defeated; inactivityLevelRivals = _level;
			A3UE_FPV_catalog = if (_hasCatalog) then {_catalog} else {createHashMap};
			_stockCalls = []; _dispatches = []; isRivalEventInProgress = false;
			private _available = [] call A3UE_fnc_fpv_rivalsEventAvailable;
			[200] call SCRT_fnc_rivals_selectAndExecuteEvent;
			[format ["MODE%1_%2_STOCK_FALLBACK", gameMode, _name], !_available
				&& {_stockCalls isEqualTo [[200]]} && {_dispatches isEqualTo []}
				&& {!isRivalEventInProgress} && {rivalEventCooldown == 123}] call _assert;
		} forEach [["UNDISCOVERED", false, false, 2, true], ["DEFEATED", true, true, 2, true],
			["LOW_PRESSURE", true, false, 3, true], ["NO_FAMILY", true, false, 2, false]];
		areRivalsDiscovered = true; areRivalsDefeated = false; inactivityLevelRivals = 1;
		A3UE_FPV_catalog = _catalog;
		[format ["MODE%1_LEVEL1_AVAILABLE", gameMode], [] call A3UE_fnc_fpv_rivalsEventAvailable] call _assert;
	} forEach [1, 2];
	{_x params ["_name", "_present", "_value"]; missionNamespace setVariable [_name, if (_present) then {_value} else {nil}];} forEach _saved;
	diag_log ["A3UE FPV TEST SUP-01", "STRUCTURAL END", _cases, _failures,
		["PASS", "FAIL"] select (_failures isNotEqualTo [])];
};
