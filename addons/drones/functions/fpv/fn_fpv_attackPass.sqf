// F4-1 per-pass attack plan, sampled once at terminal entry, owner-local:
// - outcome intent: where the pilot ends up aiming (DIRECT, GROUND_SHORT, GROUND_SIDE, OVER);
// - correction program: the pilot's fine-tuning, alternating converging aim errors.
// Keyed by controller identity, target, target revision, pass start and pass index (F4-2: the
// return pass after a flip is index 1); a stale key is replaced, never reused. 12-bit LCG
// draws only (no per-frame or global random state).
// [uav, target, controllerIdentity, settings] -> hashmap (empty when off or invalid)
params [["_uav", objNull], ["_target", objNull], ["_controllerIdentity", []], ["_settings", []]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {createHashMap};
if (isNull _uav || {isNull _target}) exitWith {createHashMap};
if (_settings isEqualTo []) then {_settings = call A3UE_fnc_fpv_attackSettings;};
if !(_settings # 0) exitWith {createHashMap};
private _enteredAt = _uav getVariable ["A3UE_FPV_terminalVectorEnteredAt", -1];
if (!(_enteredAt isEqualType 0) || {!finite _enteredAt} || {_enteredAt < 0}) exitWith {createHashMap};
private _revision = _uav getVariable ["A3UE_FPV_targetRevision", 0];
// F4-2: after a flip the return pass is a pass of its own (index 1), from the re-dive time.
private _passIndex = 0;
private _passStart = _enteredAt;
private _flip = _uav getVariable ["A3UE_FPV_attackReversal", createHashMap];
if (_flip isEqualType createHashMap && {(_flip getOrDefault ["passIndex", 0]) isEqualTo 1}
	&& {(_flip getOrDefault ["key", []]) isEqualTo [+_controllerIdentity, netId _target, _revision, _enteredAt]}) then {
	_passIndex = 1;
	_passStart = _flip getOrDefault ["divedAt", _enteredAt];
};
private _key = [+_controllerIdentity, netId _target, _revision, _enteredAt, _passIndex];
private _record = _uav getVariable ["A3UE_FPV_attackPass", createHashMap];
if (_record isEqualType createHashMap && {(_record getOrDefault ["key", []]) isEqualTo _key}) exitWith {_record};
if (!local _uav || {!(_controllerIdentity isEqualType [])} || {count _controllerIdentity != 4}
	|| {!((_uav getVariable ["A3UE_FPV_controllerIdentity", []]) isEqualTo _controllerIdentity)}) exitWith {createHashMap};
private _engagement = [_uav, _target, _controllerIdentity, false] call A3UE_fnc_fpv_attackEngagement;
private _profile = if (_engagement isEqualTo []) then {"DIRECT"} else {_engagement # 1};
private _rng = _settings # 9;
if (_rng < 0) then {
	private _salt = _uav getVariable ["A3UE_FPV_attackSalt", -1];
	if (!(_salt isEqualType 0) || {_salt < 0}) then {
		_salt = floor (random 4096);
		_uav setVariable ["A3UE_FPV_attackSalt", _salt];
	};
	_rng = (_salt + 37 * ((_controllerIdentity # 0) mod 4096) + 101 * (_revision mod 4096) + ((round (_enteredAt * 10)) mod 4096) + 701 * _passIndex) mod 4096;
} else {
	_rng = (_rng + 1531 + 701 * _passIndex) mod 4096;
};
private _seed = _rng;
private _draw = {_rng = ((1597 * _rng) + 51) mod 4096; _rng / 4096};
call _draw;
// Outcome intent. Starting weights approved by EJ (2026-11-08); emergent misses from the
// pilot's reaction lag (attackNavigation) come on top of these.
private _isMan = (_target isKindOf "Man") && {isNull objectParent _target};
private _targetSpeed = vectorMagnitude (velocity _target);
private _choice = call _draw;
private _groundChoice = call _draw;
private _intent = "DIRECT";
// QA may force the near-miss style: OVER_TOP / OVER_SIDE are OVER with that style.
private _forcedStyle = "";
private _forced = {
	params ["_value"];
	if (_value in ["OVER_TOP", "OVER_SIDE"]) exitWith {_forcedStyle = _value select [5]; "OVER"};
	_value
};
if (!(_target isKindOf "Air") && {_passIndex == 1}) then {
	// Return pass: the pilot is close and slow now. Mostly direct, some ground, no second
	// over-the-head pass (QA may force one with A3UE_FPV_QA_forceReturnIntent).
	if ((_settings # 13) != "") then {
		_intent = [_settings # 13] call _forced;
	} else {
		if (_settings # 5) then {
			_intent = if (_choice < 0.85) then {"DIRECT"} else {["GROUND_SIDE", "GROUND_SHORT"] select (_groundChoice < 0.5)};
		};
	};
	if (_intent == "OVER" && {!_isMan}) then {_intent = "GROUND_SIDE";};
};
if (!(_target isKindOf "Air") && {_passIndex == 0}) then {
	if ((_settings # 8) != "") then {
		_intent = [_settings # 8] call _forced;
	} else {
		if (_settings # 5) then {
			private _weights = switch (true) do {
				case (_isMan && {_targetSpeed < 1.5}): {[0.75, 0.15]};
				case (_isMan): {[0.60, 0.25]};
				case (_targetSpeed > 8): {[0.60, 0.30]};
				default {[0.75, 0.15]};
			};
			_intent = switch (true) do {
				case (_choice < (_weights # 0)): {"DIRECT"};
				case (_choice < ((_weights # 0) + (_weights # 1))): {["GROUND_SIDE", "GROUND_SHORT"] select (_groundChoice < 0.5)};
				default {"OVER"};
			};
		};
	};
	// Over the head needs a person on foot and a shallow final approach.
	if (_intent == "OVER" && {!_isMan || {_profile == "HIGH_DIVE"}}) then {
		_intent = ["GROUND_SIDE", "GROUND_SHORT"] select (_profile == "HIGH_DIVE");
	};
};
// Correction program: segment ends (s), yaw and pitch as fractions of the time-to-go
// dependent maximum applied in attackAimOffset. Usually swaps side, sometimes not.
private _ends = [];
private _yaw = [];
private _pitch = [];
private _elapsed = 0;
private _sign = [1, -1] select ((call _draw) < 0.5);
for "_i" from 0 to 23 do {
	_elapsed = _elapsed + 0.8 + 0.6 * (call _draw);
	_ends pushBack _elapsed;
	if (_i > 0 && {(call _draw) < 0.8}) then {_sign = -_sign;};
	_yaw pushBack (_sign * (0.6 + 0.4 * (call _draw)));
	_pitch pushBack (-0.25 + (call _draw));
};
// Final window [end, start] in time-to-go seconds, long enough to be flyable.
private _envelope = [0.35, 1.0];
if (_intent in ["GROUND_SHORT", "GROUND_SIDE"]) then {_envelope = [0.35, 1.5];};
private _groundDistance = 0.8 + 1.7 * (call _draw);
private _groundSide = [1, -1] select ((call _draw) < 0.5);
// Near miss (EJ, two engine runs: "OMG, it just missed me", never a drone deciding to miss).
// Style TOP: 0.55-0.95 m over the head (planned; flown about 0.1 m lower) and 0.1-0.4 m to one side. Style SIDE: past the head or
// shoulder, 1.1-1.5 m to one side at 1.9-2.3 m (planned; flown about 0.1-0.2 m closer). Either way 1.15 m or more from the body point,
// outside its 1 m contact sphere, aiming only 1.5-3 m beyond the target so the dive barely
// changes. Style (55% TOP) and side come from the seed, so the pass's later draws are unchanged.
private _overStyle = ["SIDE", "TOP"] select (((((1597 * (_seed + 2311)) + 51) mod 4096) / 4096) < 0.55);
if (_forcedStyle != "") then {_overStyle = _forcedStyle;};
private _sideDraw = (((1597 * (_seed + 977)) + 51) mod 4096) / 4095;
private _overClearance = (call _draw) * 0.4;
private _overLead = 1.5 + 1.5 * (call _draw);
private _overSide = 0;
if (_overStyle == "TOP") then {
	_overClearance = 0.55 + _overClearance;
	_overSide = _groundSide * (0.1 + 0.3 * _sideDraw);
} else {
	_overClearance = 0.05 + _overClearance;
	_overSide = _groundSide * (1.1 + 0.4 * _sideDraw);
};
// A near miss converges like a direct hit and only drifts off late: over the head in the last
// 0.9 s (about 25 m at dive speed), beside the head from 1.2 s (sideways steering is slower,
// KVN most of all; still about 2 deg at 34 m). It reads as a pilot who just missed.
if (_intent == "OVER") then {_envelope = [[0.3, 1.2], [0.25, 0.9]] select (_overStyle == "TOP");};
_record = createHashMapFromArray [
	["key", _key], ["seed", _seed], ["profile", _profile], ["intent", _intent],
	["groundDist", _groundDistance], ["groundSide", _groundSide], ["overClear", _overClearance], ["overLead", _overLead], ["overSide", _overSide], ["overStyle", _overStyle],
	["segTimes", _ends], ["segYaw", _yaw], ["segPitch", _pitch], ["envelope", _envelope],
	["start", _passStart], ["passIndex", _passIndex], ["entryRange", (getPosASL _uav) vectorDistance (getPosASL _target)],
	["rng", _rng], ["sampleAt", -1], ["samplePos", []], ["sampleVel", [0, 0, 0]], ["nextSampleAt", -1],
	["frame", []], ["closest", 1e6], ["maxSpeed", 0], ["memoAt", -1], ["memoKey", []], ["memo", []]
];
_uav setVariable ["A3UE_FPV_attackPass", _record];
_record
