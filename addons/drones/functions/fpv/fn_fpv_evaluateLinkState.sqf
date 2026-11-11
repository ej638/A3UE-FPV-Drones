params [["_uav", objNull], ["_profile", createHashMap]];

if (isRemoteExecutedJIP || {isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}}) exitWith {false};

if (isNull _uav) exitWith {"OK"};
if (!local _uav) exitWith {_uav getVariable ["A3UE_FPV_cachedLinkState", "OK"]};
private _generation = _uav getVariable ["A3UE_FPV_controllerGeneration", 0];

private _linkModel = _uav getVariable ["A3UE_FPV_linkModel", "RADIO"];
if (_linkModel != "RADIO") exitWith {
	_uav setVariable ["A3UE_FPV_signalStrength", 1, true];
	"OK"
};

private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) then {
	_catalog = call A3UE_fnc_fpv_buildCompatCatalog;
};

private _vendorId = _uav getVariable ["A3UE_FPV_vendorId", ""];
private _familyData = _catalog getOrDefault [_vendorId, createHashMap];
private _jammerClasses = _familyData getOrDefault ["jammerClasses", []];
private _siteMarker = _uav getVariable ["A3UE_FPV_siteMarker", ""];
private _controlPosAtl = _uav getVariable ["A3UE_FPV_controlPosATL", []];
if (_controlPosAtl isEqualTo []) then {
    _controlPosAtl = if (_siteMarker isEqualTo "") then {getPosATL _uav} else {getMarkerPos _siteMarker};
};
if (_controlPosAtl isEqualTo [0, 0, 0]) then {_controlPosAtl = getPosATL _uav;};
private _positionATL = getPosATL _uav;
private _sampledAt = serverTime;
// LT-2: a flying drone reuses the relays it found for 10 s or 300 m of travel instead of
// scanning 1.5 km around itself and its control point on every sample (relays are placed
// objects; a destroyed one drops out at once). A3UE_FPV_leanBrain = false: scan every sample.
private _relayCache = _uav getVariable ["A3UE_FPV_relayCache", []];
private _relayLean = (call A3UE_fnc_fpv_wingSettings) # 6;
private _relaysKnown = _relayLean && {count _relayCache == 3} && {time >= (_relayCache # 0)} && {time - (_relayCache # 0) < 10}
    && {((_relayCache # 1) distance2D _positionATL) < 300};
private _sample = if (_relaysKnown) then {
    [_positionATL, _controlPosAtl, _familyData, _uav, -1, _relayCache # 2] call A3UE_fnc_fpv_sampleRadioLink
} else {
    [_positionATL, _controlPosAtl, _familyData, _uav] call A3UE_fnc_fpv_sampleRadioLink
};
private _signalStrength = _sample get "signal";
private _obstacleCount = _sample get "obstacles";
private _terrainMask = _sample get "terrainMask";
private _findJammers = {
    params ["_centerPos", "_radius"];
    if (_jammerClasses isEqualTo []) exitWith {[]};
    (_centerPos nearEntities [_jammerClasses, _radius]) select {_x getVariable ["DB_jammer_isActive", false]}
};

private _now = time;
private _previousEval = _uav getVariable ["A3UE_FPV_lastJammerEvalAt", _now];
private _elapsed = (_now - _previousEval) max 0;
private _timeInJammerZone = _uav getVariable ["A3UE_FPV_timeInJammerZone", 0];
private _jammersNearUav = [getPosATL _uav, 1000] call _findJammers;
if (_jammersNearUav isNotEqualTo []) then {
	_timeInJammerZone = _timeInJammerZone + _elapsed;
	private _jammerImpact = 1 - (_timeInJammerZone * 1.75);
	_signalStrength = (_signalStrength * _jammerImpact) max 0;
} else {
	_timeInJammerZone = 0;
};

_signalStrength = (_signalStrength max 0) min 1;
private _linkState = switch (true) do {
	case (_signalStrength <= 0.15): { "EW_DENIED" };
	case (_signalStrength <= 0.45): { "DEGRADED" };
	default { "OK" };
};

// Geometry calls can be scheduled: publish only if this owner still holds the claim.
isNil {
	if (local _uav && {(_uav getVariable ["A3UE_FPV_controllerGeneration", 0]) == _generation}) then {
		_uav setVariable ["A3UE_FPV_lastJammerEvalAt", _now];
		if (_relayLean && {!_relaysKnown}) then {
			_uav setVariable ["A3UE_FPV_relayCache", [time, +_positionATL, +(_sample getOrDefault ["retranslators", []])]];
		};
		_uav setVariable ["A3UE_FPV_timeInJammerZone", _timeInJammerZone];
		_uav setVariable ["A3UE_FPV_signalStrength", _signalStrength, true];
		if (_vendorId isEqualTo "armafpv" && {!isNil "DB_fnc_fpv_getSignal"}
			&& {!isNil "DB_fnc_fpv_ppfx_setInput"} && {!isNil "DB_fnc_fpv_onSignalLost"}) then {
			private _inJammer = _jammersNearUav isNotEqualTo [];
			private _context = [
				"altAGL", _positionATL # 2,
				"distance", _sample get "distance",
				"maxDistance", _sample get "maxDistance",
				"inJammer", _inJammer,
				"jammerFactor", if (_inJammer) then {(_timeInJammerZone * 1.75) min 1} else {0},
				"obstacleCount", _obstacleCount,
				"terrainMask", _terrainMask
			];
			// One bounded replicated sample; native fields belong to the viewing client.
			[_uav, "signal", [_sampledAt, _signalStrength, _context]] call A3UE_fnc_fpv_sendLifecycle;
		};
		if (_vendorId isEqualTo "fpv_ua") then {
			_uav setVariable ["UA_fpv_isUAVsignalLost", _linkState == "EW_DENIED", true];
		};
	};
};

if (!isNil "A3UE_FPV_QA_sink") then {[_uav, "LINK", [_linkState, _signalStrength, _obstacleCount,
	_terrainMask, _sample get "distance", _sample get "maxDistance", count _jammersNearUav, _timeInJammerZone]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
_linkState
