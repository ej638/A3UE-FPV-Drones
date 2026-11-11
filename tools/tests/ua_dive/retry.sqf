// Optional diagnostic fault injection. Hosted owner/server only; no admission bypass.
// [uav, 2] execVM ...; changes exactly two real detonate reports to a degenerate pose.
// The real broker/commit rejects them; subsequent reports use the original implementation.
params [["_u", objNull], ["_rejectCount", 2]];
if (!isServer || {isRemoteExecuted} || {!local _u} || {!canSuspend} || {isNull _u}
	|| {!(_rejectCount in [1,2])} || {!isNil "A3UE_FPV_QA_retryOriginal"}) exitWith {diag_log "UAQA RETRY BLOCKED hosted local specimen / one injection required";};
A3UE_FPV_QA_retryOriginal = A3UE_fnc_fpv_sendLifecycle;
A3UE_FPV_QA_retryUav = _u;
A3UE_FPV_QA_retryId = netId _u;
A3UE_FPV_QA_retryLeft = _rejectCount;
A3UE_FPV_QA_retryCancel = false;
private _wrapper = {
	params ["_vehicle", "_event", "_payload"];
	private _original = {};
	// Capture the sender and alter the bounded payload before a restore worker can interleave.
	isNil {
		_original = missionNamespace getVariable ["A3UE_FPV_QA_retryOriginal", A3UE_fnc_fpv_sendLifecycle];
		if (_vehicle == (missionNamespace getVariable ["A3UE_FPV_QA_retryUav", objNull]) && {_event == "detonate"}
			&& {(missionNamespace getVariable ["A3UE_FPV_QA_retryLeft", 0]) > 0}
			&& {!(missionNamespace getVariable ["A3UE_FPV_QA_retryCancel", true])}) then {
			A3UE_FPV_QA_retryLeft = A3UE_FPV_QA_retryLeft - 1;
			_payload = +_payload;
			private _bad = +(_payload # 0); _bad set ["deliveryDir", [0,0,0]]; _payload set [0, _bad];
			if (!isNil "A3UE_FPV_QA_sink") then {[_vehicle, "INJECTION", ["REAL_POSE_REJECTION", A3UE_FPV_QA_retryLeft]] call A3UE_FPV_QA_sink;};
		};
	};
	[_vehicle, _event, _payload] call _original
};
A3UE_fnc_fpv_sendLifecycle = _wrapper;
private _until = diag_tickTime + 60;
waitUntil {sleep 0.05; A3UE_FPV_QA_retryLeft == 0 || {A3UE_FPV_QA_retryCancel} || {isNull _u} || {!local _u} || {diag_tickTime >= _until}};
if (A3UE_fnc_fpv_sendLifecycle isEqualRef _wrapper) then {A3UE_fnc_fpv_sendLifecycle = A3UE_FPV_QA_retryOriginal;};
diag_log ["UAQA RETRY RESTORED", netId _u, "unconsumed", A3UE_FPV_QA_retryLeft];
missionNamespace setVariable ["A3UE_FPV_QA_retryOriginal", nil];
missionNamespace setVariable ["A3UE_FPV_QA_retryUav", nil];
missionNamespace setVariable ["A3UE_FPV_QA_retryLeft", nil];
missionNamespace setVariable ["A3UE_FPV_QA_retryCancel", nil];
missionNamespace setVariable ["A3UE_FPV_QA_retryId", nil];
