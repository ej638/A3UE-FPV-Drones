// Local Exec: [] call compileScript ["scripts\ua_dive\catalog.sqf"];
// Read the initialized catalog; don't silently repair a failed startup.
params [["_target", objNull, [objNull]]];
private _rows = [];
{
	private _family = _x;
	{
		private _d = _y;
		private _side = switch (_d get "sideKey") do {case "east": {east}; case "west": {west}; default {independent};};
		private _eligible = if (isNull _target) then {false} else {
			!isNull ([_target, [_side] call A3UE_fnc_fpv_getHostileSides] call A3UE_fnc_fpv_filterTarget)
		};
		if (_d get "canDetonate" && {(_d get "ammoClass") != ""}) then {
			_rows pushBack [_d get "className", _family, _d get "sideKey", _d get "taskRoles",
				_d get "physicalPayload", _d get "ammoClass", _d get "linkModel", _eligible];
		};
	} forEach (_y getOrDefault ["classDescriptors", createHashMap]);
} forEach (missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap]);
_rows sort true;
{diag_log ["A3UE_FPV_QA_CATALOG", _x]} forEach _rows;
if (hasInterface) then {copyToClipboard str _rows;};
_rows
