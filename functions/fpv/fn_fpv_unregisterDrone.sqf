params [["_uav", objNull], ["_uavNetId", ""], ["_reason", ""]];

_reason;

if (!isServer) exitWith {false};

if (_uavNetId isEqualTo "" && {!isNull _uav}) then {
	_uavNetId = _uav getVariable ["A3UE_FPV_netId", netId _uav];
};

if (_uavNetId isEqualTo "") exitWith {false};

private _registry = missionNamespace getVariable ["A3UE_FPV_registry", createHashMap];
private _registryChanged = false;

{
	private _markerX = _x;
	private _entry = _y;
	private _drones = _entry getOrDefault ["drones", []];
	private _filteredDrones = [];
	private _entryChanged = false;

	{
		if (isNull _x) then {
			_entryChanged = true;
		} else {
			private _candidateNetId = _x getVariable ["A3UE_FPV_netId", netId _x];
			if (_candidateNetId isEqualTo _uavNetId) then {
				_entryChanged = true;
			} else {
				_filteredDrones pushBack _x;
			};
		};
	} forEach _drones;

	if (_entryChanged) then {
		_entry set ["drones", _filteredDrones];
		_entry set ["lastCleanup", serverTime];
		_entry set ["lastCleanupReason", _reason];
		_entry set ["lastCleanupNetId", _uavNetId];

		if ((_entry getOrDefault ["status", "registered"]) == "active" && {_filteredDrones isEqualTo []}) then {
			_entry set ["status", "depleted"];
		};

		_registry set [_markerX, _entry];
		_registryChanged = true;
	};
} forEach _registry;

if (_registryChanged) then {
	missionNamespace setVariable ["A3UE_FPV_registry", _registry];
};

_registryChanged