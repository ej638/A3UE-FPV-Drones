params [["_uav", objNull]];

if (isNull _uav) exitWith {objNull};

private _targetNetId = _uav getVariable ["A3UE_FPV_targetNetId", ""];
if (_targetNetId isEqualTo "") exitWith {objNull};

private _target = objectFromNetId _targetNetId;
if (isNull _target) exitWith {objNull};
if !(alive _target) exitWith {objNull};

_target