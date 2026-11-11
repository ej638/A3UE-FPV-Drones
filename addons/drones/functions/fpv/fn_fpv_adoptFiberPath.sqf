params [["_uav", objNull], ["_path", []], ["_generation", -1]];
if (isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}) exitWith {false};
if (isNull _uav || {!local _uav} || {!(_uav getVariable ["A3UE_FPV_managed", false])}
    || {(_uav getVariable ["A3UE_FPV_controllerGeneration", -1]) != _generation}
    || {!([_path, true] call A3UE_fnc_fpv_validFiberPath)}) exitWith {false};
// Exactly once per successful controller claim; same-generation normalization
// can run again without replacing the local path or its unsent tail.
if ((_uav getVariable ["A3UE_FPV_fiberAdoptGeneration", -2]) == _generation) exitWith {true};
private _length = 0;
for "_i" from 1 to (count _path - 1) do {_length = _length + ((_path # (_i - 1)) distance (_path # _i));};
private _adopted = _path apply {+_x};
_uav setVariable ["A3UE_FPV_fiberLocalPath", _adopted];
_uav setVariable ["kvn_fiber_path", _adopted];
_uav setVariable ["kvn_fiber_length", _length];
_uav setVariable ["kvn_fiber_length_count", count _path];
_uav setVariable ["A3UE_FPV_fiberLastSync", time];
_uav setVariable ["A3UE_FPV_fiberAdoptGeneration", _generation];
true
