// 1.0.9 friendly FPV swarm (SW-2): wraps AU's SCRT_fnc_ui_setSupportCostText (the drop-down's selection
// handler). AU's own copy runs first: it sets the global supportType from the row and the cost text
// (its default branch, 1 support point, for a type it doesn't know). For the swarm the text then
// shows the full cost in AU's own words: 1 support point and 500 (A3A_IDC_COMMANDER_MENU_SUPPORT_COSTS_TEXT
// 1751).
// [] -> nothing (AU's functions return nothing)
_this call (["ui_setSupportCostText"] call A3UE_fnc_fpv_getStockAUFunction);
if (!hasInterface || {isNil "supportType"} || {supportType isNotEqualTo "A3UE_FPV_SWARM"}) exitWith {};
disableSerialization;
private _display = findDisplay 60000;
if (isNull _display) exitWith {};
private _settings = call A3UE_fnc_fpv_swarmSettings;
private _currency = if (isNil "A3A_faction_civ") then {""} else {A3A_faction_civ getOrDefault ["currencySymbol", ""]};
(_display displayCtrl 1751) ctrlSetText format [localize "STR_commander_menu_abilities_cost_support_point_and_money",
	_settings get "costPoints", _settings get "costMoney", _currency];
