// Returns true when A3UE can service the rival UAVGRENADE slot through installed wrappers.
//
// Intentionally cheap: checks pre-computed hook state, catalog presence, and global rival
// state variables.  Does NOT call SCRT_fnc_rivals_findSuitableEncounterPosition.
//
// Used by the selector and handler wrappers on the rival event hot-path.

// --- User setting (1.0.7) -------------------------------------------------------
// "Rivals FPV drone" off: report unavailable, so both wrappers take AU's stock path
// (stock rival UAVs, or a clean reroll without UAVGRENADE). Read live, no restart.
if !(["rivalsEnabled"] call A3UE_fnc_fpv_userSetting) exitWith {false};

// --- Hook state ---------------------------------------------------------------
if (!(missionNamespace getVariable ["A3UE_FPV_rivalsHooksInstalled", false])) exitWith {false};
// Event-time guard closes the interval before the low-cadence diagnostic check.
if (!(missionNamespace getVariable ["SCRT_fnc_rivals_selectAndExecuteEvent", 0] isEqualTo A3UE_fnc_fpv_rivalsSelectAndExecuteEvent)
	|| {!(missionNamespace getVariable ["SCRT_fnc_rivals_encounter_uavFlyby", 0] isEqualTo A3UE_fnc_fpv_rivalsUavFlyby)}) exitWith {false};
if (isNil "A3UE_FPV_originalRivalsSelectAndExecuteEvent") exitWith {false};
if (isNil "A3UE_FPV_originalRivalsUavFlyby")             exitWith {false};

// AU excludes Rivals events in mode 3, including the managed UAVGRENADE slot.
if (gameMode == 3) exitWith {false};

// --- Compat catalog -----------------------------------------------------------
private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) exitWith {false};

// Rivals = opfor (east).  Require at least one east-side FPV family to be available.
private _hasRivalFamilies = false;
{
    private _familyData = _catalog getOrDefault [_x, createHashMap];
    if (count _familyData > 0) then {
        private _classesBySide = _familyData getOrDefault ["classesBySide", createHashMap];
        private _eastClasses   = _classesBySide getOrDefault ["east", createHashMap];
        if (count _eastClasses > 0) then {
            _hasRivalFamilies = true;
        };
    };
} forEach ["armafpv", "fpv_ua", "kvn"];

if (!_hasRivalFamilies) exitWith {false};

// --- Rival discovery / defeat (soft checks: variables may be absent) ----------
if (!isNil "areRivalsDiscovered" && {!areRivalsDiscovered}) exitWith {false};
if (!isNil "areRivalsDefeated"   && {areRivalsDefeated})   exitWith {false};

// --- Activity level -----------------------------------------------------------
// Only service the slot at intrusive (2) or omnipresent (1) pressure.
// INTRUSIVE_ACTIVITY = 2
if (isNil "inactivityLevelRivals") exitWith {false};
if (inactivityLevelRivals > 2)     exitWith {false};

true
