// F4-2 steering envelope for the flip, applied to the existing writer's limits (SI units).
// Pull-up and over the top (PULL/OVER): brake hard toward the flip speed with a higher lateral
// acceleration, turn rate and rate slew, per family (KVN gentler). Return pass (DIVE): speed,
// lateral and descent are the dive envelope again, while the higher turn rate and slew carry
// over so the stored rotation never exceeds the limit (no steering reset). Otherwise unchanged.
// [uav, target, controllerIdentity, profile, limits] -> limits
params [["_uav", objNull], ["_target", objNull], ["_controllerIdentity", []], ["_profile", createHashMap], ["_limits", []]];
if (!(_limits isEqualType []) || {count _limits != 10} || {isNull _uav} || {isNull _target}) exitWith {_limits};
private _record = _uav getVariable ["A3UE_FPV_attackReversal", createHashMap];
if (!(_record isEqualType createHashMap) || {!((_record getOrDefault ["phase", ""]) in ["PULL", "OVER", "DIVE"])}) exitWith {_limits};
private _settings = call A3UE_fnc_fpv_attackSettings;
if (!(_settings # 0) || {!(_settings # 10)}
	|| {(_record getOrDefault ["key", []]) isNotEqualTo [+_controllerIdentity, netId _target,
		_uav getVariable ["A3UE_FPV_targetRevision", 0], _uav getVariable ["A3UE_FPV_terminalVectorEnteredAt", -1]]}) exitWith {_limits};
// Flip speed m/s, braking m/s^2, lateral m/s^2, turn rad/s, rate slew rad/s^2. Offline
// (perfect actuator) from a 34/30/28 m/s pass: overshoot about 19/21/16 m, climb 11/13/10 m,
// flip 1.6-1.9 s (Crocus/KVN/UA). About 3-3.5 g for the quads, gentler for the heavier KVN.
private _flip = switch (_profile getOrDefault ["familyId", ""]) do {
	case "armafpv": {[7, 28, 34, 3.0, 12]};
	case "kvn": {[9, 20, 24, 2.3, 8]};
	default {[8, 25, 30, 2.7, 10]};
};
private _result = +_limits;
_result set [5, (_limits # 5) max (_flip # 3)];
_result set [6, (_limits # 6) max (_flip # 4)];
if ((_record get "phase") != "DIVE") then {
	_result set [0, (_flip # 0) min (_limits # 0)];
	_result set [2, (_limits # 2) max (_flip # 1)];
	_result set [3, (_limits # 3) max (_flip # 2)];
};
_result
