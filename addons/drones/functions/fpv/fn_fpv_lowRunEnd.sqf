// LOW_RUN end and its one RPT line (lowest line LL-1), owner-local. Every low run ends exactly once:
// COMMITTED (it reached the sprint, then a strike or a miss) or ENDED (control taken, target changed
// or lost, the switch off, a starved scheduler). Nothing is rewritten: a run that ends before its
// hand-off leaves a LOW_RUN engagement, which the dive flies like DIRECT (straight in, no FLANK leg).
// [uav, target, result, reason] -> true when this call ended the low run
//   result "" = COMMITTED from the sprint, else ENDED;
//   "SWEEP" (the controller, after every tick): end a low run whose engagement is over (another
//   identity, target or revision, or a mode outside TRACKING/TERMINAL_VECTOR). Its reason gives the
//   context: "CONTROL" (a player or Zeus took control), "STOPPED" (the controller stopped).
params [["_uav", objNull], ["_target", objNull], ["_result", ""], ["_reason", ""]];
// F5 / PB-01: an RPC from a client never mutates this drone's state (sender fence).
if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};
if (isNull _uav) exitWith {false};
private _record = _uav getVariable ["A3UE_FPV_lowRun", createHashMap];
if (!(_record isEqualType createHashMap) || {count _record == 0} || {_record getOrDefault ["logged", true]}) exitWith {false};
private _stage = _record getOrDefault ["stage", ""];
private _key = _record getOrDefault ["key", []];
if (_result == "SWEEP") then {
	private _mode = _uav getVariable ["A3UE_FPV_mode", ""];
	_reason = switch (true) do {
		case (_reason == "STOPPED"): {
			["LOST", _uav getVariable ["A3UE_FPV_lastDetonationReason", "LOST"]] select (_uav getVariable ["A3UE_FPV_detonating", false])
		};
		case (_reason == "CONTROL"): {"CONTROL"};
		case ([_uav getVariable ["A3UE_FPV_controllerIdentity", []], _uav getVariable ["A3UE_FPV_targetNetId", ""],
			_uav getVariable ["A3UE_FPV_targetRevision", 0]] isNotEqualTo _key): {"TARGET"};
		case (_mode == "LOST_TARGET"): {"MISSED"};
		case !(_mode in ["TRACKING", "TERMINAL_VECTOR"]): {"MODE"};
		default {""};
	};
	_result = "";
};
if (_reason == "") exitWith {false};
_result = ["ENDED", "COMMITTED"] select (_stage == "SPRINT");
_record set ["logged", true];
_record set ["reason", _reason];
_record set ["stage", "ENDED"];
_record set ["check", createHashMap];
private _round = {(round (_this * 10)) / 10};
private _waited = 0;
if ((_uav getVariable ["A3UE_FPV_lowWaiter", []]) isEqualTo [_key, true]) then {_waited = 1;};
private _hopBy = _record getOrDefault ["hopBy", ""];
// The run, in the words of the design: where it handed off and on what glide, where the skim began
// and where it first got within 5 m of the ground, its lowest clearance while skimming, the tallest
// thing the line flew over and what it was, the surveys' count and the most expensive single call.
// -1 = not reached or not measured.
private _minClear = _record getOrDefault ["minClear", 1e9];
diag_log format ["[A3UE_FPV] lowRun id=%1 target=%2 result=%3 reason=%4 heightM=%5 handoffM=%6 glideDeg=%7 skimFromM=%8 under5M=%9 minClearM=%10 hopTopM=%11 hopBy=%12 surveys=%13 sliceMsMax=%14 waited=%15",
	_uav getVariable ["A3UE_FPV_netId", netId _uav], _key param [1, ""], _result, _reason,
	(_record getOrDefault ["height", 0]) call _round, round (_record getOrDefault ["handoffM", -1]),
	(_record getOrDefault ["glideUsed", -1]) call _round, round (_record getOrDefault ["skimFrom", -1]),
	round (_record getOrDefault ["under5M", -1]), ([_minClear, -1] select (_minClear > 1e8)) call _round,
	(_record getOrDefault ["hopTop", 0]) call _round, ["none", _hopBy] select (_hopBy != ""),
	_record getOrDefault ["surveys", 0], (round ((_record getOrDefault ["sliceMsMax", 0]) * 100)) / 100, _waited];
true
