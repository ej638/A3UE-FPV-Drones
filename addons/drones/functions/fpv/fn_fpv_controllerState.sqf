// LT-2 controller state: what one controller keeps between its ticks. runController's scheduled
// script creates it once and paces the ticks; the frame director ticks the same state while the
// drone attacks. Owner-local, never broadcast. Also installs this machine's director once (one
// EachFrame handler per machine, idle cost a single empty-list test).
// [uav, generation] -> state hashmap
params [["_uav", objNull], ["_generation", -1]];
// F5 / PB-01: an RPC from a client never creates controller state or handlers (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {createHashMap};
if (isNil "A3UE_FPV_directorHandler") then {
	A3UE_FPV_directorStates = [];
	// [director ticks, director s, longest tick s, frames over budget, frames with attackers,
	//  most attackers, scheduled wake-ups, their lateness s, longest lateness s, scheduled ticks,
	//  longest frame s, window start (diag_tickTime)]
	A3UE_FPV_perf = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, diag_tickTime];
	A3UE_FPV_controllerStates = [];
	missionNamespace setVariable ["A3UE_FPV_perfNextAt", diag_tickTime + 10];
	A3UE_FPV_directorHandler = addMissionEventHandler ["EachFrame", {call A3UE_fnc_fpv_directorFrame}];
};
private _state = createHashMapFromArray [
	["uav", _uav], ["generation", _generation],
	// The controller keeps the identity and profile it started with (its original ticket).
	["identity", +(_uav getVariable ["A3UE_FPV_controllerIdentity", []])],
	["profile", [_uav] call A3UE_fnc_fpv_getProfile],
	["nextGuidance", 0], ["nextScan", 0], ["nextLink", 0], ["nextStrikeRetry", 0],
	["nextTargetability", 0], ["targetabilitySuspended", true],
	["aiRecoveryPending", (_uav getVariable ["A3UE_FPV_nativeControl", []]) isNotEqualTo []],
	// Model-space anchors are owner-local; every new controller must trace its own solution.
	["impactCacheReady", false],
	["nextRetarget", 0], ["role", ""], ["wingHot", false],
	["running", true], ["hot", false], ["listed", false], ["dueAt", 0], ["tickedAt", -1]
];
// Counted by the director's evidence line, which also drops finished controllers.
A3UE_FPV_controllerStates pushBack _state;
_state
