params [["_uav", objNull], ["_profile", createHashMap]];

if (isNull _uav) exitWith {false};
if (!local _uav) exitWith {false};

private _siteType = _uav getVariable ["A3UE_FPV_siteType", ""];
private _siteMarker = _uav getVariable ["A3UE_FPV_siteMarker", ""];

private _searchHeight = [_profile, "searchHeightAGL", -1] call A3UE_fnc_fpv_profileValue;
if (!(_searchHeight isEqualType 0)) then {
	_searchHeight = -1;
};

if (_searchHeight < 0) then {
	_searchHeight = switch (_siteType) do {
		case "Airport": { 45 };
		case "Outpost": { 35 };
		default { 25 };
	};
};

private _holdRadius = switch (_siteType) do {
	case "Airport": { 300 };
	case "Outpost": { 180 };
	default { 120 };
};

private _centerPos = if (_siteMarker isEqualTo "") then {
	getPosATL _uav
} else {
	getMarkerPos _siteMarker
};

if (_centerPos isEqualTo [0, 0, 0]) then {
	_centerPos = getPosATL _uav;
};

_uav enableAI "ALL";
_uav setBehaviour "CARELESS";
_uav setCombatMode "BLUE";
_uav setSpeedMode "NORMAL";
_uav flyInHeight _searchHeight;

private _nextHoldUpdate = _uav getVariable ["A3UE_FPV_nextHoldUpdate", 0];
if (time >= _nextHoldUpdate) then {
	private _holdTarget = _centerPos getPos [_holdRadius, random 360];
	private _holdTargetATL = +_holdTarget;
	_holdTargetATL set [2, _searchHeight];

	_uav doMove _holdTargetATL;
	_uav setVariable ["A3UE_FPV_holdMoveTarget", _holdTargetATL];
	_uav setVariable ["A3UE_FPV_nextHoldUpdate", time + 5];
};

true