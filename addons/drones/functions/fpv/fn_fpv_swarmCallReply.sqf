// 1.0.9 friendly FPV swarm (SW-2): the server's answer to the commander's menu call (swarmCall),
// on the commander's machine. Stored for the waiting launch (SCRT_fnc_ui_launchSupport, our wrapper).
// [ok, reason or swarm id, token] -> nothing
params [["_ok", false], ["_why", ""], ["_token", 0]];
if (!hasInterface || {isRemoteExecutedJIP} || {isRemoteExecuted && {remoteExecutedOwner != 2}}) exitWith {};
if !(_ok isEqualType true && {_why isEqualType ""} && {_token isEqualType 0}) exitWith {};
missionNamespace setVariable ["A3UE_FPV_swarmCallReply", [_ok, _why, _token]];
