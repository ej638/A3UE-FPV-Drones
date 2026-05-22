// A3UE compatibility wrapper around SCRT_fnc_rivals_selectAndExecuteEvent.
//
// Installed by A3UE_fnc_fpv_installRivalsHooks at runtime; replaces the stock
// selector in-place so the AU rival event loop continues to call the normal function
// variable name.
//
// Behavior:
//   • If stock rival UAVs are available -> delegate entirely to stored stock selector.
//   • If managed FPV is unavailable -> delegate entirely to stored stock selector.
//   • If stock rival UAVs are empty AND managed FPV is available -> run a
//     stock-equivalent selection that keeps UAVGRENADE in the candidate list.
//     UAVGRENADE routes to SCRT_fnc_rivals_encounter_uavFlyby (our handler wrapper).
//
// This is intentionally narrow: it only widens UAVGRENADE availability.
// Equal event weights, scheduler dispatch, and isRivalEventInProgress are all
// preserved to match stock AU behavior exactly.
//
// Event constants (from AU Rivals/Constants.inc):
//   CARDEMO              = 100
//   UAVGRENADE           = 200
//   ROVINGMORTAR         = 300
//   HELIRAID             = 400
//   SKIRMISH_OCCVSRIV    = 500
//   SKIRMISH_POLICEVSRIV = 600

params [["_excludeId", 0]];

private _origSelector = missionNamespace getVariable ["A3UE_FPV_originalRivalsSelectAndExecuteEvent", {}];

// Delegate to stock when stock rival UAVs are available (stock handles UAVGRENADE directly)
// or when A3UE cannot service the slot.
private _stockUavsAvailable = !((A3A_faction_riv get "vehiclesRivalsUavs") isEqualTo []);
private _fpvAvailable        = [] call A3UE_fnc_fpv_rivalsEventAvailable;

if (_stockUavsAvailable || {!_fpvAvailable}) exitWith {
    [_excludeId] call _origSelector;
};

// Stock rival UAVs are empty AND managed FPV is available.
// Run a stock-equivalent selection path that keeps UAVGRENADE eligible.
private _allEvents = [100, 200, 300, 400, 500, 600]; // matches stock event list order

private _events = if (_excludeId isNotEqualTo 0) then {
    _allEvents select {_x != _excludeId}
} else {
    _allEvents
};

// Intentionally NOT removing UAVGRENADE (200) here even though stock rival UAVs are empty:
// A3UE managed FPV will handle the slot through the installed handler wrapper.

isRivalEventInProgress = true;

private _weight          = 1 / (count _events);
private _eventsWithWeights = flatten (_events apply {[_x, _weight]});
private _eventType       = selectRandomWeighted _eventsWithWeights;

// UAVGRENADE routes to SCRT_fnc_rivals_encounter_uavFlyby which is now our handler wrapper.
// All other events use the stock scheduler entry-points unchanged.
switch (_eventType) do {
    case 100: {  // CARDEMO
        [[], "SCRT_fnc_rivals_encounter_carDemo"] call A3A_fnc_scheduler;
    };
    case 200: {  // UAVGRENADE -> A3UE handler wrapper
        [[], "SCRT_fnc_rivals_encounter_uavFlyby"] call A3A_fnc_scheduler;
    };
    case 300: {  // ROVINGMORTAR
        [[], "SCRT_fnc_rivals_encounter_rovingMortar"] call A3A_fnc_scheduler;
    };
    case 400: {  // HELIRAID
        [[], "SCRT_fnc_rivals_encounter_heliRaid"] call A3A_fnc_scheduler;
    };
    case 500: {  // SKIRMISH_OCCVSRIV
        [[], "SCRT_fnc_rivals_encounter_OccVsRivalsSkirmish"] call A3A_fnc_scheduler;
    };
    case 600: {  // SKIRMISH_POLICEVSRIV
        [[], "SCRT_fnc_rivals_encounter_policeVsRivalsskirmish"] call A3A_fnc_scheduler;
    };
};
