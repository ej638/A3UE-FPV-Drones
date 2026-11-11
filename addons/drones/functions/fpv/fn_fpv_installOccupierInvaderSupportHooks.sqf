// One campaign waiter shared by support and Rivals. No save-selection expiry.
if (!isServer || {isRemoteExecuted}) exitWith {false};
if (isNil "A3UE_FPV_supportRegistry") then {missionNamespace setVariable ["A3UE_FPV_supportRegistry", createHashMap];};
missionNamespace setVariable ["A3UE_FPV_integrationHooksEnabled", true];
if (missionNamespace getVariable ["serverInitDone", false]) exitWith {
	["INSTALL"] call A3UE_fnc_fpv_reportIntegrationHooks;
	missionNamespace getVariable ["A3UE_FPV_supportHooksInstalled", false]
};
["CHECK"] call A3UE_fnc_fpv_reportIntegrationHooks;
// Concurrent scheduled callers must claim the one waiter atomically too.
isNil {
	if (missionNamespace getVariable ["A3UE_FPV_supportPatchPending", false]) exitWith {};
	missionNamespace setVariable ["A3UE_FPV_supportPatchPending", true];
	[] spawn {
		private _started = diag_tickTime;
		private _warned = false;
		waitUntil {
			sleep 1;
			if (!_warned && {diag_tickTime - _started > 120}) then {
				_warned = true;
				diag_log "[A3UE_FPV] hooks registered, not ready: waiting for AU serverInitDone/save selection; no installation success claimed";
			};
			missionNamespace getVariable ["serverInitDone", false]
		};
		missionNamespace setVariable ["A3UE_FPV_supportPatchPending", false];
		if (missionNamespace getVariable ["A3UE_FPV_integrationHooksEnabled", true]) then {["INSTALL"] call A3UE_fnc_fpv_reportIntegrationHooks;};
	};
};
false
