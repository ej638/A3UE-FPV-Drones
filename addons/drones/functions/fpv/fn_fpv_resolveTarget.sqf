params [["_uav", objNull]];

if (isNull _uav) exitWith {objNull};

private _targetNetId = _uav getVariable ["A3UE_FPV_targetNetId", ""];
if (_targetNetId isEqualTo "") exitWith {objNull};

// LT-2 tick memo. Within one controller tick (one unscheduled slice) the same target id and
// revision resolve to the same object, unless that object died in this tick (its own strike).
// Outside a tick there is no memo.
private _revision = _uav getVariable ["A3UE_FPV_targetRevision", 0];
private _memo = if (isNil "_fpvTick") then {[]} else {_fpvTick getOrDefault ["target", []]};
if (count _memo == 4 && {(_memo # 0) isEqualTo _uav} && {(_memo # 1) isEqualTo _targetNetId} && {(_memo # 2) isEqualTo _revision}
	&& {isNull (_memo # 3) || {alive (_memo # 3)}}) exitWith {_memo # 3};

private _target = objectFromNetId _targetNetId;

private _siteSide = side group effectiveCommander _uav;
if (_siteSide == sideUnknown) then {_siteSide = side _uav;};
private _hostileSides = [_siteSide, _uav getVariable ["A3UE_FPV_targetSide", sideUnknown]] call A3UE_fnc_fpv_getHostileSides;
private _result = [_target, _hostileSides] call A3UE_fnc_fpv_filterTarget;
if (!isNull _result && {!isNil "_fpvTick"}) then {_fpvTick set ["target", [_uav, _targetNetId, _revision, _result]];};
_result
