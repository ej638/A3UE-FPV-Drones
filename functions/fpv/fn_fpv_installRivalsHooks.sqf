// Installs A3UE addon-owned runtime wrappers around the AU rival UAVGRENADE event slot.
//
// Runs on the server after A3UE registration completes. Internally spawns a wait
// loop so it does not block the postInit caller.
//
// On success:  A3UE_FPV_rivalsHooksInstalled = true
//              A3UE_FPV_originalRivalsSelectAndExecuteEvent = <captured code>
//              A3UE_FPV_originalRivalsUavFlyby             = <captured code>
//              SCRT_fnc_rivals_selectAndExecuteEvent        = A3UE_fnc_fpv_rivalsSelectAndExecuteEvent
//              SCRT_fnc_rivals_encounter_uavFlyby           = A3UE_fnc_fpv_rivalsUavFlyby
//
// Fail-closed: if capture or wrapper validation fails the mission-namespace hook
//              state remains false and stock AU rival behavior is unchanged.

if (!isServer) exitWith {};

[] spawn {
    // AU CfgFunctions compile all SCRT_fnc_rivals_* before postInit runs, so the
    // wait should resolve on the first tick.  The 30s ceiling is a safety net only.
    private _waitStart = time;
    waitUntil {
        sleep 1;
        private _ready = (!isNil "SCRT_fnc_rivals_selectAndExecuteEvent") &&
                         (!isNil "SCRT_fnc_rivals_encounter_uavFlyby");
        _ready || ((time - _waitStart) > 30)
    };

    if (isNil "SCRT_fnc_rivals_selectAndExecuteEvent" || {isNil "SCRT_fnc_rivals_encounter_uavFlyby"}) exitWith {
        diag_log "[A3UE_FPV] installRivalsHooks: AU rival functions not found after timeout. Hooks not installed. Stock AU rival behavior unchanged.";
        missionNamespace setVariable ["A3UE_FPV_rivalsHooksInstalled", false];
    };

    // Validate that our own wrapper functions exist (compiled from CfgFunctions).
    if (isNil "A3UE_fnc_fpv_rivalsSelectAndExecuteEvent" || {isNil "A3UE_fnc_fpv_rivalsUavFlyby"}) exitWith {
        diag_log "[A3UE_FPV] installRivalsHooks: A3UE wrapper functions not compiled. Hooks not installed.";
        missionNamespace setVariable ["A3UE_FPV_rivalsHooksInstalled", false];
    };

    // Capture originals before any reassignment.
    private _origSelector = SCRT_fnc_rivals_selectAndExecuteEvent;
    private _origHandler  = SCRT_fnc_rivals_encounter_uavFlyby;

    missionNamespace setVariable ["A3UE_FPV_originalRivalsSelectAndExecuteEvent", _origSelector];
    missionNamespace setVariable ["A3UE_FPV_originalRivalsUavFlyby",              _origHandler];

    // Replace function variables with A3UE wrappers.
    // Any code path that calls SCRT_fnc_rivals_selectAndExecuteEvent or
    // SCRT_fnc_rivals_encounter_uavFlyby by variable lookup will now execute our wrappers.
    SCRT_fnc_rivals_selectAndExecuteEvent = A3UE_fnc_fpv_rivalsSelectAndExecuteEvent;
    SCRT_fnc_rivals_encounter_uavFlyby    = A3UE_fnc_fpv_rivalsUavFlyby;

    missionNamespace setVariable ["A3UE_FPV_rivalsHooksInstalled", true];
    diag_log "[A3UE_FPV] installRivalsHooks: Rival UAVGRENADE hooks installed successfully.";
};
