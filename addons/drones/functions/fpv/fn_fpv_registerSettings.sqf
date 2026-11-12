// User settings (1.0.7): declares the CBA Addon Options entries. Runs in CBA's XEH preInit on
// every machine (config.cpp Extended_PreInit_EventHandlers), as Antistasi Ultimate registers its
// own settings. Every entry is global (1): the server's value applies to everyone and only the
// host or a logged-in admin can change it. Values are read live through A3UE_fnc_fpv_userSetting,
// which validates them and falls back to the defaults below, so nothing here needs a restart.
// Without CBA this does nothing and the defaults apply.
if (isNil "CBA_fnc_addSetting") exitWith {false};

private _category = localize "STR_A3UE_FPV_SET_CATEGORY";
private _sites = [_category, localize "STR_A3UE_FPV_SET_SUB_SITES"];
private _supports = [_category, localize "STR_A3UE_FPV_SET_SUB_SUPPORTS"];
private _diagnostics = [_category, localize "STR_A3UE_FPV_SET_SUB_DIAGNOSTICS"];
private _text = {[localize format ["STR_A3UE_FPV_SET_%1", _this], localize format ["STR_A3UE_FPV_SET_%1_TIP", _this]]};

// The server logs each value at start-up and on every change (one RPT line, never per frame).
[
	"A3UE_FPV_siteFrequency", "LIST", "FREQUENCY" call _text, _sites,
	[["OFF", "LESS", "NORMAL", "MORE", "ALWAYS"],
	 ["STR_A3UE_FPV_SET_OPT_OFF", "STR_A3UE_FPV_SET_OPT_LESS", "STR_A3UE_FPV_SET_OPT_NORMAL",
	  "STR_A3UE_FPV_SET_OPT_MORE", "STR_A3UE_FPV_SET_OPT_ALWAYS"] apply {localize _x}, 2],
	1, {if (isServer) then {diag_log format ["[A3UE_FPV] setting siteFrequency=%1", _this];};}
] call CBA_fnc_addSetting;

[
	"A3UE_FPV_sitePerSite", "LIST", "PERSITE" call _text, _sites,
	[["FEWER", "NORMAL", "MORE"],
	 ["STR_A3UE_FPV_SET_OPT_FEWER", "STR_A3UE_FPV_SET_OPT_NORMAL", "STR_A3UE_FPV_SET_OPT_MORE"] apply {localize _x}, 1],
	1, {if (isServer) then {diag_log format ["[A3UE_FPV] setting sitePerSite=%1", _this];};}
] call CBA_fnc_addSetting;

[
	"A3UE_FPV_siteStockRefillSeconds", "LIST", "REFILL" call _text, _sites,
	[[0, 900, 1800, 3600],
	 ["STR_A3UE_FPV_SET_OPT_NEVER", "STR_A3UE_FPV_SET_OPT_15MIN", "STR_A3UE_FPV_SET_OPT_30MIN",
	  "STR_A3UE_FPV_SET_OPT_60MIN"] apply {localize _x}, 1],
	1, {if (isServer) then {diag_log format ["[A3UE_FPV] setting siteStockRefillSeconds=%1", _this];};}
] call CBA_fnc_addSetting;

[
	"A3UE_FPV_supportEnabled", "CHECKBOX", "SUPPORT" call _text, _supports, true,
	1, {if (isServer) then {diag_log format ["[A3UE_FPV] setting supportEnabled=%1", _this];};}
] call CBA_fnc_addSetting;

[
	"A3UE_FPV_supportMinWarTier", "SLIDER", "WARTIER" call _text, _supports, [1, 10, 3, 0],
	1, {if (isServer) then {diag_log format ["[A3UE_FPV] setting supportMinWarTier=%1", _this];};}
] call CBA_fnc_addSetting;

[
	"A3UE_FPV_rivalsEnabled", "CHECKBOX", "RIVALS" call _text, _supports, true,
	1, {if (isServer) then {diag_log format ["[A3UE_FPV] setting rivalsEnabled=%1", _this];};}
] call CBA_fnc_addSetting;

[
	"A3UE_FPV_debug", "CHECKBOX", "DEBUG" call _text, _diagnostics, false,
	1, {if (isServer) then {diag_log format ["[A3UE_FPV] setting debug=%1", _this];};}
] call CBA_fnc_addSetting;

true
