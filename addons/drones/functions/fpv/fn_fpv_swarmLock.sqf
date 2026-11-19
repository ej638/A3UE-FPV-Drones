// 1.0.9 friendly FPV swarm: only the server flies a swarm drone (EJ, 17 November: no player
// takeover). Runs on every machine with a player, sent by the server with the drone as its JIP key
// (removed with the drone), and stops this player's UAV terminal from connecting to it.
// Known gap: the lock is per unit, so a player who respawns while a swarm is up could connect.
// The controller still pauses under any direct control (project rule).
// [uav] -> nothing
params [["_uav", objNull]];
if (!hasInterface || {isRemoteExecuted && {remoteExecutedOwner != 2}}) exitWith {};
if (isNull _uav || {isNull player}) exitWith {};
player disableUAVConnectability [_uav, true];
