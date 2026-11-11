params [["_uav", objNull], ["_generation", -1], ["_state", createHashMap]];

if (isRemoteExecutedJIP || {isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}}) exitWith {false};

if (isNull _uav) exitWith {
	// LT-2: a deleted drone ends its controller state, so its pacer and the director drop it.
	if (count _state > 0) then {
		_state set ["running", false];
		_state set ["hot", false];
	};
	false
};
if (_generation < 0) then {
	_generation = _uav getVariable ["A3UE_FPV_controllerGeneration", -1];
};

// LT-2 pacer: the spawned, scheduled script. Every controller pass is a tick (this same
// function called with the state, in one unscheduled slice). The script ticks the drone when
// its own deadlines ask for it. While the drone attacks, the frame director ticks it every
// frame and this script only checks that the director still does (it takes over after 0.5 s).
if (count _state == 0) exitWith {
	_state = [_uav, _generation] call A3UE_fnc_fpv_controllerState;
	if (count _state == 0) exitWith {false};
	while {_state get "running"} do {
		private _sleepFor = 0.25;
		if (!(_state get "listed") || {diag_tickTime - (_state get "tickedAt") > 0.5}) then {
			isNil {_sleepFor = ([_uav, _generation, _state] call A3UE_fnc_fpv_runController) param [1, 0.25];};
			A3UE_FPV_perf set [9, (A3UE_FPV_perf # 9) + 1];
		};
		private _wakeAt = diag_tickTime + _sleepFor;
		sleep _sleepFor;
		// How late the scheduler woke this script (real seconds), for the director's evidence line.
		private _late = (diag_tickTime - _wakeAt) max 0;
		A3UE_FPV_perf set [6, (A3UE_FPV_perf # 6) + 1];
		A3UE_FPV_perf set [7, (A3UE_FPV_perf # 7) + _late];
		if (_late > (A3UE_FPV_perf # 8)) then {A3UE_FPV_perf set [8, _late];};
	};
	true
};

// LT-2 tick: one controller pass. It always runs in one unscheduled slice (the pacer wraps it
// in isNil, the director calls it from EachFrame), so nothing changes between its checks and
// its writes. The locals that used to live across the loop are kept in _state.
// _fpvTick: helpers called from here work out their per-tick facts once (canActuate,
// resolveTarget, attackSettings, trajectoryLimits, wingSettings).
private _fpvTick = createHashMap;
private _wing = call A3UE_fnc_fpv_wingSettings;
// The controller keeps the identity it started with (its original ticket).
private _controllerIdentity = +(_state get "identity");

private _profile = _state get "profile";
private _nextGuidanceTick = _state get "nextGuidance";
private _nextTargetScanTick = _state get "nextScan";
private _nextLinkEvalTick = _state get "nextLink";
private _nextStrikeRetryTick = _state get "nextStrikeRetry";
private _nextTargetabilityCheckAt = _state get "nextTargetability";
private _targetabilitySuspended = _state get "targetabilitySuspended";
private _terminalAIRecoveryPending = _state get "aiRecoveryPending";
// Model-space anchors are owner-local; every new controller must trace its own solution.
private _impactCacheReady = _state get "impactCacheReady";
private _nextRetargetTick = _state get "nextRetarget";
private _wingRole = _state get "role";
// Cleared to attack and within 450 m: kept between ticks, as most ticks have no guidance pass.
private _wingHot = _state get "wingHot";
private _qa = false;
private _clearTrackingOrderContext = {
	// Metadata only, including suspension: never clear a replacement controller's cache.
	isNil {
		if (local _uav && {(_uav getVariable ["A3UE_FPV_controllerGeneration", -1]) == _generation}
			&& {(_uav getVariable ["A3UE_FPV_controllerIdentity", []]) isEqualTo _controllerIdentity}
			&& {(_uav getVariable ["A3UE_FPV_trackingOrderContext", []]) isNotEqualTo []}) then {
			_uav setVariable ["A3UE_FPV_trackingOrderContext", []];
		};
	};
};
private _clearTerminalPoseContext = {
	// A resumed old controller must not erase a replacement identity's local epoch.
    isNil {
        if (local _uav && {(_uav getVariable ["A3UE_FPV_controllerGeneration", -1]) == _generation}
            && {(_uav getVariable ["A3UE_FPV_controllerIdentity", []]) isEqualTo _controllerIdentity}) then {
            _uav setVariable ["A3UE_FPV_terminalPoseContext", []];
            _uav setVariable ["A3UE_FPV_terminalSteeringState", []];
        };
    };
};

private _storeTargetMemory = {
	params ["_uav", "_target", "_profile"];

	if (isNull _target || {!alive _target}) exitWith {false};

	private _lostTargetTTL = [_profile, "lostTargetTTL", 4] call A3UE_fnc_fpv_profileValue;
	if (!(_lostTargetTTL isEqualType 0) || {_lostTargetTTL <= 0}) then {
		_lostTargetTTL = 4;
	};

	[_uav, "A3UE_FPV_lastKnownTargetNetId", netId _target] call A3UE_fnc_fpv_publishTelemetry;
	[_uav, "A3UE_FPV_lastKnownTargetPosASL", getPosASL _target] call A3UE_fnc_fpv_publishTelemetry;
	[_uav, "A3UE_FPV_lastKnownTargetVel", velocity _target] call A3UE_fnc_fpv_publishTelemetry;
	[_uav, "A3UE_FPV_lastKnownTargetTime", time] call A3UE_fnc_fpv_publishTelemetry;
	[_uav, "A3UE_FPV_lostTargetExpireAt", time + _lostTargetTTL] call A3UE_fnc_fpv_publishTelemetry;

	true
};

private _restoreTerminalVectorControl = {
	params ["_uav"];

	if (isNull _uav) exitWith {false};
	private _restored = false;
	isNil {
		if (local _uav && {(_uav getVariable ["A3UE_FPV_controllerGeneration", -1]) == _generation}
            && {(_uav getVariable ["A3UE_FPV_controllerIdentity", []]) isEqualTo _controllerIdentity}) then {
			private _canRestoreAI = [_uav, _controllerIdentity] call A3UE_fnc_fpv_canActuate;
            _terminalAIRecoveryPending = !_canRestoreAI;
            if (_canRestoreAI) then {
                private _native = _uav getVariable ["A3UE_FPV_nativeControl",[]];
                if (count _native == 3 && {(_native # 0) isEqualTo _controllerIdentity}) then {
                    {
                        _x params ["_unit","_path","_fsm","_combat"];
                        if (!isNull _unit && {local _unit} && {alive _unit} && {_unit in crew _uav}) then {
                            if (_path) then {_unit enableAI "PATH";} else {_unit disableAI "PATH";};
                            if (_fsm) then {_unit enableAI "FSM";} else {_unit disableAI "FSM";};
                            if (_combat) then {_unit enableAI "AUTOCOMBAT";} else {_unit disableAI "AUTOCOMBAT";};
                        };
                    } forEach (_native # 1);
                    _uav forceSpeed (_native # 2);
                    _uav setVariable ["A3UE_FPV_nativeControl",[]];
                };
			};

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
			call _clearTerminalPoseContext;
            _uav setVariable ["A3UE_FPV_trajectory",[]];
            _uav setVariable ["A3UE_FPV_navigation",[]];
			_uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", -1];
			_restored = true;
		};
	};

	_restored
};

private _impactSolutionFromCache = {
	params ["_uav"];

	if (isNull _uav) exitWith {[objNull, "NONE", "NO_UAV"] call A3UE_fnc_fpv_emptyImpactSolution};

	createHashMapFromArray [
		["valid", _uav getVariable ["A3UE_FPV_lastImpactValid", false]],
		["impactMode", _uav getVariable ["A3UE_FPV_terminalImpactMode", "NONE"]],
		["impactPointASL", _uav getVariable ["A3UE_FPV_lastImpactPointASL", []]],
		["surfaceType", _uav getVariable ["A3UE_FPV_lastImpactSurfaceType", "none"]],
		["surfaceObject", _uav getVariable ["A3UE_FPV_impactAnchorObject", objectFromNetId (_uav getVariable ["A3UE_FPV_lastImpactSurfaceObjectNetId", ""])]],
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

	{
		[_uav, _x select 0, _x select 1] call A3UE_fnc_fpv_publishTelemetry;
	} forEach [
		["A3UE_FPV_terminalImpactMode", _impactMode],
		["A3UE_FPV_lastImpactValid", _valid],
		["A3UE_FPV_lastImpactPointASL", _impactPointAsl],
		["A3UE_FPV_lastImpactSurfaceType", _surfaceType],
		["A3UE_FPV_lastImpactSurfaceObjectNetId", if (isNull _surfaceObject) then {""} else {netId _surfaceObject}],
		["A3UE_FPV_lastImpactTargetNetId", _targetNetId],
		["A3UE_FPV_lastImpactReason", _reason],
		["A3UE_FPV_lastImpactFallbackAllowed", _fallbackAllowed],
		["A3UE_FPV_lastImpactFallbackRadius", _fallbackRadius],
		["A3UE_FPV_lastImpactEvalPosASL", _uavPosAsl],
		["A3UE_FPV_lastImpactTargetPosASL", _targetPosAsl],
		["A3UE_FPV_lastImpactTelemetryAt", _updatedAt]
	];
	private _objectSurface = _valid && {!isNull _surfaceObject} && {
		_impactPointAsl isEqualType [] && {count _impactPointAsl == 3}
	};
	_uav setVariable ["A3UE_FPV_impactLocalAnchor", if (_objectSurface) then {
		_surfaceObject worldToModel (ASLToAGL _impactPointAsl)
	} else {[]}];
	_uav setVariable ["A3UE_FPV_impactAnchorObject", if (_objectSurface) then {_surfaceObject} else {objNull}];
	_impactCacheReady = true;

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
	private _anchorObject = _uav getVariable ["A3UE_FPV_impactAnchorObject", objNull];
	private _anchor = _uav getVariable ["A3UE_FPV_impactLocalAnchor", []];
	private _hasObjectSurface = (_uav getVariable ["A3UE_FPV_lastImpactValid", false]) && {
		!(_anchor isEqualTo []) || {!((_uav getVariable ["A3UE_FPV_lastImpactSurfaceObjectNetId", ""]) isEqualTo "")}
	};
	private _anchorValid = !isNull _anchorObject && {_anchor isEqualType []} && {count _anchor == 3};
	private _needsRefresh = _force || {!_impactCacheReady} ||
		{_hasObjectSurface && {!_anchorValid}} ||
		{_cachedTargetNetId != netId _target} ||
		{!(_cachedPoint isEqualType []) || {_cachedPoint isEqualTo []}} ||
		{!(_cachedEvalPos isEqualType []) || {_cachedEvalPos isEqualTo []}} ||
		{!(_cachedTargetPos isEqualType []) || {_cachedTargetPos isEqualTo []}} ||
		{!(_cachedUpdatedAt isEqualType 0) || {_cachedUpdatedAt < 0}} ||
		{_now >= (_cachedUpdatedAt + _refreshTTL)} ||
		{(_uavPosAsl vectorDistance _cachedEvalPos) > _refreshDistance} ||
		{(_targetPosAsl vectorDistance _cachedTargetPos) > _refreshDistance};

	private _geometryAt = if (_qa) then {diag_tickTime} else {0};
	private _solution = if (_needsRefresh) then {
		private _impactSolution = [_uav, _target, _profile] call A3UE_fnc_fpv_resolveImpactPoint;
		[_uav, _impactSolution, _uavPosAsl, _targetPosAsl] call _storeImpactSolution;
		_impactSolution
	} else {
		if (_anchorValid) then {
			// Use simulation transforms; modelToWorldWorld returns ASL directly.
			_uav setVariable ["A3UE_FPV_lastImpactPointASL", _anchorObject modelToWorldWorld _anchor];
		};
		[_uav] call _impactSolutionFromCache
	};
	if (_qa) then {[_uav, "GEOMETRY", [diag_tickTime - _geometryAt, _needsRefresh,
		_solution getOrDefault ["impactMode", "NONE"], netId (_solution getOrDefault ["surfaceObject", objNull]),
		_solution getOrDefault ["surfaceType", "none"], _solution getOrDefault ["reason", "NONE"],
		typeOf (_solution getOrDefault ["surfaceObject", objNull])]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
	_solution
};

// Guidance/fuse evaluation and proposal retry have independent clocks.
private _tryStrike = {
	params ["_target","_targetRevision"];
	if (diag_tickTime < _nextStrikeRetryTick) exitWith {false};
	// Advance before calling: even a script error cannot make proposals unbounded.
	_nextStrikeRetryTick = diag_tickTime + 0.5;
	[_uav, _target, _uav getVariable ["A3UE_FPV_lastDetonationReason", "NONE"],
		_uav getVariable ["A3UE_FPV_lastFallbackReason", "NONE"],_targetRevision] call A3UE_fnc_fpv_detonateCompat
};
private _evaluateFuse = {
	params ["_target","_targetRevision"];
	private _at = if (_qa) then {diag_tickTime} else {0};
    private _approved = false;
    isNil {
        if ([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate
            && {(_uav getVariable ["A3UE_FPV_mode",""]) == "TERMINAL_VECTOR"}
            && {(_uav getVariable ["A3UE_FPV_targetRevision",0]) == _targetRevision}
            && {!isNull _target} && {(_uav getVariable ["A3UE_FPV_targetNetId",""]) == netId _target}
            && {([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _target}
            && {!((_uav getVariable ["A3UE_FPV_linkModel","RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState","OK"]) == "EW_DENIED"})}) then {
            _approved = [_uav, _target, _profile] call A3UE_fnc_fpv_shouldDetonateNow;
        };
    };
	if (_qa) then {[_uav, "FUSE", [_approved, diag_tickTime - _at,
		_nextStrikeRetryTick, _uav getVariable ["A3UE_FPV_lastDetonationReason", "NONE"],
		_uav getVariable ["A3UE_FPV_lastFallbackReason", "NONE"]]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
	_approved
};

private _setSafetyReason = {
	params ["_reason"];
	if ((_uav getVariable ["A3UE_FPV_engagementFailureReason", ""]) != _reason) then {
		_uav setVariable ["A3UE_FPV_engagementFailureReason", _reason, true];
		if (missionNamespace getVariable ["A3UE_FPV_debug", false]) then {
			diag_log format ["[A3UE_FPV] engagementPermission id=%1 generation=%2 target=%3 reason=%4", netId _uav, _generation, _uav getVariable ["A3UE_FPV_targetNetId", ""], _reason];
		};
	};
};
private _holdForSafety = {
	params ["_reason"];
	isNil {
    if (!([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate)
        || {(_uav getVariable ["A3UE_FPV_linkModel","RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState","OK"]) == "EW_DENIED"}}) exitWith {};
	// Only actual collateral failures create a timer. Expiration retains its cause.
    if (_reason != "UNSAFE_ENGAGEMENT" && {(_uav getVariable ["A3UE_FPV_engagementBlockedAt",-1]) < 0}) exitWith {};
	[_reason] call _setSafetyReason;
	private _blockedAt = _uav getVariable ["A3UE_FPV_engagementBlockedAt", -1];
	if (_blockedAt < 0) then {
		_blockedAt = serverTime;
		_uav setVariable ["A3UE_FPV_engagementBlockedAt", _blockedAt, true];
	};
	if (_uav getVariable ["A3UE_FPV_terminalSteeringActive", false]) then {[_uav] call _restoreTerminalVectorControl;};
	if ((_uav getVariable ["A3UE_FPV_targetNetId", ""]) != "") then {[_uav] call A3UE_fnc_fpv_clearTarget;};
	// No new cleanup/RPC route: stop attempts after 15 s; existing package TTL retires it.
	_mode = ["SAFETY_HOLD", "SAFETY_ABORT"] select (serverTime - _blockedAt >= 15);
	if ((_uav getVariable ["A3UE_FPV_mode", ""]) != _mode) then {_uav setVariable ["A3UE_FPV_mode", _mode, true];};
	if (_mode == "SAFETY_ABORT" && {!(_uav getVariable ["A3UE_FPV_engagementAborted", false])}) then {_uav setVariable ["A3UE_FPV_engagementAborted", true, true];};
	[_uav, _profile] call A3UE_fnc_fpv_holdPattern;
	_nextGuidanceTick = _now + 0.5;
	_nextTargetScanTick = _now + 0.5;
	};
};

// F2 affected planning/transition boundaries retain the controller's original ticket.
private _refreshTrajectoryImpact = {
    params ["_target"];
    isNil {
        if ([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate
            && {(_uav getVariable ["A3UE_FPV_controllerGeneration",-1]) == _generation}
            && {!isNull _target} && {alive _target}
            && {([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _target}
            && {(_uav getVariable ["A3UE_FPV_targetNetId",""]) == netId _target}
            && {!((_uav getVariable ["A3UE_FPV_linkModel","RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState","OK"]) == "EW_DENIED"})}) then {
            [_uav,_target,_profile,false,time] call _resolveImpactSolution;
        };
    };
};
// Normalize/retire invalid intent atomically before support disposition or guidance.
// Empty/canonical-changed targets use ordinary selection, never the old velocity cone.
private _revalidateTarget = {
    isNil {
        if (!([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate)
            || {(_uav getVariable ["A3UE_FPV_linkModel","RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState","OK"]) == "EW_DENIED"}}
            || {!((_uav getVariable ["A3UE_FPV_mode",""]) in ["TRACKING","TERMINAL_ATTACK","TERMINAL_VECTOR"])}) exitWith {};
        private _oldId = _uav getVariable ["A3UE_FPV_targetNetId",""];
        private _legal = [_uav] call A3UE_fnc_fpv_resolveTarget;
        if (isNull _legal || {netId _legal != _oldId}) then {
            [_uav] call _restoreTerminalVectorControl;
            [_uav] call A3UE_fnc_fpv_clearTarget;
            _impactCacheReady = false;
            _nextGuidanceTick = time;
            _nextTargetScanTick = time;
            _mode = "SEARCHING";
            if (!isNull _legal) then {
                _uav setVariable ["A3UE_FPV_targetNetId",netId _legal,true];
                _mode = "TRACKING";
            };
            _uav setVariable ["A3UE_FPV_mode",_mode,true];
        };
    };
};
private _adoptTarget = {
    params ["_candidate","_expectedMode"];
    private _adopted = false;
    isNil {
        if (!([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate)
            || {(_uav getVariable ["A3UE_FPV_mode",""]) != _expectedMode}
            || {(_uav getVariable ["A3UE_FPV_targetNetId",""]) != ""}
            || {(_uav getVariable ["A3UE_FPV_linkModel","RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState","OK"]) == "EW_DENIED"}}) exitWith {};
        private _side = side group effectiveCommander _uav;
        if (_side == sideUnknown) then {_side = side _uav;};
        private _legal = [_candidate,[_side,_uav getVariable ["A3UE_FPV_targetSide",sideUnknown]] call A3UE_fnc_fpv_getHostileSides] call A3UE_fnc_fpv_filterTarget;
        if (isNull _legal) exitWith {};
        if (_expectedMode == "SAFETY_HOLD" && {([_uav,_legal,true,[],true,createHashMap,true] call A3UE_fnc_fpv_supportEngagementReason) != ""}) exitWith {};
        _uav setVariable ["A3UE_FPV_targetNetId",netId _legal,true];
        _uav setVariable ["A3UE_FPV_mode","TRACKING",true];
        if (_expectedMode == "SAFETY_HOLD") then {
            [""] call _setSafetyReason;
            _uav setVariable ["A3UE_FPV_engagementBlockedAt",-1,true];
        };
        _nextGuidanceTick = time;
        _adopted = true;
    };
    _adopted
};
// LT-2: a drone waiting in overwatch leaves for a clearly better target (selection counts the
// drones already on each one). The same atomic clear and adoption as any other target change.
private _retarget = {
    params ["_target","_revision"];
    private _other = [_uav, _profile] call A3UE_fnc_fpv_selectTarget;
    if (isNull _other || {_other isEqualTo _target}) exitWith {false};
    private _left = false;
    isNil {
        if (!([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate)
            || {(_uav getVariable ["A3UE_FPV_mode",""]) != "TRACKING"}
            || {(_uav getVariable ["A3UE_FPV_targetRevision",0]) != _revision}
            || {(_uav getVariable ["A3UE_FPV_targetNetId",""]) == ""}
            || {(_uav getVariable ["A3UE_FPV_linkModel","RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState","OK"]) == "EW_DENIED"}}) exitWith {};
        [_uav] call A3UE_fnc_fpv_clearTarget;
        _impactCacheReady = false;
        _mode = "SEARCHING";
        _uav setVariable ["A3UE_FPV_mode","SEARCHING",true];
        _nextTargetScanTick = time;
        _left = true;
    };
    if (_left) then {
        diag_log format ["[A3UE_FPV] wing id=%1 event=RETARGET from=%2 to=%3", netId _uav, netId _target, netId _other];
        [_other,"SEARCHING"] call _adoptTarget;
    };
    _left
};
// Existing range/missed-pass policy, fenced against a resumed obsolete caller.
private _loseTarget = {
    params ["_target","_expectedMode","_revision",["_passAt",-1]];
    isNil {
        if (!([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate)
            || {(_uav getVariable ["A3UE_FPV_mode",""]) != _expectedMode}
            || {(_uav getVariable ["A3UE_FPV_targetRevision",0]) != _revision}
            || {(_uav getVariable ["A3UE_FPV_targetNetId",""]) != netId _target}
            || {([_uav] call A3UE_fnc_fpv_resolveTarget) isNotEqualTo _target}
            || {_passAt >= 0 && {(_uav getVariable ["A3UE_FPV_terminalVectorEnteredAt",-1]) != _passAt}}
            || {(_uav getVariable ["A3UE_FPV_linkModel","RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState","OK"]) == "EW_DENIED"}}) exitWith {};
        [_uav,_target,_profile] call _storeTargetMemory;
        if (_expectedMode == "TERMINAL_VECTOR") then {[_uav] call _restoreTerminalVectorControl;};
        [_uav] call A3UE_fnc_fpv_clearTarget;
        _uav setVariable ["A3UE_FPV_mode","LOST_TARGET",true];
        _nextGuidanceTick = time + 0.1;
        _nextTargetScanTick = time + 0.1;
    };
};
private _attemptIngress = {
    params ["_target"];
    private _expectedMode = _uav getVariable ["A3UE_FPV_mode",""];
    [_target] call _refreshTrajectoryImpact;
    private _entered = false;
    // LT-1: plan and enter in one unscheduled slice; a saturated scheduler cannot suspend
    // between them and turn every entry attempt into a stale-plan refusal.
    isNil {
        private _result = [_uav,_target,_profile,_generation,_controllerIdentity] call A3UE_fnc_fpv_prepareTrajectory;
        if (count _result != 5 || {(_result # 0) == -2}) exitWith {};
        private _navigation = [_uav,_target,_controllerIdentity] call A3UE_fnc_fpv_targetNavigation;
        if (!([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate)
            || {(_uav getVariable ["A3UE_FPV_mode",""]) != _expectedMode}
            || {!(_expectedMode in ["TRACKING","TERMINAL_ATTACK"])}
            || {_navigation isEqualTo []} || {!((_navigation # 0) isEqualTo (_result # 4))}
            || {!((_uav getVariable ["A3UE_FPV_trajectory",[]]) isEqualTo (_result # 2))}
            || {(_uav getVariable ["A3UE_FPV_trajectoryAttemptAt",-1]) != (_result # 3)}
            || {(_uav getVariable ["A3UE_FPV_linkModel","RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState","OK"]) == "EW_DENIED"}}
            || {!(([_uav,_target,false,[],true] call A3UE_fnc_fpv_supportEngagementReason) in ["","NO_VISIBLE_TARGET"])}) exitWith {};
        private _vectors = [getPosASL _uav,velocity _uav,vectorDir _uav];
        if ((_vectors findIf {count _x != 3 || {(_x findIf {!(_x isEqualType 0) || {!finite _x} || {abs _x > 1e6}}) >= 0}}) >= 0) exitWith {};
        _uav setVariable ["A3UE_FPV_mode","TERMINAL_VECTOR",true];
        _uav setVariable ["A3UE_FPV_terminalVectorEnteredAt",time];
        _uav setVariable ["A3UE_FPV_terminalVectorEntryDistance",(getPosASL _uav) vectorDistance (_navigation # 5),true];
        _uav setVariable ["A3UE_FPV_terminalVectorLastUpdateAt",-1];
        call _clearTerminalPoseContext;
        _uav setVariable ["A3UE_FPV_lastTerminalVectorDistance",-1];
        // Establish finite zero-dt logical state before relinquishing native ownership.
        _entered = [_uav,_target,_profile,_generation,_controllerIdentity] call A3UE_fnc_fpv_runTerminalVector;
        if (!_entered) then {
            [_uav] call _restoreTerminalVectorControl;
            _uav setVariable ["A3UE_FPV_mode","TRACKING",true];
        };
    };
    _entered
};

// Corrupt geometry is a diagnostic refusal, never a commitment abort. Restore
// only the native settings this controller owns and retry finite tracking/planning.
private _restoreInvalidNavigation = {
    params ["_target","_revision","_passAt"];
    isNil {
        if (!([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate)
            || {(_uav getVariable ["A3UE_FPV_mode",""]) != "TERMINAL_VECTOR"}
            || {(_uav getVariable ["A3UE_FPV_targetRevision",0]) != _revision}
            || {(_uav getVariable ["A3UE_FPV_terminalVectorEnteredAt",-1]) != _passAt}
            || {(_uav getVariable ["A3UE_FPV_targetNetId",""]) != netId _target}
            || {([_uav] call A3UE_fnc_fpv_resolveTarget) isNotEqualTo _target}) exitWith {};
        private _vectors = [getPosASL _uav,velocity _uav];
        if (([_uav,_target,_controllerIdentity] call A3UE_fnc_fpv_targetNavigation) isEqualTo []
            || {(_vectors findIf {count _x != 3 || {(_x findIf {!(_x isEqualType 0) || {!finite _x} || {abs _x > 1e6}}) >= 0}}) >= 0}) then {
            [_uav] call _restoreTerminalVectorControl;
            _uav setVariable ["A3UE_FPV_mode","TRACKING",true];
            _uav setVariable ["A3UE_FPV_trajectoryReason","INPUT"];
        };
    };
};

private _running = alive _uav && {local _uav} &&
	{!(_uav getVariable ["A3UE_FPV_detonating", false])} &&
	{_uav getVariable ["A3UE_FPV_managed", false]} &&
	{(_uav getVariable ["A3UE_FPV_controllerGeneration", -1]) == _generation} &&
	{_uav getVariable ["A3UE_FPV_controllerRunning", false]};
private _tickSleep = 0.25;
if (_running) then {
	_qa = !isNil "A3UE_FPV_QA_sink" && {_uav getVariable ["A3UE_FPV_QA_capture", false]};
	private _loopAt = if (_qa) then {diag_tickTime} else {0};
	private _mode = _uav getVariable ["A3UE_FPV_mode", "IDLE"];
	private _modeAtEntry = _mode;
	if (_mode != "TRACKING") then {call _clearTrackingOrderContext;};
	if (_mode != "TERMINAL_VECTOR") then {call _clearTerminalPoseContext;};
	if (_mode != "TERMINAL_VECTOR" && {_terminalAIRecoveryPending || {_uav getVariable ["A3UE_FPV_terminalSteeringActive", false]}}) then {
		[_uav] call _restoreTerminalVectorControl;
	};

	private _now = time;
	private _sleepTime = 0.05;
	private _linkState = _uav getVariable ["A3UE_FPV_cachedLinkState", _uav getVariable ["A3UE_FPV_linkState", "OK"]];
	private _target = objNull;

    private _externalControl = [_uav] call A3UE_fnc_fpv_isExternallyControlled;
    if (_externalControl != (_uav getVariable ["A3UE_FPV_reportedControl", false])) then {
        _uav setVariable ["A3UE_FPV_reportedControl", _externalControl];
        if (_qa) then {[_uav, "CONTROL", [_externalControl]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
        [_uav, "control", [_externalControl]] call A3UE_fnc_fpv_sendLifecycle;
    };
    if (!_externalControl && {_now >= _nextLinkEvalTick}) then {
		private _radioAt = if (_qa) then {diag_tickTime} else {0};
		_linkState = [_uav, _profile] call A3UE_fnc_fpv_cacheLinkState;
		if (_qa) then {[_uav, "RADIO", [diag_tickTime - _radioAt, _linkState, _uav getVariable ["A3UE_FPV_signalStrength", 1]]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
		_nextLinkEvalTick = _uav getVariable ["A3UE_FPV_nextLinkEvalAt", (_now + 0.35)];
	};

	if (_externalControl || {!([_uav] call A3UE_fnc_fpv_isSiteDroneActive)}) then {
		call _clearTrackingOrderContext;
        isNil {if (local _uav && {(_uav getVariable ["A3UE_FPV_controllerIdentity",[]]) isEqualTo _controllerIdentity}) then {_uav setVariable ["A3UE_FPV_trajectory",[]];
            _uav setVariable ["A3UE_FPV_navigation",[]];};};
		_targetabilitySuspended = true;
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
		// Immediate autonomy transition; <=1 Hz fallback for inline/late native writers.
		// Do not replay full compatibility init here (it also initializes KVN trails).
		if (_targetabilitySuspended || {_now >= _nextTargetabilityCheckAt}) then {
			[_uav, _generation] call A3UE_fnc_fpv_applyTargetability;
			_targetabilitySuspended = false;
			_nextTargetabilityCheckAt = _now + 1;
		};
		if ((_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) isEqualTo "RADIO" && {_linkState == "EW_DENIED"}) then {
			call _clearTrackingOrderContext;
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
			// A control/owner handoff cannot restart a timed-out safety episode.
			if (_uav getVariable ["A3UE_FPV_engagementAborted", false] && {_mode != "SAFETY_ABORT"}) then {
				_mode = "SAFETY_ABORT";
				_uav setVariable ["A3UE_FPV_mode", _mode, true];
			};
			private _blockedAt = _uav getVariable ["A3UE_FPV_engagementBlockedAt", -1];
			if (_blockedAt >= 0 && {serverTime - _blockedAt >= 15} && {_mode != "SAFETY_ABORT"}) then {
				[_uav getVariable ["A3UE_FPV_engagementFailureReason", "NO_VISIBLE_TARGET"]] call _holdForSafety;
			};
            if (_mode in ["TRACKING","TERMINAL_ATTACK","TERMINAL_VECTOR"] && {_now >= _nextGuidanceTick}) then {call _revalidateTarget;};
			// Validate acquired/boarded/replacement targets before any attack guidance.
			if ((_uav getVariable ["A3UE_FPV_supportSafetyRadius", 0]) > 0
				&& {_mode in ["TRACKING", "TERMINAL_ATTACK", "TERMINAL_VECTOR"]} && {_now >= _nextGuidanceTick}) then {
				isNil {
				_target = [_uav] call A3UE_fnc_fpv_resolveTarget;
				private _terminal = _mode != "TRACKING" || {[_uav, _target, _profile] call A3UE_fnc_fpv_shouldEnterTerminal};
				private _reason = [_uav, _target, false, [], _terminal] call A3UE_fnc_fpv_supportEngagementReason;
				if (_reason == "UNSAFE_ENGAGEMENT") then {[_reason] call _holdForSafety;};
				};
			};
			switch (_mode) do {
				case "SAFETY_HOLD": {
					if (_now >= _nextGuidanceTick) then {
						if (serverTime - (_uav getVariable ["A3UE_FPV_engagementBlockedAt", serverTime]) >= 15) then {
							[_uav getVariable ["A3UE_FPV_engagementFailureReason", "NO_VISIBLE_TARGET"]] call _holdForSafety;
						} else {
							_target = [_uav, _profile] call A3UE_fnc_fpv_selectTarget;
							if (isNull _target) then {
								[_uav,_profile] call A3UE_fnc_fpv_holdPattern; _nextGuidanceTick = _now + 0.5;
							} else {
								private _reason = [_uav, _target, true, [], true, createHashMap, true] call A3UE_fnc_fpv_supportEngagementReason;
								if (_reason != "") then {
                                    if (_reason == "UNSAFE_ENGAGEMENT") then {[_reason] call _holdForSafety;} else {[_uav,_profile] call A3UE_fnc_fpv_holdPattern; _nextGuidanceTick = _now + 0.5;};
                                } else {
									[_target,"SAFETY_HOLD"] call _adoptTarget;
								};
							};
						};
					};
				};
				case "SAFETY_ABORT": {
					if (_now >= _nextGuidanceTick) then {
						[_uav, _profile] call A3UE_fnc_fpv_holdPattern;
						_nextGuidanceTick = _now + 0.5;
						_nextTargetScanTick = _now + 0.5;
					};
				};

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
							_nextTargetScanTick = _now + ([0.35, 1] select (_wing # 6));
						} else {
							[_target,"SEARCHING"] call _adoptTarget;
							_nextTargetScanTick = _now + ([0.35, 1] select (_wing # 6));
						};
					};
				};

				case "TRACKING": {
					if (_now >= _nextGuidanceTick) then {
						_target = [_uav] call A3UE_fnc_fpv_resolveTarget;
						private _guidanceRevision = _uav getVariable ["A3UE_FPV_targetRevision",0];
                        private _trackBreakDistance = [_profile, "trackBreakDistance", 700] call A3UE_fnc_fpv_profileValue;

						if (isNull _target || {!alive _target} || {(_uav distance _target) > _trackBreakDistance}) then {
                            if (isNull _target || {!alive _target}) then {call _revalidateTarget;} else {
                                [_target,"TRACKING",_guidanceRevision] call _loseTarget;
                            };
						} else {
							[_uav, _target, _profile] call _storeTargetMemory;
                            // LT-2: one drone attacks a target at a time; the others watch it from a ring and go in
                            // after the outcome (attackSlot). A3UE_FPV_attackersPerTarget = 0: every drone attacks.
                            private _slot = [_uav, _target] call A3UE_fnc_fpv_attackSlot;
                            private _role = ["OVERWATCH", "ATTACK"] select ((_slot # 0) == "ATTACK");
                            // Published on change only (clearTarget resets it with the target).
                            if (_role != (_uav getVariable ["A3UE_FPV_attackRole", ""])) then {
                                _uav setVariable ["A3UE_FPV_attackRole", _role, true];
                                _nextRetargetTick = _now + 4 + ((_slot # 1) mod 4);
                            };
                            _wingRole = _role;
                            private _entered = false;
                            private _retargeted = false;
                            if (_role == "OVERWATCH") then {
                                _wingHot = false;
                                // Its place on the ring comes from its own lifecycle number, so it keeps it while the queue moves.
                                [_uav, _target, _profile, _controllerIdentity # 0, netId _target, _guidanceRevision] call A3UE_fnc_fpv_overwatch;
                                if ((_wing # 5) && {_now >= _nextRetargetTick}) then {
                                    _nextRetargetTick = _now + 5;
                                    _retargeted = [_target, _guidanceRevision] call _retarget;
                                };
                            } else {
                            // F4-1: sample this engagement's approach profile before the entry gate.
                            [_uav,_target,_controllerIdentity,true] call A3UE_fnc_fpv_attackEngagement;
                            if ([_uav,_target,_profile] call A3UE_fnc_fpv_shouldEnterTerminal) then {
                                _entered = [_target] call _attemptIngress;
                            };
                            if (!_entered && {(_uav getVariable ["A3UE_FPV_mode",""]) == "TRACKING"}) then {
                                private _intercept = [_uav,_target,_profile] call A3UE_fnc_fpv_computeIntercept;
                                _intercept = [_uav,_target,_controllerIdentity,_intercept] call A3UE_fnc_fpv_attackApproach;
                                [_uav,"A3UE_FPV_lastInterceptASL",_intercept] call A3UE_fnc_fpv_publishTelemetry;
                                [_uav, _intercept, _profile, netId _target,_guidanceRevision] call A3UE_fnc_fpv_applyGuidance;
                            };
                            _wingHot = (_uav distance _target) <= 450;
                            };
                            // Attack: 10 passes a second (the AI takes orders every 0.15 s). Overwatch: 2.
                            if (!_retargeted) then {
                                _nextGuidanceTick = _now + (if (_entered) then {0.01} else {[0.05, [0.1, 0.5] select (_role == "OVERWATCH")] select (_wing # 6)});
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
							_nextGuidanceTick = _now + ([0.08, 0.2] select (_wing # 6));
						};
					};

					if (_now >= _nextTargetScanTick && {(_uav getVariable ["A3UE_FPV_mode", "LOST_TARGET"]) isEqualTo "LOST_TARGET"}) then {
						_target = [_uav, _profile, true] call A3UE_fnc_fpv_runLostTarget;
						if (isNull _target) then {
							_nextTargetScanTick = _now + ([0.2, 0.5] select (_wing # 6));
						} else {
							if ([_target,"LOST_TARGET"] call _adoptTarget) then {[_uav, _target, _profile] call _storeTargetMemory;};
							_nextTargetScanTick = _now + ([0.35, 1] select (_wing # 6));
						};
					};
				};

                case "TERMINAL_ATTACK": {
                    // Legacy mode compatibility: no second native terminal movement writer.
                    if (_now >= _nextGuidanceTick) then {
                        _target = [_uav] call A3UE_fnc_fpv_resolveTarget;
                        if (!isNull _target) then {[_target] call _attemptIngress;};
                        _nextGuidanceTick = _now + 0.05;
                    };
                };

				case "TERMINAL_VECTOR": {
					if (_now >= _nextGuidanceTick) then {
						// Valid even if fuse approval leaves a pending/rejected/errored proposal.
						_nextGuidanceTick = _now + 0.01;
						_target = [_uav] call A3UE_fnc_fpv_resolveTarget;
						private _guidanceRevision = _uav getVariable ["A3UE_FPV_targetRevision",0];
                        private _trackBreakDistance = [_profile, "trackBreakDistance", 700] call A3UE_fnc_fpv_profileValue;

						if (isNull _target || {!alive _target} || {(_uav distance _target) > _trackBreakDistance}) then {
                            if (isNull _target || {!alive _target}) then {call _revalidateTarget;} else {
                                [_target,"TERMINAL_VECTOR",_guidanceRevision] call _loseTarget;
                            };
						} else {
							[_target] call _refreshTrajectoryImpact;
                            private _navigation = [_uav,_target,_controllerIdentity] call A3UE_fnc_fpv_targetNavigation;
                            private _currentDistance = if (_navigation isEqualTo []) then {-1} else {(getPosASL _uav) vectorDistance (_navigation # 5)};
							private _enteredAt = _uav getVariable ["A3UE_FPV_terminalVectorEnteredAt", _now];

							private _lastDistance = _uav getVariable ["A3UE_FPV_lastTerminalVectorDistance", _currentDistance];
							if (_lastDistance < 0) then {
								_lastDistance = _currentDistance;
							};
							private _missedPass = _currentDistance >= 0 && {(_now > (_enteredAt + 0.15))} && {(_currentDistance > (_lastDistance + 8))};
                            // F4-2 flip: a close miss pulls up and comes straight back (once per drone) instead
                            // of the wide native reacquire. While it flips the range grows by design.
                            private _flip = ["OFF",""];
                            if (_currentDistance >= 0) then {
                                isNil {_flip = [_uav,_target,_controllerIdentity,_navigation,_lastDistance,_enteredAt] call A3UE_fnc_fpv_attackReversal;};
                            };
                            switch (_flip # 0) do {
                                case "STARTED": {
                                    _missedPass = false;
                                    diag_log format ["[A3UE_FPV] attackPass id=%1 target=%2 outcome=MISSED %3 nowM=%4 next=FLIP",
                                        netId _uav, netId _target, _flip # 1, round _currentDistance];
                                };
                                case "PULL": {_missedPass = false;};
                                case "OVER": {_missedPass = false;};
                                case "REDIVE": {
                                    // The return pass measures its own closest approach and miss.
                                    _missedPass = false;
                                    _lastDistance = _currentDistance;
                                    _uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", -1];
                                    diag_log format ["[A3UE_FPV] attackFlip id=%1 target=%2 result=REDIVE %3", netId _uav, netId _target, _flip # 1];
                                };
                                case "ABORT": {_missedPass = true;};
                            };
							if (_missedPass) then {
                                // F4-1: a genuine miss flies past (no proximity rescue) and is logged once.
                                private _attackSummary = [_uav,_target] call A3UE_fnc_fpv_attackPassSummary;
                                [_target,"TERMINAL_VECTOR",_guidanceRevision,_enteredAt] call _loseTarget;
                                if ((_uav getVariable ["A3UE_FPV_mode",""]) == "LOST_TARGET") then {
                                    if ((_flip # 0) == "ABORT") then {
                                        _uav setVariable ["A3UE_FPV_attackLastMissAt", time];
                                        diag_log format ["[A3UE_FPV] attackFlip id=%1 target=%2 result=ABORT %3", netId _uav, netId _target, _flip # 1];
                                    } else {
                                        if (_attackSummary != "") then {
                                            private _flipWhy = switch (true) do {
                                                case ((_flip # 0) == "OFF"): {"OFF"};
                                                case ((_flip # 1) == ""): {"EARLY"};
                                                default {_flip # 1};
                                            };
                                            _uav setVariable ["A3UE_FPV_attackLastMissAt", time];
                                            diag_log format ["[A3UE_FPV] attackPass id=%1 target=%2 outcome=MISSED %3 nowM=%4 next=REACQUIRE flip=%5",
                                                netId _uav, netId _target, _attackSummary, round _currentDistance, _flipWhy];
                                        };
                                    };
                                };
							} else {
								[_uav, _target, _profile] call _storeTargetMemory;
								private _guidanceAt = if (_qa) then {diag_tickTime} else {0};
                                private _planning = [];
                                private _driven = false;
                                // LT-1: plan, step and progress share one unscheduled slice. Under a
                                // saturated scheduler a suspension between them aged the plan past its
                                // 0.1/0.25 s and 2 m freshness gates, so the step was refused (no write).
                                isNil {
                                _planning = [_uav,_target,_profile,_generation,_controllerIdentity] call A3UE_fnc_fpv_prepareTrajectory;
                                _driven = (_planning # 0) != -2 && {[_uav, _target, _profile, _generation, _controllerIdentity] call A3UE_fnc_fpv_runTerminalVector};
                                if (_driven) then {
                                    // Progress belongs only to that exact plan and active steering episode.
                                    isNil {
                                        if ([_uav,_controllerIdentity] call A3UE_fnc_fpv_canActuate
                                            && {(_uav getVariable ["A3UE_FPV_mode",""]) == "TERMINAL_VECTOR"}
                                            && {(_uav getVariable ["A3UE_FPV_targetNetId",""]) == netId _target}
                                            && {(_uav getVariable ["A3UE_FPV_terminalVectorEnteredAt",-1]) == _enteredAt}
                                            && {(_uav getVariable ["A3UE_FPV_targetRevision",0]) == _guidanceRevision}
                                            && {_currentDistance >= 0} && {([_uav] call A3UE_fnc_fpv_resolveTarget) isEqualTo _target}
                                            && {(_uav getVariable ["A3UE_FPV_trajectory",[]]) isEqualTo (_planning # 2)}
                                            && {!((_uav getVariable ["A3UE_FPV_linkModel","RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState","OK"]) == "EW_DENIED"})}) then {
                                            _uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", _lastDistance min _currentDistance];
                                        };
                                    };
								};
                                };
								if (_qa) then {[_uav, "GUIDANCE_WORK", [diag_tickTime - _guidanceAt, "VECTOR"]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
                                if (!_driven) then {
                                    // LT-1 attackPass diagnostics: a dive pass refused before any write.
                                    private _passRecord = _uav getVariable ["A3UE_FPV_attackPass", createHashMap];
                                    if (_passRecord isEqualType createHashMap && {count _passRecord > 0}) then {
                                        private _stats = _passRecord getOrDefault ["steps", [0, 0, 0, 0, 0]];
                                        _stats set [3, (_stats # 3) + 1];
                                        _passRecord set ["steps", _stats];
                                    };
                                    [_target,_guidanceRevision,_enteredAt] call _restoreInvalidNavigation;
                                };

								if ([_target,_guidanceRevision] call _evaluateFuse) then {
									[_target,_guidanceRevision] call _tryStrike;
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

	// Ignore inactive scans/radio; keep *due* active work and sample after this pass.
	private _activeMode = _uav getVariable ["A3UE_FPV_mode", "IDLE"];
	if (_activeMode != "TRACKING") then {call _clearTrackingOrderContext;};
	if (_qa && {_activeMode != _modeAtEntry}) then {[_uav, "MODE", [_modeAtEntry, _activeMode,
		_externalControl, _linkState, _uav getVariable ["A3UE_FPV_engagementFailureReason", ""]]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
	private _deadlines = [_nextGuidanceTick];
	if (_activeMode in ["SEARCHING", "LOST_TARGET"]) then {_deadlines pushBack _nextTargetScanTick;};
	if (!_externalControl) then {_deadlines pushBack _nextLinkEvalTick;};
	_sleepTime = [time, _deadlines] call A3UE_fnc_fpv_controllerSleep;
	if (_qa) then {[_uav, "LOOP", [_loopAt, diag_tickTime - _loopAt, time, _nextGuidanceTick,
		_nextTargetScanTick, _nextLinkEvalTick, _sleepTime, _nextStrikeRetryTick, _externalControl,
		[_uav] call A3UE_fnc_fpv_isSiteDroneActive]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};

	_tickSleep = _sleepTime;
	if !(_activeMode in ["TRACKING", "TERMINAL_ATTACK", "TERMINAL_VECTOR"]) then {_wingRole = "";};
	// LT-2: an attacking drone (diving, or cleared and within 450 m of its target) is ticked
	// by the frame director; every other drone stays with the scheduled pacer.
	private _hot = (_wing # 0) && {!isNil "A3UE_FPV_directorHandler"}
		&& {_activeMode in ["TERMINAL_VECTOR", "TERMINAL_ATTACK"] || {_activeMode == "TRACKING" && {_wingRole == "ATTACK"} && {_wingHot}}};
	_state set ["hot", _hot];
	if (_hot && {!(_state get "listed")}) then {
		_state set ["listed", true];
		A3UE_FPV_directorStates pushBack _state;
	};
};

if (!_running) then {
isNil {
	if (!isNull _uav && {local _uav} && {(_uav getVariable ["A3UE_FPV_controllerGeneration", -1]) == _generation}
        && {(_uav getVariable ["A3UE_FPV_controllerIdentity", []]) isEqualTo _controllerIdentity}) then {
		if (_uav getVariable ["A3UE_FPV_terminalSteeringActive", false]) then {
			[_uav] call _restoreTerminalVectorControl;
		};

		// LT-2: a stopped controller leaves the attack board (its attack has ended).
		[_uav, "STOPPED"] call A3UE_fnc_fpv_attackRelease;
		_uav setVariable ["A3UE_FPV_controllerRunning", false];
		call _clearTrackingOrderContext;
		call _clearTerminalPoseContext;
		_uav setVariable ["A3UE_FPV_controllerHandle", scriptNull];
		// Server-issued identity is invalidated by terminal settlement/new claims.
		_uav setVariable ["A3UE_FPV_terminalSteeringActive", false, true];
	};
};
	_state set ["running", false];
	_state set ["hot", false];
};

// Controller locals for the next tick.
_state set ["nextGuidance", _nextGuidanceTick];
_state set ["nextScan", _nextTargetScanTick];
_state set ["nextLink", _nextLinkEvalTick];
_state set ["nextStrikeRetry", _nextStrikeRetryTick];
_state set ["nextTargetability", _nextTargetabilityCheckAt];
_state set ["targetabilitySuspended", _targetabilitySuspended];
_state set ["aiRecoveryPending", _terminalAIRecoveryPending];
_state set ["impactCacheReady", _impactCacheReady];
_state set ["nextRetarget", _nextRetargetTick];
_state set ["role", _wingRole];
_state set ["wingHot", _wingHot];
_state set ["dueAt", time + _tickSleep];
_state set ["tickedAt", diag_tickTime];

[_running, _tickSleep]
