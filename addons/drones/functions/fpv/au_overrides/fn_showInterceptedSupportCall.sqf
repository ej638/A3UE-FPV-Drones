#include "\x\A3A\addons\core\script_component.hpp"
FIX_LINE_NUMBERS()

params ["_reveal", "_position", "_side", "_supportType", "_markerType", "_markerLifeTime"];

if (toUpperANSI _supportType isNotEqualTo "FPV") exitWith {
    _this call (["showInterceptedSupportCall"] call A3UE_fnc_fpv_getStockAUFunction)
};
if (_reveal <= 0.2) exitWith {};

private _text = "";
private _markerText = "";
private _sideName = if(_side == Occupants) then {FactionGet(occ,"name")} else {FactionGet(inv,"name")};
if (_reveal <= 0.5) then {
    _text = format [localize "STR_notifiers_SUP_execute_unknown", _sideName];
} else {
    _text = format [localize "STR_A3UE_FPV_NOTIFIERS_SUP_EXECUTE_FPV", _sideName];
    _markerText = localize "STR_A3UE_FPV_NOTIFIERS_SUP_EXECUTE_FPV_MARKER";

    if (_reveal < 0.8) exitWith {};

    _text = format ["%1. Target marked on map!", _text];
    private _targetMarker = format ["%1_target_%2", _supportType, A3A_supportMarkerCount];
    private _textMarker = format ["%1_text_%2", _supportType, A3A_supportMarkerCount];
    A3A_supportMarkerCount = A3A_supportMarkerCount + 1;

    if (_markerType isEqualType 0) then
    {
        createMarkerLocal [_targetMarker, _position];
        _targetMarker setMarkerShapeLocal "ELLIPSE";
        _targetMarker setMarkerBrushLocal "Grid";
        _targetMarker setMarkerSizeLocal [_markerType, _markerType];
        _targetMarker setMarkerColorLocal (if(_side == Occupants) then { colorOccupants } else { colorInvaders });
        _targetMarker setMarkerAlpha 1;

        createMarkerLocal [_textMarker, _position];
        _textMarker setMarkerShapeLocal "ICON";
        _textMarker setMarkerTypeLocal "mil_dot";
        _textMarker setMarkerTextLocal _markerText;
        _textMarker setMarkerAlpha 0.75;

        [_textMarker, _targetMarker, _markerLifeTime] spawn {
            params ["_textMarker", "_targetMarker", "_lifeTime"];
            sleep _lifeTime;
            deleteMarker _textMarker;
            deleteMarker _targetMarker;
        };
    }
    else
    {
        createMarkerLocal [_textMarker, _position];
        _textMarker setMarkerShapeLocal "ICON";
        _textMarker setMarkerTypeLocal "mil_objective";
        _textMarker setMarkerTextLocal _markerText;
        _textMarker setMarkerAlphaLocal 0.75;

        [_textMarker, _markerType, time + _markerlifeTime] spawn {
            params ["_marker", "_target", "_timeout"];
            while { time < _timeout and alive _target } do {
                _marker setMarkerPos getPos _target;
                sleep 5;
            };
            deleteMarker _marker;
        };
    };
};

private _nearbyPlayers = allPlayers select {(_x distance2D _position) <= 2000};
if (count _nearbyPlayers > 0) then
{
    ["RadioIntercepted", [_text]] remoteExec ["BIS_fnc_showNotification", _nearbyPlayers];
};