// Installed-SQF STRUCTURAL contracts only: NOT vendor/AU combat or ownership evidence.
// Server Local Exec in a disposable, fully ready AU MP mission:
// [] execVM "scripts\v01_targetability.sqf"; restart afterward.
if (!isServer || {isRemoteExecuted} || {isNil "sidesX"} || {isNull sidesX}) exitWith {
	diag_log "[A3UE FPV TEST V01] BLOCKED need server-local ready AU MP mission";
	false
};
isNil {
	private _names = ["DB_fnc_fpv_handleSettings", "UA_fnc_fpv_handleSettings",
		"A3UE_FPV_crocusTargetabilityAdapterInstalled", "A3UE_FPV_uaTargetabilityAdapterInstalled",
		"A3UE_FPV_crocusNativeHandleSettings", "A3UE_FPV_uaNativeHandleSettings",
		"A3UE_FPV_targetabilityDrones", "FPV_isUavCaptive"];
	private _saved = _names apply {[_x, !isNil {missionNamespace getVariable _x}, missionNamespace getVariable [_x, {}]]};
	private _oldControl = A3UE_fnc_fpv_isExternallyControlled;
	private _controlled = false;
	private _control = {_controlled};
	A3UE_fnc_fpv_isExternallyControlled = _control;
	if (A3UE_fnc_fpv_isExternallyControlled isNotEqualTo _control) exitWith {
		diag_log "[A3UE FPV TEST V01] BLOCKED immutable control fixture binding";
	};
	private _cases = 0;
	private _failures = 0;
	private _check = {
		params ["_case", "_pass"];
		_cases = _cases + 1;
		if (!_pass) then {_failures = _failures + 1;};
		diag_log format ["[A3UE FPV TEST V01] STRUCTURAL case=%1 pass=%2", _case, _pass];
	};
	diag_log "[A3UE FPV TEST V01] STRUCTURAL BEGIN";
	DB_fnc_fpv_handleSettings = nil;
	UA_fnc_fpv_handleSettings = nil;
	A3UE_FPV_crocusTargetabilityAdapterInstalled = false;
	A3UE_FPV_uaTargetabilityAdapterInstalled = false;
	A3UE_FPV_targetabilityDrones = createHashMap;
	["absent vendors are optional", !(call A3UE_fnc_fpv_installTargetabilityAdapters)] call _check;
	private _u = createVehicle ["O_UAV_01_F", [50, 50, 100], [], 0, "NONE"];
	private _native = createVehicle ["O_UAV_01_F", [60, 50, 100], [], 0, "NONE"];
	{_x enableSimulationGlobal false; createVehicleCrew _x;} forEach [_u, _native];
	private _groups = [group driver _u, group driver _native];
	if (isNull driver _u || {isNull driver _native} || {netId _u == ""}) exitWith {
		{private _v = _x; {_v deleteVehicleCrew _x;} forEach crew _v; deleteVehicle _v;} forEach [_u, _native];
		{if (!isNull _x) then {deleteGroup _x;};} forEach _groups;
		A3UE_fnc_fpv_isExternallyControlled = _oldControl;
		{_x params ["_name", "_exists", "_value"]; missionNamespace setVariable [_name, if (_exists) then {_value} else {nil}];} forEach _saved;
		diag_log "[A3UE FPV TEST V01] BLOCKED missing crew/MP netId; no qualified END";
	};
	_u setVariable ["A3UE_FPV_managed", true];
	_u setVariable ["A3UE_FPV_netId", netId _u];
	_u setVariable ["A3UE_FPV_controllerGeneration", 7];
	{
		_u setVariable ["A3UE_FPV_vendorId", _x];
		_u setCaptive true;
		private _ok = [_u, 7] call A3UE_fnc_fpv_applyTargetability;
		[format ["%1 autonomous captivity repaired", _x], _ok && {!captive _u}] call _check;
	} forEach ["armafpv", "fpv_ua", "kvn"];
	_u setCaptive true;
	_controlled = true;
	["direct control retains captivity", !([_u, 7] call A3UE_fnc_fpv_applyTargetability) && {captive _u}] call _check;
	_controlled = false;
	["release restores targetability", ([_u, 7] call A3UE_fnc_fpv_applyTargetability) && {!captive _u}] call _check;
	_u setCaptive true;
	["stale generation rejected", !([_u, 6] call A3UE_fnc_fpv_applyTargetability) && {captive _u}] call _check;
	_u setVariable ["A3UE_FPV_netId", netId _native];
	["copied identity rejected", !([_u, 7] call A3UE_fnc_fpv_applyTargetability) && {captive _u}] call _check;
	_u setVariable ["A3UE_FPV_netId", netId _u];
	_u setVariable ["A3UE_FPV_preserveControlOnCleanup", true];
	["retirement cannot be normalized", !([_u, 7] call A3UE_fnc_fpv_applyTargetability) && {captive _u}] call _check;
	_u setVariable ["A3UE_FPV_preserveControlOnCleanup", false];
	_native setCaptive true;
	["unmanaged untouched", !([_native] call A3UE_fnc_fpv_applyTargetability) && {captive _native}] call _check;
	private _marker = format ["A3UE_QA_V01_%1", netId _u];
	private _side = side group driver _u;
	sidesX setVariable [_marker, _side];
	_u setVariable ["A3UE_FPV_siteEpoch", "QA_V01"];
	_u setVariable ["A3UE_FPV_siteMarker", _marker];
	_u setVariable ["A3UE_FPV_siteSide", _side];
	(driver _u) setCaptive true;
	["bare captive pilot remains active and is repaired", ([_u] call A3UE_fnc_fpv_isSiteDroneActive)
		&& {[_u, 7] call A3UE_fnc_fpv_applyTargetability} && {!captive driver _u} && {!captive _u}] call _check;
	_u setCaptive true;
	(driver _u) setVariable ["surrendered", true];
	["explicit surrender still inhibits", !([_u] call A3UE_fnc_fpv_isSiteDroneActive)
		&& {!([_u, 7] call A3UE_fnc_fpv_applyTargetability)} && {captive _u}] call _check;
	(driver _u) setVariable ["surrendered", false];
	sidesX setVariable [_marker, civilian];
	["captured site still inhibits", !([_u, 7] call A3UE_fnc_fpv_applyTargetability) && {captive _u}] call _check;
	sidesX setVariable [_marker, _side];
	_u setVariable ["A3UE_FPV_siteRetired", true];
	["retired site still inhibits", !([_u, 7] call A3UE_fnc_fpv_applyTargetability) && {captive _u}] call _check;
	_u setVariable ["A3UE_FPV_siteRetired", false];
	_u setVariable ["A3UE_FPV_vendorId", "armafpv"];
	// Running sentinel avoids controller/delayed-init launch; exercises actual cache/EHs.
	_u setVariable ["A3UE_FPV_controllerRunning", true];
	[_u] call A3UE_fnc_fpv_bootstrapLocal;
	private _eh = _u getVariable ["A3UE_FPV_targetabilityDeletedEH", -1];
	[_u] call A3UE_fnc_fpv_bootstrapLocal;
	["bootstrap cache/EH idempotent", (A3UE_FPV_targetabilityDrones getOrDefault [netId _u, objNull]) isEqualTo _u
		&& {_eh >= 0} && {(_u getVariable ["A3UE_FPV_targetabilityDeletedEH", -1]) == _eh}
		&& {count A3UE_FPV_targetabilityDrones == 1}] call _check;
	private _nativeArgs = [];
	DB_fnc_fpv_handleSettings = {
		_nativeArgs = +_this;
		{_x setCaptive (missionNamespace getVariable ["FPV_isUavCaptive", true]);} forEach [_u, _native];
		17
	};
	UA_fnc_fpv_handleSettings = {23};
	["install callable adapters", call A3UE_fnc_fpv_installTargetabilityAdapters] call _check;
	private _captured = A3UE_FPV_crocusNativeHandleSettings;
	private _wrapper = DB_fnc_fpv_handleSettings;
	["adapter install idempotent", (call A3UE_fnc_fpv_installTargetabilityAdapters)
		&& {_captured isEqualTo A3UE_FPV_crocusNativeHandleSettings} && {_wrapper isEqualTo DB_fnc_fpv_handleSettings}] call _check;
	{
		FPV_isUavCaptive = _x;
		private _value = ["argument", 9] call DB_fnc_fpv_handleSettings;
		[format ["settings %1 preserve native arguments/return/policy", _x], _value isEqualTo 17
			&& {_nativeArgs isEqualTo ["argument", 9]} && {!captive _u} && {(captive _native) isEqualTo _x}
			&& {FPV_isUavCaptive isEqualTo _x}] call _check;
	} forEach [true, false];
	["UA native return preserved", ([] call UA_fnc_fpv_handleSettings) isEqualTo 23] call _check;
	private _id = netId _u;
	// An old Deleted event must not remove an entry for a different exact object.
	A3UE_FPV_targetabilityDrones set [_id, _native];
	{_u deleteVehicleCrew _x;} forEach crew _u;
	deleteVehicle _u;
	["deleted old object cannot remove different cache identity", (A3UE_FPV_targetabilityDrones getOrDefault [_id, objNull]) isEqualTo _native] call _check;
	A3UE_FPV_targetabilityDrones deleteAt _id;
	_native setVariable ["A3UE_FPV_managed", true];
	_native setVariable ["A3UE_FPV_netId", netId _native];
	_native setVariable ["A3UE_FPV_vendorId", "armafpv"];
	_native setVariable ["A3UE_FPV_controllerRunning", true];
	[_native] call A3UE_fnc_fpv_bootstrapLocal;
	_id = netId _native;
	{_native deleteVehicleCrew _x;} forEach crew _native;
	deleteVehicle _native;
	["actual deletion removes exact cached object", !(_id in A3UE_FPV_targetabilityDrones)] call _check;
	sidesX setVariable [_marker, nil];
	{if (!isNull _x) then {deleteGroup _x;};} forEach _groups;
	A3UE_fnc_fpv_isExternallyControlled = _oldControl;
	{_x params ["_name", "_exists", "_value"]; missionNamespace setVariable [_name, if (_exists) then {_value} else {nil}];} forEach _saved;
	diag_log format ["[A3UE FPV TEST V01] STRUCTURAL END cases=%1 failures=%2; vendor/AU combat/locality NOT RUN", _cases, _failures];
};
true
