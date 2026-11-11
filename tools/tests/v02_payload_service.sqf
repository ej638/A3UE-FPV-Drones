// Installed wrapper contracts only; NOT live UA UI/RPC/AU-route qualification.
// Server Local Exec in a disposable ready AU MP mission; restart afterward.
// [] execVM "scripts\v02_payload_service.sqf";
if (!isServer || {isRemoteExecuted}) exitWith {
	diag_log "[A3UE FPV TEST V02] BLOCKED need server-local MP mission";
	false
};
isNil {
	private _names = ["UA_fnc_fpv_canChangePayload", "UA_fnc_fpv_serverChangePayload",
		"A3UE_FPV_uaPayloadUiAdapterInstalled", "A3UE_FPV_uaPayloadServerAdapterInstalled",
		"A3UE_FPV_uaNativeCanChangePayload", "A3UE_FPV_uaNativeServerChangePayload", "A3UE_FPV_catalog"];
	private _saved = _names apply {[_x, !isNil {missionNamespace getVariable _x}, missionNamespace getVariable [_x, {}]]};
	private _restore = {
		{_x params ["_name", "_exists", "_value"]; missionNamespace setVariable [_name, if (_exists) then {_value} else {nil}];} forEach _saved;
	};
	private _cases = 0;
	private _failures = 0;
	private _check = {
		params ["_case", "_pass"];
		_cases = _cases + 1;
		if (!_pass) then {_failures = _failures + 1;};
		diag_log format ["[A3UE FPV TEST V02] STRUCTURAL case=%1 pass=%2", _case, _pass];
	};
	UA_fnc_fpv_canChangePayload = nil;
	UA_fnc_fpv_serverChangePayload = nil;
	A3UE_FPV_uaPayloadUiAdapterInstalled = false;
	A3UE_FPV_uaPayloadServerAdapterInstalled = false;
	if (!isNil "UA_fnc_fpv_canChangePayload" || {!isNil "UA_fnc_fpv_serverChangePayload"}) exitWith {
		call _restore;
		diag_log "[A3UE FPV TEST V02] BLOCKED immutable vendor fixture bindings";
	};
	diag_log "[A3UE FPV TEST V02] STRUCTURAL BEGIN";
	["absent UA optional", !(call A3UE_fnc_fpv_installUaPayloadAdapter)] call _check;
	// Give the synthetic class a valid descriptor so the UA guard is the gate tested.
	A3UE_FPV_catalog = createHashMapFromArray [["fpv_ua", createHashMapFromArray [["signalModel", "RADIO"],
		["classDescriptors", createHashMapFromArray [["O_UAV_01_F", createHashMapFromArray [
			["taskRoles", ["AT"]], ["sideKey", "east"], ["canDetonate", true], ["ammoClass", "R_PG32V_F"]
		]]]]]]];
	private _spec = createHashMapFromArray [["spawnPosATL", [50, 50, 100]], ["searchAnchorMarker", "QA_V02"],
		["siteType", "Outpost"], ["profileId", "QA_V02"], ["familyId", "fpv_ua"],
		["payloadRole", "AT"], ["uavClass", "O_UAV_01_F"]];
	private _countBefore = count (allMissionObjects "O_UAV_01_F");
	["unguarded managed UA spawn rejected before creation", isNull ([_spec] call A3UE_fnc_fpv_spawnManagedDrone)
		&& {count (allMissionObjects "O_UAV_01_F") == _countBefore}] call _check;
	private _uiCalls = 0;
	private _serverCalls = 0;
	private _uiArgs = [];
	private _serverArgs = [];
	private _uiResult = true;
	private _serverResult = objNull;
	UA_fnc_fpv_canChangePayload = {_uiCalls = _uiCalls + 1; _uiArgs = +_this; _uiResult};
	["partial binding remains unready", !(call A3UE_fnc_fpv_installUaPayloadAdapter)
		&& {A3UE_FPV_uaPayloadUiAdapterInstalled} && {!A3UE_FPV_uaPayloadServerAdapterInstalled}] call _check;
	UA_fnc_fpv_serverChangePayload = {_serverCalls = _serverCalls + 1; _serverArgs = +_this; if (isNil "_serverResult") exitWith {}; _serverResult};
	["late server binding completes install", call A3UE_fnc_fpv_installUaPayloadAdapter] call _check;
	private _uiWrapper = UA_fnc_fpv_canChangePayload;
	private _serverWrapper = UA_fnc_fpv_serverChangePayload;
	private _nativeUi = A3UE_FPV_uaNativeCanChangePayload;
	private _nativeServer = A3UE_FPV_uaNativeServerChangePayload;
	["repeat install never captures itself", (call A3UE_fnc_fpv_installUaPayloadAdapter)
		&& {_uiWrapper isEqualTo UA_fnc_fpv_canChangePayload} && {_serverWrapper isEqualTo UA_fnc_fpv_serverChangePayload}
		&& {_nativeUi isEqualTo A3UE_FPV_uaNativeCanChangePayload} && {_nativeServer isEqualTo A3UE_FPV_uaNativeServerChangePayload}] call _check;
	private _u = createVehicle ["O_UAV_01_F", [50, 50, 100], [], 0, "NONE"];
	if (isNull _u || {netId _u == ""}) exitWith {
		deleteVehicle _u;
		call _restore;
		diag_log "[A3UE FPV TEST V02] BLOCKED missing MP object; no qualified END";
	};
	_u enableSimulationGlobal false;
	_serverResult = _u;
	_u setVariable ["A3UE_FPV_managed", true];
	_u setVariable ["A3UE_FPV_netId", netId _u];
	_u setVariable ["A3UE_FPV_controllerRunning", true];
	_u setVariable ["A3UE_FPV_localityEH", 42];
	_u setVariable ["A3UE_FPV_payloadRole", "AT"];
	private _varsBefore = allVariables _u;
	_varsBefore sort true;
	["managed UI rejects without vendor call", !([_u, objNull] call UA_fnc_fpv_canChangePayload) && {_uiCalls == 0}] call _check;
	{
		private _result = [_u, "IED", objNull, _x] call UA_fnc_fpv_serverChangePayload;
		[format ["managed server force=%1 rejects without vendor side effects", _x], isNull _result && {_serverCalls == 0}] call _check;
	} forEach [false, true];
	private _varsAfter = allVariables _u;
	_varsAfter sort true;
	["rejection preserves metadata and object", !isNull _u && {_varsAfter isEqualTo _varsBefore}
		&& {_u getVariable ["A3UE_FPV_controllerRunning", false]}
		&& {(_u getVariable ["A3UE_FPV_localityEH", -1]) == 42}
		&& {(_u getVariable ["A3UE_FPV_netId", ""]) == netId _u}
		&& {(_u getVariable ["A3UE_FPV_payloadRole", ""]) == "AT"}] call _check;
	_u setVariable ["A3UE_FPV_managed", false];
	["cleanup-cleared managed flag cannot expose UI", !([_u, objNull] call UA_fnc_fpv_canChangePayload) && {_uiCalls == 0}] call _check;
	["cleanup-cleared managed flag cannot expose forced replacement", isNull ([_u, "EMPTY", objNull, true] call UA_fnc_fpv_serverChangePayload)
		&& {_serverCalls == 0}] call _check;
	_u setVariable ["A3UE_FPV_netId", nil];
	_u setVariable ["A3UE_FPV_managed", true];
	["early managed flag alone inhibits", !([_u] call UA_fnc_fpv_canChangePayload)
		&& {isNull ([_u, "IED", objNull, true] call UA_fnc_fpv_serverChangePayload)}
		&& {_uiCalls == 0} && {_serverCalls == 0}] call _check;
	// No release API is implied: strip only fixture metadata on a fixture object.
	_u setVariable ["A3UE_FPV_managed", nil];
	{
		private _args = [_u, objNull, "extra"];
		_uiResult = _x;
		private _result = _args call UA_fnc_fpv_canChangePayload;
		[format ["unmanaged UI preserves %1 result and full arguments", _x], _result isEqualTo _x && {_uiArgs isEqualTo _args}] call _check;
	} forEach [true, false];
	{
		private _args = [_u, "pg7vl", objNull, _x, "extra"];
		private _result = _args call UA_fnc_fpv_serverChangePayload;
		[format ["unmanaged server force=%1 preserves result and full arguments", _x], _result isEqualTo _u && {_serverArgs isEqualTo _args}] call _check;
	} forEach [false, true];
	_serverResult = nil;
	["native nil return preserved", isNil {[_u, "EMPTY"] call UA_fnc_fpv_serverChangePayload}] call _check;
	["unmanaged calls delegated exactly once", _uiCalls == 2 && {_serverCalls == 3}] call _check;
	deleteVehicle _u;
	["deleted object delegates native rejection", isNil {[_u, "EMPTY"] call UA_fnc_fpv_serverChangePayload}
		&& {_serverArgs isEqualTo [_u, "EMPTY"]} && {_serverCalls == 4}] call _check;
	call _restore;
	diag_log format ["[A3UE FPV TEST V02] STRUCTURAL END cases=%1 failures=%2; UI/RPC/AU/locality NOT RUN", _cases, _failures];
};
true
