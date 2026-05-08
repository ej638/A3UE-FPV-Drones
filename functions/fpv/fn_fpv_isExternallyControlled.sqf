params [["_uav", objNull]];

if (isNull _uav) exitWith {false};

if ({isPlayer _x} count (crew _uav) > 0) exitWith {true};
if (isUAVConnected _uav) exitWith {true};

private _uavControl = UAVControl _uav;
private _uavController = if (_uavControl isEqualType []) then {
	_uavControl param [0, objNull]
} else {
	objNull
};

if (!isNull _uavController) exitWith {true};

private _zeusOwner = _uav getVariable ["bis_fnc_moduleRemoteControl_owner", objNull];
if (_zeusOwner isEqualType objNull) exitWith {!isNull _zeusOwner};
if (_zeusOwner isEqualType 0) exitWith {_zeusOwner > 0};

false