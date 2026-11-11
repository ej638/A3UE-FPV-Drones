// Destructive ENGINE fixture, server LOCAL scheduled execVM; real managed factory specimen.
// [uav, deliveryPosASL, target, "packed", false] execVM ...;
// "source" exercises raw PBO SQF; "packed" exercises the loaded CfgFunctions implementation.
// final true deliberately runs the historical expression; expected RPT error is isolated by sentinels.
params [["_u", objNull], ["_pos", []], ["_target", objNull], ["_implementation", "packed"], ["_legacy", false]];
if (!isServer || {isRemoteExecuted} || {!canSuspend} || {isNull _u} || {!alive _u} || {!local _u}
	|| {count _pos != 3} || {[_u] call A3UE_fnc_fpv_isExternallyControlled}) exitWith {diag_log "UAQA CONTRACT BLOCKED prerequisites";};
private _life = _u getVariable ["A3UE_FPV_lifecycleIdServer", -1];
private _id = netId _u;
private _impl = if (_implementation == "source") then {
	compile preprocessFileLineNumbers "\fpv_ai_drones\functions\fpv\fn_fpv_commitDetonation.sqf"
} else {A3UE_fnc_fpv_commitDetonation};
private _strike = createHashMapFromArray [["uavNetId", _id], ["targetNetId", netId _target],
	["deliveryPosASL", _pos], ["deliveryDir", [0,1,0]], ["deliveryUp", [0,0,1]],
	["detonationReason", "DIRECT_CONTACT"], ["fallbackReason", "NONE"],
	["boolProbe", true], ["boolFalseProbe", false], ["emptyProbe", []]];
private _failures = 0;
private _check = {params ["_name", "_ok"]; if (!_ok) then {_failures = _failures + 1;}; diag_log ["UAQA CONTRACT", _implementation, _id, _name, _ok];};
diag_log ["UAQA CONTRACT BEGIN", _id, _life, _implementation, productVersion];
if (_legacy) then {
	diag_log "UAQA LEGACY EXPECTED_ERROR BEGIN (exclude ONLY this sentinel span from candidate validation)";
	private _legacyCode = compile preprocessFileLineNumbers "scripts\ua_dive\legacy_snapshot.sqf";
	private _legacyResult = "NO_RETURN";
	isNil {_legacyResult = [_strike] call _legacyCode;};
	diag_log ["UAQA LEGACY RAW RESULT", if (isNil "_legacyResult") then {"NIL"} else {typeName _legacyResult}, if (isNil "_legacyResult") then {"NO_RETURN"} else {_legacyResult}];
	_legacyCode = compileScript ["scripts\ua_dive\legacy_snapshot.sqf"];
	_legacyResult = "NO_RETURN";
	isNil {_legacyResult = [_strike] call _legacyCode;};
	diag_log ["UAQA LEGACY COMPILESCRIPT RESULT", if (isNil "_legacyResult") then {"NIL"} else {typeName _legacyResult}, if (isNil "_legacyResult") then {"NO_RETURN"} else {_legacyResult}];
	// Numeric result without comparison: documents intermediate type independently.
	private _index = (values _strike) findIf {false};
	diag_log ["UAQA FINDIF TYPE", typeName _index, _index, (_index isEqualType 0) && {_index < 0}];
	diag_log "UAQA LEGACY EXPECTED_ERROR END";
};
private _accepted = false;
// No scheduled interleaving during negative probes and the final valid commit.
isNil {
	{
		_x params ["_key", "_value", "_name"];
		private _bad = +_strike; _bad set [_key, _value];
		[_name, !([_u, _life, _bad] call _impl) && {!(_u getVariable ["A3UE_FPV_detonationCommitted", false])}] call _check;
	} forEach [["bad", objNull, "object snapshot"], ["bad", [[1]], "nested array"],
		["bad", [1,true,3], "boolean vector"], ["bad", [1,"x",3], "string vector"],
		["bad", [1,2,3,4], "oversize array"], ["bad", createHashMap, "nested map"],
		["deliveryPosASL", [1000001,0,1], "coordinate bound"], ["deliveryDir", [0,0,0], "degenerate direction"],
		["deliveryUp", [0,1,0], "parallel pose"], ["deliveryUp", 1, "scalar pose"],
		["detonationReason", "FORGED", "reason admission"], ["fallbackReason", "FORGED", "fallback admission"],
		["uavNetId", "FORGED", "identity admission"], ["12345678901234567890123456789012345", 1, "key length"]];
};
// Explicit bound probes and valid value types, each through the real engine implementation.
isNil {
	private _long = ""; for "_i" from 1 to 129 do {_long = _long + "x";};
	private _bad = +_strike; _bad set ["bad", _long]; ["string bound", !([_u,_life,_bad] call _impl)] call _check;
	_bad = +_strike; for "_i" from 1 to 33 do {_bad set [str _i, 0];}; ["map bound", !([_u,_life,_bad] call _impl)] call _check;
	["wrong lifetime", !([_u,_life+1,_strike] call _impl)] call _check;
	private _sleep = [10, [9,10.1]] call A3UE_fnc_fpv_controllerSleep;
	["due deadline uses floor", abs (_sleep - 0.02) < 0.0001] call _check;
	["future deadline cap", ([10,[11]] call A3UE_fnc_fpv_controllerSleep) == 0.25] call _check;
	if (_failures == 0) then {_accepted = [_u,_life,_strike] call _impl;};
};
["valid bounded snapshot committed", _accepted] call _check;
private _rows = (missionNamespace getVariable ["A3UE_FPV_recentDetonations", []]) select {(_x getOrDefault ["uavNetId", ""]) == _id && {(_x getOrDefault ["lifecycleId", -1]) == _life}};
["exactly one receipt", count _rows == 1] call _check;
if (_accepted) then {
	[_u,_life,+_strike] call _impl;
	private _again = (missionNamespace getVariable ["A3UE_FPV_recentDetonations", []]) select {(_x getOrDefault ["uavNetId", ""]) == _id && {(_x getOrDefault ["lifecycleId", -1]) == _life}};
	["duplicate adds no receipt", count _again == 1] call _check;
	diag_log ["UAQA CONTRACT RECEIPT", _rows];
};
diag_log ["UAQA CONTRACT END", _implementation, _id, _failures, "receipt only; actual effects/contact/smoothness require flight cases"];
