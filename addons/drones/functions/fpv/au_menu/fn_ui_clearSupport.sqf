// 1.0.9 friendly FPV swarm (SW-2): wraps AU's SCRT_fnc_ui_clearSupport (spawned by AU when the type,
// tab or menu changes and after a support's cooldown). AU's own copy runs first (it waits out the
// cooldown and removes the start and end markers); then the swarm's circle goes too.
// [] -> nothing (scheduled, as AU spawns it). AU's function returns nothing, so neither does this.
_this call (["ui_clearSupport"] call A3UE_fnc_fpv_getStockAUFunction);
deleteMarkerLocal "A3UE_FPV_swarmCircle";
