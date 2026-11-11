//includes commonly included files to clean up includes in other files
//Line number fix
// Build-only HEMTT compatibility: its preprocessor already retains source locations.
// The upstream macro emits a #line directive from a macro, which HEMTT's SQF
// parser treats as SQF tokens. Runtime .sqf still includes Antistasi's own header.
#define FIX_LINE_NUMBERS2(sharp) sharp##line __LINE__ __FILE__
#define FIX_LINE_NUMBERS()

#include "LogMacros.inc"

//Template macros
#define Faction(SIDE) (switch SIDE do {case west:{A3A_faction_occ}; case east:{A3A_faction_inv}; case resistance:{A3A_faction_reb}; case civilian:{A3A_faction_civ}; case opfor:{A3A_faction_riv}; default {Error_1("Bad side passed passed to Faction(side), Side: %1", SIDE); createHashMap};})
#define FactionGet(FAC, VAR) (A3A_faction_##FAC get VAR)
#define FactionGetOrDefault(FAC, VAR, DEF) (A3A_faction_##FAC getOrDefault [VAR, DEF])
#define FactionGetTiered(FAC, VAR) (switch true do {case (tierWar < 5):{(A3A_faction_##FAC get VAR) select 0}; case (tierWar < 8 && {tierWar > 4}):{(A3A_faction_##FAC get VAR) select 1}; case (tierWar > 7):{(A3A_faction_##FAC get VAR) select 2}; default {Error("Something wrong.");""};})
#define GetTiered(FACVAR, UNITVAR) (switch true do {case (tierWar < 5):{(FACVAR get UNITVAR) select 0}; case (tierWar < 8 && {tierWar > 4}):{(FACVAR get UNITVAR) select 1}; case (tierWar > 7):{(FACVAR get UNITVAR) select 2}; default {Error("Something wrong.");""};})

/// Feature Toggles ///
// Force new experimental UI.
// #define UseDoomGUI
// Enable completed sections of experimental UI.
#define UseDoomGUIPreview
