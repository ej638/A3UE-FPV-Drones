// Deliberate link-loss diagnostic; owner LOCAL execVM. Restores exact node even on control/ownership loss.
params [["_u", objNull], ["_seconds", 5]];
if (isRemoteExecuted || {!canSuspend} || {isNull _u} || {!local _u} || {_seconds < 1} || {_seconds > 15}
	|| {(_u getVariable ["A3UE_FPV_linkModel", ""]) != "RADIO"}) exitWith {diag_log "UAQA LINK BLOCKED owner-local radio specimen required";};
private _claimed = false;
isNil {
	if (!(_u getVariable ["A3UE_FPV_QA_linkInjection", false])) then {
		_u setVariable ["A3UE_FPV_QA_linkInjection", true];
		_u setVariable ["A3UE_FPV_QA_linkCancel", false]; _claimed = true;
	};
};
if (!_claimed) exitWith {diag_log "UAQA LINK BLOCKED: this specimen already has a link injection";};
private _node = _u getVariable ["A3UE_FPV_controlPosATL", []];
_u setVariable ["A3UE_FPV_controlPosATL", (getPosATL _u) vectorAdd [15000,0,0]];
if (!isNil "A3UE_FPV_QA_sink") then {[_u,"INJECTION",["CONTROL_NODE_OUT_OF_RANGE",_seconds]] call A3UE_FPV_QA_sink;};
private _until = diag_tickTime + _seconds;
waitUntil {sleep 0.05; isNull _u || {_u getVariable ["A3UE_FPV_QA_linkCancel", false]} || {diag_tickTime >= _until}};
if (!isNull _u) then {
	_u setVariable ["A3UE_FPV_controlPosATL", _node];
	_u setVariable ["A3UE_FPV_QA_linkInjection", nil];
	_u setVariable ["A3UE_FPV_QA_linkCancel", nil];
};
diag_log ["UAQA LINK RESTORED", netId _u, _node];
