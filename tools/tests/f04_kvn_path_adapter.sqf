// Structural adapter contract only. Run on the server in a disposable diagnostic MP mission.
// Copy to scripts/ and [] execVM "scripts\f04_kvn_path_adapter.sqf".
// Atomic stubs are restored before native callbacks resume; this is NOT JIP/vendor evidence.
if (!isServer) exitWith {false};
isNil {
	private _names = [
		"DB_kvn_fnc_fpv_updateFiberPath", "DB_kvn_fnc_fpv_syncPath", "DB_kvn_fnc_fpv_receivePath",
		"A3UE_FPV_kvnPathAdapterInstalled", "A3UE_FPV_kvnNativeUpdateFiberPath",
		"A3UE_FPV_kvnNativeSyncPath", "A3UE_FPV_kvnNativeReceivePath", "kvn_showFiber", "A3UE_fnc_fpv_sendLifecycle"
	];
	private _saved = _names apply {[_x, !isNil {missionNamespace getVariable _x}, missionNamespace getVariable [_x, {}]]};
	private _failures = 0;
	private _check = {
		params ["_name", "_ok"];
		if (!_ok) then {_failures = _failures + 1;};
		diag_log format ["[A3UE FPV TEST F04] STRUCTURAL case=%1 pass=%2", _name, _ok];
	};
	missionNamespace setVariable ["A3UE_FPV_kvnPathAdapterInstalled", false];
	missionNamespace setVariable ["DB_kvn_fnc_fpv_syncPath", nil];
	["absent vendor", !(call A3UE_fnc_fpv_installKvnPathAdapter)] call _check;
	DB_kvn_fnc_fpv_updateFiberPath = {
		params ["_pl", "_uav"];
		_uav setVariable ["QA_F04_nativeUpdate", _this];
		17
	};
	DB_kvn_fnc_fpv_syncPath = {
		params ["_uav", "_path"];
		_uav setVariable ["QA_F04_nativeSync", _this];
		18
	};
	DB_kvn_fnc_fpv_receivePath = {
		params ["_uav", "_path"];
		_uav setVariable ["kvn_fiber_path", _path];
		19
	};
	["install", call A3UE_fnc_fpv_installKvnPathAdapter] call _check;
	private _captured = missionNamespace getVariable "A3UE_FPV_kvnNativeUpdateFiberPath";
	private _wrapper = DB_kvn_fnc_fpv_updateFiberPath;
	private _again = call A3UE_fnc_fpv_installKvnPathAdapter;
	["idempotent capture", _again && {_captured isEqualTo (missionNamespace getVariable "A3UE_FPV_kvnNativeUpdateFiberPath")} && {_wrapper isEqualTo DB_kvn_fnc_fpv_updateFiberPath}] call _check;
	private _uav = createVehicle ["Land_HelipadEmpty_F", [50, 50, 0], [], 0, "CAN_COLLIDE"];
	private _path = [[50, 50, 0], [52, 50, 0]];
	_uav setVariable ["A3UE_FPV_managed", true];
	_uav setVariable ["A3UE_FPV_vendorId", "kvn"];
	_uav setVariable ["kvn_fiber_path", +_path];
	private _update = [objNull, _uav] call DB_kvn_fnc_fpv_updateFiberPath;
	private _sync = [_uav, []] call DB_kvn_fnc_fpv_syncPath;
	private _receive = [_uav, []] call DB_kvn_fnc_fpv_receivePath;
	["managed writers and stale receive suppressed", _update isEqualTo false && {_sync isEqualTo false} && {_receive isEqualTo false}
		&& {isNil {_uav getVariable "QA_F04_nativeUpdate"}} && {isNil {_uav getVariable "QA_F04_nativeSync"}}
		&& {(_uav getVariable "kvn_fiber_path") isEqualTo _path}] call _check;
	_uav setVariable ["A3UE_FPV_managed", false];
	_update = [objNull, _uav] call DB_kvn_fnc_fpv_updateFiberPath;
	_sync = [_uav, _path] call DB_kvn_fnc_fpv_syncPath;
	_receive = [_uav, []] call DB_kvn_fnc_fpv_receivePath;
	["unmanaged arguments and returns preserved", _update isEqualTo 17 && {_sync isEqualTo 18} && {_receive isEqualTo 19}
		&& {(_uav getVariable "QA_F04_nativeUpdate") isEqualTo [objNull, _uav]}
		&& {(_uav getVariable "QA_F04_nativeSync") isEqualTo [_uav, _path]} && {(_uav getVariable "kvn_fiber_path") isEqualTo []}] call _check;
	_uav setVariable ["A3UE_FPV_managed", true];
	_uav setVariable ["A3UE_FPV_vendorId", "fpv_ua"];
	["other family passes through", ([objNull, _uav] call DB_kvn_fnc_fpv_updateFiberPath) isEqualTo 17] call _check;
	_uav setVariable ["A3UE_FPV_vendorId", "kvn"];
	_uav setVariable ["kvn_lastSync", time + 1000000];
	_uav setVariable ["A3UE_FPV_fiberLastSync", time - 1];
	missionNamespace setVariable ["kvn_showFiber", true];
	private _sent = [];
    A3UE_fnc_fpv_sendLifecycle = {_sent = +_this; true}; // Publisher shape, no RPC proof.
    private _result = [_uav] call A3UE_fnc_fpv_updateFiberTrailCompat;
	["native timer cannot suppress managed publication", _result && {(_uav getVariable "A3UE_FPV_fiberLastSync") == time} && {(_uav getVariable "kvn_lastSync") == time + 1000000}] call _check;
	_uav setVariable ["A3UE_FPV_controllerGeneration", 3];
    private _curve = [[50,50,0],[55,50,0],[55,55,0]];
    [_uav, _curve, 3] call A3UE_fnc_fpv_adoptFiberPath;
    ["claim history length/count", (_uav getVariable "kvn_fiber_path") isEqualTo _curve && {(_uav getVariable "kvn_fiber_length") == 10} && {(_uav getVariable "kvn_fiber_length_count") == 3}] call _check;
    _uav setVariable ["kvn_fiber_path", [[0,0,0]]]; // A delayed public echo.
    [_uav] call A3UE_fnc_fpv_updateFiberTrailCompat;
    ["public echo cannot erase local accepted bends", ((_uav getVariable "kvn_fiber_path") select [0,3]) isEqualTo _curve] call _check;
    kvn_showFiber = false; [_uav] call A3UE_fnc_fpv_updateFiberTrailCompat;
    ["intentional hide clears both paths and publishes once", (_uav getVariable "kvn_fiber_path") isEqualTo [] && {(_uav getVariable "A3UE_FPV_fiberLocalPath") isEqualTo []} && {_sent isEqualTo [_uav, "fiber", [[]]]}] call _check;
    _uav setVariable ["A3UE_FPV_managed", false];
	["unmanaged addon updater rejected", !([_uav] call A3UE_fnc_fpv_updateFiberTrailCompat)] call _check;
	deleteVehicle _uav;
	{
		_x params ["_name", "_existed", "_value"];
		missionNamespace setVariable [_name, if (_existed) then {_value} else {nil}];
	} forEach _saved;
	diag_log format ["[A3UE FPV TEST F04] STRUCTURAL complete=11 failures=%1 (not JIP/vendor evidence)", _failures];
};
true
