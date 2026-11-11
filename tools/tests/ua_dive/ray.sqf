// ENGINE geometry-only fixture, hosted server local scheduled; TWO real managed specimens.
// [attacker, crossing, qaTarget] execVM ...; never use a player target.
// Temporarily repositions exact objects in one atomic slice, then restores poses/velocities.
params [["_a", objNull], ["_b", objNull], ["_t", objNull]];
if (!isServer || {isRemoteExecuted} || {!canSuspend} || {isNull _a} || {isNull _b} || {isNull _t}
	|| {!local _a} || {!local _b} || {!local _t} || {isPlayer _t}
	|| {[_a] call A3UE_fnc_fpv_isExternallyControlled} || {[_b] call A3UE_fnc_fpv_isExternallyControlled}) exitWith {diag_log "UAQA RAY BLOCKED prerequisites";};
private _base = getPosATL _t;
private _wall = createVehicle ["Land_CncWall4_F", _base, [], 0, "CAN_COLLIDE"];
if (isNull _wall) exitWith {diag_log "UAQA RAY BLOCKED wall creation";};
_wall setDir 0;
sleep 0.1;
private _saved = [_a,_b,_t] apply {[getPosASL _x, vectorDir _x, vectorUp _x, velocity _x]};
private _mode = _b getVariable ["A3UE_FPV_mode", ""];
private _managed = _b getVariable ["A3UE_FPV_managed", false];
private _crewB = crew _b;
private _crewGroupsB = _crewB apply {group _x};
private _hostiles = [side group driver _a] call A3UE_fnc_fpv_getHostileSides;
private _hostileGroup = if (_hostiles isEqualTo []) then {grpNull} else {createGroup [_hostiles # 0, true]};
private _failures = 0;
private _check = {params ["_name", "_ok"]; if (!_ok) then {_failures = _failures + 1;}; diag_log ["UAQA RAY", _name, _ok];};
isNil {
	private _z = getTerrainHeightASL _base;
	_a setPosASL [_base # 0, (_base # 1)-20, _z+1.15];
	_b setPosASL [_base # 0, (_base # 1)-10, _z+1.15];
	_t setPosASL [_base # 0, (_base # 1)+20, _z];
	_b setVariable ["A3UE_FPV_mode", "TERMINAL_ATTACK"];
	private _start = getPosASL _a;
	private _end = (getPosASL _t) vectorAdd [0,0,1.15];
	private _raw = lineIntersectsSurfaces [_start,_end,_a,objNull,true,16,"GEOM","NONE"];
	diag_log ["UAQA RAY RAW", _raw];
	private _crossIndex = _raw findIf {(_x # 2) == _b || {(_x # 3) == _b}};
	private _wallIndex = _raw findIf {(_x # 2) == _wall || {(_x # 3) == _wall}};
	if (_crossIndex < 0 || {_wallIndex < 0} || {_crossIndex >= _wallIndex}) then {
		diag_log "UAQA RAY BLOCKED: ray did not actually hit crossing before wall; choose flat range/adjust geometry; no PASS";
		_failures = _failures + 1;
	} else {
		["allied attacking classification", [_a,_t,_b] call A3UE_fnc_fpv_isAlliedAttacker] call _check;
		private _hits = [_a,_t,_start,_end] call A3UE_fnc_fpv_traceAttackRay;
		["wall retained behind ally", _hits isNotEqualTo [] && {((_hits # 0) # 2) == _wall || {((_hits # 0) # 3) == _wall}}] call _check;
		["VIEW obstruction still blocked", ([_a,_t] call A3UE_fnc_fpv_isTargetObstructed) get "blocked"] call _check;
		private _solution = [_a,_t,[_a] call A3UE_fnc_fpv_getProfile] call A3UE_fnc_fpv_resolveImpactPoint;
		["resolver selects wall", (_solution get "surfaceObject") == _wall] call _check;
		["explicit UAV target retained", !([_a,_b,_b] call A3UE_fnc_fpv_isAlliedAttacker)] call _check;
		_b setVariable ["A3UE_FPV_managed", false];
		_hits = [_a,_t,_start,_end] call A3UE_fnc_fpv_traceAttackRay;
		["unmanaged UAV remains obstacle", _hits isNotEqualTo [] && {((_hits # 0) # 2) == _b || {((_hits # 0) # 3) == _b}}] call _check;
		if (!isNull _hostileGroup) then {
			_crewB joinSilent _hostileGroup;
			["hostile UAV is eligible target", !isNull ([_b,_hostiles] call A3UE_fnc_fpv_filterTarget)] call _check;
			_solution = [_a,_b,[_a] call A3UE_fnc_fpv_getProfile] call A3UE_fnc_fpv_resolveImpactPoint;
			["hostile UAV target retained", (_solution get "surfaceObject") == _b] call _check;
			_b setVariable ["A3UE_FPV_managed", _managed];
			["hostile managed crossing not filtered", !([_a,_t,_b] call A3UE_fnc_fpv_isAlliedAttacker)] call _check;
			{[_x] joinSilent (_crewGroupsB # _forEachIndex);} forEach _crewB;
		} else {diag_log "UAQA RAY HOSTILE_UAV NOT RUN: no hostile-side group available";};
		_b setVariable ["A3UE_FPV_managed", _managed];
		_b setVariable ["A3UE_FPV_mode", "IDLE"];
		["nonattacking managed UAV retained", !([_a,_t,_b] call A3UE_fnc_fpv_isAlliedAttacker)] call _check;
	};
	{
		private _pose = _saved # _forEachIndex;
		_x setPosASL (_pose # 0); _x setVectorDirAndUp [_pose # 1,_pose # 2]; _x setVelocity (_pose # 3);
	} forEach [_a,_b,_t];
	_b setVariable ["A3UE_FPV_mode", _mode]; _b setVariable ["A3UE_FPV_managed", _managed];
};
deleteVehicle _wall;
if (!isNull _hostileGroup && {units _hostileGroup isEqualTo []}) then {deleteGroup _hostileGroup;};
diag_log ["UAQA RAY END", _failures, "static engine geometry only; physical contact/crossing motion requires separate flight case"];
