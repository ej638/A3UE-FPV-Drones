// F4-2 missed-pass reversal ("flip back"). After a genuine close miss the pilot pulls up hard,
// goes over the top and dives straight back at the target (about 15-21 m past it, a flip of
// under 2 s, envelope in attackLimits) instead of the wide native reacquire. One flip per drone lifetime: the budget is a public
// object variable, so neither a control hand-off nor a new controller can reset it.
// The controller calls this once per TERMINAL_VECTOR tick, before navigation, inside isNil.
// [uav, target, controllerIdentity, navigation (raw targetNavigation), closest, enteredAt]
//   -> [state, detail]
//  "OFF"     not applicable (F4-2 off, air target, stale caller): the F4-1 rules apply
//  "NONE"    no flip; detail = why a miss in this pass will not flip ("" = no miss yet)
//  "STARTED" the flip began this tick; detail = the missed first pass summary
//  "PULL"/"OVER" flip in progress: the range grows by design, no missed-pass rule
//  "REDIVE"  the return pass began this tick; detail = flip metrics for the RPT
//  "DIVE"    return pass in progress: the ordinary missed-pass rule applies, never a 2nd flip
//  "ABORT"   the flip did not come round in time; detail = reason and metrics
params [["_uav", objNull], ["_target", objNull], ["_controllerIdentity", []], ["_navigation", []],
	["_closest", -1], ["_enteredAt", -1]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {["OFF", ""]};
private _settings = call A3UE_fnc_fpv_attackSettings;
if (!(_settings # 0) || {!(_settings # 10)} || {isNull _uav} || {isNull _target} || {_target isKindOf "Air"}
	|| {!(_navigation isEqualType [])} || {count _navigation != 6}) exitWith {["OFF", ""]};
if (!local _uav || {(_uav getVariable ["A3UE_FPV_controllerIdentity", []]) isNotEqualTo _controllerIdentity}
	|| {(_uav getVariable ["A3UE_FPV_mode", ""]) != "TERMINAL_VECTOR"}
	|| {(_uav getVariable ["A3UE_FPV_terminalVectorEnteredAt", -1]) isNotEqualTo _enteredAt}) exitWith {["OFF", ""]};
private _now = time;
private _key = [+_controllerIdentity, netId _target, _uav getVariable ["A3UE_FPV_targetRevision", 0], _enteredAt];
private _record = _uav getVariable ["A3UE_FPV_attackReversal", createHashMap];
if (!(_record isEqualType createHashMap) || {(_record getOrDefault ["key", []]) isNotEqualTo _key}) then {_record = createHashMap;};
private _phase = _record getOrDefault ["phase", ""];
if (_phase == "DECLINED") exitWith {["NONE", _record getOrDefault ["reason", ""]]};
if (_phase == "DIVE") exitWith {["DIVE", "BUDGET"]};
if (_phase == "ABORT") exitWith {["ABORT", "reason=TIMEOUT"]};
private _uavPos = getPosASL _uav;
private _velocity = velocity _uav;
private _speed = vectorMagnitude _velocity;
private _reference = _navigation # 5;
private _metrics = {
	format ["turnS=%1 overshootM=%2 climbM=%3 minSpeed=%4", (round ((_now - (_record get "startedAt")) * 10)) / 10,
		round ((_record get "overshoot") max 0), (round (((_record get "peak") - (_record get "startZ")) * 10)) / 10,
		(round ((_record get "minSpeed") * 10)) / 10]
};
if (_phase in ["PULL", "OVER"]) exitWith {
	// Flip geometry for the RPT: furthest point past the target along the pass, highest point.
	_record set ["overshoot", (_record get "overshoot") max ((_uavPos vectorDiff _reference) vectorDotProduct (_record get "heading"))];
	_record set ["peak", (_record get "peak") max (_uavPos # 2)];
	_record set ["minSpeed", (_record get "minSpeed") min _speed];
	private _result = [_phase, ""];
	if (_now - (_record get "startedAt") > 4.5) then {
		_record set ["phase", "ABORT"];
		_result = ["ABORT", "reason=TIMEOUT " + (call _metrics)];
	} else {
		if (_phase == "PULL") then {
			// Nose high enough that turning onto the target goes over the top, never under.
			if (((_velocity # 2) / (_speed max 0.1)) >= 0.766 || {_now - (_record get "phaseAt") >= 1.5}) then {
				_record set ["phase", "OVER"];
				_record set ["phaseAt", _now];
				_result = ["OVER", ""];
			};
		} else {
			private _toTarget = _reference vectorDiff _uavPos;
			private _range = vectorMagnitude _toTarget;
			private _facing = if (_range > 0.1 && {_speed > 0.1}) then {(_velocity vectorDotProduct _toTarget) / (_range * _speed)} else {1};
			if (_facing >= 0.6 || {_now - (_record get "phaseAt") >= 2}) then {
				_record set ["phase", "DIVE"];
				_record set ["passIndex", 1];
				_record set ["divedAt", _now];
				_result = ["REDIVE", call _metrics];
			};
		};
	};
	_result
};
// No flip in progress: is this tick a genuine miss (range growing again after a close pass)?
// Within 8 m of the target the range only grows once the drone is past it.
if (_closest < 0 || {(_uavPos vectorDistance _reference) <= _closest + 1.5} || {_now <= _enteredAt + 0.5}) exitWith {["NONE", ""]};
private _why = switch (true) do {
	case ((_uav getVariable ["A3UE_FPV_attackReversalUsed", false]) isEqualTo true): {"BUDGET"};
	case (_closest > 8): {"FAR"};
	case (_speed < 8): {"SLOW"};
	default {""};
};
private _heading = [_velocity # 0, _velocity # 1, 0];
if (vectorMagnitude _heading < 0.5) then {_heading = _uavPos vectorDiff _reference; _heading set [2, 0];};
_heading = if (vectorMagnitude _heading > 0.01) then {vectorNormalized _heading} else {[0, 1, 0]};
if (_why == "") then {
	// Height to pull up from: not too low, not sinking into the ground within 0.25 s.
	private _agl = (_uavPos # 2) - (getTerrainHeightASL [_uavPos # 0, _uavPos # 1]);
	if (_agl < (_settings # 14) || {(_agl + 0.25 * (_velocity # 2)) < 0.6}) then {_why = "LOW";};
};
if (_why == "" && {_settings # 11}) then {
	// Room for the flip: ahead-and-up along the pull, and straight up.
	if (([_uav, _target, _uavPos, (_uavPos vectorAdd (_heading vectorMultiply 16)) vectorAdd [0, 0, 10], false, false] call A3UE_fnc_fpv_obstacleProbe) isNotEqualTo []
		|| {([_uav, _target, _uavPos, _uavPos vectorAdd [0, 0, 14], false, false] call A3UE_fnc_fpv_obstacleProbe) isNotEqualTo []}) then {
		_why = "OBSTACLE";
	};
};
if (_why != "") exitWith {
	// Decided once per pass; later ticks of this miss reuse it (no repeated probes).
	_uav setVariable ["A3UE_FPV_attackReversal", createHashMapFromArray [["key", _key], ["phase", "DECLINED"], ["reason", _why], ["passIndex", 0]]];
	["NONE", _why]
};
// Start. The budget is spent now, whatever happens next.
_uav setVariable ["A3UE_FPV_attackReversalUsed", true, true];
private _summary = [_uav, _target] call A3UE_fnc_fpv_attackPassSummary;
_record = createHashMapFromArray [["key", _key], ["phase", "PULL"], ["startedAt", _now], ["phaseAt", _now],
	["heading", _heading], ["startZ", _uavPos # 2], ["peak", _uavPos # 2],
	["overshoot", (_uavPos vectorDiff _reference) vectorDotProduct _heading], ["minSpeed", _speed],
	["passIndex", 0], ["divedAt", -1]];
_uav setVariable ["A3UE_FPV_attackReversal", _record];
["STARTED", _summary]
