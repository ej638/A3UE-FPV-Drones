// LOW_RUN before the hand-off (lowest line LL-1), owner-local. The controller calls it once per
// TRACKING pass of a drone cleared to attack, inside its unscheduled tick (never suspends). It keeps
// the low-run record of a nominated engagement and surveys the path about once a second from 100 m
// before this drone's hand-off (350-500 m), while the AI still flies at transit height.
//   CHECKING -> READY once a survey has come back. A survey never blocks: the drone flies the line
//   it finds. The hand-off gate is in shouldEnterTerminal, at the record's handoffRun.
// A drone that loses its turn to another one keeps its low run, and surveys again when cleared.
// The run ends before the hand-off only with the master switch off, or with no survey back by 100 m
// inside the nearest hand-off (a starved scheduler: LATE); the drone then dives as it would.
// [uav, target, controllerIdentity] -> stage ("" when this engagement is not a low run)
params [["_uav", objNull], ["_target", objNull], ["_controllerIdentity", []]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {""};
if (isNull _uav || {isNull _target} || {!local _uav}) exitWith {""};
private _engagement = [_uav, _target, _controllerIdentity, false] call A3UE_fnc_fpv_attackEngagement;
if (_engagement isEqualTo [] || {(_engagement # 1) != "LOW_RUN"}) exitWith {""};
private _settings = call A3UE_fnc_fpv_lowRunSettings;
private _record = _uav getVariable ["A3UE_FPV_lowRun", createHashMap];
if (!(_record isEqualType createHashMap) || {(_record getOrDefault ["key", []]) isNotEqualTo (_engagement # 0)}) then {
	(_engagement # 2) params [["_height", 1], ["_skim", 18], ["_glide", 17.5]];
	// How far the airframe's lowest point sits below its model centre, read once per drone.
	private _below = _uav getVariable ["A3UE_FPV_lowRunBelow", -1];
	if (!(_below isEqualType 0) || {!finite _below} || {_below < 0}) then {
		_below = ((-(((boundingBoxReal _uav) # 0) # 2)) max 0) min 2;
		_uav setVariable ["A3UE_FPV_lowRunBelow", _below];
	};
	_record = createHashMapFromArray [
		["key", +(_engagement # 0)], ["stage", "CHECKING"], ["reason", ""], ["logged", false], ["created", time],
		["height", _height], ["skim", _skim], ["glide", _glide], ["check", createHashMap], ["result", []],
		["surveys", 0], ["surveyMsMax", 0], ["sliceMsMax", 0], ["minClear", 1e9],
		["glideFrom", []], ["wantZ", -1e9], ["wantAt", -1], ["hopTop", 0], ["hopBy", ""]
	];
	_uav setVariable ["A3UE_FPV_lowRun", _record];
};
if ((_record get "logged") || {!((_record get "stage") in ["CHECKING", "READY"])}) exitWith {_record get "stage"};
if !(_settings get "enabled") exitWith {
	[_uav, _target, "", "OFF"] call A3UE_fnc_fpv_lowRunEnd;
	""
};
private _uavPos = getPosASL _uav;
private _targetPos = getPosASL _target;
private _range = _uavPos distance2D _targetPos;
private _handoff = _settings get "handoff";
if (_range <= _handoff - 100 && {(_record get "result") isEqualTo []}) exitWith {
	[_uav, _target, "", "LATE"] call A3UE_fnc_fpv_lowRunEnd;
	""
};
private _handoffMax = (_settings get "handoffMax") max _handoff;
if (_range > _handoffMax + 100) exitWith {_record get "stage"};
private _surface = {
	params ["_p"];
	private _z = getTerrainHeightASL [_p # 0, _p # 1];
	if (_z < 1) then {_z = [_p # 0, _p # 1] call A3UE_fnc_fpv_surfaceZ;};
	_z
};
// The glide this drone needs (LR-1c, engine session 1b: from a hill outpost the drone had far more to
// lose than its height over the ground under it). The glide must be down at skim height levelOut
// before skimFrom (250 m out), over the real ground there, starting at the airframe's own height
// above sea level. The drawn 15-20 deg is kept by handing off farther out, up to handoffMax; only
// beyond that is it steepened, at most glideMax.
private _away = [(_uavPos # 0) - (_targetPos # 0), (_uavPos # 1) - (_targetPos # 1), 0];
_away = if (vectorMagnitude _away > 0.01) then {vectorNormalized _away} else {[0, -1, 0]};
private _bottom = ((getPosWorld _uav) # 2) - (_uav getVariable ["A3UE_FPV_lowRunBelow", 0]);
private _height = _record get "height";
private _down = (_settings get "skimFrom") + (_settings get "levelOut");
private _downZ = ([_targetPos vectorAdd (_away vectorMultiply _down)] call _surface) + _height;
private _tanDrawn = (tan (_record get "glide")) max 0.05;
private _handoffRun = ((_down + ((_bottom - _downZ) max 0) / _tanDrawn) max _handoff) min _handoffMax;
_record set ["handoffRun", _handoffRun];
// Surveys start 100 m before this drone's hand-off.
if (_range > _handoffRun + 100) exitWith {_record get "stage"};
private _result = _record get "result";
private _start = [];
if (count (_record get "check") == 0
	&& {_result isEqualTo [] || {time < (_result # 0)} || {time - (_result # 0) >= (_settings get "recheck")}}) then {
	// The surveyed line starts at the hand-off point H, on the line to the target at this drone's
	// hand-off range, or at the drone once it is closer, at the airframe's height (never below skim
	// height over the ground there); it glides down from there.
	private _from = [_uavPos # 0, _uavPos # 1, _bottom];
	if (_range > _handoffRun) then {
		_from = _targetPos vectorAdd (_away vectorMultiply _handoffRun);
		_from set [2, _bottom];
	};
	_from set [2, (_from # 2) max (([_from] call _surface) + _height)];
	private _tan = (_tanDrawn max (((_from # 2) - _downZ) / (((_from distance2D _targetPos) - _down) max 50)))
		min (tan (_settings get "glideMax"));
	_start = [_from, +_targetPos, _tan];
};
if (([_uav, _target, _record, _settings, _start] call A3UE_fnc_fpv_lowRunCheck) == "DONE") then {_record set ["stage", "READY"];};
_record get "stage"
