private _s = missionNamespace getVariable ["A3UE_F2RA",createHashMap];
if (_s getOrDefault ["state",""] != "LAUNCHING" || {_s getOrDefault ["cancel",false]}) exitWith {diag_log ["F2R_PREP","WRAPPER_IDENTITY_OR_PHASE"]; false};
// Extracted tested F2R inline factory; no production edits.
// Scheduled, server LOCAL execVM. Production transient factory; NOT natural site deployment.
// Required map: class, role, target. Optional: count, originATL, altitude, bearing,
// range, spacing, duration, seed, instrument. Positions are never auto-teleported.
params [["_options", createHashMap, [createHashMap]]];
private _motion = missionNamespace getVariable ["A3UE_FPV_QA_motionState",createHashMap];
if ((missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap]) getOrDefault ["active",false]) exitWith {
    if (hasInterface) then {["UA QA BLOCKED: motion preparation busy"] call {params ["_message"]; diag_log ["F2R_PREP",_message];};};
    diag_log ["A3UE_FPV_QA_BLOCKED","MOTION_PREPARATION_BUSY"];
};
if (count _motion > 0 && {!(_motion getOrDefault ["finished",false])}) exitWith {
    if (hasInterface) then {["UA QA BLOCKED: motion fixture/cleanup/export unfinished"] call {params ["_message"]; diag_log ["F2R_PREP",_message];};};
    diag_log ["A3UE_FPV_QA_BLOCKED","MOTION_FIXTURE_BUSY"];
};
private _blocked = {params ["_why"]; if (hasInterface) then {[("UA QA BLOCKED: " + _why)] call {params ["_message"]; diag_log ["F2R_PREP",_message];};}; diag_log ["A3UE_FPV_QA_BLOCKED", _why]; false};
if (!isServer || {isRemoteExecuted} || {!canSuspend}) exitWith {["server Local Exec with execVM required"] call _blocked};
if (missionNamespace getVariable ["A3UE_FPV_debug", false]) exitWith {["debug forces site rolls; use a fresh debug-off diagnostic session"] call _blocked};
if (!(missionNamespace getVariable ["A3UE_FPV_registrationComplete", false])
    || {count (missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap]) == 0}
    || {count (missionNamespace getVariable ["A3UE_FPV_doctrine", createHashMap]) == 0}) exitWith {
    ["ordinary AU/addon initialization not ready; preserve startup evidence first"] call _blocked
};
private _runs = missionNamespace getVariable ["A3UE_FPV_QA_runs", createHashMap];
private _liveRuns = (values _runs) select {!(_x getOrDefault ["cleaned", false])};
if (_liveRuns isNotEqualTo []) exitWith {["clean up the previous run before launching/teleporting"] call _blocked};
if (count _runs >= 10) exitWith {["ten retained runs; restart disposable mission after saving evidence"] call _blocked};
// Block every launch (including capture OFF) until the prior export has finished.
private _cap = missionNamespace getVariable ["A3UE_FPV_QA_captureState", createHashMap];
if (count _cap > 0 && {!(_cap getOrDefault ["exported", false])}) exitWith {
    ["previous capture/export unfinished; stop safely and wait for EXPORT_DONE"] call _blocked
};
private _siteType = _options getOrDefault ["siteType", ""];
if !(_siteType in ["Airport", "Outpost", "Resource"]) exitWith {["explicit active site required"] call _blocked};
private _class = _options getOrDefault ["class", ""];
private _role = _options getOrDefault ["role", ""];
private _count = _options getOrDefault ["count", 1];
private _target = _options getOrDefault ["target", objNull];
private _altitude = _options getOrDefault ["altitude", 45];
private _bearing = _options getOrDefault ["bearing", 0];
private _range = _options getOrDefault ["range", 350];
private _spacing = _options getOrDefault ["spacing", 15];
private _duration = _options getOrDefault ["duration", 60];
private _seed = _options getOrDefault ["seed", true];
private _instrument = _options getOrDefault ["instrument", true];
private _origin = _options getOrDefault ["originATL", []];
private _invalidNumber = [_count, _altitude, _bearing, _range, _spacing, _duration] findIf {!(_x isEqualType 0) || {!finite _x}};
if (_invalidNumber >= 0 || {!(_seed isEqualType true)} || {!(_instrument isEqualType true)}
    || {!(_target isEqualType objNull)} || {!(_class isEqualType "")} || {!(_role isEqualType "")}) exitWith {["incorrect parameter types"] call _blocked};
if (!(_count in [1,2,3]) || {_altitude < 5} || {_altitude > 500} || {_range < 100} || {_range > 600}
    || {_spacing < 0} || {_spacing > 100} || {_duration < 5} || {_duration > 180}) exitWith {
    ["count 1/2/3; altitude 5..500m; range 100..600m; spacing 0..100m; duration 5..180s"] call _blocked
};
if (isNull _target || {!alive _target}) exitWith {["select a live eligible target (player is allowed)"] call _blocked};
private _desc = createHashMap;
private _family = "";
{
    private _candidate = [_class, _x, _role] call A3UE_fnc_fpv_getClassDescriptor;
    if (count _candidate > 0 && {_candidate get "canDetonate"} && {(_candidate get "ammoClass") != ""}) exitWith {_desc = _candidate; _family = _x;};
} forEach ["fpv_ua", "armafpv", "kvn"];
if (count _desc == 0 || {!(_role in ["AT", "AP", "RECON"])}) exitWith {["class unavailable/unsupported, incompatible role or missing ammo; run catalog first"] call _blocked};
private _side = switch (_desc get "sideKey") do {case "east": {east}; case "west": {west}; default {independent};};
private _filtered = [_target, [_side] call A3UE_fnc_fpv_getHostileSides] call A3UE_fnc_fpv_filterTarget;
if (isNull _filtered) exitWith {["class side is not hostile under live getFriend rules, or target is captive/empty/managed"] call _blocked};
_target = _filtered;
if (!(_origin isEqualType [])) exitWith {["originATL must be [] or [x,y,z]"] call _blocked};
if (_origin isEqualTo []) then {
    _origin = (getPosATL _target) getPos [_range, _bearing];
    _origin set [2, _altitude];
};
private _badPos = _origin findIf {!(_x isEqualType 0) || {!finite _x} || {abs _x > 1000000}};
if (count _origin != 3 || {_badPos >= 0} || {(_origin # 2) < 5}) exitWith {["invalid/unsafe originATL"] call _blocked};
// Isolate the range; never stop/reset production manager or hide interfering stock.
private _interference = vehicles select {_x getVariable ["A3UE_FPV_managed", false] && {_x distance2D _target < 1000}};
if (_interference isNotEqualTo []) exitWith {[format ["existing managed drones within 1km: %1; wait for normal retirement or choose another range", _interference apply {netId _x}]] call _blocked};
private _id = format ["UAQA-%1-%2-%3", clientOwner, diag_frameNo toFixed 0, count _runs];
_motion = missionNamespace getVariable ["A3UE_FPV_QA_motionState",createHashMap];
if ((missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap]) getOrDefault ["active",false]) exitWith {["motion preparation reserved during admission"] call _blocked};
if (count _motion > 0 && {!(_motion getOrDefault ["finished",false])}) exitWith {["motion fixture reserved during admission"] call _blocked};
private _marker = _id + "-anchor";
private _run = createHashMapFromArray [["id", _id], ["drones", []], ["ids", []], ["crew", []], ["groups", []],
    ["marker", _marker], ["cleaned", false], ["options", +_options], ["origin", +_origin], ["target", _target]];
private _runReserved = false;
isNil {
    if ((missionNamespace getVariable ["A3UE_FPV_QA_motionPreparation",createHashMap]) getOrDefault ["active",false]
        || {private _latestMotion = missionNamespace getVariable ["A3UE_FPV_QA_motionState",createHashMap]; count _latestMotion > 0 && {!(_latestMotion getOrDefault ["finished",false])}}) exitWith {};
    createMarkerLocal [_marker, getPosATL _target];
    _runs set [_id, _run]; missionNamespace setVariable ["A3UE_FPV_QA_runs", _runs];
    _runReserved = true;
};
if (!_runReserved) exitWith {["motion preparation or fixture reserved before roster"] call _blocked};
missionNamespace setVariable ["A3UE_FPV_QA_lastRun", _id];
_s set ["runId",_id]; _s set ["run",_run]; A3UE_POLICY_run = _id;
_s set ["runRoster",[[],[],[],[],_marker]];
private _captureOK = true;
if (_instrument) then {_captureOK = ["start", _id, _run get "drones", _duration] call compileScript ["scripts\ua_dive\capture.sqf"];};
if (!_captureOK) exitWith {deleteMarkerLocal _marker; _run set ["cleaned", true]; ["capture unavailable; wait for prior export"] call _blocked};
private _parameters = [_class, _family, _role, str _side, _count, _origin, _bearing, _spacing, _duration,
    netId _target, getPosASL _target, _seed, _instrument, "TRANSIENT_DIRECT_BOOTSTRAP", "ISOLATED_NO_MANAGER_OVERRIDE"];
diag_log ["A3UE_FPV_QA_CASE", _id, _parameters];
if (_instrument) then {[objNull, "PARAMETERS", _parameters] call A3UE_FPV_QA_sink;};
for "_i" from 0 to (_count - 1) do {
    private _pos = _origin vectorAdd ([cos _bearing, -sin _bearing, 0] vectorMultiply ((_i - ((_count - 1) / 2)) * _spacing));
    private _spec = createHashMapFromArray [["spawnPosATL", _pos], ["searchAnchorMarker", _marker],
        ["controlPosATL", [_origin # 0, _origin # 1, _altitude]], ["siteType", _siteType],
        ["profileId", (A3UE_FPV_doctrine get _siteType) get "profileId"], ["side", _side], ["familyId", _family], ["payloadRole", _role],
        ["uavClass", _class], ["launchDir", _bearing + 180], ["vehicleInitMode", "DIRECT_BOOTSTRAP"],
        ["eventId", _id], ["postCrewInit", {
            params ["_u", "_group"];
            // Register test membership before owner-local bootstrap/controller work.
            (_run get "drones") pushBack _u;
            (_run get "ids") pushBack netId _u;
            {(_run get "crew") pushBackUnique _x;} forEach crew _u;
            (_run get "groups") pushBackUnique _group;
        _s set ["runRoster",[+(_run get "drones"),+(_run get "crew"),+(_run get "groups"),+(_run get "ids"),_run get "marker"]];
            if (_instrument) then {_u setVariable ["A3UE_FPV_QA_capture", true];};
        }]];
    if (_seed) then {_spec set ["seedTarget", _target];};
    private _u = [_spec] call A3UE_fnc_fpv_spawnManagedDrone;
    if (isNull _u || {crew _u isEqualTo []}) exitWith {diag_log ["A3UE_FPV_QA_BLOCKED", _id, "factory/crew failure; clean up this partial run"];};
};
if (hasInterface) then {[format ["%1: %2/%3 created. Roster retained in A3UE_FPV_QA_runs; capture %4. Clean up before next case.", _id, count (_run get "drones"), _count, _instrument]] call {params ["_message"]; diag_log ["F2R_PREP",_message];};};
diag_log ["A3UE_FPV_QA_ROSTER", _id, _run get "ids", (_run get "drones") apply {[typeOf _x, owner _x, _x getVariable ["A3UE_FPV_lifecycleId", -1], netId driver _x]}];
_run
