params [["_uav", objNull]];

if (isNull _uav) exitWith {false};
if (!local _uav) exitWith {false};

private _anchorDist = 1.5;
private _maxSpool = 200;
private _now = time;
private _uavPos = _uav modelToWorldVisual [0, -0.48, -0.05];
private _path = _uav getVariable ["kvn_fiber_path", []];

if !(missionNamespace getVariable ["kvn_showFiber", true]) exitWith {
	if !(_path isEqualTo []) then {
		_uav setVariable ["kvn_fiber_path", [], false];
		_uav setVariable ["kvn_fiber_length", 0, false];
		_uav setVariable ["kvn_fiber_length_count", 0, false];
		_uav setVariable ["kvn_lastSync", _now, false];

		if (isNil "DB_kvn_fnc_fpv_receivePath") then {
			_uav setVariable ["kvn_fiber_path", [], true];
		} else {
			[_uav, []] remoteExecCall ["DB_kvn_fnc_fpv_receivePath", -clientOwner, _uav];
		};
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

while {_len > _maxSpool && {count _path > 2}} do {
	_len = (_len - ((_path select 0) distance (_path select 1))) max 0;
	_path deleteAt 0;
	_changed = true;
};

_uav setVariable ["kvn_fiber_length", _len, false];
_uav setVariable ["kvn_fiber_length_count", count _path, false];
if (_changed) then {
	_uav setVariable ["kvn_fiber_path", _path, false];
};

private _lastSync = _uav getVariable ["kvn_lastSync", 0];
if (_changed || {(_now - _lastSync) >= 2}) then {
	_uav setVariable ["kvn_lastSync", _now, false];

	if (isNil "DB_kvn_fnc_fpv_receivePath") then {
		_uav setVariable ["kvn_fiber_path", _path, true];
	} else {
		[_uav, _path] remoteExecCall ["DB_kvn_fnc_fpv_receivePath", -clientOwner, _uav];
	};
};

true