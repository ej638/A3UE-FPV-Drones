params [["_uav", objNull]];

if (isNull _uav) exitWith {false};

private _crew = crew _uav;
if ((_crew findIf {isPlayer _x}) >= 0) exitWith {true};

private _uavControl = UAVControl _uav;
if ((_uavControl param [1, ""]) in ["DRIVER", "GUNNER"]) exitWith {true};
if ((_uavControl param [3, ""]) in ["DRIVER", "GUNNER"]) exitWith {true};

// remoteControlled can only inspect crew local to this machine.
if ((_crew findIf {local _x && {!isNull (remoteControlled _x)}}) >= 0) exitWith {true};

(([_uav] + _crew) findIf {
	private _controller = _x getVariable ["bis_fnc_moduleRemoteControl_owner", objNull];
	if (_controller isEqualType objNull) then {
		!isNull _controller && {isPlayer _controller}
	} else {
		_controller isEqualType 0 && {_controller > 0}
	}
}) >= 0
