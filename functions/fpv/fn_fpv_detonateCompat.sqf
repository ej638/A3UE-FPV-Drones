params [["_uav", objNull], ["_target", objNull]];

if (isNull _uav) exitWith {false};
if (_uav getVariable ["A3UE_FPV_detonating", false]) exitWith {true};

_uav setVariable ["A3UE_FPV_detonating", true];
_uav setVariable ["DB_fpv_isDetonating", true, true];

private _vendorId = _uav getVariable ["A3UE_FPV_vendorId", ""];
private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];
private _missileCandidates = switch (_payloadRole) do {
	case "AT": { ["FPV_RPG42_AT", "R_PG32V_F", "M_NLAW_AT_F"] };
	default { ["R_TBG32V_F"] };
};

private _missileType = "";
{
	if (isClass (configFile >> "CfgAmmo" >> _x)) exitWith {
		_missileType = _x;
	};
} forEach _missileCandidates;

if (_missileType isEqualTo "") exitWith {
	false
};

[objNull, _uav getVariable ["A3UE_FPV_netId", netId _uav], "detonate"] remoteExecCall ["A3UE_fnc_fpv_unregisterDrone", 2];

if (_vendorId isEqualTo "kvn") then {
	private _path = _uav getVariable ["kvn_fiber_path", []];
	if !(_path isEqualTo []) then {
		private _ttl = missionNamespace getVariable ["kvn_fiberTTL", 20];
		private _now = time;
		if (_ttl > 0) then {
			missionNamespace setVariable [
				"kvn_deadFibers",
				(missionNamespace getVariable ["kvn_deadFibers", []]) + [[_path, _now + _ttl, _now, +_path]],
				true
			];
		};
	};
};

private _killer = driver _uav;
private _instigator = (UAVControl _uav) param [0, objNull];

if (!isNull _killer) then {
	if (local _killer) then {
		_killer setCaptive false;
	} else {
		[_killer, false] remoteExec ["setCaptive", 2];
	};
};

private _missile = createVehicle [_missileType, _uav modelToWorld [0, 0, 0]];
if (isNull _missile) exitWith {false};

_missile setVectorDirAndUp [vectorDir _uav, vectorUp _uav];

[_missile, [_killer, _instigator]] remoteExec ["setShotParents", 2];
[_missile, true] remoteExec ["hideObjectGlobal", 2];

{
	_uav deleteVehicleCrew _x;
} forEach crew _uav;

deleteVehicle _uav;

[_missile, [_killer, _instigator]] spawn {
	params ["_missile", "_shotParents"];

	private _deadline = time + 1;
	waitUntil {
		sleep 0.01;
		isNull _missile || {(getShotParents _missile) isEqualTo _shotParents} || {time > _deadline}
	};

	if (!isNull _missile) then {
		triggerAmmo _missile;
	};
	};

true