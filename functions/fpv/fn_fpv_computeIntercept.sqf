params [["_uav", objNull], ["_target", objNull], ["_profile", createHashMap], ["_isTerminal", false]];

if (isNull _uav || {isNull _target}) exitWith {[]};

private _uavPos = getPosASL _uav;
private _uavVel = velocity _uav;
private _targetPos = getPosASL _target;
private _targetVel = velocity _target;
private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];
private _impactMode = "NONE";
private _impactSurfaceType = "target";
private _impactPointAsl = _uav getVariable ["A3UE_FPV_lastImpactPointASL", []];
private _hasTerminalImpact = _isTerminal && {
	(_uav getVariable ["A3UE_FPV_lastImpactValid", false]) && {
		(_uav getVariable ["A3UE_FPV_lastImpactTargetNetId", ""]) == netId _target && {
			_impactPointAsl isEqualType [] && {
				count _impactPointAsl >= 3
			}
		}
	}
};

if (_hasTerminalImpact) then {
	_impactMode = _uav getVariable ["A3UE_FPV_terminalImpactMode", "NONE"];
	_impactSurfaceType = _uav getVariable ["A3UE_FPV_lastImpactSurfaceType", "target"];
	_targetPos = +_impactPointAsl;

	if (_impactSurfaceType in ["ground", "obstruction", "static"] || {_impactMode in ["GROUND_NEAR_TARGET", "OBSTRUCTION_SURFACE", "DIRECT_STATIC"]}) then {
		_targetVel = [0, 0, 0];
	};
};

private _distance = _uavPos vectorDistance _targetPos;

private _defaultTrackingSpeed = switch (_payloadRole) do {
	case "AT": { 95 };
	case "RECON": { 85 };
	default { 90 };
};

private _defaultTerminalSpeed = switch (_payloadRole) do {
	case "AT": { 110 };
	case "RECON": { 95 };
	default { 100 };
};

private _speedKey = ["trackingSpeed", "terminalSpeed"] select _isTerminal;
private _speedDefault = [_defaultTrackingSpeed, _defaultTerminalSpeed] select _isTerminal;
private _chaseSpeed = [_profile, _speedKey, _speedDefault] call A3UE_fnc_fpv_profileValue;
if (!(_chaseSpeed isEqualType 0) || {_chaseSpeed <= 0}) then {
	_chaseSpeed = _speedDefault;
};

private _relPos = _targetPos vectorDiff _uavPos;
private _relVel = _targetVel vectorDiff _uavVel;

private _a = (_relVel vectorDotProduct _relVel) - (_chaseSpeed * _chaseSpeed);
private _b = 2 * (_relPos vectorDotProduct _relVel);
private _c = _relPos vectorDotProduct _relPos;

private _timeToImpact = 0;

if (abs _a < 0.001) then {
	if (abs _b > 0.001) then {
		_timeToImpact = (-_c / _b) max 0;
	};
} else {
	private _disc = (_b * _b) - (4 * _a * _c);
	if (_disc >= 0) then {
		private _root = sqrt _disc;
		private _t1 = (-_b - _root) / (2 * _a);
		private _t2 = (-_b + _root) / (2 * _a);
		private _valid = [_t1, _t2] select { _x > 0 };

		if (_valid isNotEqualTo []) then {
			_timeToImpact = selectMin _valid;
		};
	};
};

if (_timeToImpact <= 0) then {
	_timeToImpact = ((vectorMagnitude _relPos) / _chaseSpeed) max 0.1;
};

private _nearLeadDistance = [_profile, "nearLeadDistance", 60] call A3UE_fnc_fpv_profileValue;
if (!(_nearLeadDistance isEqualType 0) || {_nearLeadDistance < 0}) then {
	_nearLeadDistance = 60;
};

private _maxLeadDistance = [_profile, "maxLeadDistance", 550] call A3UE_fnc_fpv_profileValue;
if (!(_maxLeadDistance isEqualType 0) || {_maxLeadDistance <= _nearLeadDistance}) then {
	_maxLeadDistance = (_nearLeadDistance + 490) max 550;
};

private _maxLeadTimeNear = [_profile, "maxLeadTimeNear", 0.25] call A3UE_fnc_fpv_profileValue;
if (!(_maxLeadTimeNear isEqualType 0) || {_maxLeadTimeNear <= 0}) then {
	_maxLeadTimeNear = 0.25;
};

private _maxLeadTimeFar = [_profile, "maxLeadTimeFar", 2.4] call A3UE_fnc_fpv_profileValue;
if (!(_maxLeadTimeFar isEqualType 0) || {_maxLeadTimeFar <= _maxLeadTimeNear}) then {
	_maxLeadTimeFar = _maxLeadTimeNear + 1.5;
};

private _adaptiveLeadCap = linearConversion [_nearLeadDistance, _maxLeadDistance, _distance, _maxLeadTimeNear, _maxLeadTimeFar, true];
_timeToImpact = _timeToImpact min _adaptiveLeadCap;

private _intercept = _targetPos vectorAdd (_targetVel vectorMultiply _timeToImpact);

if (_isTerminal) then {
	if (_impactMode != "AIR_PROXIMITY") then {
		private _terminalGateDistance = [_profile, "terminalGateDistance", 90] call A3UE_fnc_fpv_profileValue;
		private _impactOffsetFar = [_profile, "terminalImpactOffsetFar", (_profile getOrDefault ["attackHeightASL", 8])] call A3UE_fnc_fpv_profileValue;
		private _impactOffsetNear = [_profile, "terminalImpactOffsetNear", 0] call A3UE_fnc_fpv_profileValue;

		if (!(_terminalGateDistance isEqualType 0) || {_terminalGateDistance <= 0}) then {
			_terminalGateDistance = 90;
		};

		if (!(_impactOffsetFar isEqualType 0) || {_impactOffsetFar < 0}) then {
			_impactOffsetFar = _profile getOrDefault ["attackHeightASL", 8];
		};

		if (!(_impactOffsetNear isEqualType 0) || {_impactOffsetNear < 0}) then {
			_impactOffsetNear = 0;
		};

		_impactOffsetNear = _impactOffsetNear min _impactOffsetFar;

		private _impactOffset = linearConversion [_terminalGateDistance, 0, _distance, _impactOffsetFar, _impactOffsetNear, true];
		_intercept set [2, (_targetPos select 2) + _impactOffset];
	};
} else {
	private _heightOffset = [_profile, "attackHeightASL", 12] call A3UE_fnc_fpv_profileValue;
	if (!(_heightOffset isEqualType 0)) then {
		_heightOffset = 12;
	};

	_intercept set [2, ((_targetPos select 2) + _heightOffset) max (_intercept select 2)];
};

_uav setVariable ["A3UE_FPV_lastLeadTime", _timeToImpact, true];

_intercept