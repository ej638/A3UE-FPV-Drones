params [["_uav", objNull]];

if (isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}) exitWith {false};

if (isNull _uav) exitWith {false};
if (!local _uav) exitWith {false};
if !(_uav getVariable ["A3UE_FPV_managed", false]) exitWith {false};

private _anchorDist = 1.5;
private _maxSpool = 200;
private _now = time;
private _uavPos = _uav modelToWorldVisual [0, -0.48, -0.05];
private _path = _uav getVariable ["A3UE_FPV_fiberLocalPath", _uav getVariable ["kvn_fiber_path", []]];

if !(missionNamespace getVariable ["kvn_showFiber", true]) exitWith {
	if !(_path isEqualTo []) then {
		// Public object state supplies JIP independently of the bootstrap RPC.
		_uav setVariable ["kvn_fiber_path", []];
        _uav setVariable ["A3UE_FPV_fiberLocalPath", []];
        [_uav, "fiber", [[]]] call A3UE_fnc_fpv_sendLifecycle;
		_uav setVariable ["kvn_fiber_length", 0, false];
		_uav setVariable ["kvn_fiber_length_count", 0, false];
		_uav setVariable ["A3UE_FPV_fiberLastSync", _now, false];
	};

	true
};

private _changed = false;
private _len = _uav getVariable ["kvn_fiber_length", -1];
private _lenCount = _uav getVariable ["kvn_fiber_length_count", -1];

if (_len < 0 || {_lenCount != count _path}) then {
	_len = 0;
	for "_i" from 0 to (count _path - 2) do {
		_len = _len + ((_path select _i) distance (_path select (_i + 1)));
	};
};

if (_path isEqualTo []) then {
	private _anchorPos = _uav getVariable ["A3UE_FPV_fiberAnchorPos", []];
	if (_anchorPos isEqualTo []) then {
		_anchorPos = _uavPos;
		_uav setVariable ["A3UE_FPV_fiberAnchorPos", _anchorPos];
	};

	_path pushBack _anchorPos;
	if ((_anchorPos distanceSqr _uavPos) > 0.01) then {
		_path pushBack _uavPos;
		_len = _anchorPos distance _uavPos;
	} else {
		_len = 0;
	};
	_changed = true;
};

private _last = _path select ((count _path) - 1);
private _anchorDistSqr = _anchorDist * _anchorDist;
if ((_last distanceSqr _uavPos) > _anchorDistSqr) then {
	_len = _len + (_last distance _uavPos);
	_path pushBack _uavPos;
	_changed = true;
};

while {(_len > _maxSpool || {count _path > 256}) && {count _path > 2}} do {
	_len = (_len - ((_path select 0) distance (_path select 1))) max 0;
	_path deleteAt 0;
	_changed = true;
};

_uav setVariable ["kvn_fiber_length", _len, false];
_uav setVariable ["kvn_fiber_length_count", count _path, false];
_uav setVariable ["A3UE_FPV_fiberLocalPath", _path];
// Reference assignment on the existing sampler, no history scan/rebuild.
if (_changed || {!(_path isEqualRef (_uav getVariable ["kvn_fiber_path", []]))}) then {
	_uav setVariable ["kvn_fiber_path", _path, false];
};

private _lastSync = _uav getVariable ["A3UE_FPV_fiberLastSync", 0];
if ((_now - _lastSync) >= 0.5) then {
	_uav setVariable ["A3UE_FPV_fiberLastSync", _now, false];
	[_uav, "fiber", [+_path]] call A3UE_fnc_fpv_sendLifecycle;
};

true
