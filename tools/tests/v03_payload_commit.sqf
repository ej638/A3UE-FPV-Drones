// DESTRUCTIVE engine fixture: one disposable real managed UAV, actual server payload.
// Server-local execVM, isolated range; restart copied campaign afterward.
// Tests production commit and receipt data, not actual explosion/submunition/credit.
// DIRECT_CONTACT is an allowed proposal reason, not proof of engine contact.
params [
    ["_uav", objNull, [objNull]],
    ["_deliveryPos", [], [[]]],
    ["_target", objNull, [objNull]]
];
if (!isServer || {isRemoteExecuted} || {isNull _uav} || {!alive _uav}
    || {!(_uav getVariable ["A3UE_FPV_managed", false])}
    || {[_uav] call A3UE_fnc_fpv_isExternallyControlled}
    || {count _deliveryPos != 3}) exitWith {
    diag_log "[A3UE FPV TEST V03] BLOCKED: live autonomous managed UAV and approved ASL pose required on server";
};
private _id = _uav getVariable ["A3UE_FPV_netId", netId _uav];
private _life = _uav getVariable ["A3UE_FPV_lifecycleIdServer", -1];
private _crew = +(crew _uav);
private _groups = _crew apply {group _x};
private _strike = createHashMapFromArray [
    ["uavNetId", _id], ["targetNetId", netId _target],
    ["deliveryPosASL", +_deliveryPos], ["deliveryDir", [0.6, 0.8, 0]],
    ["deliveryUp", [0, 0, 1]], ["detonationReason", "DIRECT_CONTACT"], ["fallbackReason", "NONE"]
];
private _records = {
    (missionNamespace getVariable ["A3UE_FPV_recentDetonations", []]) select {
        (_x getOrDefault ["uavNetId", ""]) == _id && {(_x getOrDefault ["lifecycleId", -1]) == _life}
    }
};
if (_life < 0 || {(call _records) isNotEqualTo []}) exitWith {
    diag_log "[A3UE FPV TEST V03] BLOCKED: invalid or previously committed lifetime";
};
private _cases = 0;
private _failures = 0;
private _assert = {
    params ["_case", "_ok"];
    _cases = _cases + 1;
    if (!_ok) then {_failures = _failures + 1;};
    diag_log format ["[A3UE FPV TEST V03] COMMIT case=%1 pass=%2", _case, _ok];
};
// Negative controls cannot race the normal owner controller in this slice.
isNil {
    ["wrong lifetime rejected", !([_uav, _life + 1, _strike] call A3UE_fnc_fpv_commitDetonation)] call _assert;
    private _badPose = +_strike;
    _badPose set ["deliveryDir", [0, 0, 0]];
    ["degenerate pose rejected", !([_uav, _life, _badPose] call A3UE_fnc_fpv_commitDetonation)] call _assert;
    private _badCoordinate = +_strike;
    _badCoordinate set ["deliveryPosASL", [1000001, 0, 100]];
    ["oversized delivery coordinate rejected", !([_uav, _life, _badCoordinate] call A3UE_fnc_fpv_commitDetonation)] call _assert;
    private _badReason = +_strike;
    _badReason set ["detonationReason", "ARBITRARY_STATUS"];
    ["arbitrary proposal reason rejected", !([_uav, _life, _badReason] call A3UE_fnc_fpv_commitDetonation)] call _assert;
    ["rejections leave no commit", (call _records) isEqualTo [] && {!(_uav getVariable ["A3UE_FPV_detonationCommitted", false])}] call _assert;
};
if (_failures > 0) exitWith {
    diag_log format ["[A3UE FPV TEST V03] END result=FAIL cases=%1 failures=%2; negative commit contract; restart", _cases, _failures];
};
// execVM is scheduled: production must enter its own non-suspending server slice.
private _accepted = [_uav, _life, _strike] call A3UE_fnc_fpv_commitDetonation;
if (!_accepted) exitWith {
    diag_log format ["[A3UE FPV TEST V03] BLOCKED: positive commit rejected id=%1 life=%2; inspect active-site/support/safety preconditions", _id, _life];
};
private _rows = call _records;
["one recorded production commit", count _rows == 1] call _assert;
if (count _rows == 1) then {
    private _row = _rows # 0;
    ["requested position retained within 2 cm", vectorMagnitude ((_row get "projectilePosASL") vectorDiff _deliveryPos) <= 0.02] call _assert;
    ["direction retained", ((_row get "projectileDir") vectorDotProduct [0.6, 0.8, 0]) >= 0.99999] call _assert;
    ["up retained", ((_row get "projectileUp") vectorDotProduct [0, 0, 1]) >= 0.99999] call _assert;
    ["no velocity before trigger", vectorMagnitude (_row get "projectileVelocity") <= 0.01] call _assert;
    ["create and trigger in same frame", (_row get "projectileCreatedFrameNo") == (_row get "triggerFrameNo")] call _assert;
    ["server-local projectile", (_row get "projectileOwnerId") == 2] call _assert;
    ["shot parents assigned synchronously", (_row get "shotParentNetIds") isEqualTo (_row get "requestedShotParentNetIds")] call _assert;
    ["virtual pilot alive at trigger", _crew isNotEqualTo [] && {(_row get "shotParentsAlive") # 0}] call _assert;
    ["trigger time recorded", (_row get "triggerAt") >= (_row get "committedAt") && {(_row get "triggerTickTime") >= 0}] call _assert;
    private _ammoCfg = configFile >> "CfgAmmo" >> (_row get "ammoClass");
    ["resolved ammo and identity recorded", isClass _ammoCfg && {(_row get "payloadEventId") == format ["managed:%1:%2", _id, _life]}] call _assert;
    diag_log ["V03", "TRIGGER_RECORD", _row, "COMMIT EVIDENCE ONLY: effect count, explosion pose, submunition and AU credit require observers"];
};
[_uav, _life, _strike] call A3UE_fnc_fpv_commitDetonation;
["late duplicate adds no record", count (call _records) == count _rows] call _assert;
private _deadline = diag_tickTime + 20;
waitUntil {sleep 0.1; isNull _uav || {diag_tickTime >= _deadline}};
["production cleanup deletes UAV and crew", isNull _uav && {_crew findIf {!isNull _x} < 0}] call _assert;
diag_log ["V03", "CLEANUP_GROUPS", _groups apply {isNull _x}];
diag_log format ["[A3UE FPV TEST V03] END result=%1 cases=%2 failures=%3; COMMIT ONLY; restart", ["PASS", "FAIL"] select (_failures > 0), _cases, _failures];
