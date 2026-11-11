// F4-1 per-engagement approach profile, owner-local. An engagement is the controller
// identity + target + target revision. Its profile is sampled once, never per frame,
// from a 12-bit LCG (exact in single precision), so a QA seed reproduces it exactly.
// [uav, target, controllerIdentity, create] -> [] or
// [key, profile, parameters, stage, bearingFromTargetDeg, createdAt]
//   HIGH_DIVE parameters: [heightAboveTarget m, diveAngle deg]
//   FLANK parameters:     [side +1/-1, offsetAngle deg, ringRadius m], stage "LEG" -> "IN"
params [["_uav", objNull], ["_target", objNull], ["_controllerIdentity", []], ["_create", false]];
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
		case ((_settings # 7) != ""): {_settings # 7};
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
_record = [_key, _profile, _parameters, ["", "LEG"] select (_profile == "FLANK"), _bearing, time];
_uav setVariable ["A3UE_FPV_attackEngagement", _record];
_record
