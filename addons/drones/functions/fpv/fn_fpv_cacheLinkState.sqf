params [['_uav', objNull], ['_profile', createHashMap], ['_force', false]];

if !(call A3UE_fnc_fpv_helperAccess) exitWith {'OK'};

if (isNull _uav) exitWith {'OK'};

private _cachedState = _uav getVariable ['A3UE_FPV_cachedLinkState', _uav getVariable ['A3UE_FPV_linkState', 'OK']];
if (!local _uav) exitWith {_cachedState};

private _now = time;
private _currentPosAtl = getPosATL _uav;
private _lastEvalPosAtl = _uav getVariable ['A3UE_FPV_lastLinkEvalPosATL', _currentPosAtl];
private _nextEvalAt = _uav getVariable ['A3UE_FPV_nextLinkEvalAt', 0];
private _movedFarEnough = (_currentPosAtl distance2D _lastEvalPosAtl) > 150;
// LT-2: values every machine already has are not sent again (they were re-broadcast per pass).
private _publish = {
	params ['_key', '_value'];
	if ((_uav getVariable [_key, '']) isNotEqualTo _value) then {_uav setVariable [_key, _value, true];};
};

if (_force || {_cachedState isEqualTo ''} || {_now >= _nextEvalAt} || {_movedFarEnough}) then {
	_cachedState = [_uav, _profile] call A3UE_fnc_fpv_evaluateLinkState;
	['A3UE_FPV_cachedLinkState', _cachedState] call _publish;
	['A3UE_FPV_cachedSignalStrength', _uav getVariable ['A3UE_FPV_signalStrength', 1]] call _publish;
	// LT-2: the link is sampled once a second (A3UE_FPV_leanBrain; 0.35 s before). A drone flies
	// at most about 35 m in that time, against link geometry measured in hundreds of metres.
	_uav setVariable ['A3UE_FPV_nextLinkEvalAt', _now + ([0.35, 1] select ((call A3UE_fnc_fpv_wingSettings) # 6))];
	_uav setVariable ['A3UE_FPV_lastLinkEvalPosATL', _currentPosAtl];
};

['A3UE_FPV_linkState', _cachedState] call _publish;

_cachedState
