// User settings (1.0.7): the one validated reader for the CBA Addon Options values that
// fn_fpv_registerSettings declares. CBA stores each value as a missionNamespace variable of the
// same name, synced from the server (global settings). A missing or invalid value (no CBA, a
// bad cba_settings.sqf entry, a script override) always yields the shipped default, so callers
// never see an out-of-range value. Cheap: one getVariable and a type/range check, no state.
//   ["siteFrequency"]     -> "OFF" | "LESS" | "NORMAL" | "MORE" | "ALWAYS"   (default "NORMAL")
//   ["sitePerSite"]       -> "FEWER" | "NORMAL" | "MORE"                       (default "NORMAL")
//   ["siteRefillSeconds"] -> 0 (never) or 60..7200 seconds                      (default 900)
//   ["supportEnabled"]    -> Boolean                                            (default true)
//   ["supportMinWarTier"] -> integer 1..10                                      (default 3)
//   ["rivalsEnabled"]     -> Boolean                                            (default true)
//   ["debug"]             -> Boolean                                            (default false)
//   ["swarmEnabled"]      -> Boolean: the FPV drone swarm in the commander's menu (default true)
//   ["swarmSize"]         -> integer 3..8 drones per swarm                     (default 7)
// 1.0.8: "A3UE_FPV_lowRunWeight" (Low approach chance, 0..1, default 1/3) is read and validated
// with the other low-run tunables in A3UE_fnc_fpv_lowRunSettings, not here.
params [["_name", ""]];

private _choice = {
	params ["_var", "_allowed", "_default"];
	private _value = missionNamespace getVariable [_var, _default];
	if (_value isEqualType "" && {_value in _allowed}) then {_value} else {_default}
};
private _flag = {
	params ["_var", "_default"];
	private _value = missionNamespace getVariable [_var, _default];
	if (_value isEqualType true) then {_value} else {_default}
};

switch (_name) do {
	case "siteFrequency": {["A3UE_FPV_siteFrequency", ["OFF", "LESS", "NORMAL", "MORE", "ALWAYS"], "NORMAL"] call _choice};
	case "sitePerSite": {["A3UE_FPV_sitePerSite", ["FEWER", "NORMAL", "MORE"], "NORMAL"] call _choice};
	case "siteRefillSeconds": {
		// Kept under its pre-settings name so existing server scripts still work.
		private _value = missionNamespace getVariable ["A3UE_FPV_siteStockRefillSeconds", 900];
		if (!(_value isEqualType 0) || {!finite _value}) then {_value = 900;};
		if (_value != 0 && {_value < 60 || {_value > 7200}}) then {_value = 900;};
		_value
	};
	case "supportEnabled": {["A3UE_FPV_supportEnabled", true] call _flag};
	case "supportMinWarTier": {
		private _value = missionNamespace getVariable ["A3UE_FPV_supportMinWarTier", 3];
		if (!(_value isEqualType 0) || {!finite _value}) then {_value = 3;};
		((round _value) max 1) min 10
	};
	case "rivalsEnabled": {["A3UE_FPV_rivalsEnabled", true] call _flag};
	case "debug": {["A3UE_FPV_debug", false] call _flag};
	// 1.0.9 friendly swarm (EJ, 17 November: 7 drones, 3-8).
	case "swarmEnabled": {["A3UE_FPV_swarmEnabled", true] call _flag};
	case "swarmSize": {
		private _value = missionNamespace getVariable ["A3UE_FPV_swarmSize", 7];
		if (!(_value isEqualType 0) || {!finite _value}) then {_value = 7;};
		((round _value) max 3) min 8
	};
	default {nil};
}
