params [["_uav",objNull],["_target",objNull],["_profile",createHashMap]];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {false};
if (isNull _uav || {isNull _target}) exitWith {false};
if ((_uav getVariable ["A3UE_FPV_mode",""]) != "TERMINAL_VECTOR") exitWith {false};
private _identity = if (isNil "_controllerIdentity") then {+(_uav getVariable ["A3UE_FPV_controllerIdentity",[]])} else {+_controllerIdentity};
[_uav,_target,_profile,_identity param [3,-1],_identity] call A3UE_fnc_fpv_runTerminalVector
