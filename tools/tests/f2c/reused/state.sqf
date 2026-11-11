// F2R-only transition table, also read by offline state regression tests.
params ["_s","_next"];
private _edges = [
    ["QUEUED","PREFLIGHT"],["QUEUED","REFUSED"],
    ["PREFLIGHT","PREPARING"],["PREPARING","REVIEW"],["PREPARING","LAUNCHING"],
    ["LAUNCHING","CAPTURING"],["CAPTURING","EXPORTING"],
    ["QUEUED","FINALIZING"],["PREFLIGHT","FINALIZING"],["PREPARING","FINALIZING"],
    ["REVIEW","FINALIZING"],["LAUNCHING","FINALIZING"],["CAPTURING","FINALIZING"],["EXPORTING","FINALIZING"],
    ["NEEDS_RECOVERY","FINALIZING"],
    ["FINALIZING","OBSERVING_RETENTION"],["FINALIZING","TEARDOWN"],["OBSERVING_RETENTION","TEARDOWN"],
    ["TEARDOWN","STOPPED"],["FINALIZING","NEEDS_RECOVERY"],["OBSERVING_RETENTION","NEEDS_RECOVERY"],["TEARDOWN","NEEDS_RECOVERY"]
];
private _old = _s getOrDefault ["state",""];
if (!([_old,_next] in _edges)) exitWith {
    diag_log ["F2R_AUTO",1,_s get "ticket","STATE_REFUSED",diag_tickTime,[_old,_next]];
    _s set ["cancel",true]; false
};
_s set ["state",_next];
diag_log ["F2R_AUTO",1,_s get "ticket","STATE",diag_tickTime,[_next]];
true
