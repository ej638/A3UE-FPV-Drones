if (!isServer || {isRemoteExecutedJIP}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
if (isNil "_this" || {!(_this isEqualType [])} || {count _this != 3}
    || {!((_this # 0) isEqualType objNull)} || {!((_this # 1) isEqualType 0)} || {!((_this # 2) isEqualType 0)}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
// Read provenance once before switching scheduled calls to an atomic transaction.
private _sender = remoteExecutedOwner;
private _trustedLocal = call A3UE_fnc_fpv_lifecycleAccess;
private _receive = {
    params [["_uav", objNull, [objNull]], ["_baseEpisode", -1, [0]], ["_generation", -1, [0]]];
    if (isNull _uav || {!alive _uav} || {!finite _baseEpisode} || {_baseEpisode != floor _baseEpisode} || {_baseEpisode < 0} || {_baseEpisode > 1000000} || {!finite _generation} || {_generation < 0} || {_generation > 1000000} || {_generation != floor _generation}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
    private _id = (missionNamespace getVariable ["A3UE_FPV_lifecycleIndex", createHashMap]) getOrDefault [netId _uav, -1];
    private _record = (missionNamespace getVariable ["A3UE_FPV_lifecycles", createHashMap]) getOrDefault [str _id, createHashMap];
    if (count _record == 0 || {(_record get "phase") != "live"} || {!((_record get "object") isEqualTo _uav)}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
    private _actualOwner = owner _uav;
    private _hc = _actualOwner > 2 && {_actualOwner in (missionNamespace getVariable ["hcArray", []])}
        && {(entities "HeadlessClient_F") findIf {owner _x == _actualOwner} >= 0};
    // HC zero can request a challenge for the actual registered owner. Only that
    // owner receives its secret; confirming it is mandatory before issuing an episode.
    if (!_trustedLocal && {!(_sender > 2 && {_sender == _actualOwner})} && {!(_sender == 0 && {_hc})}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
    // Generations are owner-local. Promotion and newer claims fence delayed native
    // requests from this owner without constraining a different owner's counter.
    private _pending = _record getOrDefault ["challenge", []];
    if ((_actualOwner == (_record get "owner") && {_generation < (_record get "generation")})
        || {count _pending == 4 && {(_pending # 0) == _actualOwner} && {_generation < (_pending # 1)}}
        || {_actualOwner == (_record getOrDefault ["managedGenerationOwner", -1])
            && {_generation < (_record getOrDefault ["managedGenerationFloor", -1])}}) exitWith {false};
    if (serverTime < (_record getOrDefault ["nextClaimAt", -1])) exitWith {false};
    _record set ["nextClaimAt", serverTime + 0.25];
    if (_actualOwner == (_record get "owner") && {_generation == (_record get "generation")}
        && {!(_record getOrDefault ["released", false])} && {(_record get "token") != ""}
        && {_baseEpisode <= (_record get "episode")}) exitWith {
        // Recover a lost ready reply without issuing another episode or token.
        private _reply = [_uav, "ready", _id, _actualOwner, _record get "episode", _generation, _record get "token", +(_record get "path")];
        private _A3UE_FPV_lifecycleAuthorized = A3UE_FPV_lifecycleCapability;
        if (local _uav) then {_reply call A3UE_fnc_fpv_acceptLifecycle;} else {_reply remoteExecCall ["A3UE_fnc_fpv_acceptLifecycle", _actualOwner];};
        true
    };
    if (_baseEpisode != (_record get "episode")) exitWith {
        private _reply = [_uav, "retry", _id, _actualOwner, _record get "episode", _generation, "", []];
        private _A3UE_FPV_lifecycleAuthorized = A3UE_FPV_lifecycleCapability;
        if (local _uav) then {_reply call A3UE_fnc_fpv_acceptLifecycle;} else {_reply remoteExecCall ["A3UE_fnc_fpv_acceptLifecycle", _actualOwner];};
        false
    };
    private _token = format ["%1:%2:%3:%4", _id, _record get "episode", diag_tickTime, random 1000000000];
    _record set ["challenge", [_actualOwner, _generation, _token, serverTime + 5]];
    _record set ["released", true];
    _uav setVariable ["A3UE_FPV_signalIdentity", [], true];
    _uav setVariable ["A3UE_FPV_crocusSignalSnapshot", [], true];
    private _reply = [_uav, "challenge", _id, _actualOwner, _baseEpisode, _generation, _token, []];
    if (local _uav) then {
        private _A3UE_FPV_lifecycleAuthorized = A3UE_FPV_lifecycleCapability;
        _reply call A3UE_fnc_fpv_acceptLifecycle;
    } else {_reply remoteExecCall ["A3UE_fnc_fpv_acceptLifecycle", _actualOwner];};
    true
};
private _accepted = false;
isNil {_accepted = _this call _receive;};
_accepted
