// 1.0.9 friendly FPV swarm: a swarm drone's task and the replicated mode other code and clients
// read (sent only on change). INBOUND, LOITER and LEAVE show as SEARCHING, ATTACK (the AI run-in) as
// TRACKING, DIVE as TERMINAL_VECTOR. Server-local task, owner = server.
// [uav, task] -> nothing
params [["_uav", objNull], ["_task", ""]];
if (isNull _uav || {!(_task in ["INBOUND", "LOITER", "ATTACK", "DIVE", "LEAVE"])}) exitWith {};
private _mode = switch (_task) do {
	case "ATTACK": {"TRACKING"};
	case "DIVE": {"TERMINAL_VECTOR"};
	default {"SEARCHING"};
};
if ((_uav getVariable ["A3UE_FPV_swarmTask", ""]) != _task) then {
	_uav setVariable ["A3UE_FPV_swarmTask", _task];
	_uav setVariable ["A3UE_FPV_swarmTaskAt", time];
};
if ((_uav getVariable ["A3UE_FPV_mode", ""]) != _mode) then {_uav setVariable ["A3UE_FPV_mode", _mode, true];};
