params [["_uav", objNull]];

if (isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}) exitWith {false};

if (isNull _uav) exitWith {false};
if (!local _uav) exitWith {false};
if !(_uav getVariable ["A3UE_FPV_managed", false]) exitWith {false};
if ((_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) != "FIBER_VISUAL") exitWith {false};
if (_uav getVariable ["A3UE_FPV_fiberTrailRunning", false]) exitWith {true};

private _anchorPos = _uav getVariable ["A3UE_FPV_fiberAnchorPos", []];
if (_anchorPos isEqualTo []) then {
	private _markerName = _uav getVariable ["A3UE_FPV_siteMarker", ""];
	if (_markerName isEqualTo "") then {
		_anchorPos = _uav modelToWorldVisual [0, -0.48, -0.05];
	} else {
		private _markerPos = getMarkerPos _markerName;
		_anchorPos = if (_markerPos isEqualTo [0, 0, 0]) then {
			_uav modelToWorldVisual [0, -0.48, -0.05]
		} else {
			[_markerPos select 0, _markerPos select 1, 0.5]
		};
	};
	_uav setVariable ["A3UE_FPV_fiberAnchorPos", _anchorPos];
};

private _started = false;
isNil {
	if (local _uav && {_uav getVariable ["A3UE_FPV_managed", false]} && {(_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) == "FIBER_VISUAL"} && {!(_uav getVariable ["A3UE_FPV_fiberTrailRunning", false])}) then {
		private _generation = 1 + (_uav getVariable ["A3UE_FPV_fiberGeneration", 0]);
		_uav setVariable ["A3UE_FPV_fiberGeneration", _generation];
		_uav setVariable ["A3UE_FPV_fiberTrailRunning", true];

		private _handle = [_uav, _generation] spawn {
			params ["_uav", "_generation"];

			while {
				alive _uav && {local _uav} &&
				{_uav getVariable ["A3UE_FPV_managed", false]} &&
				{(_uav getVariable ["A3UE_FPV_fiberGeneration", -1]) == _generation} &&
				{_uav getVariable ["A3UE_FPV_fiberTrailRunning", false]}
			} do {
				// Finish one bounded sample before a locality event can invalidate this generation.
				isNil {
					if (local _uav && {(_uav getVariable ["A3UE_FPV_fiberGeneration", -1]) == _generation}) then {
						[_uav] call A3UE_fnc_fpv_updateFiberTrailCompat;
					};
				};
				sleep 0.1;
			};

			isNil {
				if (!isNull _uav && {local _uav} && {(_uav getVariable ["A3UE_FPV_fiberGeneration", -1]) == _generation}) then {
					_uav setVariable ["A3UE_FPV_fiberTrailRunning", false];
					_uav setVariable ["A3UE_FPV_fiberTrailHandle", scriptNull];
				};
			};
		};
		_uav setVariable ["A3UE_FPV_fiberTrailHandle", _handle];
		_started = true;
	};
};

_started || {local _uav && {_uav getVariable ["A3UE_FPV_fiberTrailRunning", false]}}
