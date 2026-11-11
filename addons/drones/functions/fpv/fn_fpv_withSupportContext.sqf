params ["_context", "_code"];

// This callback-bearing helper is local-only, including AU nested calls.
if (isRemoteExecuted && {remoteExecutedOwner != 2} && {
    isNil "_A3UE_FPV_contextAuthorized" || {!(_A3UE_FPV_contextAuthorized isEqualTo true)}
    || {!([true] call A3UE_fnc_fpv_isTrustedSupportCaller)}
}) exitWith {false};
if !(_context isEqualType createHashMap && {_code isEqualType {}}) exitWith {false};
private _A3UE_FPV_callContext = _context;
call _code
