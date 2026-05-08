params [['_uav', objNull], ['_profile', createHashMap], ['_force', false]];

if (isNull _uav) exitWith {'OK'};

private _cachedState = _uav getVariable ['A3UE_FPV_cachedLinkState', _uav getVariable ['A3UE_FPV_linkState', 'OK']];
if (!local _uav) exitWith {_cachedState};

private _now = time;
private _currentPosAtl = getPosATL _uav;
private _lastEvalPosAtl = _uav getVariable ['A3UE_FPV_lastLinkEvalPosATL', _currentPosAtl];
private _nextEvalAt = _uav getVariable ['A3UE_FPV_nextLinkEvalAt', 0];
private _movedFarEnough = (_currentPosAtl distance2D _lastEvalPosAtl) > 150;

if (_force || {_cachedState isEqualTo ''} || {_now >= _nextEvalAt} || {_movedFarEnough}) then {
	_cachedState = [_uav, _profile] call A3UE_fnc_fpv_evaluateLinkState;
	_uav setVariable ['A3UE_FPV_cachedLinkState', _cachedState, true];
	_uav setVariable ['A3UE_FPV_cachedSignalStrength', _uav getVariable ['A3UE_FPV_signalStrength', 1], true];
	_uav setVariable ['A3UE_FPV_nextLinkEvalAt', _now + 0.35];
	_uav setVariable ['A3UE_FPV_lastLinkEvalPosATL', _currentPosAtl];
};

_uav setVariable ['A3UE_FPV_linkState', _cachedState, true];

_cachedState