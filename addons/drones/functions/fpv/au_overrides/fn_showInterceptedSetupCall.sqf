#include "\x\A3A\addons\core\script_component.hpp"
FIX_LINE_NUMBERS()

params ["_reveal", "_side", "_supportType", "_position", "_setupTime"];

if (toUpperANSI _supportType isNotEqualTo "FPV") exitWith {
    _this call (["showInterceptedSetupCall"] call A3UE_fnc_fpv_getStockAUFunction)
};
if (_reveal <= 0.2) exitWith {};

private _sideName = Faction(_side) get "name";
private _text = format [localize (["STR_notifiers_SUP_setup_unknown2", "STR_A3UE_FPV_NOTIFIERS_SUP_SETUP_FPV"] select (_reveal > 0.5)), _sideName];

_setupTime = _setupTime * (_reveal + random (2 - 2*_reveal));
private _timeStr = if (_setupTime < 60) then { "&lt;1" } else { str round (_setupTime / 60) };

if (_reveal >= 0.8) then {
    _text = format [localize "STR_notifiers_SUP_QRF_setup_arrival", _text, _timeStr];
};

private _nearbyPlayers = allPlayers select {(_x distance2D _position) <= 2000};
if (count _nearbyPlayers > 0) then
{
    ["RadioIntercepted", [_text]] remoteExec ["BIS_fnc_showNotification", _nearbyPlayers];
};