// Unmanaged calls delegate to captured vendor code; managed paths use only the owner loop.
if (missionNamespace getVariable ["A3UE_FPV_kvnPathAdapterInstalled", false]) exitWith {true};
if (isNil "DB_kvn_fnc_fpv_updateFiberPath" || {isNil "DB_kvn_fnc_fpv_syncPath"} || {isNil "DB_kvn_fnc_fpv_receivePath"}) exitWith {false};

private _installed = false;
isNil {
	if (missionNamespace getVariable ["A3UE_FPV_kvnPathAdapterInstalled", false]) exitWith {_installed = true;};
	private _nativeUpdate = DB_kvn_fnc_fpv_updateFiberPath;
	private _nativeSync = DB_kvn_fnc_fpv_syncPath;
	private _nativeReceive = DB_kvn_fnc_fpv_receivePath;
	if !(_nativeUpdate isEqualType {} && {_nativeSync isEqualType {}} && {_nativeReceive isEqualType {}}) exitWith {};

	missionNamespace setVariable ["A3UE_FPV_kvnNativeUpdateFiberPath", _nativeUpdate];
	missionNamespace setVariable ["A3UE_FPV_kvnNativeSyncPath", _nativeSync];
	missionNamespace setVariable ["A3UE_FPV_kvnNativeReceivePath", _nativeReceive];

	DB_kvn_fnc_fpv_updateFiberPath = {
		params ["_pl", "_uav"];
		if (_uav getVariable ["A3UE_FPV_managed", false] && {(_uav getVariable ["A3UE_FPV_vendorId", ""]) isEqualTo "kvn"}) exitWith {false};
		_this call (missionNamespace getVariable "A3UE_FPV_kvnNativeUpdateFiberPath")
	};
	DB_kvn_fnc_fpv_syncPath = {
		params ["_uav", "_path"];
		if (_uav getVariable ["A3UE_FPV_managed", false] && {(_uav getVariable ["A3UE_FPV_vendorId", ""]) isEqualTo "kvn"}) exitWith {false};
		_this call (missionNamespace getVariable "A3UE_FPV_kvnNativeSyncPath")
	};
	DB_kvn_fnc_fpv_receivePath = {
		params ["_uav", "_path"];
		// Ignore queued native snapshots as well as current native writers on managed UAVs.
		if (_uav getVariable ["A3UE_FPV_managed", false] && {(_uav getVariable ["A3UE_FPV_vendorId", ""]) isEqualTo "kvn"}) exitWith {false};
		_this call (missionNamespace getVariable "A3UE_FPV_kvnNativeReceivePath")
	};
	missionNamespace setVariable ["A3UE_FPV_kvnPathAdapterInstalled", true];
	_installed = true;
};

_installed
