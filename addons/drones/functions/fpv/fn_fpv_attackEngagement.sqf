// F4-1 per-engagement approach profile, owner-local. An engagement is the controller
// identity + target + target revision. Its profile is sampled once, never per frame,
// from a 12-bit LCG (exact in single precision), so a QA seed reproduces it exactly.
// [uav, target, controllerIdentity, create, peek] -> [] or
// [key, profile, parameters, stage, bearingFromTargetDeg, createdAt]
//   peek (LR-1c, lowRunWaiter): the engagement this drone would get, not stored, with the low
//   run's range minimum not applied (a waiting drone waits on the outer ring for it).
//   HIGH_DIVE parameters: [heightAboveTarget m, diveAngle deg]
//   FLANK parameters:     [side +1/-1, offsetAngle deg, ringRadius m], stage "LEG" -> "IN"
//   LOW_RUN parameters:   [skim clearance m, skim speed m/s, glide deg] (EN-02, lowest line LL-1;
//                          the run itself is lowRunTrack/lowRunAim)
params [["_uav", objNull], ["_target", objNull], ["_controllerIdentity", []], ["_create", false], ["_peek", false]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {[]};
if (isNull _uav || {isNull _target}) exitWith {[]};
private _settings = call A3UE_fnc_fpv_attackSettings;
if !(_settings # 0) exitWith {[]};
private _revision = _uav getVariable ["A3UE_FPV_targetRevision", 0];
private _key = [+_controllerIdentity, netId _target, _revision];
private _record = _uav getVariable ["A3UE_FPV_attackEngagement", []];
if (_record isEqualType [] && {count _record == 6} && {(_record # 0) isEqualTo _key}) exitWith {_record};
// Only the current owner-local controller samples a new engagement.
if (!_create || {!local _uav} || {!(_controllerIdentity isEqualType [])} || {count _controllerIdentity != 4}
	|| {!((_uav getVariable ["A3UE_FPV_controllerIdentity", []]) isEqualTo _controllerIdentity)}) exitWith {[]};
private _relative = (getPosASL _uav) vectorDiff (getPosASL _target);
private _horizontal = sqrt (((_relative # 0) ^ 2) + ((_relative # 1) ^ 2));
private _above = _relative # 2;
private _bearing = if (_horizontal > 0.01) then {(_relative # 0) atan2 (_relative # 1)} else {0};
private _rng = _settings # 9;
if (_rng < 0) then {
	// One global draw per drone lifetime; every later value comes from the LCG.
	private _salt = _uav getVariable ["A3UE_FPV_attackSalt", -1];
	if (!(_salt isEqualType 0) || {_salt < 0}) then {
		_salt = floor (random 4096);
		_uav setVariable ["A3UE_FPV_attackSalt", _salt];
	};
	_rng = (_salt + 37 * ((_controllerIdentity # 0) mod 4096) + 101 * (_revision mod 4096) + 977) mod 4096;
};
private _draw = {_rng = ((1597 * _rng) + 51) mod 4096; _rng / 4096};
call _draw;
private _choice = call _draw;
private _a = call _draw;
private _b = call _draw;
private _profile = "DIRECT";
if ((_settings # 4) && {!(_target isKindOf "Air")}) then {
	_profile = switch (true) do {
		case ((_settings # 7) in ["DIRECT", "HIGH_DIVE", "FLANK"]): {_settings # 7};
		case (_choice < 0.4): {"DIRECT"};
		case (_choice < 0.7): {["DIRECT", "HIGH_DIVE"] select ((_horizontal >= 200) || {(_above >= 30) && {_horizontal >= 90}})};
		default {["DIRECT", "FLANK"] select (_horizontal >= 180)};
	};
};
private _parameters = switch (_profile) do {
	case "HIGH_DIVE": {[40 + 25 * _a, 28 + 8 * _b]};
	case "FLANK": {[[1, -1] select (_a < 0.5), 35 + 25 * _b, ((0.7 * _horizontal) max 110) min 220]};
	default {[]};
};
// LOW_RUN (EN-02 design section 3): one more draw, appended after the existing ones, so every QA seed
// still picks exactly the profile it picked before (a low run never falls back to it).
// Eligible: a fiber-optic drone (LL-1, EJ 16 November: low flight behind cover cuts a radio link,
// so radio drones never go low), a ground target (a person on foot, or a vehicle or static weapon
// standing still, never an aircraft) at most 2.5 m above the ground, at least 300 m away, and a
// drone without a support safety radius. The engagement is sampled once per target revision, so a
// return pass after a flip is never low.
// LR-1c: a drone that waited its turn on the outer ring (lowRunWaiter) was nominated by this same
// draw; the QA force LOW_RUN_WING applies to such drones only, so the first drone attacks as it
// otherwise would.
private _lowDraw = call _draw;
private _low = call A3UE_fnc_fpv_lowRunSettings;
private _force = _settings # 7;
private _waited = (_uav getVariable ["A3UE_FPV_lowWaiter", []]) isEqualTo [_key, true];
if ((_low get "enabled") && {_settings # 4} && {!(_target isKindOf "Air")}
	&& {(_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) != "RADIO"}
	&& {_force == "LOW_RUN" || {_force == "LOW_RUN_WING" && {_peek || _waited}} || {_lowDraw < (_low get "weight")}}
	&& {_peek || {_horizontal >= (_low get "minRange")}}
	&& {(_uav getVariable ["A3UE_FPV_supportSafetyRadius", 0]) <= 0}
	&& {((_target isKindOf "Man") && {isNull objectParent _target})
		|| {!(_target isKindOf "Man") && {(vectorMagnitude (velocity _target)) < 1}}}
	&& {((getPosASL _target) # 2) - ([(getPosASL _target) # 0, (getPosASL _target) # 1] call A3UE_fnc_fpv_surfaceZ) <= 2.5}) then {
	// Skim clearance weighted low (median about 1.75 m between 1 and 4 m), speed and glide.
	private _u = call _draw;
	private _height = (_low get "floor") + ((_low get "max") - (_low get "floor")) * _u * _u;
	if ((_low get "forcedHeight") > 0) then {_height = _low get "forcedHeight";};
	private _speeds = _low get "skimSpeed";
	private _skim = (_speeds # 0) + ((_speeds # 1) - (_speeds # 0)) * (call _draw);
	private _glide = 15 + 5 * (call _draw);
	_parameters = [_height, _skim, _glide];
	_profile = "LOW_RUN";
};
_record = [_key, _profile, _parameters, ["", "LEG"] select (_profile == "FLANK"), _bearing, time];
if (_peek) exitWith {_record};
_uav setVariable ["A3UE_FPV_attackEngagement", _record];
_record
