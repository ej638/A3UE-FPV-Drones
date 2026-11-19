// 1.0.9 friendly FPV swarm: one scan of the call circle for the whole swarm (the brain, on the
// server; also once at the call, for the drone mix). Legal targets only, read live: a hostile side,
// crewed, not captive, not a managed drone (filterTarget). Targets hidden for a while (out of sight,
// friendlies near, missed) are left out. Friendly safety is checked per reservation, not here.
// [record, settings] -> [[target, class, posASL, last resort], ...]; class "ARMOR" (tanks, APCs), "GUN"
// (another vehicle or a boat with a live gunner: an armed car or truck, a gunboat), "VEHICLE" (other
// crewed vehicles and boats; SW-1m, EJ after SW1l: a seaport's gunboat "was the most deadly threat"
// and was never seen, the scan took land vehicles only), "STATIC"
// (crewed static weapons), "SYSTEM" (an autonomous static: a SAM launcher, a radar, an automatic
// turret; SW-1h, EJ after SW1g: anti-personnel drones hit them again and again for nothing), "MG"
// (a man carrying a machine gun) or "MAN" (other men on foot).
// SW-1f (EJ after SW1e: "increase target priority for manned machine guns"): the machine gun is
// Arma's own weapon type (BIS_fnc_itemType, the one AU sorts its arsenal by), looked up once per
// weapon class and remembered (machine-local, never broadcast).
// SW-1l (EJ after SW1k: "the guy on the stairs always survives. And then drones keep going for the guy
// on the stairs but they can never got him ... They can go for the guys upstairs or mounted on the gun up
// there, but not the regular infantry standing on the stairs"): a man on foot on the stairs of a patrol
// tower is never a target: off the ground, within "stairM" of the tower and more than 1 m below its deck
// (the deck is the tower's building position 1, where AU puts its gun; a ruin's stairs at any height).
// The men on the deck and the gun stay targets: a hit on the top brings it down on them. The towers in
// the circle are found once per swarm and remembered in its record.
// SW-1m (EJ after SW1l: two men at a caved-in tower "kept shooting at me" while the drones orbited;
// "if there are really no other targets after a short time, a drone will pick and dive on one of the
// seen but obstructed targets"): a man on the stairs is passed on flagged as a last resort, which
// swarmAssign takes only when nothing else is left (no longer left out here).
params [["_record", createHashMap], ["_settings", createHashMap]];
if !(call A3UE_fnc_fpv_helperAccess) exitWith {[]};
private _center = _record getOrDefault ["center", []];
if !(_center isEqualType [] && {count _center >= 2}) exitWith {[]};
private _hostile = [_record getOrDefault ["side", sideUnknown], sideUnknown] call A3UE_fnc_fpv_getHostileSides;
if (_hostile isEqualTo []) exitWith {[]};
private _hidden = _record getOrDefault ["hidden", createHashMap];
private _radius = _settings getOrDefault ["radius", 300];
private _now = time;
private _out = [];
private _guns = missionNamespace getVariable ["A3UE_FPV_swarmGunTypes", createHashMap];
missionNamespace setVariable ["A3UE_FPV_swarmGunTypes", _guns];
private _towers = _record getOrDefault ["towers", -1];
if (_towers isEqualTo -1) then {
	_towers = [];
	{
		private _deck = (_x buildingPos 1) # 2;
		_towers pushBack [getPosASL _x, [1e3, _deck] select (_deck > 1)];
	} forEach (nearestObjects [_center, _settings getOrDefault ["stairTowers", []], _radius + 20]);
	_record set ["towers", _towers];
	diag_log format ["[A3UE_FPV] swarm id=%1 event=TOWERS count=%2 deckM=%3",
		_record getOrDefault ["id", ""], count _towers, _towers apply {round ((_x # 1) * 10) / 10}];
};
private _stairM = _settings getOrDefault ["stairM", 6];
private _onStairs = _record getOrDefault ["onStairs", createHashMap];
_record set ["onStairs", _onStairs];
{
	private _target = [_x, _hostile] call A3UE_fnc_fpv_filterTarget;
	if (!isNull _target && {_target isEqualTo _x} && {_now >= (_hidden getOrDefault [netId _target, -1])}) then {
		private _pos = getPosASL _target;
		if ((_pos distance2D _center) <= _radius) then {
			private _class = switch (true) do {
				case (_target isKindOf "Man"): {
					private _weapon = primaryWeapon _target;
					private _mg = _guns getOrDefault [_weapon, -1];
					if (_mg isEqualTo -1) then {
						_mg = _weapon != "" && {(([_weapon] call BIS_fnc_itemType) param [1, ""]) == "MachineGun"};
						_guns set [_weapon, _mg];
					};
					["MAN", "MG"] select _mg
				};
				case (_target isKindOf "StaticWeapon"): {["STATIC", "SYSTEM"] select (unitIsUAV _target)};
				case (_target isKindOf "Tank" || {_target isKindOf "Wheeled_APC_F"}): {"ARMOR"};
				case (alive gunner _target): {"GUN"};
				default {"VEHICLE"};
			};
			private _stairs = false;
			if (_class in ["MAN", "MG"] && {_towers isNotEqualTo []}) then {
				private _atl = (getPosATL _target) # 2;
				if (_atl >= 0.5) then {
					_stairs = (_towers findIf {((_x # 0) distance2D _pos) < _stairM && {_atl < ((_x # 1) - 1)}}) >= 0;
					// Evidence: once per man and swarm.
					if (_stairs && {!(netId _target in _onStairs)}) then {
						_onStairs set [netId _target, _now];
						diag_log format ["[A3UE_FPV] swarm id=%1 event=STAIRS target=%2 class=%3 atlM=%4",
							_record getOrDefault ["id", ""], netId _target, _class, (round (_atl * 10)) / 10];
					};
				};
			};
			_out pushBack [_target, _class, _pos, _stairs];
		};
	};
} forEach (_center nearEntities [["Man", "LandVehicle", "Ship"], _radius]);
_out
