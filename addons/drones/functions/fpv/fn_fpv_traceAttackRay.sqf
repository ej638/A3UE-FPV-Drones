// One bounded, sorted trace. Continue through allied attackers to the real surface.
// Saturation with no retained hit is conservatively blocked, never CLEAR_PATH.
params ["_uav", "_target", "_startASL", "_endASL", ["_lod", "GEOM"], ["_ignoreTarget", false]];
private _hits = lineIntersectsSurfaces [_startASL, _endASL, _uav,
	[objNull, _target] select _ignoreTarget, true, 16, _lod, "NONE", true];
private _retained = _hits select {
	private _object = _x param [3, objNull];
	if (isNull _object) then {_object = _x param [2, objNull];};
	isNull _object || {_object != _uav && {_object != objectParent _uav}
		&& {!([_uav, _target, _object] call A3UE_fnc_fpv_isAlliedAttacker)}}
};
// Proxy hits use the owning object for target identity and model-space anchoring.
_retained = _retained apply {
	private _hit = +_x;
	private _parent = _hit param [3, objNull];
	if (!isNull _parent) then {_hit set [2, _parent];};
	_hit
};
if (_retained isEqualTo [] && {count _hits == 16}) then {
	private _last = +(_hits # 15);
	_last set [2, objNull];
	_last set [3, objNull];
	_retained = [_last];
};
_retained
