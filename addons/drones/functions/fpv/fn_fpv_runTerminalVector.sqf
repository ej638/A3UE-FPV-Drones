params [["_uav", objNull], ["_target", objNull], ["_profile", createHashMap],
	["_generation", -1], ["_controllerIdentity", []]];

if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};

if (isNull _uav || {isNull _target}) exitWith {false};
if (!local _uav) exitWith {false};

// Optional arguments preserve direct callers; bind once, never rebind a stale controller at the write site.
if (_generation < 0) then {_generation = _uav getVariable ["A3UE_FPV_controllerGeneration", -1];};
if (count _this < 5) then {_controllerIdentity = +(_uav getVariable ["A3UE_FPV_controllerIdentity", []]);};
if (!(_controllerIdentity isEqualType []) || {count _controllerIdentity != 4} || {(_controllerIdentity findIf {!(_x isEqualType 0) || {!finite _x} || {_x < 0} || {_x != floor _x}}) >= 0}
	|| {!(_controllerIdentity isEqualTo [_uav getVariable ["A3UE_FPV_lifecycleId", -1], clientOwner,
		_uav getVariable ["A3UE_FPV_lifecycleEpisode", -1], _generation])}
	|| {!([_uav, _generation] call A3UE_fnc_fpv_hasCurrentLifecycle)}) exitWith {false};
// Capture exact intent/state before scheduled planning; stale work cannot clear a newer tuple.
private _readSteeringKey = {
    [+_controllerIdentity, _target, _uav getVariable ["A3UE_FPV_targetNetId", ""],
        _uav getVariable ["A3UE_FPV_mode", ""],
        [_uav getVariable ["A3UE_FPV_siteEpoch", ""], _uav getVariable ["A3UE_FPV_siteMarker", ""],
            _uav getVariable ["A3UE_FPV_siteSide", sideUnknown]],
        _uav getVariable ["A3UE_FPV_terminalVectorEnteredAt", -1],
        ["TARGET",_target,_uav getVariable ["A3UE_FPV_targetRevision",0]],
        _uav getVariable ["A3UE_FPV_supportName", ""], _uav getVariable ["A3UE_FPV_rivalEventId", ""]]
};
private _steeringKey = call _readSteeringKey;
private _steeringBefore = _uav getVariable ["A3UE_FPV_terminalSteeringState", []];
private _poseBefore = _uav getVariable ["A3UE_FPV_terminalPoseContext", []];
private _clearSteeringSnapshot = {
    isNil {
        if (local _uav && {(_uav getVariable ["A3UE_FPV_controllerGeneration", -1]) == _generation}
            && {(_uav getVariable ["A3UE_FPV_controllerIdentity", []]) isEqualTo _controllerIdentity}
            && {(call _readSteeringKey) isEqualTo _steeringKey}
            && {(_uav getVariable ["A3UE_FPV_terminalSteeringState", []]) isEqualTo _steeringBefore}) then {
            _uav setVariable ["A3UE_FPV_terminalSteeringState", []];
            _uav setVariable ["A3UE_FPV_terminalVectorLastUpdateAt", -1];
            if ((_uav getVariable ["A3UE_FPV_terminalPoseContext", []]) isEqualTo _poseBefore) then {
                _uav setVariable ["A3UE_FPV_terminalPoseContext", []];
            };
        };
    };
};
if ([_uav] call A3UE_fnc_fpv_isExternallyControlled
    || {(_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) isEqualTo "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState", "OK"]) == "EW_DENIED"}}) exitWith {
    call _clearSteeringSnapshot; false
};
private _planningAt = time;
private _planningObservedAt = diag_tickTime;
private _validVector = {
    _this isEqualType [] && {count _this == 3} && {(_this findIf {!(_x isEqualType 0) || {!finite _x} || {abs _x > 1e6}}) < 0}
};

private _navigation = [_uav,_target,_controllerIdentity] call A3UE_fnc_fpv_targetNavigation;
if (_navigation isEqualTo []) exitWith {call _clearSteeringSnapshot; false};
// F4-1 pilot model moves only the steering point/velocity; key and reference unchanged.
_navigation = [_uav,_target,_controllerIdentity,_navigation] call A3UE_fnc_fpv_attackNavigation;
private _navigationPoint = _navigation # 3;
private _trajectoryBefore = _uav getVariable ["A3UE_FPV_trajectory", []];
private _trajectoryKey = [_steeringKey # 0,_steeringKey # 1,_steeringKey # 2,_steeringKey # 4,
    _steeringKey # 6,_steeringKey # 7,_steeringKey # 8];

private _limits = [_profile] call A3UE_fnc_fpv_trajectoryLimits;
// F4-2 flip envelope (pull-up and over the top); unchanged outside a flip.
_limits = [_uav,_target,_controllerIdentity,_profile,_limits] call A3UE_fnc_fpv_attackLimits;
private _uavPosAsl = getPosASL _uav;
if !(_uavPosAsl call _validVector) exitWith {call _clearSteeringSnapshot; false};
private _currentDistance = _uavPosAsl vectorDistance (_navigation # 5);
private _terminalVectorEntryDistance = _uav getVariable ["A3UE_FPV_terminalVectorEntryDistance", _currentDistance];
private _follow = [];
private _curveCurrent = count _trajectoryBefore == 7 && {(_trajectoryBefore # 0) isEqualTo _trajectoryKey}
    && {_planningAt >= (_trajectoryBefore # 1)} && {_planningAt - (_trajectoryBefore # 1) <= 0.25}
    && {_planningObservedAt >= (_trajectoryBefore # 2)} && {_planningObservedAt - (_trajectoryBefore # 2) <= 0.5}
    && {_navigationPoint vectorDistance (_trajectoryBefore # 4) <= 8};
if (_curveCurrent) then {_follow = [_trajectoryBefore # 6,_uavPosAsl,vectorMagnitude (velocity _uav),_limits] call A3UE_fnc_fpv_followTrajectory;};
private _delta = _navigationPoint vectorDiff _uavPosAsl;
private _normalizedAimVector = if (vectorMagnitude _delta >= 0.01) then {vectorNormalized _delta} else {[1,0,0]};
if !(_follow isEqualTo []) then {_normalizedAimVector = _follow # 0;};
private _qaMove = !isNil "A3UE_FPV_QA_sink" && {_uav getVariable ["A3UE_FPV_QA_capture", false]};
// D1 actuator remains below; logical planning commits with its original admission in one slice.
private _applied = false;
isNil {
if (!([_uav, _controllerIdentity] call A3UE_fnc_fpv_canActuate) || {!alive _uav} || {!local _uav} || {!(_uav getVariable ["A3UE_FPV_managed", false])}
	|| {isNull _target} || {!alive _target} || {objectFromNetId (netId _target) isNotEqualTo _target}
    || {([_uav] call A3UE_fnc_fpv_resolveTarget) isNotEqualTo _target}
	|| {!(_uav getVariable ["A3UE_FPV_controllerRunning", false])} || {_uav getVariable ["A3UE_FPV_detonating", false]}
	|| {(_uav getVariable ["A3UE_FPV_controllerGeneration", -1]) != _generation}
	|| {!((_uav getVariable ["A3UE_FPV_controllerIdentity", []]) isEqualTo _controllerIdentity)}
	|| {!([_uav, _generation] call A3UE_fnc_fpv_hasCurrentLifecycle)}
	|| {(_uav getVariable ["A3UE_FPV_mode", ""]) != "TERMINAL_VECTOR"}
	|| {(_uav getVariable ["A3UE_FPV_targetNetId", ""]) != netId _target}
	|| {[_uav] call A3UE_fnc_fpv_isExternallyControlled}
	|| {(_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState", "OK"]) == "EW_DENIED"}}) exitWith {
    call _clearSteeringSnapshot;
    false
};
if (!((call _readSteeringKey) isEqualTo _steeringKey)
    || {!((_uav getVariable ["A3UE_FPV_terminalSteeringState", []]) isEqualTo _steeringBefore)}
    || {time < _planningAt} || {time - _planningAt > 0.25}
    || {diag_tickTime < _planningObservedAt} || {diag_tickTime - _planningObservedAt > 0.5}) exitWith {};
if (!((_steeringKey # 5) isEqualType 0) || {!finite (_steeringKey # 5)} || {(_steeringKey # 5) < 0}) exitWith {call _clearSteeringSnapshot;};
private _currentNavigation = [_uav,_target,_controllerIdentity] call A3UE_fnc_fpv_targetNavigation;
_currentNavigation = [_uav,_target,_controllerIdentity,_currentNavigation] call A3UE_fnc_fpv_attackNavigation;
if (_currentNavigation isEqualTo [] || {!((_currentNavigation # 0) isEqualTo (_navigation # 0))}
    || {!((_uav getVariable ["A3UE_FPV_trajectory",[]]) isEqualTo _trajectoryBefore)}
    || {(getPosASL _uav) vectorDistance _uavPosAsl > 2}) exitWith {};
// A deferred/stale/unfollowable curve always has current-target continuation.
if (_curveCurrent && {time - (_trajectoryBefore # 1) > 0.25
    || {diag_tickTime - (_trajectoryBefore # 2) > 0.5}
    || {(_currentNavigation # 3) vectorDistance (_trajectoryBefore # 4) > 8}}) then {_follow = [];};
_navigation = _currentNavigation;
_navigationPoint = _navigation # 3;
private _permission = [_uav,_target,false,[],true] call A3UE_fnc_fpv_supportEngagementReason;
if !(_permission in ["","NO_VISIBLE_TARGET"]) exitWith {};
private _nativeBefore = _uav getVariable ["A3UE_FPV_nativeControl",[]];
if (!(_nativeBefore isEqualTo []) && {count _nativeBefore != 3
    || {!((_nativeBefore # 0) isEqualTo _controllerIdentity)}
    || {!(((_nativeBefore # 1) apply {_x # 0}) isEqualTo (crew _uav))}}) exitWith {};
private _vectorUpdateAt = time;
private _observedAt = diag_tickTime;
private _status = [_steeringBefore, _steeringKey, _vectorUpdateAt, _observedAt,
	(missionNamespace getVariable ["A3UE_FPV_loadTolerantDive", true]) isNotEqualTo false] call A3UE_fnc_fpv_terminalSteeringStatus;
private _resetReason = _status # 0;
if (_resetReason == "CLOCK_INVALID") exitWith {call _clearSteeringSnapshot;};
private _dt = _status # 1;
// LT-1: LATE continues the logical state; STALL/GAP/INIT/KEY re-seed from the real airframe.
private _isFirstVectorTick = !(_resetReason in ["STEP", "DUPLICATE", "LATE"]);
private _currentVelocity = velocity _uav;
if !(_currentVelocity call _validVector) exitWith {call _clearSteeringSnapshot;};
private _currentSpeedBudget = vectorMagnitude _currentVelocity;
private _state = if (_isFirstVectorTick) then {
    private _seedDir = if (_currentSpeedBudget >= 0.01) then {vectorNormalized _currentVelocity} else {vectorDir _uav};
    if (!(_seedDir call _validVector) || {vectorMagnitude _seedDir < 1e-6}) then {_seedDir = +_normalizedAimVector;};
    _seedDir = vectorNormalized _seedDir;
    private _seedUp = if (abs (_seedDir # 2) < 0.95) then {[0,0,1]} else {[0,1,0]};
    _seedUp = vectorNormalized (_seedUp vectorDiff (_seedDir vectorMultiply (_seedUp vectorDotProduct _seedDir)));
    private _serial = _uav getVariable ["A3UE_FPV_terminalSteeringSerial", 0];
    if (!(_serial isEqualType 0) || {!finite _serial} || {_serial < 0} || {_serial != floor _serial} || {_serial >= 1e6}) then {_serial = 0;};
    _serial = _serial + 1;
    _uav setVariable ["A3UE_FPV_terminalSteeringSerial", _serial];
    [+_steeringKey, _vectorUpdateAt, _observedAt, _seedDir, _seedUp, _currentSpeedBudget, [0,0,0], _serial, _resetReason, 0, +_normalizedAimVector, +_currentVelocity]
} else {+_steeringBefore};
private _normalizedCurrentDir = _state # 3;
private _speedBudgetNow = _state # 5;
private _motion = [_state,_follow,_uavPosAsl,_navigationPoint,_navigation # 4,_currentSpeedBudget,_limits,_dt] call A3UE_fnc_fpv_trajectorySteering;
private _step = _motion # 0;
_normalizedAimVector = _motion # 1;
private _desiredTargetSpeed = _motion # 2;
private _alignment = ((_normalizedCurrentDir vectorDotProduct _normalizedAimVector) max -1) min 1;
if (_step isEqualTo []) exitWith {call _clearSteeringSnapshot;};
private _blendedDir = _step # 0;
private _up = _step # 1;
private _nextSpeedBudget = _step # 2;
private _appliedAcceleration = _step # 4;
private _appliedSpeedDelta = _nextSpeedBudget - _speedBudgetNow;
private _desiredVelocity = if (_dt > 0) then {_blendedDir vectorMultiply _nextSpeedBudget} else {+(_state # 11)};
// No post-integration velocity overlay: the pose intent and velocity use the same frame.
// Inherited envelope violations converge through the same bounded integrator.
_uav setVariable ["A3UE_FPV_navigation",_navigation];
_uav setVariable ["A3UE_FPV_navigationContinuation",_motion # 3];
_state set [1, _vectorUpdateAt];
_state set [2, _observedAt];
_state set [3, _blendedDir];
_state set [4, _up];
_state set [5, _nextSpeedBudget];
_state set [6, _step # 3];
// Slot 9 = dt of the last step that integrated time; a same-frame DUPLICATE keeps it (LT-1 LATE).
if (_dt > 0) then {_state set [9, _dt];};
_state set [10, +_normalizedAimVector];
_state set [11, +_desiredVelocity];
if (_isFirstVectorTick) then {
    _uav setVariable ["A3UE_FPV_steeringReconstruction",[_state # 7,_vectorUpdateAt,_observedAt,
        +_currentVelocity,+(_state # 3),_state # 5,_resetReason,0]];
};
_uav setVariable ["A3UE_FPV_terminalSteeringState", _state];
_uav setVariable ["A3UE_FPV_terminalVectorLastUpdateAt", _vectorUpdateAt];
// Reconstruction/duplicate time does not manufacture movement; caller still evaluates the fuse.
// LT-1: LATE/STALL steps carry a capped 0.25 s dt here, so a late controller still owns the dive.
if (_dt > 0) then {

private _native = _uav getVariable ["A3UE_FPV_nativeControl",[]];
if (_native isEqualTo []) then {
    private _crewSettings = (crew _uav) apply {[_x, _x checkAIFeature "PATH", _x checkAIFeature "FSM", _x checkAIFeature "AUTOCOMBAT"]};
    _native = [+_controllerIdentity,_crewSettings,getForcedSpeed _uav];
    _uav setVariable ["A3UE_FPV_nativeControl",_native];
    {
        (_x # 0) disableAI "PATH";
        (_x # 0) disableAI "FSM";
        (_x # 0) disableAI "AUTOCOMBAT";
    } forEach _crewSettings;
    _uav forceSpeed -1;
};
private _poseContext = _uav getVariable ["A3UE_FPV_terminalPoseContext", []];
private _passAt = _uav getVariable ["A3UE_FPV_terminalVectorEnteredAt", -1];
private _poseNow = time;
private _poseFrame = diag_frameNo;
private _poseSerial = _uav getVariable ["A3UE_FPV_terminalPoseSerial", 0];
private _poseReady = _passAt isEqualType 0 && {finite _passAt} && {_passAt >= 0}
	&& {_poseSerial isEqualType 0} && {finite _poseSerial} && {_poseSerial >= 0} && {_poseSerial == floor _poseSerial};
private _contextValid = _poseContext isEqualType [] && {count _poseContext in [0,8]};
if (_contextValid && {count _poseContext == 8}) then {
	_contextValid = (_poseContext # 0) isEqualType [] && {(_poseContext # 1) isEqualType objNull}
		&& {([2,3,4,5,6,7] findIf {private _v = _poseContext # _x; !(_v isEqualType 0) || {!finite _v}}) < 0};
	if (_contextValid) then {
		_contextValid = (_poseContext # 3) >= 1 && {(_poseContext # 3) == _poseSerial}
			&& {(_poseContext # 4) >= -1} && {(_poseContext # 5) >= -1}
			&& {(_poseContext # 5) == floor (_poseContext # 5)}
			&& {(_poseContext # 7) >= 0} && {(_poseContext # 7) == floor (_poseContext # 7)}
			&& {_poseNow >= (_poseContext # 6)} && {_poseFrame >= (_poseContext # 7)};
	};
};
if (!_poseReady || {!_contextValid}) then {
	// Corruption/rollback invalidates pose history; velocity and guidance time still advance below.
	_poseReady = false;
	_poseContext = [];
	_uav setVariable ["A3UE_FPV_terminalPoseContext", []];
};
if (_poseReady) then {
	if (count _poseContext == 0 || {!((_poseContext # 0) isEqualTo _controllerIdentity)}
		|| {!((_poseContext # 1) isEqualTo _target)} || {(_poseContext # 2) != _passAt}) then {
		_poseSerial = _poseSerial + 1;
		_poseContext = [+_controllerIdentity, _target, _passAt, _poseSerial, -1, -1, _poseNow, _poseFrame];
		_uav setVariable ["A3UE_FPV_terminalPoseSerial", _poseSerial];
		_uav setVariable ["A3UE_FPV_terminalPoseContext", _poseContext];
	};
	_poseContext set [6, _poseNow];
	_poseContext set [7, _poseFrame];
};
private _poseDue = _poseReady && {(_poseContext # 4) < 0 || {
	_poseFrame - (_poseContext # 5) >= 3 && {_poseNow - (_poseContext # 4) >= 0.05}
}};
private _poseEvidence = [];
private _movementAt = if (_qaMove) then {diag_tickTime} else {0};
if (_poseDue) then {
	// F2C-L: presentation-only level-horizon up with bounded bank. The logical
	// steering basis (_up in the stored state) is unchanged, so travel is F2C.
	private _attitudeKey = [+_controllerIdentity, _target, _passAt, _poseContext # 3];
	private _attitude = _uav getVariable ["A3UE_FPV_terminalPoseAttitude", []];
	private _attitudePrevious = [];
	private _attitudeDt = 0;
	if (_attitude isEqualType [] && {count _attitude == 3} && {(_attitude # 0) isEqualTo _attitudeKey}
		&& {(_attitude # 1) isEqualType 0} && {finite (_attitude # 1)} && {_poseNow >= (_attitude # 1)}) then {
		_attitudePrevious = _attitude # 2;
		_attitudeDt = _poseNow - (_attitude # 1);
	};
	private _presentation = [_blendedDir, _step # 3, _nextSpeedBudget, _attitudePrevious, _attitudeDt] call A3UE_fnc_fpv_terminalPresentationUp;
	private _poseUp = if (_presentation isEqualTo []) then {vectorNormalized _up} else {_presentation # 0};
	// Sample at the actual setter, not loop start. Different bracketing frames are ambiguous.
	private _poseDiagBefore = if (_qaMove) then {diag_tickTime} else {0};
	private _poseFrameBefore = diag_frameNo;
	_uav setVectorDirAndUp [_blendedDir, _poseUp];
	private _poseFrameAfter = diag_frameNo;
	private _poseDiagAfter = if (_qaMove) then {diag_tickTime} else {0};
	private _poseTimeAfter = time;
	if (_presentation isNotEqualTo []) then {
		_uav setVariable ["A3UE_FPV_terminalPoseAttitude", [_attitudeKey, _poseTimeAfter, _presentation # 1]];
	};
	// Conservative completion clocks also cover a setter spanning recorded frames.
	_poseContext set [4, _poseTimeAfter];
	_poseContext set [5, _poseFrameAfter];
	_poseContext set [6, _poseTimeAfter];
	_poseContext set [7, _poseFrameAfter];
	if (_qaMove) then {_poseEvidence = [1, _poseDiagBefore, _poseDiagAfter, _poseFrameBefore, _poseFrameAfter,
		_generation, _controllerIdentity # 2, _poseContext # 3];};
};
_uav setVelocity _desiredVelocity;
if (_qaMove) then {[_uav, "MOVE", [diag_tickTime, _movementAt, +_desiredVelocity, velocity _uav,
	_dt, _dt, _nextSpeedBudget * 3.6, _desiredTargetSpeed * 3.6]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
if !(_poseEvidence isEqualTo []) then {[_uav, "POSE", _poseEvidence] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
};

if (_isFirstVectorTick) then {
	_uav setVariable ["A3UE_FPV_terminalVectorEntrySpeed", _speedBudgetNow * 3.6, true];
	_uav setVariable ["A3UE_FPV_terminalVectorEntryDistance", _terminalVectorEntryDistance, true];
};

{
	[_uav, _x select 0, _x select 1] call A3UE_fnc_fpv_publishTelemetry;
} forEach [
	["A3UE_FPV_terminalVectorCurrentSpeed", _speedBudgetNow * 3.6],
	["A3UE_FPV_terminalVectorTargetSpeed", _desiredTargetSpeed * 3.6],
	["A3UE_FPV_terminalVectorAccelApplied", _appliedAcceleration * 3.6],
	["A3UE_FPV_terminalVectorAlignment", _alignment],
	["A3UE_FPV_terminalVectorDt", _dt],
	["A3UE_FPV_terminalVectorSpeedJump", _appliedSpeedDelta * 3.6]
];
if !(_uav getVariable ["A3UE_FPV_terminalSteeringActive", false]) then {
	_uav setVariable ["A3UE_FPV_terminalSteeringActive", true, true];
};
// LT-1 attackPass diagnostics, owner-local: [steps that wrote, of which late, zero-dt steps,
// refused passes (controller), longest step gap ms]. Constant cost; nothing is broadcast.
private _passRecord = _uav getVariable ["A3UE_FPV_attackPass", createHashMap];
if (_passRecord isEqualType createHashMap && {count _passRecord > 0}) then {
	private _stats = _passRecord getOrDefault ["steps", [0, 0, 0, 0, 0]];
	if (_dt > 0) then {
		_stats set [0, (_stats # 0) + 1];
		if (_resetReason in ["LATE", "STALL"]) then {_stats set [1, (_stats # 1) + 1];};
	} else {
		_stats set [2, (_stats # 2) + 1];
	};
	if (_resetReason in ["STEP", "LATE", "STALL", "GAP"] && {count _steeringBefore == 12}) then {
		_stats set [4, (_stats # 4) max round (1000 * (_vectorUpdateAt - (_steeringBefore # 1)))];
	};
	_passRecord set ["steps", _stats];
};

_applied = true;
};
_applied
