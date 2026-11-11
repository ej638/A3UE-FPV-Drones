// Only data crosses this boundary: no support name, status, force flag or code.
if (!isServer || {isRemoteExecutedJIP}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
if (isNil "_this" || {!(_this isEqualType [])} || {count _this != 6}
    || {!((_this # 0) isEqualType 0)} || {!((_this # 1) isEqualType 0)} || {!((_this # 2) isEqualType 0)}
    || {!((_this # 3) isEqualType "")} || {!((_this # 4) isEqualType "")} || {!((_this # 5) isEqualType [])}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
// Read provenance once before switching scheduled calls to an atomic transaction.
private _sender = remoteExecutedOwner;
private _trustedLocal = call A3UE_fnc_fpv_lifecycleAccess;
private _receive = {
    params [["_id", -1, [0]], ["_episode", -1, [0]], ["_seq", -1, [0]], ["_event", "", [""]], ["_token", "", [""]], ["_payload", [], [[]]]];
    if (count _token > 128 || {!(_event in ["claim", "detonate", "destroy", "fiber", "signal", "control", "release"])}
        || {[_id, _episode, _seq] findIf {!finite _x || {_x != floor _x} || {_x < 0} || {_x > 10000000}} >= 0}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
    private _record = (missionNamespace getVariable ["A3UE_FPV_lifecycles", createHashMap]) getOrDefault [str _id, createHashMap];
    if (count _record == 0) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
    private _previous = _record getOrDefault ["previous", []];
    private _latePrevious = _event == "destroy" && {(_record get "phase") == "closed"}
        && {count _previous == 4} && {_episode == (_previous # 1)} && {serverTime <= (_previous # 3)};
    if (_episode != (_record get "episode") && {!_latePrevious}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
    private _uav = _record get "object";
    private _owner = if (_latePrevious) then {_previous # 0} else {_record get "owner"};
    private _closed = (_record get "phase") == "closed";
    private _actualOwner = if (_closed || {_event == "release"}) then {_owner} else {if (isNull _uav) then {-1} else {owner _uav}};
    private _hc = _actualOwner > 2 && {_actualOwner in (missionNamespace getVariable ["hcArray", []])}
        && {(entities "HeadlessClient_F") findIf {owner _x == _actualOwner} >= 0};
    private _provenance = _trustedLocal || {_sender > 2 && {_sender == _actualOwner}} || {_sender == 0 && {_hc}};
    if (!_provenance) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
    if (_event == "claim") exitWith {
        private _challenge = _record getOrDefault ["challenge", []];
        if (_closed || {count _challenge != 4} || {_seq != 0} || {_payload isNotEqualTo []}
            || {_actualOwner != (_challenge # 0)} || {_token != (_challenge # 2)} || {serverTime > (_challenge # 3)}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
        if (_episode == 0 && {_record get "fiber"}) then {
            private _initial = _uav getVariable ["kvn_fiber_path", []];
            if ([_initial, true] call A3UE_fnc_fpv_validFiberPath) then {_record set ["path", _initial apply {+_x}];};
        };
        private _nextEpisode = _episode + 1;
        if (_nextEpisode > 1000000) exitWith {false};
        _record set ["previous", [_owner, _episode, _record get "token", serverTime + 5]];
        _record set ["owner", _actualOwner];
        _record set ["episode", _nextEpisode];
        _record set ["generation", _challenge # 1];
        _record set ["token", _token];
        _record set ["previousSequences", _record get "sequences"];
        _record set ["sequences", createHashMap];
        _record set ["signalSince", serverTime];
        _record set ["signalEpoch", 0];
        _record set ["autonomous", true];
        _record set ["released", false];
        _uav setVariable ["A3UE_FPV_signalEpoch", 0, true];
        _record deleteAt "challenge";
        _record deleteAt "pendingGeometry";
        private _identity = [_id, _actualOwner, _nextEpisode, _challenge # 1];
        _uav setVariable ["A3UE_FPV_controllerIdentity", _identity, true];
        _uav setVariable ["A3UE_FPV_signalIdentity", _identity + [0], true];
        _uav setVariable ["A3UE_FPV_lifecycleEpisode", _nextEpisode, true];
        _uav setVariable ["A3UE_FPV_controllerOwnerId", _actualOwner, true];
        _uav setVariable ["A3UE_FPV_crocusSignalSnapshot", [], true];
        private _reply = [_uav, "ready", _id, _actualOwner, _nextEpisode, _challenge # 1, _token, +(_record get "path")];
        private _A3UE_FPV_lifecycleAuthorized = A3UE_FPV_lifecycleCapability;
        if (local _uav) then {_reply call A3UE_fnc_fpv_acceptLifecycle;} else {_reply remoteExecCall ["A3UE_fnc_fpv_acceptLifecycle", _actualOwner];};
        true
    };
    if (_token == "" || {_token != (if (_latePrevious) then {_previous # 2} else {_record get "token"})} || {_seq < 1} || {_seq > 1000000}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
    if (_closed && {_event != "destroy" || {serverTime > (_record get "lateUntil")}}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
    if (!_closed && {_event != "release"} && {_actualOwner != _owner || {isNull _uav} || {_record getOrDefault ["released", false]}}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
    private _sequences = _record get (if (_latePrevious) then {"previousSequences"} else {"sequences"});
    // Reject duplicates/reordering before payload traversal, path copies or archive scans.
    if (_seq <= (_sequences getOrDefault [_event, 0])) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
    private _A3UE_FPV_lifecycleAuthorized = A3UE_FPV_lifecycleCapability;
    switch (_event) do {
        case "release": {
            if (_closed || {_payload isNotEqualTo []}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
            _sequences set [_event, _seq];
            _record set ["released", true];
            _record set ["signalSince", serverTime];
            _uav setVariable ["A3UE_FPV_controllerIdentity", [], true];
            _uav setVariable ["A3UE_FPV_signalIdentity", [], true];
            _uav setVariable ["A3UE_FPV_crocusSignalSnapshot", [], true];
            true
        };
        case "detonate": {
            if (_closed || {!(_record get "managed")} || {count _payload != 3}
                || {serverTime < (_record getOrDefault ["nextDetonateAt", -1])}) exitWith {
                if (!isNil "A3UE_FPV_QA_sink") then {
                    private _reason = switch (true) do {
                        case _closed: {"CLOSED"};
                        case (!(_record get "managed")): {"UNMANAGED"};
                        case (count _payload != 3): {"PAYLOAD_SHAPE"};
                        default {"THROTTLED"};
                    };
                    [_uav, "BROKER", ["REJECTED", _reason, _id, _episode, _seq]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);
                };
                call A3UE_fnc_fpv_rejectLifecycle
            };
            _record set ["nextDetonateAt", serverTime + 0.5];
            _payload params ["_strike", "_path", "_ttl"];
            if !(_strike isEqualType createHashMap && {_path isEqualType []} && {_ttl isEqualType 0}
                && {finite _ttl} && {_ttl >= 0} && {_ttl <= 300} && {[_path, true] call A3UE_fnc_fpv_validFiberPath}) exitWith {
                if (!isNil "A3UE_FPV_QA_sink") then {[_uav, "BROKER", ["REJECTED", "PAYLOAD_PATH_OR_TTL", _id, _episode, _seq]] call (missionNamespace getVariable ["A3UE_FPV_QA_sink", {}]);};
                call A3UE_fnc_fpv_rejectLifecycle
            };
            _sequences set [_event, _seq];
            [_uav, _id, _strike, _path, _ttl] call A3UE_fnc_fpv_commitDetonation
        };
        case "destroy": {
            if (!(_record get "fiber") || {count _payload != 2}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
            if (_record get "archived" || {(_sequences getOrDefault [_event, 0]) > 0}) exitWith {true};
            _payload params ["_path", "_ttl"];
            if !(_path isEqualType [] && {_ttl isEqualType 0} && {finite _ttl} && {_ttl > 0} && {_ttl <= 300}
                && {count _path > 0} && {count _path <= 256}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
            if (_closed) exitWith {
                _sequences set [_event, _seq];
                [_path, _ttl, str _id] call A3UE_fnc_fpv_archiveFiber
            };
            if (serverTime < (_record getOrDefault ["nextDestroyAt", -1])) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
            _record set ["nextDestroyAt", serverTime + 0.5];
            if !([_path] call A3UE_fnc_fpv_validFiberPath) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
            _sequences set [_event, _seq];
            // Native onDestroy precedes deleteVehicle. One bounded pending tail is
            // eligible only after a server kill/delete event; never archive a live report.
            _record set ["pendingGeometry", [_path apply {+_x}, _ttl]];
            _record set ["pendingUntil", serverTime + 5];
            if (!alive _uav) then {[_id, "kill"] call A3UE_fnc_fpv_endLifecycle;};
            true
        };
        case "fiber": {
            if (_closed || {!(_record get "managed")} || {!(_record get "fiber")} || {count _payload != 1}
                || {!((_payload # 0) isEqualType [])} || {count (_payload # 0) > 256}
                || {serverTime < (_record getOrDefault ["nextFiberAt", -1]) && {(_payload # 0) isNotEqualTo [] || {(_record get "path") isEqualTo []}}}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
            _record set ["nextFiberAt", serverTime + 0.5];
            if !([_payload # 0, true] call A3UE_fnc_fpv_validFiberPath) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
            _sequences set [_event, _seq];
            _record set ["path", (_payload # 0) apply {+_x}];
            _uav setVariable ["A3UE_FPV_fiberAccepted", [_id, _episode, _seq, +(_payload # 0)], true];
            // Keep public object/JIP state. The producer retains a separate local
            // tail so a server echo cannot erase points added during transit.
            _uav setVariable ["kvn_fiber_path", (_payload # 0) apply {+_x}, true];
            true
        };
        case "control": {
            if (_closed || {count _payload != 1} || {!((_payload # 0) isEqualType true)}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
            _sequences set [_event, _seq];
            if ((_record get "autonomous") == !(_payload # 0)) exitWith {true};
            _record set ["autonomous", !(_payload # 0)];
            private _signalEpoch = 1 + (_record getOrDefault ["signalEpoch", 0]);
            _record set ["signalEpoch", _signalEpoch];
            _uav setVariable ["A3UE_FPV_signalEpoch", _signalEpoch, true];
            _uav setVariable ["A3UE_FPV_signalIdentity", [_id, _owner, _episode, _record get "generation", _signalEpoch], true];
            _record set ["signalSince", serverTime];
            _uav setVariable ["A3UE_FPV_crocusSignalSnapshot", [], true];
            true
        };
        case "signal": {
            if (_closed || {!(_record get "managed")} || {!(_record get "autonomous")} || {count _payload != 3}
                || {(_uav getVariable ["A3UE_FPV_vendorId", ""]) != "armafpv"}
                || {[_uav] call A3UE_fnc_fpv_isExternallyControlled}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
            _payload params ["_at", "_quality", "_context"];
            if !(_at isEqualType 0 && {finite _at} && {_at >= (_record get "signalSince")}
                && {_at >= (_record getOrDefault ["lastSignalAt", -1])}
                && {serverTime - _at >= 0} && {serverTime - _at <= 2}
                && {_quality isEqualType 0} && {finite _quality} && {_quality >= 0} && {_quality <= 1}
                && {_context isEqualType []} && {count _context == 14}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
            private _names = ["altAGL", "distance", "maxDistance", "inJammer", "jammerFactor", "obstacleCount", "terrainMask"];
            private _valid = true;
            for "_i" from 0 to 6 do {
                private _v = _context # (_i * 2 + 1);
                if ((_context # (_i * 2)) != (_names # _i) || {if (_i == 3) then {!(_v isEqualType true)} else {!(_v isEqualType 0) || {!finite _v} || {abs _v > 1000000}}}) then {_valid = false;};
            };
            if (!_valid || {serverTime < (_record getOrDefault ["nextSignalAt", -1])}) exitWith {call A3UE_fnc_fpv_rejectLifecycle};
            _sequences set [_event, _seq];
            _record set ["nextSignalAt", serverTime + 0.3];
            _record set ["lastSignalAt", _at];
            _uav setVariable ["A3UE_FPV_crocusSignalSnapshot", [_record get "netId", [_id, _owner, _episode, _record get "generation", _record getOrDefault ["signalEpoch", 0]], _seq, _at, _quality, +_context], true];
            true
        };
        default {call A3UE_fnc_fpv_rejectLifecycle};
    }
};
private _accepted = false;
isNil {_accepted = _this call _receive;};
_accepted
