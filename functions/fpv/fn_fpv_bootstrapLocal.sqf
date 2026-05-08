params [["_uav", objNull]];

if (isNull _uav) exitWith {false};
if !(_uav getVariable ["A3UE_FPV_managed", false]) exitWith {false};

private _localityEhId = _uav getVariable ["A3UE_FPV_localityEH", -1];
if (_localityEhId < 0) then {
	_localityEhId = _uav addEventHandler ["Local", {
		params ["_vehicle", "_isLocal"];

		if !(_vehicle getVariable ["A3UE_FPV_managed", false]) exitWith {};

		if (_isLocal) then {
			[_vehicle] spawn A3UE_fnc_fpv_bootstrapLocal;
		} else {
			_vehicle setVariable ["A3UE_FPV_controllerRunning", false];
			_vehicle setVariable ["A3UE_FPV_controllerOwnerId", -1, true];
			_vehicle setVariable ["A3UE_FPV_fiberTrailRunning", false];
			_vehicle setVariable ["A3UE_FPV_terminalSteeringActive", false, true];
		};
	}];

	_uav setVariable ["A3UE_FPV_localityEH", _localityEhId];
};

private _deletedEhId = _uav getVariable ["A3UE_FPV_deletedEH", -1];
if (_deletedEhId < 0) then {
	_deletedEhId = _uav addEventHandler ["Deleted", {
		params ["_vehicle"];

		[objNull, _vehicle getVariable ["A3UE_FPV_netId", netId _vehicle], "deleted"] remoteExecCall ["A3UE_fnc_fpv_unregisterDrone", 2];
	}];

	_uav setVariable ["A3UE_FPV_deletedEH", _deletedEhId];
};

private _mpKilledEhId = _uav getVariable ["A3UE_FPV_mpKilledEH", -1];
if (_mpKilledEhId < 0) then {
	_mpKilledEhId = _uav addMPEventHandler ["MPKilled", {
		params ["_vehicle"];

		[objNull, _vehicle getVariable ["A3UE_FPV_netId", netId _vehicle], "mpkilled"] remoteExecCall ["A3UE_fnc_fpv_unregisterDrone", 2];
	}];

	_uav setVariable ["A3UE_FPV_mpKilledEH", _mpKilledEhId];
};

if (!local _uav) exitWith {false};

if (_uav getVariable ["A3UE_FPV_controllerRunning", false]) exitWith {
	if ((_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) isEqualTo "FIBER_VISUAL") then {
		[_uav] call A3UE_fnc_fpv_startFiberTrailCompat;
	};

	true
};

[_uav] call A3UE_fnc_fpv_applyCompatInit;

if ((_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) isEqualTo "FIBER_VISUAL") then {
	[_uav] call A3UE_fnc_fpv_startFiberTrailCompat;
};

if ((_uav getVariable ["A3UE_FPV_mode", ""]) isEqualTo "") then {
	_uav setVariable ["A3UE_FPV_mode", "IDLE", true];
};

if !((_uav getVariable ["A3UE_FPV_mode", "IDLE"]) in ["IDLE", "SEARCHING", "TRACKING", "LOST_TARGET", "TERMINAL_ATTACK", "TERMINAL_VECTOR"]) then {
	_uav setVariable ["A3UE_FPV_mode", "IDLE", true];
};

_uav setVariable ["A3UE_FPV_cachedLinkState", _uav getVariable ["A3UE_FPV_linkState", "OK"], true];
_uav setVariable ["A3UE_FPV_cachedSignalStrength", _uav getVariable ["A3UE_FPV_signalStrength", 1], true];
_uav setVariable ["A3UE_FPV_nextLinkEvalAt", 0];
_uav setVariable ["A3UE_FPV_lastLinkEvalPosATL", getPosATL _uav];
_uav setVariable ["A3UE_FPV_terminalSteeringActive", false, true];

_uav setVariable ["A3UE_FPV_controllerRunning", true];
_uav setVariable ["A3UE_FPV_controllerOwnerId", owner _uav, true];

[_uav] spawn A3UE_fnc_fpv_runController;

true