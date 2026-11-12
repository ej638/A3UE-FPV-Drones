// User settings (1.0.7): may Occupants/Invaders use the FPV support right now?
// The single gate for the "Enemy FPV strikes" and "Earliest war level" settings. Every FPV
// support request passes it in resolveSupportPackage; the wavedAttack override asks it first so
// a wave never draws FPV only to swap the refused slot for an extra attack helicopter.
// [] -> [allowed, reason] where reason is "" | "DISABLED_BY_SETTING" | "WAR_TIER_TOO_LOW"
if !(["supportEnabled"] call A3UE_fnc_fpv_userSetting) exitWith {[false, "DISABLED_BY_SETTING"]};
private _warTier = missionNamespace getVariable ["tierWar", 1];
if (!(_warTier isEqualType 0) || {!finite _warTier}) then {_warTier = 1;};
if (_warTier < (["supportMinWarTier"] call A3UE_fnc_fpv_userSetting)) exitWith {[false, "WAR_TIER_TOO_LOW"]};
[true, ""]
