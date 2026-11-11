params [["_markerX", "", [""]], ["_winner", sideUnknown, [sideUnknown]]];

if (!isServer || {isRemoteExecutedJIP} || {!([false] call A3UE_fnc_fpv_isTrustedSupportCaller)}) exitWith {false};
if (isNil "sidesX" || {sidesX getVariable [_markerX, sideUnknown] != _winner}) exitWith {false};
private _changed = false;
isNil {
	private _state = (missionNamespace getVariable ["A3UE_FPV_siteLifecycle", createHashMap]) getOrDefault [_markerX, createHashMap];
	if (count _state == 0 || {_winner == (_state getOrDefault ["siteSide", sideUnknown])}) exitWith {};
	_state set ["phase", "closed"];
	_state set ["captured", true];
	_state set ["closeReason", "captured"];
	_state set ["status", "captured"];
	// Fence ordnance now, even while the bounded queue is busy with another site.
	private _entry = A3UE_FPV_registry getOrDefault [_markerX, createHashMap];
	{if (!isNull _x) then {_x setVariable ["A3UE_FPV_siteRetired", true, true];};} forEach (_entry getOrDefault ["drones", []]);
	A3UE_FPV_siteQueue set [_markerX, true];
	_changed = true;
};
_changed
