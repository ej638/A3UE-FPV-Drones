params [["_uav", objNull]];

if (isNull _uav) exitWith {false};

_uav setVariable ["A3UE_FPV_targetNetId", "", true];
_uav setVariable ["A3UE_FPV_lastInterceptASL", [], true];

true