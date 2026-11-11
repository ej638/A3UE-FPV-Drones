params [["_params", [], [[]]], ["_function", "", [""]], ["_context", [], [[]]]];

if (isRemoteExecutedJIP) exitWith {false};
if (!isServer && {hasInterface}) exitWith {false};
if ((!isRemoteExecuted && {!isServer}) || {isRemoteExecuted && {remoteExecutedOwner != 2}}) exitWith {false};
if !(_function in ["A3A_fnc_createAIAirplane", "A3A_fnc_createAIOutposts", "A3A_fnc_createAIresources", "A3A_fnc_createAIMilbase"]) exitWith {false};
if (count _context != 5 || {(_params param [0, ""]) != (_context # 0)}) exitWith {false};
private _worker = missionNamespace getVariable [_function, {}];
// Dynamic scope lasts for the complete stock AU worker, including its wait and
// teardown. Only fixed function names and original AU params cross the wire.
private _A3UE_FPV_siteWorkerContext = +_context;
_params call _worker
