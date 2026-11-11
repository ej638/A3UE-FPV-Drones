params [["_uav", objNull], ["_target", objNull], ["_detonationReason", ""], ["_fallbackReason", ""], ["_targetRevision", -1]];

if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};

if (canSuspend) exitWith {
	private _result = false;
	// Keep the control check and detonation commit in one unscheduled slice.
	isNil {_result = _this call A3UE_fnc_fpv_detonateCompat;};
	_result
};
// Inherit the controller's original identity across scheduler preemption.
private _helperIdentity = if (isNil "_controllerIdentity") then {
    +(_uav getVariable ["A3UE_FPV_controllerIdentity", []])
} else {+_controllerIdentity};
if !([_uav, _helperIdentity] call A3UE_fnc_fpv_canActuate) exitWith {false};
if (_targetRevision < 0) then {_targetRevision = _uav getVariable ["A3UE_FPV_targetRevision",0];};

if (isNull _uav || {!local _uav}) exitWith {false};
if !(_uav getVariable ["A3UE_FPV_managed", false]) exitWith {false};
if !([_uav] call A3UE_fnc_fpv_isSiteDroneActive) exitWith {false};
if ([_uav] call A3UE_fnc_fpv_isExternallyControlled) exitWith {false};
if (_uav getVariable ["A3UE_FPV_detonating", false]) exitWith {true};
if (isNull _target || {(_uav getVariable ["A3UE_FPV_targetNetId",""]) != netId _target}
    || {(_uav getVariable ["A3UE_FPV_targetRevision",0]) != _targetRevision}
    || {([_uav] call A3UE_fnc_fpv_resolveTarget) isNotEqualTo _target}
    || {(_uav getVariable ["A3UE_FPV_linkModel","RADIO"]) == "RADIO" && {(_uav getVariable ["A3UE_FPV_linkState","OK"]) == "EW_DENIED"}}) exitWith {false};
// Bound proposal retries while the server is delayed; there is no new waiter.
if (diag_tickTime < (_uav getVariable ["A3UE_FPV_nextDetonationRequestAt", 0])) exitWith {
	if (!isNil "A3UE_FPV_QA_sink") then {[_uav, "STRIKE", ["THROTTLED", _uav getVariable ["A3UE_FPV_nextDetonationRequestAt", 0]]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
	false
};

if (_detonationReason isEqualTo "") then {
	_detonationReason = _uav getVariable ["A3UE_FPV_lastDetonationReason", "NONE"];
};

if (_fallbackReason isEqualTo "") then {
	_fallbackReason = _uav getVariable ["A3UE_FPV_lastFallbackReason", "NONE"];
};

private _vendorId = _uav getVariable ["A3UE_FPV_vendorId", ""];
private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];
private _descriptor = [typeOf _uav, _vendorId, _payloadRole] call A3UE_fnc_fpv_getClassDescriptor;
if (count _descriptor == 0 || {!(_descriptor get "canDetonate")} || {(_descriptor get "ammoClass") == ""}) exitWith {false};
private _uavPosAsl = getPosASL _uav;
private _impactPointAsl = _uav getVariable ["A3UE_FPV_lastImpactPointASL", []];
private _impactTargetNetId = _uav getVariable ["A3UE_FPV_lastImpactTargetNetId", ""];
private _impactValid = (_uav getVariable ["A3UE_FPV_lastImpactValid", false]) && {
	_impactPointAsl isEqualType [] && {
		count _impactPointAsl >= 3 && {
			_target isEqualType objNull && {
				(isNull _target) || {_impactTargetNetId == netId _target}
			}
		}
	}
};
private _directHitModes = ["DIRECT_BODY", "DIRECT_HULL", "DIRECT_STATIC"];
private _surfaceFallbackModes = ["GROUND_NEAR_TARGET", "OBSTRUCTION_SURFACE"];
private _impactMode = _uav getVariable ["A3UE_FPV_terminalImpactMode", "NONE"];
private _useImpactDelivery = _impactValid && {
	(((_impactMode in _directHitModes) && {_detonationReason in ["DIRECT_CONTACT", "PREDICTED_IMPACT", "CLOSURE_QUALIFIED"]}) ||
	{(_impactMode == "GROUND_NEAR_TARGET") && {_detonationReason == "CLOSURE_QUALIFIED"}} ||
	{(_impactMode == "OBSTRUCTION_SURFACE") && {_detonationReason == "OBSTRUCTION_FALLBACK"}})
};
private _deliveryPosAsl = +_uavPosAsl;
private _deliveryDir = vectorDir _uav;
private _deliveryUp = vectorUp _uav;
private _deliveryMode = if (_useImpactDelivery) then {"IMPACT_POINT"} else {"UAV_POSITION"};
// F4-1 ground contact (contact fuse): the warhead goes at the predicted touch-down point,
// at most 0.25 s ahead along the drone's own velocity, never at the target.
if (_detonationReason == "GROUND_CONTACT") then {
	private _velocity = velocity _uav;
	private _heightAboveTerrain = (_uavPosAsl # 2) - (getTerrainHeightASL [_uavPosAsl # 0, _uavPosAsl # 1]);
	private _touchdown = if ((_velocity # 2) < -0.5) then {(((_heightAboveTerrain - 0.2) max 0) / (-(_velocity # 2))) min 0.25} else {0};
	_deliveryPosAsl = _uavPosAsl vectorAdd (_velocity vectorMultiply _touchdown);
	_deliveryMode = "GROUND_POINT";
};
private _impactSurfaceType = _uav getVariable ["A3UE_FPV_lastImpactSurfaceType", "none"];
private _fallbackSurfaceModes = _surfaceFallbackModes;
private _strikePathClass = switch (true) do {
	case (_detonationReason == "GROUND_CONTACT"): {"GROUND_CONTACT"};
	case (_impactMode in _directHitModes): {"DIRECT_HIT"};
	case (_impactMode in _fallbackSurfaceModes): {"FALLBACK_SURFACE"};
	case (_impactMode == "AIR_PROXIMITY"): {"AIR_POLICY"};
	case (_fallbackReason != "NONE"): {"EMERGENCY_FALLBACK"};
	default {"UNCLASSIFIED"};
};
private _approvalPolicyClass = switch (true) do {
	case (_detonationReason in ["DIRECT_CONTACT", "PREDICTED_IMPACT"]): {"DIRECT_HIT_PRIMARY"};
	case (_detonationReason in ["CLOSURE_QUALIFIED", "OBSTRUCTION_FALLBACK", "GROUND_CONTACT"]): {"SURFACE_PRIMARY"};
	case (_detonationReason in ["MISSED_PASS_FALLBACK", "PROXIMITY_FAILSAFE"]): {"EMERGENCY_FALLBACK"};
	default {"UNCLASSIFIED"};
};
private _policyDeliveryMode = switch (_strikePathClass) do {
	case "DIRECT_HIT": {"IMPACT_POINT"};
	case "FALLBACK_SURFACE": {"IMPACT_POINT"};
	case "GROUND_CONTACT": {"GROUND_POINT"};
	default {"UAV_POSITION"};
};
private _deliveryPolicyMatch = _deliveryMode == _policyDeliveryMode;
private _knownBadPattern = (_impactMode == "GROUND_NEAR_TARGET") && {_detonationReason == "CLOSURE_QUALIFIED"} && {_deliveryMode == "UAV_POSITION"};

if (_useImpactDelivery) then {
	private _approachVector = _impactPointAsl vectorDiff _uavPosAsl;
	private _approachMagnitude = vectorMagnitude _approachVector;

	if (_approachMagnitude > 0.01) then {
		private _approachDir = _approachVector vectorMultiply (1 / _approachMagnitude);
		_deliveryPosAsl = _impactPointAsl vectorDiff (_approachDir vectorMultiply 0.35);
		_deliveryDir = _approachDir;
	} else {
		_deliveryPosAsl = +_impactPointAsl;
	};
};

private _permissionReason = [_uav, _target, true, ASLToATL _deliveryPosAsl, true] call A3UE_fnc_fpv_supportEngagementReason;
if (_permissionReason != "") exitWith {
	_uav setVariable ["A3UE_FPV_engagementFailureReason", _permissionReason, true];
    if (_permissionReason == "UNSAFE_ENGAGEMENT") then {
        if ((_uav getVariable ["A3UE_FPV_engagementBlockedAt", -1]) < 0) then {_uav setVariable ["A3UE_FPV_engagementBlockedAt", serverTime, true];};
        _uav setVariable ["A3UE_FPV_mode", "SAFETY_HOLD", true];
    };
	if (!isNil "A3UE_FPV_QA_sink") then {[_uav, "STRIKE", ["REJECTED", _permissionReason]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
	false
};

private _strike = createHashMapFromArray [
	["at", time],
	["uavNetId", _uav getVariable ["A3UE_FPV_netId", netId _uav]],
	["targetNetId", if (isNull _target) then {_impactTargetNetId} else {netId _target}],
	["targetRevision", _targetRevision],
	["siteMarker", _uav getVariable ["A3UE_FPV_siteMarker", ""]],
	["vendorId", _vendorId],
	["payloadRole", _payloadRole],
	["profileId", _uav getVariable ["A3UE_FPV_profileId", ""]],
	["impactMode", _impactMode],
	["surfaceType", _impactSurfaceType],
	["detonationReason", _detonationReason],
	["fallbackReason", _fallbackReason],
	["deliveryMode", _deliveryMode],
	["strikePathClass", _strikePathClass],
	["approvalPolicyClass", _approvalPolicyClass],
	["policyDeliveryMode", _policyDeliveryMode],
	["deliveryPolicyMatch", _deliveryPolicyMatch],
	["knownBadPattern", _knownBadPattern],
	["impactPointASL", _impactPointAsl],
	["uavPosASL", _uavPosAsl],
	["deliveryPosASL", _deliveryPosAsl],
	["controllerOwnerId", _uav getVariable ["A3UE_FPV_controllerOwnerId", -1]],
	["linkState", _uav getVariable ["A3UE_FPV_linkState", ""]]
];

private _lifecycleId = _uav getVariable ["A3UE_FPV_lifecycleId", -1];
if (_lifecycleId < 0) exitWith {false};

_strike set ["deliveryDir", _deliveryDir];
_strike set ["deliveryUp", _deliveryUp];
// F4-1 bounded pass summary (string <= 128 chars) for the server's attackPass RPT line.
private _attackSummary = [_uav, _target] call A3UE_fnc_fpv_attackPassSummary;
if (_attackSummary != "") then {_strike set ["attackPass", _attackSummary];};
private _path = if (_vendorId == "kvn") then {+(_uav getVariable ["kvn_fiber_path", []])} else {[]};
private _ttl = missionNamespace getVariable ["kvn_fiberTTL", 20];

// Only the server commit creates a payload or retires the UAV. A queued proposal
// is not a successful strike; duplicate proposals are coalesced at that commit.
_uav setVariable ["A3UE_FPV_nextDetonationRequestAt", diag_tickTime + 0.5];
if (!isNil "A3UE_FPV_QA_sink") then {[_uav, "STRIKE", ["PROPOSED", _detonationReason, _fallbackReason,
	_uav getVariable ["A3UE_FPV_nextDetonationRequestAt", 0]]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
private _sent = [_uav, "detonate", [_strike, _path, (_ttl max 0) min 300]] call A3UE_fnc_fpv_sendLifecycle;
if (!isNil "A3UE_FPV_QA_sink") then {[_uav, "STRIKE", [["SEND_REJECTED", "ACCEPTED_OR_QUEUED"] select _sent]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
_sent
