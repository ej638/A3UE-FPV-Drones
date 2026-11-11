// UA native replacement copies object variables, but not handlers or scripts.
// Service stays unavailable for this managed lifetime, including pending deletion.
// Optional bindings are installed on every machine and retried without a waiter.
isNil {
	if (!(missionNamespace getVariable ["A3UE_FPV_uaPayloadUiAdapterInstalled", false])
		&& {!isNil "UA_fnc_fpv_canChangePayload"} && {UA_fnc_fpv_canChangePayload isEqualType {}}) then {
		missionNamespace setVariable ["A3UE_FPV_uaNativeCanChangePayload", UA_fnc_fpv_canChangePayload];
		private _wrapper = {
			params [["_uav", objNull]];
			if (_uav getVariable ["A3UE_FPV_managed", false]
				|| {(_uav getVariable ["A3UE_FPV_netId", ""]) isNotEqualTo ""}) exitWith {false};
			_this call (missionNamespace getVariable "A3UE_FPV_uaNativeCanChangePayload")
		};
		UA_fnc_fpv_canChangePayload = _wrapper;
		missionNamespace setVariable ["A3UE_FPV_uaPayloadUiAdapterInstalled", UA_fnc_fpv_canChangePayload isEqualTo _wrapper];
	};
	if (!(missionNamespace getVariable ["A3UE_FPV_uaPayloadServerAdapterInstalled", false])
		&& {!isNil "UA_fnc_fpv_serverChangePayload"} && {UA_fnc_fpv_serverChangePayload isEqualType {}}) then {
		missionNamespace setVariable ["A3UE_FPV_uaNativeServerChangePayload", UA_fnc_fpv_serverChangePayload];
		private _wrapper = {
			params [["_uav", objNull]];
			// Guard before native _force handling, inventory use, locks or creation.
			if (_uav getVariable ["A3UE_FPV_managed", false]
				|| {(_uav getVariable ["A3UE_FPV_netId", ""]) isNotEqualTo ""}) exitWith {
				if (isServer && {missionNamespace getVariable ["A3UE_FPV_debug", false]}) then {
					diag_log format ["[A3UE_FPV] uaPayloadServiceRejected netId=%1 managedId=%2 remote=%3 sender=%4 payload=%5 force=%6",
						netId _uav, _uav getVariable ["A3UE_FPV_netId", ""], isRemoteExecuted,
						if (isRemoteExecuted) then {remoteExecutedOwner} else {0}, _this param [1, "EMPTY"], _this param [3, false]];
				};
				objNull
			};
			// Preserve native caller validation, arguments, return and scheduling.
			_this call (missionNamespace getVariable "A3UE_FPV_uaNativeServerChangePayload")
		};
		UA_fnc_fpv_serverChangePayload = _wrapper;
		missionNamespace setVariable ["A3UE_FPV_uaPayloadServerAdapterInstalled", UA_fnc_fpv_serverChangePayload isEqualTo _wrapper];
	};
	// F5: UA's config hit handler (onDestroy) detonates the drone and deletes its crew and airframe
	// alive, so AU would refund a prepaid drone and the loss line would have no killer. For a managed
	// drone that UA is about to detonate, write the loss line with the hit source and mark the drone
	// consumed first. UA's own guards decide (replicated from the pinned fpv_ua onDestroy); the
	// native call, its arguments and its result are unchanged. Optional: not a stock prerequisite.
	if (!(missionNamespace getVariable ["A3UE_FPV_uaDestroyAdapterInstalled", false])
		&& {!isNil "UA_fnc_fpv_onDestroy"} && {UA_fnc_fpv_onDestroy isEqualType {}}) then {
		missionNamespace setVariable ["A3UE_FPV_uaNativeOnDestroy", UA_fnc_fpv_onDestroy];
		private _wrapper = {
			params [["_uav", objNull], ["_source", objNull], ["_hitDamage", 0], ["_instigator", objNull]];
			if (_uav isEqualType objNull && {!isNull _uav} && {local _uav} && {_uav getVariable ["A3UE_FPV_managed", false]}
				&& {_hitDamage isEqualType 0} && {_hitDamage > 0}
				&& {!(_uav getVariable ["UA_FPV_Detonated", false])}
				&& {!(_uav getVariable ["UA_FPV_PayloadSwapProtected", false])}) then {
				if !(_source isEqualType objNull) then {_source = objNull;};
				if !(_instigator isEqualType objNull) then {_instigator = objNull;};
				private _crew = crew _uav;
				private _technical = (isNull _source || {_source isEqualTo _uav} || {_source in _crew})
					&& {isNull _instigator || {_instigator isEqualTo _uav} || {_instigator in _crew}};
				private _settling = (_uav getVariable ["UA_FPV_PayloadSpawnSettling", false]) && {_technical}
					&& {(vectorMagnitude (velocity _uav)) < 2};
				private _payload = if (isNil "UA_fnc_fpv_getPayloadType") then {""} else {[_uav] call UA_fnc_fpv_getPayloadType};
				if (!_settling && {!(_payload in ["EMPTY", "NET", "RPG18", "AKS74"])}) then {
					if (isServer) then {
						[_uav, _source, _instigator, (missionNamespace getVariable ["A3UE_FPV_lifecycleIndex", createHashMap]) getOrDefault [netId _uav, -1],
							"UA_HIT"] call A3UE_fnc_fpv_logDroneLoss;
					};
					[_uav] call A3UE_fnc_fpv_consumePool;
				};
			};
			_this call (missionNamespace getVariable "A3UE_FPV_uaNativeOnDestroy")
		};
		UA_fnc_fpv_onDestroy = _wrapper;
		missionNamespace setVariable ["A3UE_FPV_uaDestroyAdapterInstalled", UA_fnc_fpv_onDestroy isEqualTo _wrapper];
	};
};

(missionNamespace getVariable ["A3UE_FPV_uaPayloadUiAdapterInstalled", false])
	&& {missionNamespace getVariable ["A3UE_FPV_uaPayloadServerAdapterInstalled", false]}
