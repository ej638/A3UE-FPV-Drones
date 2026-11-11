params [["_uav", objNull], ["_profile", createHashMap], ["_searchContext", createHashMap]];

if !(call A3UE_fnc_fpv_helperAccess) exitWith {objNull};

if (isNull _uav) exitWith {objNull};

private _siteType = _uav getVariable ["A3UE_FPV_siteType", ""];
private _siteMarker = _uav getVariable ["A3UE_FPV_siteMarker", ""];
private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];
private _siteSide = side group effectiveCommander _uav;

if (isNil "_siteSide" || {_siteSide == sideUnknown}) then {
	_siteSide = side _uav;
};

private _hostileSides = [_siteSide, _uav getVariable ["A3UE_FPV_targetSide", sideUnknown]] call A3UE_fnc_fpv_getHostileSides;
if (_hostileSides isEqualTo []) exitWith {objNull};

private _siteRadius = [_profile, "searchRadius", -1] call A3UE_fnc_fpv_profileValue;
if (!(_siteRadius isEqualType 0)) then {
	_siteRadius = -1;
};

if (_siteRadius <= 0) then {
	_siteRadius = switch (_siteType) do {
		case "Airport": { 700 };
		case "Milbase": { 625 };
		case "Seaport": { 575 };
		case "Outpost": { 500 };
		case "Factory": { 425 };
		default { 350 };
	};
};

private _localRadius = [_profile, "localSearchRadius", 250] call A3UE_fnc_fpv_profileValue;
if (!(_localRadius isEqualType 0) || {_localRadius <= 0}) then {
	_localRadius = 250;
};

private _overrideSiteScan = _searchContext getOrDefault ["overrideSiteScan", false];
private _focusPosAtl = _searchContext getOrDefault ["focusPosATL", []];
private _focusRadius = _searchContext getOrDefault ["focusRadius", _siteRadius];
private _preferLostTarget = _searchContext getOrDefault ["preferLostTarget", false];
private _coneOriginAsl = _searchContext getOrDefault ["coneOriginASL", []];
private _coneDirection = _searchContext getOrDefault ["coneDirection", []];
private _coneHalfAngle = _searchContext getOrDefault ["coneHalfAngle", -1];

if (!(_focusRadius isEqualType 0) || {_focusRadius <= 0}) then {
	_focusRadius = _siteRadius;
};

private _scanCenter = if (_siteMarker isEqualTo "") then {
	getPosATL _uav
} else {
	getMarkerPos _siteMarker
};

if (_scanCenter isEqualTo [0, 0, 0]) then {
	_scanCenter = getPosATL _uav;
};

if (_focusPosAtl isEqualType [] && {count _focusPosAtl >= 2} && {!(_focusPosAtl isEqualTo [0, 0, 0])}) then {
	_scanCenter = _focusPosAtl;
};

private _getCandidates = {
	params ["_key", "_center", "_radius", "_ttl"];

	private _cache = _uav getVariable [_key, []];
	private _refresh = count _cache != 4;
	if (!_refresh) then {
		_refresh = time >= (_cache select 0) ||
			{_radius != (_cache select 2)} ||
			{_center distance2D (_cache select 1) > 10};
	};

	if (_refresh) then {
		private _objects = nearestObjects [_center, ["Man", "LandVehicle", "Air", "Ship", "StaticWeapon"], _radius, true];
		_cache = [time + _ttl, +_center, _radius, _objects];
		_uav setVariable [_key, _cache];
	};

	+(_cache select 3)
};

private _siteScanRadius = if (_overrideSiteScan) then {_focusRadius} else {_siteRadius};
private _localScanCenter = getPosATL _uav;
private _wing = call A3UE_fnc_fpv_wingSettings;
private _candidateObjects = [];
if (_wing # 7) then {
	// LT-2 shared scan (scanTargets). The site circle is scanned once for all of the site's
	// drones; a focused (lost target) or unmarked scan is the drone's own. The drone's local
	// circle is scanned only where it reaches outside the site circle.
	private _siteKey = if (_siteMarker isEqualTo "" || {_overrideSiteScan}) then {
		format ["%1/site", netId _uav]
	} else {
		format ["%1/%2", _siteMarker, _siteScanRadius]
	};
	_candidateObjects = [_siteKey, _scanCenter, _siteScanRadius, 1.5, _hostileSides] call A3UE_fnc_fpv_scanTargets;
	if (((_localScanCenter distance2D _scanCenter) + _localRadius) > _siteScanRadius) then {
		_candidateObjects append ([format ["%1/local", netId _uav], _localScanCenter, _localRadius, 1, _hostileSides] call A3UE_fnc_fpv_scanTargets);
	};
} else {
	_candidateObjects = ["A3UE_FPV_siteCandidateCache", _scanCenter, _siteScanRadius, 0.75] call _getCandidates;
	_candidateObjects append (["A3UE_FPV_localCandidateCache", _localScanCenter, _localRadius, 0.25] call _getCandidates);
};

private _normalizeTarget = {
	params ["_candidate"];

	if (_candidate isKindOf "Man" && {!isNull objectParent _candidate}) exitWith {
		objectParent _candidate
	};

	_candidate
};

// Cached objects can leave either scan area or board the same vehicle between scans.
_candidateObjects = (_candidateObjects select {
	!isNull _x && {
		private _candidatePos = getPosWorld _x;
		(_candidatePos distance2D _scanCenter) <= _siteScanRadius ||
			{(_candidatePos distance2D _localScanCenter) <= _localRadius}
	}
}) apply {[_x] call _normalizeTarget};
_candidateObjects = _candidateObjects arrayIntersect _candidateObjects;

private _passesCone = {
	params ["_candidate"];

	if (_coneOriginAsl isEqualTo [] || {_coneDirection isEqualTo []} || {_coneHalfAngle < 0}) exitWith {true};

	private _candidateVector = (getPosASL _candidate) vectorDiff _coneOriginAsl;
	if ((vectorMagnitude _candidateVector) <= 0.1) exitWith {true};

	private _normalizedConeDirection = vectorNormalized _coneDirection;
	if ((vectorMagnitude _normalizedConeDirection) <= 0.001) exitWith {true};

	private _normalizedCandidateVector = vectorNormalized _candidateVector;
	private _dot = ((_normalizedConeDirection vectorDotProduct _normalizedCandidateVector) max -1) min 1;
	(acos _dot) <= _coneHalfAngle
};

private _scoreCandidate = {
	params ["_target"];

	private _distanceScore = 10000 - (_uav distance _target);
	private _score = _distanceScore;

	switch (_payloadRole) do {
		case "AT": {
			if (_target isKindOf "Tank" || {_target isKindOf "Wheeled_APC_F"} || {_target isKindOf "Tracked_APC_F"}) then {
				_score = _score + 3000;
			} else {
				if (_target isKindOf "LandVehicle" || {_target isKindOf "Ship"} || {_target isKindOf "Air"}) then {
					_score = _score + 1500;
				};
			};

			if (_target isKindOf "Man") then {
				_score = _score - 4000;
			};
		};

		case "RECON": {
			if (_target isKindOf "Man") then {
				_score = _score + 2200;
			} else {
				if (_target isKindOf "Car" || {_target isKindOf "StaticWeapon"}) then {
					_score = _score + 1200;
				};
			};

			if (_target isKindOf "Tank") then {
				_score = _score - 500;
			};
		};

		default {
			if (_target isKindOf "Man") then {
				_score = _score + 2500;
			} else {
				if (_target isKindOf "Car" || {_target isKindOf "StaticWeapon"}) then {
					_score = _score + 1500;
				};
			};

			if (_target isKindOf "Tank" || {_target isKindOf "Wheeled_APC_F"} || {_target isKindOf "Tracked_APC_F"}) then {
				_score = _score - 2000;
			};
		};
	};

	_score
};

private _stickyTarget = [_uav] call A3UE_fnc_fpv_resolveTarget;
private _stickyNetId = _uav getVariable ["A3UE_FPV_targetNetId", ""];
private _lastKnownTargetNetId = _uav getVariable ["A3UE_FPV_lastKnownTargetNetId", ""];
private _lastKnownTargetTime = _uav getVariable ["A3UE_FPV_lastKnownTargetTime", -1];
private _targetStickyBonus = [_profile, "targetStickyBonus", 1800] call A3UE_fnc_fpv_profileValue;
private _targetStickyWindow = [_profile, "targetStickyWindow", 4] call A3UE_fnc_fpv_profileValue;
private _targetSwitchMargin = [_profile, "targetSwitchMargin", 900] call A3UE_fnc_fpv_profileValue;
private _losBlockedPenalty = [_profile, "losBlockedPenalty", 2200] call A3UE_fnc_fpv_profileValue;
private _obstructionPenaltyStep = [_profile, "obstructionPenaltyStep", 350] call A3UE_fnc_fpv_profileValue;

if (!(_targetStickyBonus isEqualType 0)) then { _targetStickyBonus = 1800; };
if (!(_targetStickyWindow isEqualType 0) || {_targetStickyWindow < 0}) then { _targetStickyWindow = 4; };
if (!(_targetSwitchMargin isEqualType 0) || {_targetSwitchMargin < 0}) then { _targetSwitchMargin = 900; };
if (!(_losBlockedPenalty isEqualType 0) || {_losBlockedPenalty < 0}) then { _losBlockedPenalty = 2200; };
if (!(_obstructionPenaltyStep isEqualType 0) || {_obstructionPenaltyStep < 0}) then { _obstructionPenaltyStep = 350; };

private _scoreCandidateDetailed = {
	params ["_target"];

	private _baseScore = [_target] call _scoreCandidate;
	private _stickyBonus = 0;
	private _lostStickyBonus = 0;
	private _losPenalty = 0;
	private _obstructionPenalty = 0;
	private _obstructionData = [_uav, _target] call A3UE_fnc_fpv_isTargetObstructed;
	private _obstructionCount = _obstructionData getOrDefault ["obstructionCount", 0];

	if ((netId _target) isEqualTo _stickyNetId) then {
		_stickyBonus = _targetStickyBonus;
	};

	if ((netId _target) isEqualTo _lastKnownTargetNetId && {_lastKnownTargetTime >= 0} && {(time - _lastKnownTargetTime) <= _targetStickyWindow}) then {
		_lostStickyBonus = _targetStickyBonus * ([0.5, 0.75] select _preferLostTarget);
	};

	if (_obstructionData getOrDefault ["blocked", false]) then {
		_losPenalty = _losBlockedPenalty;
		_obstructionPenalty = _obstructionCount * _obstructionPenaltyStep;
	};

	// LT-2: drones already on this target (attacking or waiting) make it less attractive, so a
	// flight spreads over the targets it can see.
	private _crowdPenalty = if ((_wing # 2) > 0) then {([_target, _uav] call A3UE_fnc_fpv_attackCrowd) * (_wing # 9)} else {0};
	private _finalScore = _baseScore + _stickyBonus + _lostStickyBonus - _losPenalty - _obstructionPenalty - _crowdPenalty;
[
		_finalScore,
		createHashMapFromArray [
			["baseScore", _baseScore],
			["stickyBonus", _stickyBonus],
			["lostStickyBonus", _lostStickyBonus],
			["losPenalty", _losPenalty],
			["obstructionPenalty", _obstructionPenalty],
			["crowdPenalty", _crowdPenalty],
			["obstructionCount", _obstructionCount]
		]
	]
};

private _bestTarget = objNull;
private _bestScore = -1e9;
private _bestScoreBreakdown = createHashMap;

if (!isNull _stickyTarget && {alive _stickyTarget}) then {
	if (!isNull ([_stickyTarget, _hostileSides] call A3UE_fnc_fpv_filterTarget)) then {
		private _stickyDetails = [_stickyTarget] call _scoreCandidateDetailed;
		_bestTarget = _stickyTarget;
		_bestScore = _stickyDetails param [0, -1e9];
		_bestScoreBreakdown = _stickyDetails param [1, createHashMap];
		_candidateObjects = _candidateObjects - [_stickyTarget];
	};
};

// LT-2: the line-of-sight trace is the expensive part of a score. With more than six
// candidates only the six best by everything else are traced.
if ((_wing # 7) && {count _candidateObjects > 6}) then {
	private _ranked = [];
	{
		if (!isNull _x && {alive _x} && {!(_x isEqualTo _uav)} && {!(_x getVariable ["A3UE_FPV_managed", false])}) then {
			private _cheap = ([_x] call _scoreCandidate) - (([_x, _uav] call A3UE_fnc_fpv_attackCrowd) * (_wing # 9));
			if ((netId _x) isEqualTo _lastKnownTargetNetId && {_lastKnownTargetTime >= 0} && {(time - _lastKnownTargetTime) <= _targetStickyWindow}) then {
				_cheap = _cheap + _targetStickyBonus * ([0.5, 0.75] select _preferLostTarget);
			};
			_ranked pushBack [_cheap, _forEachIndex];
		};
	} forEach _candidateObjects;
	_ranked sort false;
	_candidateObjects = (_ranked select [0, 6]) apply {_candidateObjects # (_x # 1)};
};

{
	private _normalizedTarget = _x;
	if (!isNull _normalizedTarget && {!(_normalizedTarget isEqualTo _uav)}) then {
		if !(_normalizedTarget getVariable ["A3UE_FPV_managed", false]) then {
			if (alive _normalizedTarget) then {
				if (!isNull ([_normalizedTarget, _hostileSides] call A3UE_fnc_fpv_filterTarget) && {[_normalizedTarget] call _passesCone}) then {
					private _isEmptyVehicle = _normalizedTarget isKindOf "AllVehicles" && {crew _normalizedTarget isEqualTo []} && {!(_normalizedTarget isKindOf "StaticWeapon")};

					if (!_isEmptyVehicle) then {
						private _details = [_normalizedTarget] call _scoreCandidateDetailed;
						private _score = _details param [0, -1e9];
						private _scoreBreakdown = _details param [1, createHashMap];
						private _switchingAwayFromSticky = !isNull _bestTarget && {
							!(_normalizedTarget isEqualTo _bestTarget) &&
							((netId _bestTarget) isEqualTo _stickyNetId)
						};
						private _requiredScore = if (_switchingAwayFromSticky) then {
							_bestScore + _targetSwitchMargin
						} else {
							_bestScore
						};

						if (_score > _requiredScore) then {
							_bestScore = _score;
							_bestTarget = _normalizedTarget;
							_bestScoreBreakdown = _scoreBreakdown;
						};
					};
				};
			};
		};
	};
} forEach _candidateObjects;

_uav setVariable ["A3UE_FPV_lastTargetScore", _bestScore, true];
_uav setVariable ["A3UE_FPV_lastTargetScoreBreakdown", _bestScoreBreakdown, true];

_bestTarget
