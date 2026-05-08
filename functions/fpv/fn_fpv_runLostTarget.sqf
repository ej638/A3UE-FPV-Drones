params [["_uav", objNull], ["_profile", createHashMap], ["_attemptReacquire", false]];

if (isNull _uav) exitWith {objNull};
if (!local _uav) exitWith {objNull};

private _originAsl = _uav getVariable ["A3UE_FPV_lastKnownTargetPosASL", []];
private _velocity = _uav getVariable ["A3UE_FPV_lastKnownTargetVel", [0, 0, 0]];
private _expireAt = _uav getVariable ["A3UE_FPV_lostTargetExpireAt", 0];

if (_originAsl isEqualTo [] || {time > _expireAt}) exitWith {
	_uav setVariable ["A3UE_FPV_mode", "SEARCHING", true];
	objNull
};

private _lastKnownTime = _uav getVariable ["A3UE_FPV_lastKnownTargetTime", time];
private _predictionAge = (time - _lastKnownTime) max 0;
private _predictedPosAsl = _originAsl vectorAdd (_velocity vectorMultiply (_predictionAge min 2));
private _predictedPosAtl = ASLToATL _predictedPosAsl;
private _climbAgl = [_profile, "lostTargetClimbAGL", 12] call A3UE_fnc_fpv_profileValue;
if (!(_climbAgl isEqualType 0) || {_climbAgl < 0}) then {
	_climbAgl = 12;
};

_predictedPosAtl set [2, ((_predictedPosAtl select 2) max _climbAgl)];
_predictedPosAsl = ATLToASL _predictedPosAtl;

_uav setVariable ["A3UE_FPV_lostTargetOriginASL", _predictedPosAsl, true];
[_uav, _predictedPosAsl, _profile] call A3UE_fnc_fpv_applyGuidance;

if (!_attemptReacquire) exitWith {objNull};

private _focusRadius = [_profile, "lostTargetRadius", 180] call A3UE_fnc_fpv_profileValue;
if (!(_focusRadius isEqualType 0) || {_focusRadius <= 0}) then {
	_focusRadius = 180;
};

private _coneHalfAngle = [_profile, "lostTargetConeHalfAngle", 30] call A3UE_fnc_fpv_profileValue;
if (!(_coneHalfAngle isEqualType 0) || {_coneHalfAngle < 0}) then {
	_coneHalfAngle = 30;
};

private _coneDirection = if ((vectorMagnitude _velocity) > 0.1) then {
	vectorNormalized _velocity
} else {
	vectorDir _uav
};

private _searchContext = createHashMapFromArray [
	["focusPosATL", _predictedPosAtl],
	["focusRadius", _focusRadius],
	["overrideSiteScan", true],
	["preferLostTarget", true],
	["coneOriginASL", _originAsl],
	["coneDirection", _coneDirection],
	["coneHalfAngle", _coneHalfAngle]
];

[_uav, _profile, _searchContext] call A3UE_fnc_fpv_selectTarget