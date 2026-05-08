params [["_uav", objNull], ["_target", objNull], ["_profile", createHashMap]];

private _result = createHashMapFromArray [
	["approved", false],
	["detonationReason", "NONE"],
	["fallbackReason", "NONE"],
	["closingDot", -2],
	["timeToContact", -1],
	["impactDistance", -1],
	["impactDistance2D", -1],
	["heightAboveImpact", 0],
	["altitudeAGL", -1],
	["impactMode", "NONE"],
	["surfaceType", "none"],
	["impactPointASL", []],
	["impactValid", false]
];

if (isNull _uav || {isNull _target} || {!alive _target}) exitWith {_result};

private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];
private _defaultDistance = switch (_payloadRole) do {
	case "AT": { 18 };
	case "RECON": { 12 };
	default { 14 };
};

private _defaultDistance2D = switch (_payloadRole) do {
	case "AT": { 9 };
	case "RECON": { 6 };
	default { 7 };
};

private _detonationDistance = [_profile, "detonationDistance", _defaultDistance] call A3UE_fnc_fpv_profileValue;
private _detonationDistance2D = [_profile, "detonationDistance2D", _defaultDistance2D] call A3UE_fnc_fpv_profileValue;
private _verticalWindow = [_profile, "detonationVerticalWindow", 12] call A3UE_fnc_fpv_profileValue;
private _maxTimeToContact = [_profile, "detonationMaxTimeToContact", 0.25] call A3UE_fnc_fpv_profileValue;
private _minClosingDot = [_profile, "detonationMinClosingDot", 0.75] call A3UE_fnc_fpv_profileValue;
private _maxAltitudeAGL = [_profile, "detonationMaxAltitudeAGL", _verticalWindow] call A3UE_fnc_fpv_profileValue;
private _impactFallbackRadius = [_profile, "impactFallbackRadius", 0] call A3UE_fnc_fpv_profileValue;

if (!(_detonationDistance isEqualType 0) || {_detonationDistance <= 0}) then {
	_detonationDistance = _defaultDistance;
};

if (!(_detonationDistance2D isEqualType 0) || {_detonationDistance2D <= 0}) then {
	_detonationDistance2D = _defaultDistance2D;
};

if (!(_verticalWindow isEqualType 0) || {_verticalWindow < 0}) then {
	_verticalWindow = 12;
};

if (!(_maxTimeToContact isEqualType 0) || {_maxTimeToContact <= 0}) then {
	_maxTimeToContact = 0.25;
};

if (!(_minClosingDot isEqualType 0)) then {
	_minClosingDot = 0.75;
};

if (!(_maxAltitudeAGL isEqualType 0) || {_maxAltitudeAGL < 0}) then {
	_maxAltitudeAGL = _verticalWindow;
};

if (!(_impactFallbackRadius isEqualType 0) || {_impactFallbackRadius < 0}) then {
	_impactFallbackRadius = 0;
};

private _uavPosAsl = getPosASL _uav;
private _targetPosAsl = getPosASL _target;
private _targetDistance = _uavPosAsl vectorDistance _targetPosAsl;
private _targetDistance2D = _uav distance2D _target;
private _targetHeightDelta = abs ((_uavPosAsl select 2) - (_targetPosAsl select 2));
private _impactMode = "NONE";
private _surfaceType = "target";
private _impactPointAsl = +_targetPosAsl;
private _impactValid = false;
private _fallbackAllowed = true;

if ((_uav getVariable ["A3UE_FPV_lastImpactValid", false]) && {(_uav getVariable ["A3UE_FPV_lastImpactTargetNetId", ""]) == netId _target}) then {
	private _cachedImpactPoint = _uav getVariable ["A3UE_FPV_lastImpactPointASL", []];
	if (_cachedImpactPoint isEqualType [] && {count _cachedImpactPoint >= 3}) then {
		_impactValid = true;
		_impactMode = _uav getVariable ["A3UE_FPV_terminalImpactMode", "NONE"];
		_surfaceType = _uav getVariable ["A3UE_FPV_lastImpactSurfaceType", "target"];
		_impactPointAsl = +_cachedImpactPoint;
		_fallbackAllowed = _uav getVariable ["A3UE_FPV_lastImpactFallbackAllowed", true];
	};
};

private _impactVector = _impactPointAsl vectorDiff _uavPosAsl;
private _impactDistance = vectorMagnitude _impactVector;
private _impactDistance2D = vectorMagnitude [_impactVector select 0, _impactVector select 1, 0];
private _currentVelocity = velocity _uav;
private _speedMps = vectorMagnitude _currentVelocity;
private _closingDot = -2;
private _speedTowardImpact = 0;

if (_speedMps > 0.1 && {_impactDistance > 0.1}) then {
	private _normalizedImpactVector = _impactVector vectorMultiply (1 / _impactDistance);
	_closingDot = ((_currentVelocity vectorDotProduct _normalizedImpactVector) / _speedMps) max -1 min 1;
	_speedTowardImpact = (_currentVelocity vectorDotProduct _normalizedImpactVector) max 0;
};

private _timeToContact = if (_speedTowardImpact > 0.1) then {
	_impactDistance / _speedTowardImpact
} else {
	-1
};

private _heightAboveImpact = (_uavPosAsl select 2) - (_impactPointAsl select 2);
private _impactHeightDelta = abs _heightAboveImpact;
private _altitudeAGL = ((_uavPosAsl select 2) - (getTerrainHeightASL [_uavPosAsl select 0, _uavPosAsl select 1])) max 0;
private _legacyEnvelope = (_targetDistance <= _detonationDistance) || {(_targetDistance2D <= _detonationDistance2D) && {_targetHeightDelta <= _verticalWindow}};
private _impactEnvelope = (_impactDistance <= _detonationDistance) || {(_impactDistance2D <= _detonationDistance2D) && {_impactHeightDelta <= _verticalWindow}};
private _contactDistance = ((_detonationDistance2D min 1.5) max 0.75);
private _mode = _uav getVariable ["A3UE_FPV_mode", ""];
private _overshootImminent = (_mode == "TERMINAL_VECTOR") && {_closingDot < 0} && {_impactDistance <= (_detonationDistance + (_impactFallbackRadius max 1))};
private _guidanceDegraded = (_mode in ["TERMINAL_ATTACK", "TERMINAL_VECTOR"]) && {_speedMps < 4} && {_impactDistance <= (_detonationDistance2D max 1.5)};
private _collapsedWindow = (_mode == "TERMINAL_VECTOR") && {_impactEnvelope} && {_closingDot >= 0} && {_closingDot < _minClosingDot} && {_impactDistance <= (_detonationDistance2D max 1.5)};
private _detonationReason = "NONE";
private _fallbackReason = "NONE";
private _approved = false;

if (_impactDistance <= _contactDistance) then {
	_approved = true;
	_detonationReason = "DIRECT_CONTACT";
} else {
	if (_impactMode == "AIR_PROXIMITY" && {_legacyEnvelope}) then {
		_approved = true;
		_detonationReason = "PROXIMITY_FAILSAFE";
		_fallbackReason = "AIR_TARGET_PROXIMITY_POLICY";
	} else {
		if (_timeToContact > 0 && {_timeToContact <= _maxTimeToContact} && {_closingDot >= _minClosingDot} && {_altitudeAGL <= _maxAltitudeAGL}) then {
			_approved = true;
			_detonationReason = "PREDICTED_IMPACT";
		} else {
			if (_impactEnvelope && {_closingDot >= _minClosingDot} && {_altitudeAGL <= _maxAltitudeAGL} && {_impactHeightDelta <= (_verticalWindow max _maxAltitudeAGL)}) then {
				_approved = true;
				_detonationReason = "CLOSURE_QUALIFIED";
			} else {
				if (_fallbackAllowed) then {
					switch (true) do {
						case (_impactMode == "OBSTRUCTION_SURFACE" && {_impactEnvelope}): {
							_approved = true;
							_detonationReason = "OBSTRUCTION_FALLBACK";
							_fallbackReason = "TARGET_DUCKED_BEHIND_OBSTRUCTION";
						};

						case (_overshootImminent): {
							_approved = true;
							_detonationReason = "MISSED_PASS_FALLBACK";
							_fallbackReason = "OVERSHOOT_IMMINENT";
						};

						case (_guidanceDegraded && {_legacyEnvelope}): {
							_approved = true;
							_detonationReason = "PROXIMITY_FAILSAFE";
							_fallbackReason = "GUIDANCE_QUALITY_DEGRADED";
						};

						case (_collapsedWindow): {
							_approved = true;
							_detonationReason = "PROXIMITY_FAILSAFE";
							_fallbackReason = "IMPACT_WINDOW_COLLAPSED";
						};

						case (!_impactValid && {_legacyEnvelope}): {
							_approved = true;
							_detonationReason = "PROXIMITY_FAILSAFE";
							_fallbackReason = "NO_VALID_IMPACT_POINT";
						};
					};
				};
			};
		};
	};
};

_result set ["approved", _approved];
_result set ["detonationReason", _detonationReason];
_result set ["fallbackReason", _fallbackReason];
_result set ["closingDot", _closingDot];
_result set ["timeToContact", _timeToContact];
_result set ["impactDistance", _impactDistance];
_result set ["impactDistance2D", _impactDistance2D];
_result set ["heightAboveImpact", _heightAboveImpact];
_result set ["altitudeAGL", _altitudeAGL];
_result set ["impactMode", _impactMode];
_result set ["surfaceType", _surfaceType];
_result set ["impactPointASL", _impactPointAsl];
_result set ["impactValid", _impactValid];

_result