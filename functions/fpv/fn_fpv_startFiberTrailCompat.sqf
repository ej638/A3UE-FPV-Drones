params [["_uav", objNull]];

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

_uav setVariable ["A3UE_FPV_fiberTrailRunning", true];

[_uav] spawn {
	params ["_uav"];

	while {
		alive _uav &&
		local _uav &&
		(_uav getVariable ["A3UE_FPV_fiberTrailRunning", false]) &&
		(_uav getVariable ["A3UE_FPV_managed", false])
	} do {
		[_uav] call A3UE_fnc_fpv_updateFiberTrailCompat;
		sleep 0.1;
	};

	if (!isNull _uav) then {
		_uav setVariable ["A3UE_FPV_fiberTrailRunning", false];
	};
	};

true