params [["_uav", objNull, [objNull]], ["_event", "", [""]], ["_payload", [], [[]]]];
if (isRemoteExecutedJIP || {isRemoteExecuted && {remoteExecutedOwner != 2} && {!(call A3UE_fnc_fpv_lifecycleAccess)}}) exitWith {false};
if (isNull _uav || {!local _uav && {_event != "release"}}) exitWith {false};
private _ticket = _uav getVariable ["A3UE_FPV_lifecycleTicket", []];
if (count _ticket != 3) exitWith {false};
private _sequences = _uav getVariable ["A3UE_FPV_reportSequences", createHashMap];
private _seq = 1 + (_sequences getOrDefault [_event, 0]);
if (_seq > 1000000) exitWith {false};
_sequences set [_event, _seq];
_uav setVariable ["A3UE_FPV_reportSequences", _sequences];
private _report = [_ticket # 0, _ticket # 1, _seq, _event, _ticket # 2, _payload];
if (isServer) exitWith {_report call A3UE_fnc_fpv_reportLifecycle};
_report remoteExecCall ["A3UE_fnc_fpv_reportLifecycle", 2];
true
