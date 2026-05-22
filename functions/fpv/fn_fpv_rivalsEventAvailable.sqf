// Returns true when A3UE can service the rival UAVGRENADE slot through installed wrappers.
//
// Intentionally cheap: checks pre-computed hook state, catalog presence, and global rival
// state variables.  Does NOT call SCRT_fnc_rivals_findSuitableEncounterPosition.
//
// Used by the selector and handler wrappers on the rival event hot-path.

// --- Hook state ---------------------------------------------------------------
if (!(missionNamespace getVariable ["A3UE_FPV_rivalsHooksInstalled", false])) exitWith {false};
if (isNil "A3UE_FPV_originalRivalsSelectAndExecuteEvent") exitWith {false};
if (isNil "A3UE_FPV_originalRivalsUavFlyby")             exitWith {false};

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
