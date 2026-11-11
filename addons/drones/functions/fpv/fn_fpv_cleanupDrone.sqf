params [["_uav", objNull], ["_preserveControl", false]];

if (!isServer) exitWith {false};
// The validated server strike worker can inherit its owner's RPC context.
private _strikeAuthorized = !isNil "_A3UE_FPV_strikeAuthorized" && {_A3UE_FPV_strikeAuthorized isEqualTo true}
	&& {_uav getVariable ["A3UE_FPV_detonationCommitted", false]};
if (!(call A3UE_fnc_fpv_lifecycleAccess) && {!_strikeAuthorized}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
if (isNull _uav) exitWith {false};

private _cleanupState = 0;
// Claim once without scheduled interleaving; stop the owner controller before deletion arrives.
isNil {
	if (_preserveControl && {!(_uav getVariable ["A3UE_FPV_preserveControlOnCleanup", false])}) then {
		_uav setVariable ["A3UE_FPV_preserveControlOnCleanup", true, true];
	};
	if (_uav getVariable ["A3UE_FPV_cleanupPending", false]) then {
		_cleanupState = 1;
	} else {
		if (_uav getVariable ["A3UE_FPV_managed", false]) then {
			_uav setVariable ["A3UE_FPV_cleanupPending", true];
			_uav setVariable ["A3UE_FPV_managed", false, true];
			_cleanupState = 2;
            private _id = (missionNamespace getVariable ["A3UE_FPV_lifecycleIndex", createHashMap]) getOrDefault [netId _uav, -1];
            [_id, "retire"] call A3UE_fnc_fpv_endLifecycle;
		};
	};
};
if (_cleanupState != 2) exitWith {_cleanupState == 1};

[_uav] spawn {
	params ["_uav"];
	// F5 kill credit: a committed airframe is unmanaged, closed and hidden 1000 m above its strike.
	// Its crew is the warhead's shot parent, so keep it 1.5 s while the blast is resolved.
	if (_uav getVariable ["A3UE_FPV_detonationCommitted", false]) then {sleep 1.5;};
	while {!isNull _uav} do {
		if (local _uav) then {
			[_uav, _uav getVariable ["A3UE_FPV_preserveControlOnCleanup", false]] call A3UE_fnc_fpv_deleteLocal;
		} else {
			[_uav, _uav getVariable ["A3UE_FPV_preserveControlOnCleanup", false]] remoteExecCall ["A3UE_fnc_fpv_deleteLocal", _uav];
		};
		sleep 1;
	};
};

true
