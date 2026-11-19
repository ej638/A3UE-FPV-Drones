// 1.0.9 friendly FPV swarm (SW-2): wraps AU's SCRT_fnc_ui_manageSupportTabEventHandler (the Supports
// tab's map click). AU's own copy runs unchanged ("ADD" stacks AU's "supportMap" click handler,
// "REMOVE" takes it off). With "ADD" a second handler is stacked for the swarm: it does nothing for
// AU's own types. For the swarm, AU's handler places its start marker on the first click and an end
// marker on the next; ours then (swarmMenuMark, a moment later, so whichever handler runs first) keeps
// one marker, labelled as the swarm's target, at the last click, with the swarm's circle around it.
// ["ADD" | "REMOVE"] -> nothing (AU's function returns nothing)
params [["_mode", ""]];
["A3UE_FPV_swarmMap", "onMapSingleClick"] call BIS_fnc_removeStackedEventHandler;
_this call (["ui_manageSupportTabEventHandler"] call A3UE_fnc_fpv_getStockAUFunction);
if (_mode isEqualTo "ADD" && {hasInterface}) then {
	[
		"A3UE_FPV_swarmMap",
		"onMapSingleClick",
		{
			if (!isNil "supportType" && {supportType isEqualTo "A3UE_FPV_SWARM"}
				&& {isNil "isSupportMarkerPlacingLocked" || {!isSupportMarkerPlacingLocked}}) then {
				[_pos] spawn A3UE_fnc_fpv_swarmMenuMark;
			};
			false
		},
		[]
	] call BIS_fnc_addStackedEventHandler;
};
