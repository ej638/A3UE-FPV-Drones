// 1.0.9 friendly FPV swarm: a short radio line to the rebel players (HQ side chat), sent by the
// server only. Fixed message keys and numeric arguments only.
// [string key, [numbers]] -> nothing
params [["_key", ""], ["_args", []]];
if (!hasInterface || {isRemoteExecutedJIP} || {isRemoteExecuted && {remoteExecutedOwner != 2}}) exitWith {};
if !(_key in ["STR_A3UE_FPV_SWARM_LAUNCHED", "STR_A3UE_FPV_SWARM_ON_STATION", "STR_A3UE_FPV_SWARM_LEAVING"]) exitWith {};
if !(_args isEqualType [] && {count _args <= 4} && {(_args findIf {!(_x isEqualType 0) || {!finite _x}}) < 0}) exitWith {};
// SW-2: the commander's menu holds AU's support cooldown until the swarm is on station (as AU's
// planes hold it until they reach the target).
if (_key == "STR_A3UE_FPV_SWARM_ON_STATION") then {A3UE_FPV_swarmArrivedAt = time;};
private _text = format ([localize _key] + _args);
if (_text isEqualTo "") exitWith {};
[playerSide, "HQ"] sideChat _text;
