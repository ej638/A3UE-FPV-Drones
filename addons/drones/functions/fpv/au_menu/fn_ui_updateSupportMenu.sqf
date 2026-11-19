// 1.0.9 friendly FPV swarm (SW-2): wraps AU's SCRT_fnc_ui_updateSupportMenu (commander menu, scrt
// addon, AU 12.0.3-12.4.2). AU's own copy runs first, unchanged. Then, with the commander menu open and
// the swarm switched on (setting), "FPV drone swarm" is added once at the end of the Supports
// drop-down. AU fills the drop-down and then calls this (SCRT_fnc_ui_populateCommanderMenu), and calls
// it again after every launch, so the row is added only when it is missing.
// IDs as AU's (12.0.3 wrote the numbers; 12.4's ids.inc: A3A_IDD_COMMANDER_MENU 60000,
// A3A_IDC_COMMANDER_MENU_SUPPORT_TYPE_COMBOBOX 1750).
// [] -> nothing (AU's functions return nothing)
_this call (["ui_updateSupportMenu"] call A3UE_fnc_fpv_getStockAUFunction);
if (!hasInterface || {!(["swarmEnabled"] call A3UE_fnc_fpv_userSetting)}) exitWith {};
disableSerialization;
private _display = findDisplay 60000;
if (isNull _display) exitWith {};
private _combo = _display displayCtrl 1750;
if (isNull _combo) exitWith {};
private _present = false;
for "_i" from 0 to ((lbSize _combo) - 1) do {
	if ((_combo lbData _i) isEqualTo "A3UE_FPV_SWARM") then {_present = true;};
};
if (!_present) then {
	private _row = _combo lbAdd (localize "STR_A3UE_FPV_SWARM_MENU_TITLE");
	_combo lbSetData [_row, "A3UE_FPV_SWARM"];
	_combo lbSetTooltip [_row, localize "STR_A3UE_FPV_SWARM_MENU_TIP"];
};
