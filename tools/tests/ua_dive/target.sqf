// Server Local Exec scheduled: [side, positionATL, moveDistance, heading] execVM ...;
// Creates ONE disposable target soldier. Moving case uses native AI doMove, not teleport samples.
params [["_side", west], ["_pos", []], ["_distance", 0], ["_heading", 90], ["_action", "create"]];
if (!isServer || {isRemoteExecuted}) exitWith {};
if (_action == "cleanup") exitWith {
	private _u = missionNamespace getVariable ["A3UE_FPV_QA_target", objNull];
	private _g = missionNamespace getVariable ["A3UE_FPV_QA_targetGroup", grpNull];
	if (!isNull _u) then {deleteVehicle _u;};
	if (!isNull _g && {units _g isEqualTo []}) then {deleteGroup _g;};
	missionNamespace setVariable ["A3UE_FPV_QA_target", nil]; missionNamespace setVariable ["A3UE_FPV_QA_targetGroup", nil];
};
if (!(_side in [east,west,independent]) || {count _pos != 3}
	|| {!isNull (missionNamespace getVariable ["A3UE_FPV_QA_target", objNull])}) exitWith {if (hasInterface) then {copyToClipboard "Target BLOCKED: combat side, [x,y,z], and cleanup of prior target required";}; diag_log ["A3UE_FPV_QA_TARGET_BLOCKED", "combat side, [x,y,z], and cleanup of prior target required"];};
private _class = switch (_side) do {case east: {"O_Soldier_F"}; case west: {"B_Soldier_F"}; default {"I_Soldier_F"};};
private _g = createGroup [_side, true];
private _u = _g createUnit [_class, _pos, [], 0, "NONE"];
_u setCaptive false; _u setBehaviour "CARELESS"; _u disableAI "AUTOCOMBAT"; _u disableAI "TARGET"; _u disableAI "AUTOTARGET";
removeAllWeapons _u; _u setUnitPos "UP";
if (_distance > 0) then {_u forceSpeed 3; _u doMove (_pos getPos [_distance, _heading]);} else {_u disableAI "PATH";};
missionNamespace setVariable ["A3UE_FPV_QA_target", _u]; missionNamespace setVariable ["A3UE_FPV_QA_targetGroup", _g];
diag_log ["A3UE_FPV_QA_TARGET", netId _u, str _side, _pos, _distance, _heading];
_u
