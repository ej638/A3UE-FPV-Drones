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
private _terminalImpactHoldoffDistance = [_profile, "terminalImpactHoldoffDistance", (_detonationDistance + 2)] call A3UE_fnc_fpv_profileValue;
private _fallbackSurfaceHoldoffDistance = [_profile, "fallbackSurfaceHoldoffDistance", _terminalImpactHoldoffDistance] call A3UE_fnc_fpv_profileValue;
private _directContactDistanceBody = [_profile, "directContactDistanceBody", 1.0] call A3UE_fnc_fpv_profileValue;
private _directContactDistanceHull = [_profile, "directContactDistanceHull", 1.4] call A3UE_fnc_fpv_profileValue;
private _predictedImpactMaxTimeToContactBody = [_profile, "predictedImpactMaxTimeToContactBody", (_maxTimeToContact * 0.45)] call A3UE_fnc_fpv_profileValue;
private _predictedImpactMaxTimeToContactHull = [_profile, "predictedImpactMaxTimeToContactHull", (_maxTimeToContact * 0.65)] call A3UE_fnc_fpv_profileValue;
private _directHitClosureQualifiedAllowed = [_profile, "directHitClosureQualifiedAllowed", false] call A3UE_fnc_fpv_profileValue;

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

if (!(_terminalImpactHoldoffDistance isEqualType 0) || {_terminalImpactHoldoffDistance < 0}) then {
	_terminalImpactHoldoffDistance = _detonationDistance + 2;
};

if (!(_fallbackSurfaceHoldoffDistance isEqualType 0) || {_fallbackSurfaceHoldoffDistance < 0}) then {
	_fallbackSurfaceHoldoffDistance = _terminalImpactHoldoffDistance;
};

if (!(_directContactDistanceBody isEqualType 0) || {_directContactDistanceBody <= 0}) then {
	_directContactDistanceBody = 1.0;
};

if (!(_directContactDistanceHull isEqualType 0) || {_directContactDistanceHull <= 0}) then {
	_directContactDistanceHull = 1.4;
};

if (!(_predictedImpactMaxTimeToContactBody isEqualType 0) || {_predictedImpactMaxTimeToContactBody <= 0}) then {
	_predictedImpactMaxTimeToContactBody = _maxTimeToContact * 0.45;
};

if (!(_predictedImpactMaxTimeToContactHull isEqualType 0) || {_predictedImpactMaxTimeToContactHull <= 0}) then {
	_predictedImpactMaxTimeToContactHull = _maxTimeToContact * 0.65;
};

if !(_directHitClosureQualifiedAllowed isEqualType true) then {
	_directHitClosureQualifiedAllowed = false;
};

_directContactDistanceHull = _directContactDistanceHull max _directContactDistanceBody;
_terminalImpactHoldoffDistance = _terminalImpactHoldoffDistance max _directContactDistanceHull;
private _fallbackSurfaceHoldoffMax = ((_detonationDistance + (_impactFallbackRadius max 2) + 2) max _terminalImpactHoldoffDistance);
_fallbackSurfaceHoldoffDistance = ((_fallbackSurfaceHoldoffDistance max _terminalImpactHoldoffDistance) min _fallbackSurfaceHoldoffMax);
_predictedImpactMaxTimeToContactBody = (_predictedImpactMaxTimeToContactBody max 0.02) min _maxTimeToContact;
_predictedImpactMaxTimeToContactHull = (_predictedImpactMaxTimeToContactHull max _predictedImpactMaxTimeToContactBody) min _maxTimeToContact;

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
private _mode = _uav getVariable ["A3UE_FPV_mode", ""];
private _overshootImminent = (_mode == "TERMINAL_VECTOR") && {_closingDot < 0} && {_impactDistance <= (_detonationDistance + (_impactFallbackRadius max 1))};
private _guidanceDegraded = (_mode in ["TERMINAL_ATTACK", "TERMINAL_VECTOR"]) && {_speedMps < 4} && {_impactDistance <= (_detonationDistance2D max 1.5)};
private _collapsedWindow = (_mode == "TERMINAL_VECTOR") && {_impactEnvelope} && {_closingDot >= 0} && {_closingDot < _minClosingDot} && {_impactDistance <= (_detonationDistance2D max 1.5)};
private _directHitModes = ["DIRECT_BODY", "DIRECT_HULL", "DIRECT_STATIC"];
private _fallbackSurfaceModes = ["GROUND_NEAR_TARGET", "OBSTRUCTION_SURFACE"];
private _isDirectHitMode = _impactMode in _directHitModes;
private _isFallbackSurfaceMode = _impactMode in _fallbackSurfaceModes;
private _isAirPolicyMode = _impactMode == "AIR_PROXIMITY";
private _directContactDistance = switch (_impactMode) do {
	case "DIRECT_BODY": { _directContactDistanceBody };
	default { _directContactDistanceHull };
};
private _predictedImpactWindow = switch (_impactMode) do {
	case "DIRECT_BODY": { _predictedImpactMaxTimeToContactBody };
	default { _predictedImpactMaxTimeToContactHull };
};
private _nonContactHoldoffDistance = if (_isFallbackSurfaceMode) then {
	_fallbackSurfaceHoldoffDistance
} else {
	_terminalImpactHoldoffDistance
};
private _emergencyFallbackDistance = _nonContactHoldoffDistance max (_impactFallbackRadius max 1.5);
private _withinNonContactHoldoff = _impactDistance <= _nonContactHoldoffDistance;
private _withinEmergencyFallbackDistance = _impactDistance <= _emergencyFallbackDistance;
private _withinTargetHoldoff = _targetDistance <= _terminalImpactHoldoffDistance;
private _altitudeEnvelopeOk = (_altitudeAGL <= _maxAltitudeAGL) && {_impactHeightDelta <= (_verticalWindow max _maxAltitudeAGL)};
private _surfaceQualified = _impactEnvelope && {_closingDot >= _minClosingDot} && {_altitudeEnvelopeOk};
private _directHitPredictedQualified = _isDirectHitMode && {_withinNonContactHoldoff} && {_timeToContact > 0} && {_timeToContact <= _predictedImpactWindow} && {_closingDot >= _minClosingDot} && {_altitudeEnvelopeOk};
private _fallbackSurfaceQualified = _isFallbackSurfaceMode && {_withinNonContactHoldoff} && {_surfaceQualified};
private _directHitClosureQualified = _isDirectHitMode && {_directHitClosureQualifiedAllowed} && {_withinNonContactHoldoff} && {_surfaceQualified};
private _detonationReason = "NONE";
private _fallbackReason = "NONE";
private _approved = false;

if (_isDirectHitMode && {_impactDistance <= _directContactDistance}) then {
	_approved = true;
	_detonationReason = "DIRECT_CONTACT";
} else {
	if (_isAirPolicyMode && {_legacyEnvelope}) then {
		_approved = true;
		_detonationReason = "PROXIMITY_FAILSAFE";
		_fallbackReason = "AIR_TARGET_PROXIMITY_POLICY";
	} else {
		if (_directHitPredictedQualified) then {
			_approved = true;
			_detonationReason = "PREDICTED_IMPACT";
		} else {
			if ((_impactMode == "OBSTRUCTION_SURFACE") && {_fallbackSurfaceQualified}) then {
				_approved = true;
				_detonationReason = "OBSTRUCTION_FALLBACK";
				_fallbackReason = "TARGET_DUCKED_BEHIND_OBSTRUCTION";
			} else {
				if ((_impactMode == "GROUND_NEAR_TARGET") && {_fallbackSurfaceQualified}) then {
					_approved = true;
					_detonationReason = "CLOSURE_QUALIFIED";
				} else {
					if (_directHitClosureQualified) then {
						_approved = true;
						_detonationReason = "CLOSURE_QUALIFIED";
					} else {
						if (_fallbackAllowed) then {
							switch (true) do {
								case (_overshootImminent && {_withinEmergencyFallbackDistance}): {
									_approved = true;
									_detonationReason = "MISSED_PASS_FALLBACK";
									_fallbackReason = "OVERSHOOT_IMMINENT";
								};

								case (_guidanceDegraded && {_withinEmergencyFallbackDistance} && {(_impactEnvelope || _legacyEnvelope)}): {
									_approved = true;
									_detonationReason = "PROXIMITY_FAILSAFE";
									_fallbackReason = "GUIDANCE_QUALITY_DEGRADED";
								};

								case (_collapsedWindow && {_withinEmergencyFallbackDistance}): {
									_approved = true;
									_detonationReason = "PROXIMITY_FAILSAFE";
									_fallbackReason = "IMPACT_WINDOW_COLLAPSED";
								};

								case (!_impactValid && {_legacyEnvelope} && {_withinTargetHoldoff}): {
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