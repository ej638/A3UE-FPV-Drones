// A3UE compatibility wrapper around SCRT_fnc_rivals_encounter_uavFlyby.
//
// Installed by A3UE_fnc_fpv_installRivalsHooks at runtime; replaces the stock
// UAV flyby handler in-place so the AU scheduler continues to dispatch by the
// normal function variable name.
//
// Behavior:
//   • If stock rival UAVs are available -> delegate to stored stock handler unchanged.
//   • If managed FPV is available AND A3UE_fnc_fpv_rivalsEventExecute exists ->
//     delegate to A3UE_fnc_fpv_rivalsEventExecute (added in Phase 4).
//   • Otherwise (managed FPV unavailable, or execute function not yet present) ->
//     reroll another rival event by calling the stored original selector with
//     UAVGRENADE excluded.  This is the explicit fail-closed reroll path.
//
// The reroll path is intentional: calling the stock handler when stock rival UAVs
// are empty and A3UE execution is unavailable is NOT a valid fallback because the
// stock handler exits immediately and issues a broken remoteExecCall reroll.
// Routing through the stored original selector produces clean behavior instead.

params [["_overridePosition", []]];

private _origSelector = missionNamespace getVariable ["A3UE_FPV_originalRivalsSelectAndExecuteEvent", {}];
private _origHandler  = missionNamespace getVariable ["A3UE_FPV_originalRivalsUavFlyby",              {}];

private _stockUavsAvailable = !((A3A_faction_riv get "vehiclesRivalsUavs") isEqualTo []);

// --- Case 1: stock rival UAVs are present -> stock handler handles everything -
if (_stockUavsAvailable) exitWith {
    [_overridePosition] call _origHandler;
};

// Stock rival UAVs are empty from here on.

private _fpvAvailable   = [] call A3UE_fnc_fpv_rivalsEventAvailable;
private _executeExists  = !isNil "A3UE_fnc_fpv_rivalsEventExecute";

// --- Case 2: A3UE can execute -> delegate to managed FPV strike ---------------
if (_fpvAvailable && {_executeExists}) exitWith {
    [_overridePosition] call A3UE_fnc_fpv_rivalsEventExecute;
};

// --- Case 3: fallback reroll --------------------------------------------------
// Managed FPV is unavailable or the execute function is not yet present.
// Reroll through the captured original selector with UAVGRENADE (200) excluded
// so we don't loop back into this wrapper.
diag_log "[A3UE_FPV] rivalsUavFlyby: managed FPV unavailable and stock rival UAVs empty. Rerolling another rival event.";
[200] call _origSelector; // 200 = UAVGRENADE
