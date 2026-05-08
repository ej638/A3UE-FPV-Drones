params [["_uav", objNull], ["_target", objNull], ["_detonationReason", ""], ["_fallbackReason", ""]];

if (isNull _uav) exitWith {false};
if (_uav getVariable ["A3UE_FPV_detonating", false]) exitWith {true};

if (_detonationReason isEqualTo "") then {
	_detonationReason = _uav getVariable ["A3UE_FPV_lastDetonationReason", "NONE"];
};

if (_fallbackReason isEqualTo "") then {
	_fallbackReason = _uav getVariable ["A3UE_FPV_lastFallbackReason", "NONE"];
};

_uav setVariable ["A3UE_FPV_lastDetonationReason", _detonationReason, true];
_uav setVariable ["A3UE_FPV_lastFallbackReason", _fallbackReason, true];

_uav setVariable ["A3UE_FPV_detonating", true];
_uav setVariable ["DB_fpv_isDetonating", true, true];

private _vendorId = _uav getVariable ["A3UE_FPV_vendorId", ""];
private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];
private _uavPosAsl = getPosASL _uav;
private _impactPointAsl = _uav getVariable ["A3UE_FPV_lastImpactPointASL", []];
private _impactTargetNetId = _uav getVariable ["A3UE_FPV_lastImpactTargetNetId", ""];
private _impactValid = (_uav getVariable ["A3UE_FPV_lastImpactValid", false]) && {
	_impactPointAsl isEqualType [] && {
		count _impactPointAsl >= 3 && {
			_target isEqualType objNull && {
				(isNull _target) || {_impactTargetNetId == netId _target}
			}
		}
	}
};
private _useImpactDelivery = _impactValid && {_detonationReason in ["DIRECT_CONTACT", "PREDICTED_IMPACT"]};
private _deliveryPosAsl = +_uavPosAsl;
private _deliveryDir = vectorDir _uav;
private _deliveryUp = vectorUp _uav;
private _deliveryMode = if (_useImpactDelivery) then {"IMPACT_POINT"} else {"UAV_POSITION"};
private _impactMode = _uav getVariable ["A3UE_FPV_terminalImpactMode", "NONE"];
private _impactSurfaceType = _uav getVariable ["A3UE_FPV_lastImpactSurfaceType", "none"];

if (_useImpactDelivery) then {
	private _approachVector = _impactPointAsl vectorDiff _uavPosAsl;
	private _approachMagnitude = vectorMagnitude _approachVector;

	if (_approachMagnitude > 0.01) then {
		private _approachDir = _approachVector vectorMultiply (1 / _approachMagnitude);
		_deliveryPosAsl = _impactPointAsl vectorDiff (_approachDir vectorMultiply 0.35);
		_deliveryDir = _approachDir;
	} else {
		_deliveryPosAsl = +_impactPointAsl;
	};
};

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

private _recentDetonations = missionNamespace getVariable ["A3UE_FPV_recentDetonations", []];
_recentDetonations pushBack createHashMapFromArray [
	["at", time],
	["uavNetId", _uav getVariable ["A3UE_FPV_netId", netId _uav]],
	["targetNetId", if (isNull _target) then {_impactTargetNetId} else {netId _target}],
	["siteMarker", _uav getVariable ["A3UE_FPV_siteMarker", ""]],
	["vendorId", _vendorId],
	["payloadRole", _payloadRole],
	["profileId", _uav getVariable ["A3UE_FPV_profileId", ""]],
	["impactMode", _impactMode],
	["surfaceType", _impactSurfaceType],
	["detonationReason", _detonationReason],
	["fallbackReason", _fallbackReason],
	["deliveryMode", _deliveryMode],
	["impactPointASL", _impactPointAsl],
	["uavPosASL", _uavPosAsl],
	["deliveryPosASL", _deliveryPosAsl],
	["controllerOwnerId", _uav getVariable ["A3UE_FPV_controllerOwnerId", -1]],
	["linkState", _uav getVariable ["A3UE_FPV_linkState", ""]]
];

while {count _recentDetonations > 20} do {
	_recentDetonations deleteAt 0;
};

missionNamespace setVariable ["A3UE_FPV_recentDetonations", _recentDetonations, true];

private _missile = createVehicle [_missileType, _uav modelToWorld [0, 0, 0], [], 0, "CAN_COLLIDE"];
if (isNull _missile) exitWith {false};

if (_useImpactDelivery) then {
	_missile setPosASL _deliveryPosAsl;
};

_missile setVectorDirAndUp [_deliveryDir, _deliveryUp];

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