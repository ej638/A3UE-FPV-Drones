// 1.0.9 friendly FPV swarm: a swarm drone gives its target back and returns to the loiter ring; the
// brain may hand it another at its next pass. The target can be hidden from the whole swarm for a
// while (out of sight, friendlies near it). A leaving swarm turns the drone round at its next pass.
// [uav, hide seconds, reason, detail (SW-1e: who made it unsafe; logged as why=)] -> nothing
params [["_uav", objNull], ["_hide", 0], ["_reason", ""], ["_detail", "", [""]]];
if (isNull _uav) exitWith {};
private _record = (missionNamespace getVariable ["A3UE_FPV_swarms", createHashMap]) getOrDefault [_uav getVariable ["A3UE_FPV_swarmId", ""], createHashMap];
private _targetId = _uav getVariable ["A3UE_FPV_targetNetId", ""];
if (_hide > 0 && {_targetId != ""} && {count _record > 0}) then {
	(_record get "hidden") set [_targetId, time + _hide];
};
if (_targetId != "") then {
	_uav setVariable ["A3UE_FPV_targetNetId", "", true];
	_uav setVariable ["A3UE_FPV_targetRevision", 1 + (_uav getVariable ["A3UE_FPV_targetRevision", 0]), true];
};
_uav setVariable ["A3UE_FPV_swarmDive", []];
_uav setVariable ["A3UE_FPV_lastImpactValid", false];
[_uav, "LOITER"] call A3UE_fnc_fpv_swarmSetTask;
if (_reason != "") then {
	if (count _record > 0) then {_record set ["drops", 1 + (_record getOrDefault ["drops", 0])];};
	diag_log format ["[A3UE_FPV] swarm id=%1 event=DROP drone=%2 target=%3 reason=%4 hideS=%5%6",
		_uav getVariable ["A3UE_FPV_swarmId", ""], netId _uav, _targetId, _reason, _hide, ["", format [" why=%1", _detail]] select (_detail != "")];
};
