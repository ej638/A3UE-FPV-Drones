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
			_vehicle setVariable ["A3UE_FPV_terminalVectorLastUpdateAt", -1];
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

private _impactProfile = [_uav] call A3UE_fnc_fpv_getProfile;
private _defaultImpactMode = _impactProfile getOrDefault ["terminalImpactMode", "NONE"];
if !(_defaultImpactMode isEqualType "") then {
	_defaultImpactMode = "NONE";
};

_uav setVariable ["A3UE_FPV_cachedLinkState", _uav getVariable ["A3UE_FPV_linkState", "OK"], true];
_uav setVariable ["A3UE_FPV_cachedSignalStrength", _uav getVariable ["A3UE_FPV_signalStrength", 1], true];
_uav setVariable ["A3UE_FPV_nextLinkEvalAt", 0];
_uav setVariable ["A3UE_FPV_lastLinkEvalPosATL", getPosATL _uav];
_uav setVariable ["A3UE_FPV_terminalSteeringActive", false, true];

private _vectorModeActive = (_uav getVariable ["A3UE_FPV_mode", "IDLE"]) isEqualTo "TERMINAL_VECTOR";
private _vectorSpeedSeed = if (_vectorModeActive) then {
	(vectorMagnitude (velocity _uav)) * 3.6
} else {
	-1
};

_uav setVariable ["A3UE_FPV_terminalVectorEnteredAt", _uav getVariable ["A3UE_FPV_terminalVectorEnteredAt", -1], true];
_uav setVariable ["A3UE_FPV_terminalVectorEntrySpeed", _uav getVariable ["A3UE_FPV_terminalVectorEntrySpeed", _vectorSpeedSeed], true];
_uav setVariable ["A3UE_FPV_terminalVectorEntryDistance", _uav getVariable ["A3UE_FPV_terminalVectorEntryDistance", -1], true];
_uav setVariable ["A3UE_FPV_terminalVectorCurrentSpeed", _uav getVariable ["A3UE_FPV_terminalVectorCurrentSpeed", _vectorSpeedSeed], true];
_uav setVariable ["A3UE_FPV_terminalVectorTargetSpeed", _uav getVariable ["A3UE_FPV_terminalVectorTargetSpeed", _vectorSpeedSeed], true];
_uav setVariable ["A3UE_FPV_terminalVectorAccelApplied", _uav getVariable ["A3UE_FPV_terminalVectorAccelApplied", -1], true];
_uav setVariable ["A3UE_FPV_terminalVectorAlignment", _uav getVariable ["A3UE_FPV_terminalVectorAlignment", -1], true];
_uav setVariable ["A3UE_FPV_terminalVectorDt", _uav getVariable ["A3UE_FPV_terminalVectorDt", (if (_vectorModeActive) then {0.01} else {-1})], true];
_uav setVariable ["A3UE_FPV_terminalVectorSpeedJump", _uav getVariable ["A3UE_FPV_terminalVectorSpeedJump", -1], true];
_uav setVariable ["A3UE_FPV_terminalVectorLastUpdateAt", _uav getVariable ["A3UE_FPV_terminalVectorLastUpdateAt", -1]];
_uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", _uav getVariable ["A3UE_FPV_lastTerminalVectorDistance", -1]];
_uav setVariable ["A3UE_FPV_terminalImpactMode", _uav getVariable ["A3UE_FPV_terminalImpactMode", _defaultImpactMode], true];
_uav setVariable ["A3UE_FPV_lastImpactValid", _uav getVariable ["A3UE_FPV_lastImpactValid", false], true];
_uav setVariable ["A3UE_FPV_lastImpactPointASL", _uav getVariable ["A3UE_FPV_lastImpactPointASL", []], true];
_uav setVariable ["A3UE_FPV_lastImpactSurfaceType", _uav getVariable ["A3UE_FPV_lastImpactSurfaceType", "none"], true];
_uav setVariable ["A3UE_FPV_lastImpactSurfaceObjectNetId", _uav getVariable ["A3UE_FPV_lastImpactSurfaceObjectNetId", ""], true];
_uav setVariable ["A3UE_FPV_lastImpactTargetNetId", _uav getVariable ["A3UE_FPV_lastImpactTargetNetId", ""], true];
_uav setVariable ["A3UE_FPV_lastImpactReason", _uav getVariable ["A3UE_FPV_lastImpactReason", "NONE"], true];
_uav setVariable ["A3UE_FPV_lastImpactFallbackAllowed", _uav getVariable ["A3UE_FPV_lastImpactFallbackAllowed", true], true];
_uav setVariable ["A3UE_FPV_lastImpactFallbackRadius", _uav getVariable ["A3UE_FPV_lastImpactFallbackRadius", 0], true];
_uav setVariable ["A3UE_FPV_lastImpactEvalPosASL", _uav getVariable ["A3UE_FPV_lastImpactEvalPosASL", []], true];
_uav setVariable ["A3UE_FPV_lastImpactTargetPosASL", _uav getVariable ["A3UE_FPV_lastImpactTargetPosASL", []], true];
_uav setVariable ["A3UE_FPV_lastClosingDot", _uav getVariable ["A3UE_FPV_lastClosingDot", -2], true];
_uav setVariable ["A3UE_FPV_lastTimeToContact", _uav getVariable ["A3UE_FPV_lastTimeToContact", -1], true];
_uav setVariable ["A3UE_FPV_lastDetonationReason", _uav getVariable ["A3UE_FPV_lastDetonationReason", "NONE"], true];
_uav setVariable ["A3UE_FPV_lastFallbackReason", _uav getVariable ["A3UE_FPV_lastFallbackReason", "NONE"], true];
_uav setVariable ["A3UE_FPV_lastImpactTelemetryAt", _uav getVariable ["A3UE_FPV_lastImpactTelemetryAt", -1], true];

_uav setVariable ["A3UE_FPV_controllerRunning", true];
_uav setVariable ["A3UE_FPV_controllerOwnerId", owner _uav, true];

[_uav] spawn A3UE_fnc_fpv_runController;

true