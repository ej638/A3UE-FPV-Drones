params [
	["_supportName", ""],
	["_targPos", []],
	["_side", sideUnknown],
	["_contextMap", createHashMap]
];

if !(call A3UE_fnc_fpv_lifecycleAccess) exitWith {""};

if !(_targPos isEqualType [] && {count _targPos >= 2}) exitWith {""};

if (isNil "A3A_supportMarkerCount") then {
	A3A_supportMarkerCount = 0;
};

A3A_supportMarkerCount = A3A_supportMarkerCount + 1;

private _markerName = format ["A3UE_FPV_support_%1_%2", _supportName, A3A_supportMarkerCount];
private _marker = createMarker [_markerName, _targPos];

if (_marker isEqualTo "") exitWith {""};

_marker setMarkerShape "ICON";
_marker setMarkerType "mil_destroy";
_marker setMarkerAlpha 0;

private _trackedSupportMarkers = missionNamespace getVariable ["A3UE_FPV_supportTransientMarkers", []];
if !(_trackedSupportMarkers isEqualType []) then {
	_trackedSupportMarkers = [];
};
_trackedSupportMarkers pushBackUnique _markerName;
missionNamespace setVariable ["A3UE_FPV_supportTransientMarkers", _trackedSupportMarkers];

_marker