// Preserve native settings/HUD behavior and arguments; repair only managed autonomy.
// Optional bindings are retried at registration/bootstrap, without a waiter.
isNil {
	if (!(missionNamespace getVariable ["A3UE_FPV_crocusTargetabilityAdapterInstalled", false])
		&& {!isNil "DB_fnc_fpv_handleSettings"} && {DB_fnc_fpv_handleSettings isEqualType {}}) then {
		missionNamespace setVariable ["A3UE_FPV_crocusNativeHandleSettings", DB_fnc_fpv_handleSettings];
		DB_fnc_fpv_handleSettings = {
			// Keep the native scan in its original scheduling context.
			private _result = _this call (missionNamespace getVariable "A3UE_FPV_crocusNativeHandleSettings");
			isNil {
				// Cache contains only managed local Crocus objects; no extra vehicle scan.
				{[_y] call A3UE_fnc_fpv_applyTargetability;} forEach (missionNamespace getVariable ["A3UE_FPV_targetabilityDrones", createHashMap]);
			};
			if (isNil "_result") exitWith {};
			_result
		};
		missionNamespace setVariable ["A3UE_FPV_crocusTargetabilityAdapterInstalled", true];
	};
	if (!(missionNamespace getVariable ["A3UE_FPV_uaTargetabilityAdapterInstalled", false])
		&& {!isNil "UA_fnc_fpv_handleSettings"} && {UA_fnc_fpv_handleSettings isEqualType {}}) then {
		missionNamespace setVariable ["A3UE_FPV_uaNativeHandleSettings", UA_fnc_fpv_handleSettings];
		UA_fnc_fpv_handleSettings = {
			private _result = _this call (missionNamespace getVariable "A3UE_FPV_uaNativeHandleSettings");
			private _player = missionNamespace getVariable ["bis_fnc_moduleRemoteControl_unit", player];
			private _uav = getConnectedUAV _player;
			if (!isNull _uav) then {[_uav] call A3UE_fnc_fpv_applyTargetability;};
			if (isNil "_result") exitWith {};
			_result
		};
		missionNamespace setVariable ["A3UE_FPV_uaTargetabilityAdapterInstalled", true];
	};
};

(missionNamespace getVariable ["A3UE_FPV_crocusTargetabilityAdapterInstalled", false])
	|| {missionNamespace getVariable ["A3UE_FPV_uaTargetabilityAdapterInstalled", false]}
