params [["_uav", objNull], ["_target", objNull], ["_profile", createHashMap]];

if (isNull _uav || {isNull _target}) exitWith {false};

private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];
private _distance = (getPosASL _uav) vectorDistance (getPosASL _target);
private _distance2D = _uav distance2D _target;

private _defaultGateDistance = switch (_payloadRole) do {
	case "AT": { 120 };
	case "RECON": { 85 };
	default { 90 };
};

private _defaultGateDistance2D = switch (_payloadRole) do {
	case "AT": { 60 };
	case "RECON": { 40 };
	default { 45 };
};

private _gateDistance = [_profile, "terminalGateDistance", _defaultGateDistance] call A3UE_fnc_fpv_profileValue;
private _gateDistance2D = [_profile, "terminalGateDistance2D", _defaultGateDistance2D] call A3UE_fnc_fpv_profileValue;

(_distance <= _gateDistance) || (_distance2D <= _gateDistance2D)