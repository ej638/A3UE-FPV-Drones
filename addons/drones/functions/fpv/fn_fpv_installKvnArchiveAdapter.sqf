if (isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}) exitWith {false};
// Replace only native archive publication; delegate UI, payload and cleanup to KVN.
if (missionNamespace getVariable ["A3UE_FPV_kvnArchiveAdapterInstalled", false]) exitWith {true};
if (isNil "DB_kvn_fnc_fpv_onDestroy" || {!(DB_kvn_fnc_fpv_onDestroy isEqualType {})}) exitWith {false};

if (isNil "A3UE_FPV_kvnCreatedEH") then {
    A3UE_FPV_kvnCreatedEH = addMissionEventHandler ["EntityCreated", {
        params ["_entity"];
        if (_entity isKindOf "frtz_drone_kvn_base_F") then {
            [_entity] spawn {params ["_uav"]; sleep 0; [_uav] call A3UE_fnc_fpv_trackKvnLifecycle;};
        };
    }];
    {[_x] call A3UE_fnc_fpv_trackKvnLifecycle;} forEach (vehicles select {_x isKindOf "frtz_drone_kvn_base_F"});
};
private _installed = false;
isNil {
	if (missionNamespace getVariable ["A3UE_FPV_kvnArchiveAdapterInstalled", false]) exitWith {_installed = true;};
	private _nativeDestroy = DB_kvn_fnc_fpv_onDestroy;
	if !(_nativeDestroy isEqualType {}) exitWith {};
	missionNamespace setVariable ["A3UE_FPV_kvnNativeOnDestroy", _nativeDestroy];
	DB_kvn_fnc_fpv_onDestroy = {
		params [["_uav", objNull, [objNull]]];
		if (canSuspend) exitWith {
			private _result = nil;
			isNil {_result = _this call DB_kvn_fnc_fpv_onDestroy;};
			if (isNil "_result") exitWith {};
			_result
		};
		if (isNull _uav) exitWith {};
		if !(typeOf _uav in (missionNamespace getVariable ["DB_kvn_fpv_dronesArray", []])) exitWith {
			_this call (missionNamespace getVariable "A3UE_FPV_kvnNativeOnDestroy")
		};
		if (_uav getVariable ["A3UE_FPV_kvnDestroyHandled", false]) exitWith {};
		_uav setVariable ["A3UE_FPV_kvnDestroyHandled", true];
		// F4-2 evidence: KVN detonates and deletes the airframe on any hit, so a managed KVN
		// lost that way never reaches MPKilled. Its config hit handler passes [unit, source,
		// damage, instigator]. A settled strike has already closed the lifecycle.
		if (isServer && {_uav getVariable ["A3UE_FPV_managed", false]}) then {
			private _source = _this param [1, objNull];
			private _instigator = _this param [3, objNull];
			if !(_source isEqualType objNull) then {_source = objNull;};
			if !(_instigator isEqualType objNull) then {_instigator = objNull;};
			[_uav, _source, _instigator, (missionNamespace getVariable ["A3UE_FPV_lifecycleIndex", createHashMap]) getOrDefault [netId _uav, -1],
				"KVN_HIT"] call A3UE_fnc_fpv_logDroneLoss;
		};
		// F5: KVN always detonates here, so the managed drone is consumed (no AU refund).
		if (_uav getVariable ["A3UE_FPV_managed", false]) then {[_uav] call A3UE_fnc_fpv_consumePool;};
		private _path = _uav getVariable ["kvn_fiber_path", []];
		private _ttl = missionNamespace getVariable ["kvn_fiberTTL", 20];
        // Native manual/damage callbacks produce a report before native deletion.
        // The server kill/delete event supplies eligibility; a token alone does not.
        if (local _uav && {_path isEqualType []} && {count _path > 0} && {count _path <= 256}
            && {_ttl isEqualType 0} && {finite _ttl} && {_ttl > 0}) then {
            [_uav, "destroy", [_path, _ttl min 300]] call A3UE_fnc_fpv_sendLifecycle;
        };
		// The captured callback reads this once, before deleting the UAV. Its archive
		// branch is skipped; all other native behavior still receives the original args.
		_uav setVariable ["kvn_fiber_path", [], false];
		private _result = _this call (missionNamespace getVariable "A3UE_FPV_kvnNativeOnDestroy");
		if (!isNull _uav) then {_uav setVariable ["kvn_fiber_path", _path, false];};
		if (isNil "_result") exitWith {};
		_result
	};
	missionNamespace setVariable ["A3UE_FPV_kvnArchiveAdapterInstalled", true];
	_installed = true;
};

_installed
