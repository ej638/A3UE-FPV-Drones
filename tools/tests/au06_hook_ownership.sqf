// Server-local STRUCTURAL ownership tests, disposable ready AU 12.0.3 mission.
// [[], "scripts\au06_hook_ownership.sqf"] call A3UE_FPV_QA_dispatch;
// Capability/class stubs isolate transactions; this cannot certify real dispatch.
if (!isServer || {isRemoteExecuted} || {!(missionNamespace getVariable ["serverInitDone", false])}
	|| {getText (configFile >> "CfgPatches" >> "A3A_core" >> "versionStr") != "12.0.3"}) exitWith {
	diag_log "[A3UE FPV TEST AU-06] BLOCKED: server-local ready campaign required";
};
// Packet A: require untouched production callbacks before installing fixture stubs.
// These positives are separate from the 15 structural ownership cases below.
private _liveSpecs = [
	["A3A_fnc_SUP_FPV", "A3A", "A3UEFPVSupport", "SUP_FPV", "au_support\fn_SUP_FPV.sqf"],
	["A3A_fnc_SUP_FPVAvailable", "A3A", "A3UEFPVSupport", "SUP_FPVAvailable", "au_support\fn_SUP_FPVAvailable.sqf"],
	["A3UE_fnc_fpv_rivalsSelectAndExecuteEvent", "A3UE", "FPV", "fpv_rivalsSelectAndExecuteEvent", "fn_fpv_rivalsSelectAndExecuteEvent.sqf"],
	["A3UE_fnc_fpv_rivalsUavFlyby", "A3UE", "FPV", "fpv_rivalsUavFlyby", "fn_fpv_rivalsUavFlyby.sqf"]
];
private _liveCheck = {
	_liveSpecs apply {
		_x params ["_name", "_tag", "_category", "_leaf", "_relative"];
		[_name, "\fpv_ai_drones\functions\fpv\" + _relative,
			configFile >> "CfgFunctions" >> _tag >> _category >> _leaf, ["fpv_ai_drones"]] call A3UE_fnc_fpv_hookBindingMatches
	}
};
private _liveBefore = call _liveCheck;
diag_log ["A3UE FPV TEST AU-06", "PRODUCTION BASELINE", _liveSpecs apply {_x # 0}, _liveBefore];
if (false in _liveBefore) exitWith {diag_log "[A3UE FPV TEST AU-06] BLOCKED: real callback qualification failed; no stubs installed";};
isNil {
	private _variables = ["serverInitDone", "Occupants", "Invaders", "A3A_supportTypesOcc", "A3A_supportTypesInv",
		"A3UE_FPV_doctrine", "A3UE_FPV_catalog", "A3UE_FPV_hookStatus", "A3UE_FPV_supportHookClaims",
		"A3UE_FPV_supportHooksInstalled", "A3UE_FPV_supportRegistryPatched", "A3UE_FPV_supportInstallFailedReason",
		"A3UE_FPV_occSupportPatchEligible", "A3UE_FPV_invSupportPatchEligible", "A3UE_FPV_occSupportRegistryPatched",
		"A3UE_FPV_invSupportRegistryPatched", "A3UE_FPV_rivalsHookClaim", "A3UE_FPV_rivalsHooksInstalled",
		"A3UE_FPV_originalRivalsSelectAndExecuteEvent", "A3UE_FPV_originalRivalsUavFlyby",
		"SCRT_fnc_rivals_selectAndExecuteEvent", "SCRT_fnc_rivals_encounter_uavFlyby",
		"A3UE_fnc_fpv_hookBindingMatches", "A3UE_fnc_fpv_selectClassForRole"];
	if (_variables findIf {
		private _value = missionNamespace getVariable [_x, 0];
		(_value isEqualTypeAny [{}, createHashMap]) && {isFinal _value}
	} >= 0) exitWith {diag_log "[A3UE FPV TEST AU-06] BLOCKED: immutable fixture bindings; use fresh immutable mission card";};
	private _saved = _variables apply {[_x, !isNil _x, missionNamespace getVariable [_x, 0]]};
	private _baselineSelector = missionNamespace getVariable ["A3UE_FPV_originalRivalsSelectAndExecuteEvent", SCRT_fnc_rivals_selectAndExecuteEvent];
	private _baselineHandler = missionNamespace getVariable ["A3UE_FPV_originalRivalsUavFlyby", SCRT_fnc_rivals_encounter_uavFlyby];
	private _failures = [];
	private _cases = 0;
	private _assert = {
		params ["_case", "_pass"];
		_cases = _cases + 1;
		if (!_pass) then {_failures pushBack _case;};
		diag_log ["A3UE FPV TEST AU-06", "STRUCTURAL", _case, _pass];
	};
	private _matches = true;
	private _hasClass = true;
	A3UE_fnc_fpv_hookBindingMatches = {_matches};
	A3UE_fnc_fpv_selectClassForRole = {["", "O_UAV_01_F"] select _hasClass};
	Occupants = west; Invaders = east;
	A3UE_FPV_doctrine = createHashMapFromArray [["ReactiveSupport", createHashMapFromArray [
		["roleWeights", createHashMapFromArray [["AT", 1]]], ["familyWeights", createHashMapFromArray [["armafpv", 1]]]
	]]];
	A3UE_FPV_hookStatus = createHashMap;
	A3UE_FPV_supportHookClaims = createHashMap;
	private _stock = ["AREA", 0.5, 150, 0];
	A3A_supportTypesOcc = createHashMapFromArray [["AIRSTRIKE", +_stock]];
	A3A_supportTypesInv = createHashMapFromArray [["AIRSTRIKE", +_stock]];
	serverInitDone = false;
	["INSTALL"] call A3UE_fnc_fpv_patchSupportRegistries;
	["WAIT_WITHOUT_FALSE_SUCCESS", !A3UE_FPV_supportHooksInstalled && {!("FPV" in A3A_supportTypesOcc)}
		&& {((A3UE_FPV_hookStatus get "A3A_supportTypesOcc") get "state") == "REGISTERED"}] call _assert;
	serverInitDone = true;
	["CHECK"] call A3UE_fnc_fpv_patchSupportRegistries;
	["READ_ONLY_CHECK", !("FPV" in A3A_supportTypesOcc) && {!A3UE_FPV_supportHooksInstalled}] call _assert;
	["INSTALL"] call A3UE_fnc_fpv_patchSupportRegistries;
	private _first = A3A_supportTypesOcc getOrDefault ["FPV", []];
	["INSTALL_VERIFIED", A3UE_FPV_supportHooksInstalled && {_first isEqualTo ["TARGET", 0.35, 0, 80]}
		&& {(A3A_supportTypesOcc get "AIRSTRIKE") isEqualTo _stock}] call _assert;
	["INSTALL"] call A3UE_fnc_fpv_patchSupportRegistries;
	["REPEAT_KEEPS_OWNED_TUPLE", _first isEqualRef (A3A_supportTypesOcc get "FPV")] call _assert;
	private _foreign = +_first;
	A3A_supportTypesOcc set ["FPV", _foreign];
	["INSTALL"] call A3UE_fnc_fpv_patchSupportRegistries;
	["IDENTICAL_FOREIGN_TUPLE_PRESERVED", _foreign isEqualRef (A3A_supportTypesOcc get "FPV")
		&& {!A3UE_FPV_occSupportRegistryPatched}] call _assert;
	["RESTORE"] call A3UE_fnc_fpv_patchSupportRegistries;
	["RESTORE_ONLY_OWNED_SIDE", _foreign isEqualRef (A3A_supportTypesOcc get "FPV")
		&& {!("FPV" in A3A_supportTypesInv)}] call _assert;
	// A new empty registry is the supported rebuild case; the stock tuples survive.
	A3UE_FPV_supportHookClaims = createHashMap;
	A3A_supportTypesOcc = createHashMapFromArray [["AIRSTRIKE", +_stock]];
	["INSTALL"] call A3UE_fnc_fpv_patchSupportRegistries;
	private _oldMap = A3A_supportTypesOcc;
	A3A_supportTypesOcc = createHashMapFromArray [["AIRSTRIKE", +_stock]];
	["INSTALL"] call A3UE_fnc_fpv_patchSupportRegistries;
	["REBUILD_EMPTY_MAP", A3UE_FPV_occSupportRegistryPatched && {"FPV" in _oldMap}
		&& {!(A3A_supportTypesOcc isEqualRef _oldMap)}] call _assert;
	A3A_supportTypesOcc deleteAt "FPV";
	["INSTALL"] call A3UE_fnc_fpv_patchSupportRegistries;
	["SAME_MAP_REMOVAL_IS_CONFLICT", !("FPV" in A3A_supportTypesOcc) && {!A3UE_FPV_occSupportRegistryPatched}] call _assert;
	_hasClass = false;
	A3A_supportTypesOcc set ["FPV", _foreign];
	["INSTALL"] call A3UE_fnc_fpv_patchSupportRegistries;
	["NO_VENDOR_PRESERVES_FOREIGN", _foreign isEqualRef (A3A_supportTypesOcc get "FPV")
		&& {!A3UE_FPV_supportHooksInstalled} && {!("FPV" in A3A_supportTypesInv)}] call _assert;
	_hasClass = true;
	["INSTALL"] call A3UE_fnc_fpv_patchSupportRegistries;
	_matches = false;
	["INSTALL"] call A3UE_fnc_fpv_patchSupportRegistries;
	["CALLBACK_CONFLICT_RELEASES_OWNED", !("FPV" in A3A_supportTypesInv)
		&& {_foreign isEqualRef (A3A_supportTypesOcc get "FPV")}] call _assert;
	_matches = true;
	// Simulate a successfully captured pair; exercise the real repeat/loss rollback.
	A3UE_FPV_catalog = createHashMapFromArray [["armafpv", createHashMapFromArray [["classesBySide",
		createHashMapFromArray [["east", createHashMapFromArray [["AT", ["O_UAV_01_F"]]]]]]]]];
	SCRT_fnc_rivals_selectAndExecuteEvent = _baselineSelector;
	SCRT_fnc_rivals_encounter_uavFlyby = _baselineHandler;
	A3UE_FPV_rivalsHookClaim = createHashMap;
	["INSTALL"] call A3UE_fnc_fpv_installRivalsHooks;
	["RIVALS_FIRST_ASSIGNMENT_READBACK", A3UE_FPV_rivalsHooksInstalled
		&& {SCRT_fnc_rivals_selectAndExecuteEvent isEqualTo A3UE_fnc_fpv_rivalsSelectAndExecuteEvent}
		&& {SCRT_fnc_rivals_encounter_uavFlyby isEqualTo A3UE_fnc_fpv_rivalsUavFlyby}
		&& {A3UE_FPV_originalRivalsSelectAndExecuteEvent isEqualTo _baselineSelector}] call _assert;
	["RESTORE"] call A3UE_fnc_fpv_installRivalsHooks;
	["RIVALS_OWNED_RELEASE_READBACK", !A3UE_FPV_rivalsHooksInstalled
		&& {SCRT_fnc_rivals_selectAndExecuteEvent isEqualTo _baselineSelector}
		&& {SCRT_fnc_rivals_encounter_uavFlyby isEqualTo _baselineHandler}] call _assert;
	private _selector = {diag_log "AU06 captured selector sentinel";};
	private _handler = {diag_log "AU06 captured handler sentinel";};
	A3UE_FPV_originalRivalsSelectAndExecuteEvent = _selector;
	A3UE_FPV_originalRivalsUavFlyby = _handler;
	SCRT_fnc_rivals_selectAndExecuteEvent = A3UE_fnc_fpv_rivalsSelectAndExecuteEvent;
	SCRT_fnc_rivals_encounter_uavFlyby = A3UE_fnc_fpv_rivalsUavFlyby;
	A3UE_FPV_rivalsHookClaim = createHashMapFromArray [["selector", A3UE_fnc_fpv_rivalsSelectAndExecuteEvent],
		["handler", A3UE_fnc_fpv_rivalsUavFlyby], ["originals", [_selector, _handler]]];
	["INSTALL"] call A3UE_fnc_fpv_installRivalsHooks;
	["RIVALS_REPEAT_NO_SELF_CAPTURE", A3UE_FPV_rivalsHooksInstalled
		&& {A3UE_FPV_originalRivalsSelectAndExecuteEvent isEqualTo _selector}
		&& {A3UE_FPV_originalRivalsUavFlyby isEqualTo _handler}] call _assert;
	private _later = {diag_log "AU06 later foreign handler sentinel";};
	SCRT_fnc_rivals_encounter_uavFlyby = _later;
	["CHECK"] call A3UE_fnc_fpv_installRivalsHooks;
	["RIVALS_CHECK_DETECTS_WITHOUT_WRITING", !A3UE_FPV_rivalsHooksInstalled
		&& {SCRT_fnc_rivals_selectAndExecuteEvent isEqualTo A3UE_fnc_fpv_rivalsSelectAndExecuteEvent}] call _assert;
	["INSTALL"] call A3UE_fnc_fpv_installRivalsHooks;
	["INSTALL"] call A3UE_fnc_fpv_installRivalsHooks;
	["LATER_WRAPPER_PRESERVED_AND_NO_FIGHT", SCRT_fnc_rivals_encounter_uavFlyby isEqualTo _later
		&& {SCRT_fnc_rivals_selectAndExecuteEvent isEqualTo _selector} && {!A3UE_FPV_rivalsHooksInstalled}] call _assert;
	{_x params ["_name", "_present", "_value"]; missionNamespace setVariable [_name, if (_present) then {_value} else {nil}];} forEach _saved;
	private _liveAfter = call _liveCheck;
	if (false in _liveAfter) then {_failures pushBack "PRODUCTION_BINDING_RESTORATION";};
	diag_log ["A3UE FPV TEST AU-06", "PRODUCTION RESTORED", _liveAfter];
	diag_log ["A3UE FPV TEST AU-06", "STRUCTURAL END", _cases, _failures,
		["PASS", "FAIL"] select (_failures isNotEqualTo [])];
};
