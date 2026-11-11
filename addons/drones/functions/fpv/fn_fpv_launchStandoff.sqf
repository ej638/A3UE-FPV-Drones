// Launch standoff placement (field findings FS-02/FS-03): never appear over players.
// Spawn-time only, bounded: at most 7 bearings, one analytic distance per threat,
// one water test per bearing, and at most 8 terrain line-of-sight tests per bearing,
// used only as a preference. Metres and compass degrees (0 = north, 90 = east).
//   _anchor    site/origin centre [x,y,...]; displaced candidates are measured from it
//   _preferred the point the caller would use without standoff [x,y,z]
//   _threats   positions to stay away from (hostile players, support target)
//   _options   "standoff" (default A3UE_FPV_launchStandoff, 800), "minOffset" (default 0),
//              "maxOffset" (default standoff + 400), "height" AGL for sight tests (default 35),
//              "probeOnly" (true: classify only, never search)
// Returns [_position, _mode, _nearestThreatM]:
//   "DIRECT"   preferred point already clear (returned unchanged)
//   "NEAR"     probeOnly and the preferred point is inside the standoff; position is []
//   "STANDOFF" displaced far-side point [x,y,0]; the caller applies its launch height
//   "BLOCKED"  no clear point within maxOffset; position is []
params [["_anchor", []], ["_preferred", []], ["_threats", []], ["_options", createHashMap]];

private _validPos = {
	_this isEqualType [] && {count _this >= 2}
		&& {((_this select [0, 2]) findIf {!(_x isEqualType 0) || {!finite _x} || {abs _x > 1e7}}) < 0}
};
if (!(_anchor call _validPos) || {!(_preferred call _validPos)} || {!(_threats isEqualType [])}) exitWith {[[], "BLOCKED", -1]};
private _valid = _threats select {_x call _validPos};

private _standoff = _options getOrDefault ["standoff", -1];
if (!(_standoff isEqualType 0) || {!finite _standoff} || {_standoff < 0}) then {
	_standoff = missionNamespace getVariable ["A3UE_FPV_launchStandoff", 800];
	if (!(_standoff isEqualType 0) || {!finite _standoff} || {_standoff < 0}) then {_standoff = 800;};
};
_standoff = _standoff min 3000;
private _minOffset = (_options getOrDefault ["minOffset", 0]) max 0;
private _maxOffset = (_options getOrDefault ["maxOffset", _standoff + 400]) max _minOffset;
private _height = (_options getOrDefault ["height", 35]) max 2;

private _nearestTo = {
	params ["_p"];
	private _best = -1;
	{
		private _d = [_p # 0, _p # 1] distance2D [_x # 0, _x # 1];
		if (_best < 0 || {_d < _best}) then {_best = _d;};
	} forEach _valid;
	_best
};
private _preferredNearest = [_preferred] call _nearestTo;
if (_standoff <= 0 || {_preferredNearest < 0} || {_preferredNearest >= _standoff}) exitWith {[+_preferred, "DIRECT", _preferredNearest]};
// Classification only: report "NEAR" without searching for a displaced point.
if (_options getOrDefault ["probeOnly", false]) exitWith {[[], "NEAR", _preferredNearest]};

// Far side: bearing from the threat nearest the anchor, through the anchor.
private _ranked = _valid apply {[[_anchor # 0, _anchor # 1] distance2D [_x # 0, _x # 1], _x]};
_ranked sort true;
private _nearest = _ranked # 0 # 1;
private _awayX = (_anchor # 0) - (_nearest # 0);
private _awayY = (_anchor # 1) - (_nearest # 1);
private _base = if ((abs _awayX) + (abs _awayY) > 1) then {_awayX atan2 _awayY} else {0};
_ranked resize ((count _ranked) min 8);
private _sightThreats = _ranked apply {_x # 1};

private _firstClear = [];
private _hidden = [];
{
	private _bearing = _base + _x;
	private _ux = sin _bearing;
	private _uy = cos _bearing;
	// Smallest distance along this bearing that leaves every threat circle.
	private _required = _minOffset;
	{
		private _wx = (_anchor # 0) - (_x # 0);
		private _wy = (_anchor # 1) - (_x # 1);
		private _uw = (_ux * _wx) + (_uy * _wy);
		private _disc = (_uw * _uw) - ((_wx * _wx) + (_wy * _wy)) + (_standoff * _standoff);
		if (_disc > 0) then {_required = _required max (sqrt _disc - _uw);};
	} forEach _valid;
	_required = _required + 10;
	if (_required <= _maxOffset) then {
		private _candidate = [(_anchor # 0) + (_ux * _required), (_anchor # 1) + (_uy * _required), 0];
		if !(surfaceIsWater _candidate) then {
			if (_firstClear isEqualTo []) then {_firstClear = _candidate;};
			private _launchAsl = [_candidate # 0, _candidate # 1, (getTerrainHeightASL _candidate) + _height];
			private _seen = _sightThreats findIf {
				!(terrainIntersectASL [[_x # 0, _x # 1, (getTerrainHeightASL _x) + 1.7], _launchAsl])
			};
			if (_seen < 0) then {_hidden = _candidate;};
		};
	};
	if (_hidden isNotEqualTo []) exitWith {};
} forEach [0, 30, -30, 60, -60, 90, -90];

private _chosen = [_firstClear, _hidden] select (_hidden isNotEqualTo []);
if (_chosen isEqualTo []) exitWith {[[], "BLOCKED", _preferredNearest]};
[_chosen, "STANDOFF", [_chosen] call _nearestTo]
