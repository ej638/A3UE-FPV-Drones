params [["_uav", objNull]];

if (isNull _uav) exitWith {false};

private _profile = [_uav] call A3UE_fnc_fpv_getProfile;
private _nextGuidanceTick = 0;
private _nextTargetScanTick = 0;
private _nextLinkEvalTick = 0;

private _storeTargetMemory = {
	params ["_uav", "_target", "_profile"];

	if (isNull _target || {!alive _target}) exitWith {false};

	private _lostTargetTTL = [_profile, "lostTargetTTL", 4] call A3UE_fnc_fpv_profileValue;
	if (!(_lostTargetTTL isEqualType 0) || {_lostTargetTTL <= 0}) then {
		_lostTargetTTL = 4;
	};

	_uav setVariable ["A3UE_FPV_lastKnownTargetNetId", netId _target, true];
	_uav setVariable ["A3UE_FPV_lastKnownTargetPosASL", getPosASL _target, true];
	_uav setVariable ["A3UE_FPV_lastKnownTargetVel", velocity _target, true];
	_uav setVariable ["A3UE_FPV_lastKnownTargetTime", time, true];
	_uav setVariable ["A3UE_FPV_lostTargetExpireAt", time + _lostTargetTTL, true];

	true
};

private _restoreTerminalVectorControl = {
	params ["_uav"];

	if (isNull _uav) exitWith {false};

	{
		if (alive _x) then {
			_x enableAI "PATH";
			_x enableAI "FSM";
			_x enableAI "AUTOCOMBAT";
		};
	} forEach crew _uav;

	_uav setVariable ["A3UE_FPV_terminalSteeringActive", false, true];
	_uav setVariable ["A3UE_FPV_terminalVectorEnteredAt", -1];
	_uav setVariable ["A3UE_FPV_terminalVectorEntrySpeed", -1, true];
	_uav setVariable ["A3UE_FPV_terminalVectorEntryDistance", -1, true];
	_uav setVariable ["A3UE_FPV_terminalVectorCurrentSpeed", -1, true];
	_uav setVariable ["A3UE_FPV_terminalVectorTargetSpeed", -1, true];
	_uav setVariable ["A3UE_FPV_terminalVectorAccelApplied", -1, true];
	_uav setVariable ["A3UE_FPV_terminalVectorAlignment", -1, true];
	_uav setVariable ["A3UE_FPV_terminalVectorDt", -1, true];
	_uav setVariable ["A3UE_FPV_terminalVectorSpeedJump", -1, true];
	_uav setVariable ["A3UE_FPV_terminalVectorLastUpdateAt", -1];
	_uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", -1];

	true
};

private _impactSolutionFromCache = {
	params ["_uav"];

	if (isNull _uav) exitWith {[objNull, "NONE", "NO_UAV"] call A3UE_fnc_fpv_emptyImpactSolution};

	createHashMapFromArray [
		["valid", _uav getVariable ["A3UE_FPV_lastImpactValid", false]],
		["impactMode", _uav getVariable ["A3UE_FPV_terminalImpactMode", "NONE"]],
		["impactPointASL", _uav getVariable ["A3UE_FPV_lastImpactPointASL", []]],
		["surfaceType", _uav getVariable ["A3UE_FPV_lastImpactSurfaceType", "none"]],
		["surfaceObject", objectFromNetId (_uav getVariable ["A3UE_FPV_lastImpactSurfaceObjectNetId", ""])],
		["targetNetId", _uav getVariable ["A3UE_FPV_lastImpactTargetNetId", ""]],
		["reason", _uav getVariable ["A3UE_FPV_lastImpactReason", "NONE"]],
		["fallbackAllowed", _uav getVariable ["A3UE_FPV_lastImpactFallbackAllowed", true]],
		["fallbackRadius", _uav getVariable ["A3UE_FPV_lastImpactFallbackRadius", 0]],
		["updatedAt", _uav getVariable ["A3UE_FPV_lastImpactTelemetryAt", -1]]
	]
};

private _storeImpactSolution = {
	params ["_uav", ["_impactSolution", createHashMap], ["_uavPosAsl", []], ["_targetPosAsl", []]];

	if (isNull _uav) exitWith {false};

	private _impactMode = _impactSolution getOrDefault ["impactMode", "NONE"];
	private _impactPointAsl = _impactSolution getOrDefault ["impactPointASL", []];
	private _surfaceType = _impactSolution getOrDefault ["surfaceType", "none"];
	private _surfaceObject = _impactSolution getOrDefault ["surfaceObject", objNull];
	private _targetNetId = _impactSolution getOrDefault ["targetNetId", ""];
	private _reason = _impactSolution getOrDefault ["reason", "NONE"];
	private _valid = _impactSolution getOrDefault ["valid", false];
	private _fallbackAllowed = _impactSolution getOrDefault ["fallbackAllowed", true];
	private _fallbackRadius = _impactSolution getOrDefault ["fallbackRadius", 0];
	private _updatedAt = _impactSolution getOrDefault ["updatedAt", time];

	if !(_impactMode isEqualType "") then {
		_impactMode = "NONE";
	};

	if !(_surfaceType isEqualType "") then {
		_surfaceType = "none";
	};

	if !(_targetNetId isEqualType "") then {
		_targetNetId = "";
	};

	if !(_reason isEqualType "") then {
		_reason = "NONE";
	};

	if !(_valid isEqualType true) then {
		_valid = false;
	};

	if !(_fallbackAllowed isEqualType true) then {
		_fallbackAllowed = true;
	};

	if !(_fallbackRadius isEqualType 0) then {
		_fallbackRadius = 0;
	};

	if !(_updatedAt isEqualType 0) then {
		_updatedAt = time;
	};

	_uav setVariable ["A3UE_FPV_terminalImpactMode", _impactMode, true];
	_uav setVariable ["A3UE_FPV_lastImpactValid", _valid, true];
	_uav setVariable ["A3UE_FPV_lastImpactPointASL", _impactPointAsl, true];
	_uav setVariable ["A3UE_FPV_lastImpactSurfaceType", _surfaceType, true];
	_uav setVariable ["A3UE_FPV_lastImpactSurfaceObjectNetId", if (isNull _surfaceObject) then {""} else {netId _surfaceObject}, true];
	_uav setVariable ["A3UE_FPV_lastImpactTargetNetId", _targetNetId, true];
	_uav setVariable ["A3UE_FPV_lastImpactReason", _reason, true];
	_uav setVariable ["A3UE_FPV_lastImpactFallbackAllowed", _fallbackAllowed, true];
	_uav setVariable ["A3UE_FPV_lastImpactFallbackRadius", _fallbackRadius, true];
	_uav setVariable ["A3UE_FPV_lastImpactEvalPosASL", _uavPosAsl, true];
	_uav setVariable ["A3UE_FPV_lastImpactTargetPosASL", _targetPosAsl, true];
	_uav setVariable ["A3UE_FPV_lastImpactTelemetryAt", _updatedAt, true];

	true
};

private _resolveImpactSolution = {
	params ["_uav", "_target", "_profile", ["_force", false], ["_now", time]];

	if (isNull _uav) exitWith {[objNull, "NONE", "NO_UAV"] call A3UE_fnc_fpv_emptyImpactSolution};

	if (isNull _target || {!alive _target}) exitWith {
		private _emptySolution = [_target, "NONE", "NO_TARGET"] call A3UE_fnc_fpv_emptyImpactSolution;
		[_uav, _emptySolution, [], []] call _storeImpactSolution;
		_emptySolution
	};

	private _refreshTTL = [_profile, "impactSurfaceRefreshTTL", 0.10] call A3UE_fnc_fpv_profileValue;
	private _refreshDistance = [_profile, "impactSurfaceRefreshDistance", 10] call A3UE_fnc_fpv_profileValue;
	if (!(_refreshTTL isEqualType 0) || {_refreshTTL <= 0}) then {
		_refreshTTL = 0.10;
	};
	if (!(_refreshDistance isEqualType 0) || {_refreshDistance <= 0}) then {
		_refreshDistance = 10;
	};

	private _uavPosAsl = getPosASL _uav;
	private _targetPosAsl = getPosASL _target;
	private _cachedTargetNetId = _uav getVariable ["A3UE_FPV_lastImpactTargetNetId", ""];
	private _cachedPoint = _uav getVariable ["A3UE_FPV_lastImpactPointASL", []];
	private _cachedEvalPos = _uav getVariable ["A3UE_FPV_lastImpactEvalPosASL", []];
	private _cachedTargetPos = _uav getVariable ["A3UE_FPV_lastImpactTargetPosASL", []];
	private _cachedUpdatedAt = _uav getVariable ["A3UE_FPV_lastImpactTelemetryAt", -1];
	private _needsRefresh = _force ||
		{_cachedTargetNetId != netId _target} ||
		{!(_cachedPoint isEqualType []) || {_cachedPoint isEqualTo []}} ||
		{!(_cachedEvalPos isEqualType []) || {_cachedEvalPos isEqualTo []}} ||
		{!(_cachedTargetPos isEqualType []) || {_cachedTargetPos isEqualTo []}} ||
		{!(_cachedUpdatedAt isEqualType 0) || {_cachedUpdatedAt < 0}} ||
		{_now >= (_cachedUpdatedAt + _refreshTTL)} ||
		{(_uavPosAsl vectorDistance _cachedEvalPos) > _refreshDistance} ||
		{(_targetPosAsl vectorDistance _cachedTargetPos) > _refreshDistance};

	if (_needsRefresh) then {
		private _impactSolution = [_uav, _target, _profile] call A3UE_fnc_fpv_resolveImpactPoint;
		[_uav, _impactSolution, _uavPosAsl, _targetPosAsl] call _storeImpactSolution;
		_impactSolution
	} else {
		[_uav] call _impactSolutionFromCache
	}
};

private _computeSleepTime = {
	params ["_now", "_tickTimes"];

	private _futureTicks = _tickTimes select { _x > _now };
	if (_futureTicks isEqualTo []) exitWith {0.02};

	(((selectMin _futureTicks) - _now) max 0.02) min 0.25
};

while {
	alive _uav &&
	local _uav &&
	(_uav getVariable ["A3UE_FPV_controllerRunning", false])
} do {
	private _mode = _uav getVariable ["A3UE_FPV_mode", "IDLE"];
	if (_mode != "TERMINAL_VECTOR" && {_uav getVariable ["A3UE_FPV_terminalSteeringActive", false]}) then {
		[_uav] call _restoreTerminalVectorControl;
	};

	private _now = time;
	private _sleepTime = 0.05;
	private _linkState = _uav getVariable ["A3UE_FPV_cachedLinkState", _uav getVariable ["A3UE_FPV_linkState", "OK"]];
	private _target = objNull;

	if (_now >= _nextLinkEvalTick) then {
		_linkState = [_uav, _profile] call A3UE_fnc_fpv_cacheLinkState;
		_nextLinkEvalTick = _uav getVariable ["A3UE_FPV_nextLinkEvalAt", (_now + 0.35)];
	} else {
		_uav setVariable ["A3UE_FPV_linkState", _linkState, true];
	};

	if ([_uav] call A3UE_fnc_fpv_isExternallyControlled) then {
		if (_mode != "IDLE") then {
			if (_mode == "TERMINAL_VECTOR") then {
				[_uav] call _restoreTerminalVectorControl;
			};
			_uav setVariable ["A3UE_FPV_mode", "IDLE", true];
			[_uav] call A3UE_fnc_fpv_clearTarget;
		};

		_nextGuidanceTick = _now + 0.5;
		_nextTargetScanTick = _now + 0.5;
	} else {
		if ((_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) isEqualTo "RADIO" && {_linkState == "EW_DENIED"}) then {
			if (_now >= _nextGuidanceTick) then {
				if (_mode == "TERMINAL_VECTOR") then {
					[_uav] call _restoreTerminalVectorControl;
				};
				[_uav, _profile] call A3UE_fnc_fpv_holdPattern;
				_uav setVariable ["A3UE_FPV_mode", "IDLE", true];
				_nextGuidanceTick = _now + 0.5;
			};
			_nextTargetScanTick = _now + 0.5;
		} else {
			switch (_mode) do {
				case "IDLE": {
					if (_now >= _nextGuidanceTick) then {
						[_uav, _profile] call A3UE_fnc_fpv_holdPattern;
						_uav setVariable ["A3UE_FPV_mode", "SEARCHING", true];
						_nextGuidanceTick = _now + 0.5;
						_nextTargetScanTick = _now + 0.2;
					};
				};

				case "SEARCHING": {
					if (_now >= _nextGuidanceTick) then {
						[_uav, _profile] call A3UE_fnc_fpv_holdPattern;
						_nextGuidanceTick = _now + 0.5;
					};

					if (_now >= _nextTargetScanTick) then {
						_target = [_uav, _profile] call A3UE_fnc_fpv_selectTarget;
						if (isNull _target) then {
							_nextTargetScanTick = _now + 0.35;
						} else {
							_uav setVariable ["A3UE_FPV_targetNetId", netId _target, true];
							_uav setVariable ["A3UE_FPV_mode", "TRACKING", true];
							_nextGuidanceTick = _now;
							_nextTargetScanTick = _now + 0.35;
						};
					};
				};

				case "TRACKING": {
					if (_now >= _nextGuidanceTick) then {
						_target = [_uav] call A3UE_fnc_fpv_resolveTarget;
						private _trackBreakDistance = [_profile, "trackBreakDistance", 700] call A3UE_fnc_fpv_profileValue;

						if (isNull _target || {!alive _target} || {(_uav distance _target) > _trackBreakDistance}) then {
							[_uav, _target, _profile] call _storeTargetMemory;
							[_uav] call A3UE_fnc_fpv_clearTarget;
							_uav setVariable ["A3UE_FPV_mode", "LOST_TARGET", true];
							_nextGuidanceTick = _now + 0.1;
							_nextTargetScanTick = _now + 0.2;
						} else {
							[_uav, _target, _profile] call _storeTargetMemory;
							private _intercept = [_uav, _target, _profile] call A3UE_fnc_fpv_computeIntercept;
							_uav setVariable ["A3UE_FPV_lastInterceptASL", _intercept, true];

							[_uav, _intercept, _profile] call A3UE_fnc_fpv_applyGuidance;

							if ([_uav, _target, _profile] call A3UE_fnc_fpv_shouldEnterTerminal) then {
								_uav setVariable ["A3UE_FPV_mode", "TERMINAL_ATTACK", true];
								_nextGuidanceTick = _now + 0.03;
							} else {
								_nextGuidanceTick = _now + 0.05;
							};
						};
					};
				};

				case "LOST_TARGET": {
					if (_now >= _nextGuidanceTick) then {
						[_uav, _profile, false] call A3UE_fnc_fpv_runLostTarget;
						if ((_uav getVariable ["A3UE_FPV_mode", "LOST_TARGET"]) isEqualTo "SEARCHING") then {
							_nextGuidanceTick = _now + 0.5;
							_nextTargetScanTick = _now + 0.2;
						} else {
							_nextGuidanceTick = _now + 0.08;
						};
					};

					if (_now >= _nextTargetScanTick && {(_uav getVariable ["A3UE_FPV_mode", "LOST_TARGET"]) isEqualTo "LOST_TARGET"}) then {
						_target = [_uav, _profile, true] call A3UE_fnc_fpv_runLostTarget;
						if (isNull _target) then {
							_nextTargetScanTick = _now + 0.2;
						} else {
							_uav setVariable ["A3UE_FPV_targetNetId", netId _target, true];
							[_uav, _target, _profile] call _storeTargetMemory;
							if ([_uav, _target, _profile] call A3UE_fnc_fpv_shouldEnterTerminal) then {
								_uav setVariable ["A3UE_FPV_mode", "TERMINAL_ATTACK", true];
								_nextGuidanceTick = _now + 0.03;
							} else {
								_uav setVariable ["A3UE_FPV_mode", "TRACKING", true];
								_nextGuidanceTick = _now;
							};
							_nextTargetScanTick = _now + 0.35;
						};
					};
				};

				case "TERMINAL_ATTACK": {
					if (_now >= _nextGuidanceTick) then {
						_target = [_uav] call A3UE_fnc_fpv_resolveTarget;
						private _trackBreakDistance = [_profile, "trackBreakDistance", 700] call A3UE_fnc_fpv_profileValue;
						private _terminalSteeringDistance = [_profile, "terminalSteeringDistance", 72] call A3UE_fnc_fpv_profileValue;

						if (isNull _target || {!alive _target} || {(_uav distance _target) > _trackBreakDistance}) then {
							[_uav, _target, _profile] call _storeTargetMemory;
							[_uav] call A3UE_fnc_fpv_clearTarget;
							_uav setVariable ["A3UE_FPV_mode", "LOST_TARGET", true];
							_nextGuidanceTick = _now + 0.1;
							_nextTargetScanTick = _now + 0.1;
						} else {
							[_uav, _target, _profile] call _storeTargetMemory;
							[_uav, _target, _profile, false, _now] call _resolveImpactSolution;
							private _distanceToTarget = (getPosASL _uav) vectorDistance (getPosASL _target);
							private _impactPointAsl = _uav getVariable ["A3UE_FPV_lastImpactPointASL", []];
							private _distanceToImpact = if ((_uav getVariable ["A3UE_FPV_lastImpactValid", false]) && {(_uav getVariable ["A3UE_FPV_lastImpactTargetNetId", ""]) == netId _target} && {_impactPointAsl isEqualType [] && {count _impactPointAsl >= 3}}) then {
								(getPosASL _uav) vectorDistance _impactPointAsl
							} else {
								_distanceToTarget
							};
							[_uav, _target, _profile] call A3UE_fnc_fpv_runTerminal;

							if ([_uav, _target, _profile] call A3UE_fnc_fpv_shouldDetonateNow) then {
								[
									_uav,
									_target,
									_uav getVariable ["A3UE_FPV_lastDetonationReason", "NONE"],
									_uav getVariable ["A3UE_FPV_lastFallbackReason", "NONE"]
								] call A3UE_fnc_fpv_detonateCompat;
							} else {
								if (_distanceToImpact <= _terminalSteeringDistance) then {
									private _entryVelocity = velocity _uav;
									private _entrySpeed = (vectorMagnitude _entryVelocity) * 3.6;
									if (_entrySpeed <= 0) then {
										_entrySpeed = [_profile, "terminalVectorEntrySpeed", [_profile, "terminalAttackSpeed", [_profile, "terminalSpeed", 120] call A3UE_fnc_fpv_profileValue] call A3UE_fnc_fpv_profileValue] call A3UE_fnc_fpv_profileValue;
									};
									_uav setVariable ["A3UE_FPV_mode", "TERMINAL_VECTOR", true];
									_uav setVariable ["A3UE_FPV_terminalVectorEnteredAt", _now];
									_uav setVariable ["A3UE_FPV_terminalVectorEntrySpeed", _entrySpeed, true];
									_uav setVariable ["A3UE_FPV_terminalVectorEntryDistance", _distanceToImpact, true];
									_uav setVariable ["A3UE_FPV_terminalVectorLastUpdateAt", -1];
									_uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", _distanceToImpact];
									_nextGuidanceTick = _now + 0.01;
								} else {
									_nextGuidanceTick = _now + 0.02;
								};
							};
						};
					};
				};

				case "TERMINAL_VECTOR": {
					if (_now >= _nextGuidanceTick) then {
						_target = [_uav] call A3UE_fnc_fpv_resolveTarget;
						private _trackBreakDistance = [_profile, "trackBreakDistance", 700] call A3UE_fnc_fpv_profileValue;

						if (isNull _target || {!alive _target} || {(_uav distance _target) > _trackBreakDistance}) then {
							[_uav, _target, _profile] call _storeTargetMemory;
							[_uav] call A3UE_fnc_fpv_clearTarget;
							[_uav] call _restoreTerminalVectorControl;
							_uav setVariable ["A3UE_FPV_mode", "LOST_TARGET", true];
							_nextGuidanceTick = _now + 0.1;
							_nextTargetScanTick = _now + 0.1;
						} else {
							private _impactPointAsl = _uav getVariable ["A3UE_FPV_lastImpactPointASL", []];
							private _currentDistance = if ((_uav getVariable ["A3UE_FPV_lastImpactValid", false]) && {(_uav getVariable ["A3UE_FPV_lastImpactTargetNetId", ""]) == netId _target} && {_impactPointAsl isEqualType [] && {count _impactPointAsl >= 3}}) then {
								(getPosASL _uav) vectorDistance _impactPointAsl
							} else {
								(getPosASL _uav) vectorDistance (getPosASL _target)
							};
							private _enteredAt = _uav getVariable ["A3UE_FPV_terminalVectorEnteredAt", _now];
							private _lastDistance = _uav getVariable ["A3UE_FPV_lastTerminalVectorDistance", _currentDistance];
							private _missedPass = (_now > (_enteredAt + 0.15)) && {(_currentDistance > (_lastDistance + 8))};
							if (_missedPass) then {
								[_uav, _target, _profile] call _storeTargetMemory;
								[_uav] call _restoreTerminalVectorControl;
								[_uav] call A3UE_fnc_fpv_clearTarget;
								_uav setVariable ["A3UE_FPV_mode", "LOST_TARGET", true];
								_nextGuidanceTick = _now + 0.1;
								_nextTargetScanTick = _now + 0.1;
							} else {
								[_uav, _target, _profile] call _storeTargetMemory;
								[_uav, _target, _profile, false, _now] call _resolveImpactSolution;
								if ([_uav, _target, _profile] call A3UE_fnc_fpv_runTerminalVector) then {
									_uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", _currentDistance];
								};

								if ([_uav, _target, _profile] call A3UE_fnc_fpv_shouldDetonateNow) then {
									[
										_uav,
										_target,
										_uav getVariable ["A3UE_FPV_lastDetonationReason", "NONE"],
										_uav getVariable ["A3UE_FPV_lastFallbackReason", "NONE"]
									] call A3UE_fnc_fpv_detonateCompat;
								} else {
									_nextGuidanceTick = _now + 0.01;
								};
							};
						};
					};
				};

				default {
					_uav setVariable ["A3UE_FPV_mode", "IDLE", true];
					_nextGuidanceTick = _now + 0.5;
					_nextTargetScanTick = _now + 0.5;
				};
			};
		};
	};

	_sleepTime = [_now, [_nextGuidanceTick, _nextTargetScanTick, _nextLinkEvalTick]] call _computeSleepTime;

	sleep _sleepTime;
};

if (!isNull _uav) then {
	if (_uav getVariable ["A3UE_FPV_terminalSteeringActive", false]) then {
		[_uav] call _restoreTerminalVectorControl;
	};

	_uav setVariable ["A3UE_FPV_controllerRunning", false];
	_uav setVariable ["A3UE_FPV_controllerOwnerId", -1, true];
	_uav setVariable ["A3UE_FPV_terminalSteeringActive", false, true];
};

true