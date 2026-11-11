params [["_uav", objNull], ["_resumeGeneration", -1]];

if (isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}) exitWith {false};
if (isNull _uav || {!alive _uav} || {_uav getVariable ["A3UE_FPV_cleanupPending", false]}) exitWith {false};
if !(_uav getVariable ["A3UE_FPV_managed", false]) exitWith {false};

// Retry optional binding discovery without adding a waiter or another publisher.
call A3UE_fnc_fpv_installTargetabilityAdapters;
call A3UE_fnc_fpv_installCrocusSignalAdapter;
call A3UE_fnc_fpv_installUaPayloadAdapter;
call A3UE_fnc_fpv_installKvnPathAdapter;
call A3UE_fnc_fpv_installKvnArchiveAdapter;

private _localityEhId = _uav getVariable ["A3UE_FPV_localityEH", -1];
if (_localityEhId < 0) then {
	_localityEhId = _uav addEventHandler ["Local", {
		params ["_vehicle", "_isLocal"];

		if (_isLocal) then {
			if (_vehicle getVariable ["A3UE_FPV_managed", false]) then {
				[_vehicle] spawn A3UE_fnc_fpv_bootstrapLocal;
			};
		} else {
            [_vehicle, "release", []] call A3UE_fnc_fpv_sendLifecycle;
			private _drones = missionNamespace getVariable ["A3UE_FPV_targetabilityDrones", createHashMap];
			private _id = _vehicle getVariable ["A3UE_FPV_netId", ""];
			if ((_drones getOrDefault [_id, objNull]) isEqualTo _vehicle) then {_drones deleteAt _id;};
			_vehicle setVariable ["A3UE_FPV_controllerGeneration", 1 + (_vehicle getVariable ["A3UE_FPV_controllerGeneration", 0])];
			_vehicle setVariable ["A3UE_FPV_fiberGeneration", 1 + (_vehicle getVariable ["A3UE_FPV_fiberGeneration", 0])];
			// terminate is deferred until the next scheduler pass; generations invalidate stale resumes.
			{
				private _handle = _vehicle getVariable [_x, scriptNull];
				if !(scriptDone _handle) then {terminate _handle;};
				_vehicle setVariable [_x, scriptNull];
			} forEach ["A3UE_FPV_controllerHandle", "A3UE_FPV_fiberTrailHandle", "A3UE_FPV_claimRetryHandle"];
			_vehicle setVariable ["A3UE_FPV_controllerRunning", false];
            _vehicle setVariable ["A3UE_FPV_lifecycleTicket", []];
            _vehicle setVariable ["A3UE_FPV_lifecycleTicketIdentity", []];
            _vehicle setVariable ["A3UE_FPV_fiberAdoptGeneration", -1];
			_vehicle setVariable ["A3UE_FPV_fiberTrailRunning", false];
			_vehicle setVariable ["A3UE_FPV_terminalVectorLastUpdateAt", -1];
			_vehicle setVariable ["A3UE_FPV_terminalPoseContext", []];
			_vehicle setVariable ["A3UE_FPV_terminalSteeringState", []];
			_vehicle setVariable ["A3UE_FPV_trajectory",[]];
        _vehicle setVariable ["A3UE_FPV_navigation",[]];
			_vehicle setVariable ["A3UE_FPV_trajectoryAttemptAt",-1];
			_vehicle setVariable ["A3UE_FPV_steeringReconstruction",[]];
            _vehicle setVariable ["A3UE_FPV_nativeControl",[]];
		};
	}];

	_uav setVariable ["A3UE_FPV_localityEH", _localityEhId];
};

if (!local _uav) exitWith {false};

private _generation = _resumeGeneration;
// Scheduled bootstrap calls can be preempted, so claim the local controller without suspension.
isNil {
	// A promoted KVN must never resume its native claim worker after managed startup.
	_uav setVariable ["A3UE_FPV_nativePromoted", true];
	private _nativeRetry = _uav getVariable ["A3UE_FPV_nativeClaimRetry", scriptNull];
	if !(scriptDone _nativeRetry) then {terminate _nativeRetry;};
	_uav setVariable ["A3UE_FPV_nativeClaimRetry", scriptNull];
	if (_resumeGeneration < 0 && {local _uav} && {_uav getVariable ["A3UE_FPV_managed", false]} && {!(_uav getVariable ["A3UE_FPV_controllerRunning", false])}) then {
		_generation = 1 + ((_uav getVariable ["A3UE_FPV_controllerGeneration", 0]) max (_uav getVariable ["A3UE_FPV_nativeGeneration", -1]));
		_uav setVariable ["A3UE_FPV_controllerGeneration", _generation];
		_uav setVariable ["A3UE_FPV_controllerRunning", true];
		_uav setVariable ["A3UE_FPV_lifecycleClaimFailure", ""];
	};
	// Local Crocus settings reconciliation uses this cache, not another vehicle scan.
	if (local _uav && {_uav getVariable ["A3UE_FPV_managed", false]}
		&& {(_uav getVariable ["A3UE_FPV_vendorId", ""]) == "armafpv"}
		&& {netId _uav == (_uav getVariable ["A3UE_FPV_netId", ""])}) then {
		if (isNil "A3UE_FPV_targetabilityDrones") then {A3UE_FPV_targetabilityDrones = createHashMap;};
		A3UE_FPV_targetabilityDrones set [netId _uav, _uav];
		if ((_uav getVariable ["A3UE_FPV_targetabilityDeletedEH", -1]) < 0) then {
			private _eh = _uav addEventHandler ["Deleted", {
				params ["_vehicle"];
				private _drones = missionNamespace getVariable ["A3UE_FPV_targetabilityDrones", createHashMap];
				private _id = _vehicle getVariable ["A3UE_FPV_netId", ""];
				if ((_drones getOrDefault [_id, objNull]) isEqualTo _vehicle) then {_drones deleteAt _id;};
			}];
			_uav setVariable ["A3UE_FPV_targetabilityDeletedEH", _eh];
		};
	};
};
if (_resumeGeneration < 0) exitWith {
    // Request/worker reservation is atomic even when two scheduled callbacks overlap.
    isNil {
        private _claimGeneration = _uav getVariable ["A3UE_FPV_controllerGeneration", -1];
        if (!local _uav || {!alive _uav} || {!(_uav getVariable ["A3UE_FPV_managed", false])}) exitWith {};
        if ((_uav getVariable ["A3UE_FPV_claimRetryGeneration", -2]) == _claimGeneration
            && {scriptDone (_uav getVariable ["A3UE_FPV_claimRetryHandle", scriptNull])}
            && {(_uav getVariable ["A3UE_FPV_lifecycleClaimFailure", ""]) in ["BROKER_TIMEOUT", "STARTUP_TIMEOUT"]}) exitWith {};
        private _current = [_uav, _claimGeneration] call A3UE_fnc_fpv_hasCurrentLifecycle;
        if (_current) then {
            [_uav, _claimGeneration] call A3UE_fnc_fpv_bootstrapLocal;
        } else {
            if (diag_tickTime >= (_uav getVariable ["A3UE_FPV_nextClaimRequestAt", -1])) then {
                _uav setVariable ["A3UE_FPV_nextClaimRequestAt", diag_tickTime + 1];
                if ((_uav getVariable ["A3UE_FPV_lifecycleId", -1]) >= 0) then {
                    private _request = [_uav, _uav getVariable ["A3UE_FPV_lifecycleEpisode", 0], _claimGeneration];
                    if (isServer) then {_request call A3UE_fnc_fpv_claimLifecycle;} else {_request remoteExecCall ["A3UE_fnc_fpv_claimLifecycle", 2];};
                };
            };
        };
        private _ready = [_uav, _claimGeneration] call A3UE_fnc_fpv_hasCurrentLifecycle
            && {(_uav getVariable ["A3UE_FPV_startedGeneration", -1]) == _claimGeneration}
            && {!(scriptDone (_uav getVariable ["A3UE_FPV_controllerHandle", scriptNull]))};
        if ((_uav getVariable ["A3UE_FPV_claimRetryGeneration", -2]) != _claimGeneration) then {
            private _retry = _uav getVariable ["A3UE_FPV_claimRetryHandle", scriptNull];
            if !(scriptDone _retry) then {terminate _retry;};
            _uav setVariable ["A3UE_FPV_claimRetryHandle", scriptNull];
        };
        if (scriptDone (_uav getVariable ["A3UE_FPV_claimRetryHandle", scriptNull])
            && {(_uav getVariable ["A3UE_FPV_claimRetryGeneration", -2]) != _claimGeneration}
            && {!_ready}) then {
            _uav setVariable ["A3UE_FPV_claimRetryGeneration", _claimGeneration];
            _uav setVariable ["A3UE_FPV_claimRetryHandle", [_uav, _claimGeneration] spawn {
                params ["_vehicle", "_generation"];
                for "_attempt" from 1 to 5 do {
                    sleep 1;
                    if (isNull _vehicle || {!local _vehicle} || {!alive _vehicle}
                        || {!(_vehicle getVariable ["A3UE_FPV_managed", false])}
                        || {(_vehicle getVariable ["A3UE_FPV_controllerGeneration", -1]) != _generation}
                        || {_vehicle getVariable ["A3UE_FPV_cleanupPending", false]}
                        || {[_vehicle, _generation] call A3UE_fnc_fpv_hasCurrentLifecycle
                            && {(_vehicle getVariable ["A3UE_FPV_startedGeneration", -1]) == _generation}
                            && {!(scriptDone (_vehicle getVariable ["A3UE_FPV_controllerHandle", scriptNull]))}}) exitWith {};
                    [_vehicle] call A3UE_fnc_fpv_bootstrapLocal;
                };
                if (!isNull _vehicle && {local _vehicle} && {alive _vehicle}
                    && {_vehicle getVariable ["A3UE_FPV_managed", false]}
                    && {!(_vehicle getVariable ["A3UE_FPV_cleanupPending", false])}
                    && {(_vehicle getVariable ["A3UE_FPV_controllerGeneration", -1]) == _generation}
                    && {!([_vehicle, _generation] call A3UE_fnc_fpv_hasCurrentLifecycle
                        && {(_vehicle getVariable ["A3UE_FPV_startedGeneration", -1]) == _generation}
                        && {!(scriptDone (_vehicle getVariable ["A3UE_FPV_controllerHandle", scriptNull]))})}) then {
                    private _reason = if ([_vehicle, _generation] call A3UE_fnc_fpv_hasCurrentLifecycle) then {"STARTUP_TIMEOUT"} else {"BROKER_TIMEOUT"};
                    _vehicle setVariable ["A3UE_FPV_lifecycleClaimFailure", _reason];
                    diag_log ["A3UE_FPV_STARTUP_FAILED", netId _vehicle, _generation, _reason];
                };
            }];
        };
    };
    true
};
if (_resumeGeneration != (_uav getVariable ["A3UE_FPV_controllerGeneration", -1]) || {!([_uav, _resumeGeneration] call A3UE_fnc_fpv_hasCurrentLifecycle)}) exitWith {false};
if ((_uav getVariable ["A3UE_FPV_startedGeneration", -1]) == _resumeGeneration) exitWith {
    private _ready = !(scriptDone (_uav getVariable ["A3UE_FPV_controllerHandle", scriptNull]));
    if (!_ready) then {_uav setVariable ["A3UE_FPV_lifecycleClaimFailure", "CONTROLLER_STOPPED"];};
    _ready
};

[_uav] call A3UE_fnc_fpv_applyCompatInit;

if ((_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) isEqualTo "FIBER_VISUAL") then {
	[_uav] call A3UE_fnc_fpv_startFiberTrailCompat;
};

private _impactProfile = [_uav] call A3UE_fnc_fpv_getProfile;
private _defaultImpactMode = _impactProfile getOrDefault ["terminalImpactMode", "NONE"];
if !(_defaultImpactMode isEqualType "") then {
	_defaultImpactMode = "NONE";
};

private _started = false;
// Publish startup state and retain the handle only while this owner still holds the claim.
isNil {
	if (alive _uav && {local _uav} && {_uav getVariable ["A3UE_FPV_managed", false]} && {(_uav getVariable ["A3UE_FPV_controllerGeneration", -1]) == _generation} && {_uav getVariable ["A3UE_FPV_controllerRunning", false]}
        && {[_uav, _generation] call A3UE_fnc_fpv_hasCurrentLifecycle}
        && {(_uav getVariable ["A3UE_FPV_startedGeneration", -1]) != _generation}
        && {scriptDone (_uav getVariable ["A3UE_FPV_controllerHandle", scriptNull])}) then {
		if ((_uav getVariable ["A3UE_FPV_mode", ""]) isEqualTo "") then {
			_uav setVariable ["A3UE_FPV_mode", "IDLE", true];
		};

		if !((_uav getVariable ["A3UE_FPV_mode", "IDLE"]) in ["IDLE", "SEARCHING", "TRACKING", "LOST_TARGET", "TERMINAL_ATTACK", "TERMINAL_VECTOR"]) then {
			_uav setVariable ["A3UE_FPV_mode", "IDLE", true];
		};

		_uav setVariable ["A3UE_FPV_cachedLinkState", _uav getVariable ["A3UE_FPV_linkState", "OK"], true];
		_uav setVariable ["A3UE_FPV_cachedSignalStrength", _uav getVariable ["A3UE_FPV_signalStrength", 1], true];
		_uav setVariable ["A3UE_FPV_nextLinkEvalAt", 0];
        _uav setVariable ["A3UE_FPV_reportedControl", false];
        _uav setVariable ["A3UE_FPV_startedGeneration", _generation];
        // A valid same-owner replacement adopts only restoration responsibility, never old steering.
        // No AI writes while directly controlled; the controller restores on admitted release.
        private _native = _uav getVariable ["A3UE_FPV_nativeControl",[]];
        if (count _native == 3) then {
            if ((_native # 0 # 0) == (_uav getVariable ["A3UE_FPV_lifecycleId",-1])
                && {(_native # 0 # 1) == clientOwner}) then {
                _native = +_native;
                _native set [0,+(_uav getVariable ["A3UE_FPV_controllerIdentity",[]])];
                _uav setVariable ["A3UE_FPV_nativeControl",_native];
            } else {_uav setVariable ["A3UE_FPV_nativeControl",[]];};
        };
        _uav setVariable ["A3UE_FPV_lifecycleClaimFailure", ""];
		_uav setVariable ["A3UE_FPV_nextDetonationRequestAt", 0];
		_uav setVariable ["A3UE_FPV_telemetryNextAt", createHashMap];
		_uav setVariable ["A3UE_FPV_siteCandidateCache", []];
		_uav setVariable ["A3UE_FPV_localCandidateCache", []];
		_uav setVariable ["A3UE_FPV_lastLinkEvalPosATL", getPosATL _uav];
		_uav setVariable ["A3UE_FPV_lastJammerEvalAt", time];
		_uav setVariable ["A3UE_FPV_terminalSteeringActive", false, true];

		private _vectorModeActive = (_uav getVariable ["A3UE_FPV_mode", "IDLE"]) isEqualTo "TERMINAL_VECTOR";
		private _vectorSpeedSeed = if (_vectorModeActive) then {
			(vectorMagnitude (velocity _uav)) * 3.6
		} else {
			-1
		};

		// Rebase owner-local pass history on every claim; a returning owner may retain an older pass.
		// The controller starts grace at its first valid distance sample, using this owner's clock.
		_uav setVariable ["A3UE_FPV_terminalVectorEnteredAt", -1];
		_uav setVariable ["A3UE_FPV_terminalVectorEntrySpeed", _uav getVariable ["A3UE_FPV_terminalVectorEntrySpeed", _vectorSpeedSeed], true];
		_uav setVariable ["A3UE_FPV_terminalVectorEntryDistance", _uav getVariable ["A3UE_FPV_terminalVectorEntryDistance", -1], true];
		_uav setVariable ["A3UE_FPV_terminalVectorCurrentSpeed", _uav getVariable ["A3UE_FPV_terminalVectorCurrentSpeed", _vectorSpeedSeed], true];
		_uav setVariable ["A3UE_FPV_terminalVectorTargetSpeed", _uav getVariable ["A3UE_FPV_terminalVectorTargetSpeed", _vectorSpeedSeed], true];
		_uav setVariable ["A3UE_FPV_terminalVectorAccelApplied", _uav getVariable ["A3UE_FPV_terminalVectorAccelApplied", -1], true];
		_uav setVariable ["A3UE_FPV_terminalVectorAlignment", _uav getVariable ["A3UE_FPV_terminalVectorAlignment", -1], true];
		_uav setVariable ["A3UE_FPV_terminalVectorDt", _uav getVariable ["A3UE_FPV_terminalVectorDt", (if (_vectorModeActive) then {0.02} else {-1})], true];
		_uav setVariable ["A3UE_FPV_terminalVectorSpeedJump", _uav getVariable ["A3UE_FPV_terminalVectorSpeedJump", -1], true];
		_uav setVariable ["A3UE_FPV_terminalVectorLastUpdateAt", -1];
		_uav setVariable ["A3UE_FPV_terminalPoseContext", []];
		_uav setVariable ["A3UE_FPV_terminalSteeringState", []];
		_uav setVariable ["A3UE_FPV_trajectory",[]];
        _uav setVariable ["A3UE_FPV_navigation",[]];
		_uav setVariable ["A3UE_FPV_trajectoryAttemptAt",-1];
		_uav setVariable ["A3UE_FPV_steeringReconstruction",[]];
		_uav setVariable ["A3UE_FPV_lastTerminalVectorDistance", -1];
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

		// Controller identity/owner is issued and published by the server broker.
		private _handle = [_uav, _generation] spawn A3UE_fnc_fpv_runController;
		_uav setVariable ["A3UE_FPV_controllerHandle", _handle];
		_started = true;
	};
};

_started
