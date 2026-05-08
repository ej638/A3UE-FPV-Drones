params [["_uav", objNull], ["_target", objNull], ["_profile", createHashMap]];

if (isNull _uav || {isNull _target}) exitWith {false};
if (_uav getVariable ["A3UE_FPV_detonating", false]) exitWith {false};

private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];
private _distance = (getPosASL _uav) vectorDistance (getPosASL _target);
private _distance2D = _uav distance2D _target;
private _heightDelta = abs (((getPosASL _uav) select 2) - ((getPosASL _target) select 2));

private _defaultDistance = switch (_payloadRole) do {
	case "AT": { 18 };
	case "RECON": { 12 };
	default { 14 };
};

private _defaultDistance2D = switch (_payloadRole) do {
	case "AT": { 9 };
	case "RECON": { 6 };
	default { 7 };
};

private _detonationDistance = [_profile, "detonationDistance", _defaultDistance] call A3UE_fnc_fpv_profileValue;
private _detonationDistance2D = [_profile, "detonationDistance2D", _defaultDistance2D] call A3UE_fnc_fpv_profileValue;
private _verticalWindow = [_profile, "detonationVerticalWindow", 12] call A3UE_fnc_fpv_profileValue;

(_distance <= _detonationDistance) || (_distance2D <= _detonationDistance2D && {_heightDelta <= _verticalWindow})