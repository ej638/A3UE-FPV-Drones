// LOW_RUN stage of this drone's current engagement (EN-02, lowest line LL-1), owner-local, read-only.
// The record (A3UE_FPV_lowRun, never broadcast) is keyed like the engagement: controller identity,
// target and target revision. A record from another identity, target or revision, or one that has
// ended (logged), is no longer current: "" is returned, so the low run can never leak into a later
// attack (the return pass after a flip is a normal dive).
// [uav, target] -> "" | "CHECKING" | "READY" | "DESCEND" | "SKIM" | "SPRINT"
params [["_uav", objNull], ["_target", objNull]];
if (isNull _uav || {isNull _target}) exitWith {""};
private _record = _uav getVariable ["A3UE_FPV_lowRun", createHashMap];
if (!(_record isEqualType createHashMap) || {count _record == 0} || {_record getOrDefault ["logged", false]}) exitWith {""};
if ((_record getOrDefault ["key", []]) isNotEqualTo [_uav getVariable ["A3UE_FPV_controllerIdentity", []], netId _target,
	_uav getVariable ["A3UE_FPV_targetRevision", 0]]) exitWith {""};
_record getOrDefault ["stage", ""]
