// 1.0.9 friendly FPV swarm (SW-2): the swarm's target on the commander's map (local markers only),
// after a click on the Supports tab with the swarm selected (SCRT_fnc_ui_manageSupportTabEventHandler,
// our wrapper). Spawned, so AU's own click handler has run: AU's start marker (BRStart, which AU's
// launch reads) is kept at the last click and labelled for the swarm; an end marker AU placed on a
// second click (BRFin) is removed; the circle shows where the drones will take targets.
// [position] -> nothing
params [["_pos", []]];
if (!hasInterface || {isNil "supportType"} || {supportType isNotEqualTo "A3UE_FPV_SWARM"}) exitWith {};
if !(_pos isEqualType [] && {count _pos >= 2}) exitWith {};
if (!isNil "supportMarkerDestination") then {
	deleteMarkerLocal supportMarkerDestination;
	supportMarkerDestination = nil;
};
deleteMarkerLocal "BRFin";
if (isNil "supportMarkerOrigin" || {(getMarkerColor supportMarkerOrigin) isEqualTo ""}) then {
	deleteMarkerLocal "BRStart";
	supportMarkerOrigin = createMarkerLocal ["BRStart", _pos];
	supportMarkerOrigin setMarkerShapeLocal "ICON";
	supportMarkerOrigin setMarkerTypeLocal "hd_destroy";
};
supportMarkerOrigin setMarkerPosLocal _pos;
supportMarkerOrigin setMarkerColorLocal "ColorRed";
supportMarkerOrigin setMarkerTextLocal (localize "STR_A3UE_FPV_SWARM_MENU_TARGET");
private _radius = (call A3UE_fnc_fpv_swarmSettings) get "radius";
deleteMarkerLocal "A3UE_FPV_swarmCircle";
private _circle = createMarkerLocal ["A3UE_FPV_swarmCircle", _pos];
_circle setMarkerShapeLocal "ELLIPSE";
_circle setMarkerSizeLocal [_radius, _radius];
_circle setMarkerColorLocal "ColorRed";
_circle setMarkerBrushLocal "Border";
