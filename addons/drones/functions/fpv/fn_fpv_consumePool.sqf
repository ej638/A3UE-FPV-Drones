// F5 accounting: a drone that detonates (a managed strike or the vendor's native hit detonation)
// is consumed, not returned. AU refunds a prepaid (attack/defence) vehicle or fight-capable crew
// member that is deleted alive, as for an asset going back to its pool, and the strike retires the
// airframe and crew alive. Switching a consumed drone and its crew to AU's unpaid "legacy" pool
// makes that retirement neutral; a switched airframe's damage is cleared so AU's legacy branch
// cannot charge d*C on top of the prepaid cost. Site stock is already legacy (AU-02): unchanged.
// Healthy despawn and expiry are not consumption and keep AU's refunds. Where the UAV is local
// (owner or server), O(crew), no world scan. [uav] -> number of objects switched
params [["_uav", objNull]];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {0};
if (isNull _uav) exitWith {0};
private _switched = 0;
private _objects = [_uav];
{_objects pushBackUnique _x;} forEach ((crew _uav) + (_uav getVariable ["A3UE_FPV_crewUnits", []]));
{
	if (!isNull _x && {(_x getVariable ["A3A_resPool", "legacy"]) in ["attack", "defence"]}) then {
		_x setVariable ["A3A_resPool", "legacy", true];
		_switched = _switched + 1;
		if (_x isEqualTo _uav && {local _uav} && {(damage _uav) > 0}) then {_uav setDamage [0, false];};
	};
} forEach _objects;
_switched
