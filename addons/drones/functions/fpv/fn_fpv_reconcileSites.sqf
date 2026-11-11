// Readiness/HC-membership catch-up only; never replay stock AU constructors.
if (!isServer || {isRemoteExecuted} || {!(missionNamespace getVariable ["A3UE_FPV_siteReady", false])}) exitWith {false};
private _states = A3UE_FPV_siteLifecycle;
{
	private _markerX = _x;
	isNil {
		if (markerShape _markerX == "") exitWith {};
		if !((spawner getVariable [_markerX, -1]) in [0, 1]) exitWith {};
		private _siteSide = sidesX getVariable [_markerX, sideUnknown];
		if !(_siteSide in [Occupants, Invaders]) exitWith {};
		// Existing pending identities use the queue's grace/epoch/capture fences.
		// Membership changes must not bypass them or revive a closed generation.
		if (_markerX in _states) exitWith {};
		private _siteType = [_markerX, ""] call A3UE_fnc_fpv_resolveSiteType;
		private _state = createHashMapFromArray [
			["generation", 1], ["siteType", _siteType], ["phase", "active"],
			["producer", -1], ["appliedGeneration", 0], ["appliedActive", false],
			["siteSide", _siteSide], ["status", "pending"], ["cleanupDrones", []],
			["recovered", true]
		];
		_states set [_markerX, _state];
		A3UE_FPV_siteTracked set [_markerX, true];
		A3UE_FPV_siteQueue set [_markerX, true];
	};
} forEach (missionNamespace getVariable ["A3UE_FPV_siteMarkers", []]);
true
