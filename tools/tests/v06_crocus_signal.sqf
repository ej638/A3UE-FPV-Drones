// Installed SQF contracts with native spies; NOT live HUD/AU/network qualification.
// Client Local Exec in a disposable ready AU MP mission; restart afterward.
// [] execVM "scripts\v06_crocus_signal.sqf";
if (!hasInterface || {isNull player} || {isRemoteExecuted}) exitWith {
	diag_log "[A3UE FPV TEST V06] BLOCKED need client-local MP player";
	false
};
isNil {
	private _names = ["DB_fnc_fpv_getSignal", "DB_fnc_fpv_ppfx_setInput", "DB_fnc_fpv_onSignalLost",
		"A3UE_FPV_crocusSignalAdapterInstalled", "A3UE_FPV_crocusNativeGetSignal",
		"A3UE_FPV_crocusNativePpfxSetInput", "A3UE_FPV_crocusNativeOnSignalLost",
		"A3UE_fnc_fpv_isExternallyControlled", "A3UE_fnc_fpv_sampleRadioLink", "A3UE_fnc_fpv_sendLifecycle",
		"bis_fnc_moduleRemoteControl_unit", "A3UE_FPV_catalog"];
	private _saved = _names apply {[_x, !isNil {missionNamespace getVariable _x}, missionNamespace getVariable [_x, {}]]};
	private _previousUav = getConnectedUAV player;
	private _u = objNull;
	private _restore = {
		player connectTerminalToUAV _previousUav;
		if (!isNull _u) then {deleteVehicle _u;};
		{_x params ["_name", "_exists", "_value"]; missionNamespace setVariable [_name, if (_exists) then {_value} else {nil}];} forEach _saved;
	};
	private _cases = 0;
	private _failures = 0;
	private _check = {
		params ["_case", "_pass"];
		_cases = _cases + 1;
		if (!_pass) then {_failures = _failures + 1;};
		diag_log format ["[A3UE FPV TEST V06] STRUCTURAL case=%1 pass=%2", _case, _pass];
	};
	DB_fnc_fpv_getSignal = nil;
	DB_fnc_fpv_ppfx_setInput = nil;
	DB_fnc_fpv_onSignalLost = nil;
	A3UE_FPV_crocusSignalAdapterInstalled = false;
	if (!isNil "DB_fnc_fpv_getSignal" || {!isNil "DB_fnc_fpv_ppfx_setInput"} || {!isNil "DB_fnc_fpv_onSignalLost"}) exitWith {
		call _restore;
		diag_log "[A3UE FPV TEST V06] BLOCKED immutable fixture bindings; no qualified END";
	};
	diag_log "[A3UE FPV TEST V06] STRUCTURAL BEGIN";
	["absent vendor remains optional", !(call A3UE_fnc_fpv_installCrocusSignalAdapter)] call _check;
	private _nativeSignalCalls = 0;
	private _nativeSignalArgs = [];
	private _nativeInputArgs = [];
	private _nativeLossCalls = 0;
	private _nativeLossArgs = [];
	DB_fnc_fpv_getSignal = {_nativeSignalCalls = _nativeSignalCalls + 1; _nativeSignalArgs = +_this; 0.87};
	DB_fnc_fpv_ppfx_setInput = {_nativeInputArgs = +_this; "input-result"};
	private _originalSignal = DB_fnc_fpv_getSignal;
	["partial APIs do not install competing half-adapter", !(call A3UE_fnc_fpv_installCrocusSignalAdapter)
		&& {DB_fnc_fpv_getSignal isEqualTo _originalSignal}] call _check;
	DB_fnc_fpv_onSignalLost = {_nativeLossCalls = _nativeLossCalls + 1; _nativeLossArgs = +_this; "loss-result"};
	["late complete APIs install", call A3UE_fnc_fpv_installCrocusSignalAdapter] call _check;
	private _wrapper = DB_fnc_fpv_getSignal;
	["repeated installation cannot capture wrapper", call A3UE_fnc_fpv_installCrocusSignalAdapter
		&& {DB_fnc_fpv_getSignal isEqualTo _wrapper} && {A3UE_FPV_crocusNativeGetSignal isEqualTo _originalSignal}] call _check;
	_u = createVehicle ["B_UAV_01_F", [50, 50, 100], [], 0, "NONE"];
	if (isNull _u || {netId _u == ""} || {!local _u}) exitWith {
		call _restore;
		diag_log "[A3UE FPV TEST V06] BLOCKED need local MP fixture; no qualified END";
	};
	_u enableSimulation false;
	bis_fnc_moduleRemoteControl_unit = player;
	player connectTerminalToUAV _u;
	if ((getConnectedUAV player) isNotEqualTo _u) exitWith {
		call _restore;
		diag_log "[A3UE FPV TEST V06] BLOCKED terminal connection; no qualified END";
	};
	private _direct = false;
	A3UE_fnc_fpv_isExternallyControlled = {_direct}; // Branch fixture only; live Q07 required.
	_u setVariable ["A3UE_FPV_managed", true];
	_u setVariable ["A3UE_FPV_vendorId", "armafpv"];
	_u setVariable ["A3UE_FPV_linkModel", "RADIO"];
	private _sent = [];
    A3UE_fnc_fpv_sendLifecycle = {_sent = +_this; true}; // Payload shape only, NOT transport.
	private _sampleCalls = 0;
	private _changeGeneration = false;
	A3UE_fnc_fpv_sampleRadioLink = {
		_sampleCalls = _sampleCalls + 1;
		if (_changeGeneration) then {(_this # 3) setVariable ["A3UE_FPV_controllerGeneration", 1];};
		createHashMapFromArray [["signal", 0.42], ["distance", 2600], ["maxDistance", 6500], ["obstacles", 3], ["terrainMask", 0.4]]
	};
	A3UE_FPV_catalog = createHashMapFromArray [["armafpv", createHashMap]];
	private _state = [_u] call A3UE_fnc_fpv_evaluateLinkState;
	private _packet = +_sent;
	["production evaluator submits one complete node context", _state == "DEGRADED" && {_sampleCalls == 1}
		&& {count _packet == 3} && {(_packet # 0) isEqualTo _u} && {(_packet # 1) == "signal"}
        && {((_packet # 2) # 1) == 0.42} && {(((_packet # 2) # 2) # 3) == 2600} && {(((_packet # 2) # 2) # 5) == 6500}] call _check;
	["evaluator never writes obsolete or native-owned signal keys", isNil {_u getVariable "DB_fpv_signal_obstacles"}
		&& {isNil {_u getVariable "DB_fpv_signal_terrainMask"}} && {isNil {_u getVariable "DB_fpv_signalObstacles"}}
		&& {isNil {_u getVariable "DB_fpv_isUAVsignalLost"}}] call _check;
	_u setVariable ["A3UE_FPV_signalStrength", 0.77];
	_changeGeneration = true;
	[_u] call A3UE_fnc_fpv_evaluateLinkState;
	["superseded sample cannot publish snapshot or strength", (_u getVariable ["A3UE_FPV_signalStrength", -1]) == 0.77
		&& {_sent isEqualTo _packet}] call _check;
	_changeGeneration = false;
	private _expectedContext = ["altAGL", 12, "distance", 2600, "maxDistance", 6500,
		"inJammer", true, "jammerFactor", 0.8, "obstacleCount", 3, "terrainMask", 0.4];
	// Synthetic selector packet only. Cross-process proof uses v06_cross_machine.sqf.
    _u setVariable ["A3UE_FPV_controllerIdentity", [71, 2, 7, 0]];
    _u setVariable ["A3UE_FPV_signalEpoch", 0];
    _u setVariable ["A3UE_FPV_signalIdentity", [71, 2, 7, 0, 0]];
    private _seed = { _u setVariable ["A3UE_FPV_crocusSignalSnapshot", [netId _u, [71, 2, 7, 0, 0], 7, serverTime, 0.12, +_expectedContext]]; };
	call _seed;
	["passive signal uses owner cache without native/sample queries", ([player, _u] call DB_fnc_fpv_getSignal) == 0.12
		&& {_nativeSignalCalls == 0} && {_sampleCalls == 2}] call _check;
	["current fields reflect cached obstacles terrain relay and jammer", (_u getVariable ["DB_fpv_signalObstacles", -1]) == 3
		&& {(_u getVariable ["DB_fpv_signalTerrainMask", -1]) == 0.4}
		&& {(_u getVariable ["DB_fpv_signalMaxDistance", -1]) == 6500}
		&& {_u getVariable ["DB_fpv_inJammer", false]} && {(_u getVariable ["DB_fpv_jammerFactor", -1]) == 0.8}] call _check;
	["PPFX replaces operator context with same cached node context", ([0.9, ["distance", 25]] call DB_fnc_fpv_ppfx_setInput) == "input-result"
		&& {_nativeInputArgs isEqualTo [0.12, _expectedContext]}] call _check;
	[player, _u] call DB_fnc_fpv_onSignalLost;
	["passive signal loss cannot invoke destructive native path", _nativeLossCalls == 0 && {alive _u}] call _check;
	{
		private _bad = +(_u getVariable "A3UE_FPV_crocusSignalSnapshot");
		_bad set [_x # 0, _x # 1];
		_u setVariable ["A3UE_FPV_crocusSignalSnapshot", _bad];
		[format ["invalid identity/owner/time/context %1 is neutral", _forEachIndex], ([player, _u] call DB_fnc_fpv_getSignal) == 1
			&& {_nativeSignalCalls == 0} && {_sampleCalls == 2}] call _check;
		call _seed;
	} forEach [[0, "other-object"], [1, [71, 3, 7, 0, 0]], [2, 6], [3, serverTime - 3], [3, serverTime + 3], [5, []]];
	_u setVariable ["A3UE_FPV_crocusSignalSnapshot", nil];
	["missing sample is neutral with no competing calculation", ([player, _u] call DB_fnc_fpv_getSignal) == 1 && {_nativeSignalCalls == 0}] call _check;
	call _seed;
	private _oldSignal = +(_u getVariable "A3UE_FPV_crocusSignalSnapshot");
    _oldSignal set [3, serverTime - 0.1]; _u setVariable ["A3UE_FPV_crocusSignalSnapshot", _oldSignal];
    _direct = true;
	private _signalArgs = [player, _u, "extra"];
	["direct pilot/gunner/Zeus branch preserves native args and return", (_signalArgs call DB_fnc_fpv_getSignal) == 0.87 && {_nativeSignalArgs isEqualTo _signalArgs}] call _check;
	private _inputArgs = [0.91, ["distance", 25], "extra"];
	["direct PPFX context is native", (_inputArgs call DB_fnc_fpv_ppfx_setInput) == "input-result" && {_nativeInputArgs isEqualTo _inputArgs}] call _check;
	private _lossArgs = [player, _u, "extra"];
	["direct loss retains native behavior", (_lossArgs call DB_fnc_fpv_onSignalLost) == "loss-result" && {_nativeLossArgs isEqualTo _lossArgs}] call _check;
	_direct = false;
	["same-owner release is neutral until a fresh sample", ([player, _u] call DB_fnc_fpv_getSignal) == 1] call _check;
    call _seed;
    ["fresh released sample selected", ([player, _u] call DB_fnc_fpv_getSignal) == 0.12] call _check;
    private _future = [netId _u, [71, 3, 8, 1, 0], 1, serverTime, 0.2, +_expectedContext];
    _u setVariable ["A3UE_FPV_crocusSignalSnapshot", _future];
    ["packet before identity is neutral", ([player, _u] call DB_fnc_fpv_getSignal) == 1] call _check;
    call _seed;
    ["old identity plus old packet cannot rewind packet fence", ([player, _u] call DB_fnc_fpv_getSignal) == 1] call _check;
    _u setVariable ["A3UE_FPV_controllerIdentity", [71, 3, 8, 1]];
    _u setVariable ["A3UE_FPV_signalIdentity", [71, 3, 8, 1, 0]]; _u setVariable ["A3UE_FPV_crocusSignalSnapshot", _future];
    ["matching future state and packet selected", ([player, _u] call DB_fnc_fpv_getSignal) == 0.2] call _check;
    _u setVariable ["A3UE_FPV_signalEpoch", 23]; // Older episode diagnostic arrives late.
    _u setVariable ["A3UE_FPV_controllerIdentity", [71, 2, 9, 2]];
    ["state-first rapid return cannot reuse old owner sample", ([player, _u] call DB_fnc_fpv_getSignal) == 1] call _check;
    _u setVariable ["A3UE_FPV_crocusSignalSnapshot", [netId _u, [71, 2, 9, 2, 0], 1, serverTime, 0.3, +_expectedContext]];
    ["new controller/packet await atomic signal state", ([player, _u] call DB_fnc_fpv_getSignal) == 1] call _check;
    _u setVariable ["A3UE_FPV_signalIdentity", [71, 2, 9, 2, 0]];
    ["returned owner current episode selected despite stale separate counter", ([player, _u] call DB_fnc_fpv_getSignal) == 0.3] call _check;
    _u setVariable ["A3UE_FPV_signalEpoch", 1];
    _u setVariable ["A3UE_FPV_signalIdentity", [71, 2, 9, 2, 1]];
    ["control-state first invalidates earlier sample", ([player, _u] call DB_fnc_fpv_getSignal) == 1] call _check;
    _u setVariable ["A3UE_FPV_crocusSignalSnapshot", [netId _u, [71, 2, 9, 2, 2], 2, serverTime, 0.4, +_expectedContext]];
    ["control-packet first neutral pending state", ([player, _u] call DB_fnc_fpv_getSignal) == 1] call _check;
    _u setVariable ["A3UE_FPV_signalEpoch", 2];
    _u setVariable ["A3UE_FPV_signalIdentity", [71, 2, 9, 2, 2]];
    ["matching control epoch selected", ([player, _u] call DB_fnc_fpv_getSignal) == 0.4] call _check;
    private _next = [71, 3, 10, 3, 0];
    _u setVariable ["A3UE_FPV_signalIdentity", _next];
    ["atomic signal state before controller invalidates old packet", ([player, _u] call DB_fnc_fpv_getSignal) == 1] call _check;
    _u setVariable ["A3UE_FPV_controllerIdentity", _next select [0,4]];
    _u setVariable ["A3UE_FPV_crocusSignalSnapshot", [netId _u, _next, 1, serverTime, 0.5, +_expectedContext]];
    ["state-first full tuple converges", ([player, _u] call DB_fnc_fpv_getSignal) == 0.5] call _check;
    _u setVariable ["A3UE_FPV_signalIdentity", []];
    ["pending challenge/release identity cannot consume queued packet", ([player, _u] call DB_fnc_fpv_getSignal) == 1] call _check;
    _u setVariable ["A3UE_FPV_signalViewWatermark", [-1,-1,-1]];
    _u setVariable ["A3UE_FPV_signalIdentity", _next]; _u setVariable ["A3UE_FPV_controllerIdentity", []];
    ["cold selector split-arrival is neutral without controller", ([player, _u] call DB_fnc_fpv_getSignal) == 1] call _check;
    _u setVariable ["A3UE_FPV_controllerIdentity", _next select [0,4]];
    ["cold selector converges after controller arrives", ([player, _u] call DB_fnc_fpv_getSignal) == 0.5] call _check;
	{
		_u setVariable [_x # 0, _x # 1];
		private _before = _nativeSignalCalls;
		[format ["unmanaged/other family/fiber %1 delegates", _forEachIndex], ([player, _u] call DB_fnc_fpv_getSignal) == 0.87 && {_nativeSignalCalls == _before + 1}] call _check;
		_u setVariable ["A3UE_FPV_managed", true]; _u setVariable ["A3UE_FPV_vendorId", "armafpv"]; _u setVariable ["A3UE_FPV_linkModel", "RADIO"];
	} forEach [["A3UE_FPV_managed", false], ["A3UE_FPV_vendorId", "fpv_ua"], ["A3UE_FPV_linkModel", "FIBER_VISUAL"]];
	_u setVariable ["A3UE_FPV_managed", false];
	["unmanaged input remains native", (_inputArgs call DB_fnc_fpv_ppfx_setInput) == "input-result" && {_nativeInputArgs isEqualTo _inputArgs}] call _check;
	["unmanaged loss remains native", (_lossArgs call DB_fnc_fpv_onSignalLost) == "loss-result" && {_nativeLossArgs isEqualTo _lossArgs}] call _check;
	player connectTerminalToUAV objNull;
	["disconnected input preserves native arguments", (_inputArgs call DB_fnc_fpv_ppfx_setInput) == "input-result" && {_nativeInputArgs isEqualTo _inputArgs}] call _check;
	deleteVehicle _u;
	["deleted object cannot supply cached input", ([_u] call A3UE_fnc_fpv_getCrocusSignalContext) isEqualTo []] call _check;
	call _restore;
	diag_log format ["[A3UE FPV TEST V06] STRUCTURAL END cases=%1 failures=%2 restored=true; live HUD/routes NOT RUN", _cases, _failures];
	_failures == 0
}
