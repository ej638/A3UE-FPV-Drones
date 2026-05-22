// Generic managed-drone spawn helper.
//
// Supports both site stock (vehicleInitMode = "AIVEHINIT") and transient rival FPV
// drones (vehicleInitMode = "DIRECT_BOOTSTRAP") from a single contract.
//
// Required spec keys:
//   spawnPosATL        - [x, y, z] ATL spawn position
//   searchAnchorMarker - marker name used as search / loiter / hold anchor
//   siteType           - doctrine key ("Airport", "Outpost", "RivalsSupport", etc.)
//   profileId          - resolved behavior profile id (stamped as-is onto the vehicle)
//   side               - spawning side
//   familyId           - FPV family id: "armafpv", "fpv_ua", or "kvn"
//   payloadRole        - "AT", "AP", or "RECON"
//
// Optional spec keys:
//   controlPosATL      - [x, y, z] radio control node; defaults to spawnPosATL
//   fiberAnchorPos     - [x, y, z] KVN fiber visual origin; defaults to ground projection
//   launchDir          - initial heading (degrees); defaults to random
//   initialMode        - initial controller mode; defaults to "IDLE"
//   seedTarget         - object to pre-seed as tracking target
//   crewFactory        - code {params ["_side", "_uav"]; returns GROUP}
//   postCrewInit       - code {params ["_uav", "_crewGroup"]; ...}
//   vehicleInitMode    - "AIVEHINIT" (default) or "DIRECT_BOOTSTRAP"
//   resourcePool       - AU resource pool for AIVEHINIT path; defaults to "defence"
//   eventId            - transient event identity string (stamps rivalry metadata)

params [["_spec", createHashMap]];

if (!isServer) exitWith {objNull};
if (count _spec == 0) exitWith {objNull};

// --- Required keys ------------------------------------------------------------
private _spawnPosATL        = _spec getOrDefault ["spawnPosATL",        []];
private _searchAnchorMarker = _spec getOrDefault ["searchAnchorMarker", ""];
private _siteType           = _spec getOrDefault ["siteType",           ""];
private _profileId          = _spec getOrDefault ["profileId",          ""];
private _side               = _spec getOrDefault ["side",               east];
private _familyId           = _spec getOrDefault ["familyId",           ""];
private _payloadRole        = _spec getOrDefault ["payloadRole",        ""];

if (_spawnPosATL isEqualTo []) exitWith {objNull};
if (_familyId   isEqualTo "") exitWith {objNull};
if (_payloadRole isEqualTo "") exitWith {objNull};
if (_siteType   isEqualTo "") exitWith {objNull};

// --- Optional keys ------------------------------------------------------------
private _controlPosATL   = _spec getOrDefault ["controlPosATL",   []];
private _fiberAnchorPos  = _spec getOrDefault ["fiberAnchorPos",  []];
private _launchDir       = _spec getOrDefault ["launchDir",       random 360];
private _initialMode     = _spec getOrDefault ["initialMode",     "IDLE"];
private _vehicleInitMode = _spec getOrDefault ["vehicleInitMode", "AIVEHINIT"];
private _resourcePool    = _spec getOrDefault ["resourcePool",    "defence"];
private _eventId         = _spec getOrDefault ["eventId",         ""];

// --- Validate family in catalog -----------------------------------------------
private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) then {
	_catalog = call A3UE_fnc_fpv_buildCompatCatalog;
};

private _familyData = _catalog getOrDefault [_familyId, createHashMap];
if (count _familyData == 0) exitWith {objNull};

// --- Step 1: Resolve UAV class from doctrine pools ----------------------------
private _uavClass = [_familyId, _payloadRole, _side, _siteType] call A3UE_fnc_fpv_selectClassForRole;
if (_uavClass isEqualTo "") exitWith {objNull};

// --- Step 2: Create UAV -------------------------------------------------------
private _spawnHeight = _spawnPosATL param [2, 35];

private _uav = createVehicle [_uavClass, _spawnPosATL, [], 0, "FLY"];
if (isNull _uav) exitWith {objNull};

_uav setDir _launchDir;
_uav setPosATL _spawnPosATL;
_uav flyInHeight _spawnHeight;

// --- Step 3: Stamp all A3UE_FPV_* metadata before any external init path -----
private _linkModel = _familyData getOrDefault ["signalModel", "RADIO"];

private _rangeTier = "STD";
if (_uavClass find "_25KM" > -1) then {
	_rangeTier = "25KM";
} else {
	if (_uavClass find "_20KM" > -1) then {
		_rangeTier = "20KM";
	};
};

// Derive positional anchors from spawnPosATL when not explicitly supplied.
if (_controlPosATL isEqualTo []) then {
	_controlPosATL = _spawnPosATL;
};
if (_fiberAnchorPos isEqualTo []) then {
	_fiberAnchorPos = [(_spawnPosATL # 0), (_spawnPosATL # 1), 0.5];
};

_uav setVariable ["A3UE_FPV_managed",            true,                true];
_uav setVariable ["A3UE_FPV_mode",               _initialMode,        true];
_uav setVariable ["A3UE_FPV_siteMarker",         _searchAnchorMarker, true];
_uav setVariable ["A3UE_FPV_siteType",           _siteType,           true];
_uav setVariable ["A3UE_FPV_profileId",          _profileId,          true];
_uav setVariable ["A3UE_FPV_vendorId",           _familyId,           true];
_uav setVariable ["A3UE_FPV_payloadRole",        _payloadRole,        true];
_uav setVariable ["A3UE_FPV_linkModel",          _linkModel,          true];
_uav setVariable ["A3UE_FPV_rangeTier",          _rangeTier,          true];
_uav setVariable ["A3UE_FPV_netId",              netId _uav,          true];
_uav setVariable ["A3UE_FPV_controlPosATL",      _controlPosATL,      true];
_uav setVariable ["A3UE_FPV_fiberAnchorPos",     _fiberAnchorPos,     false];
_uav setVariable ["A3UE_FPV_targetNetId",        "",                  true];
_uav setVariable ["A3UE_FPV_lastInterceptASL",   [],                  true];
_uav setVariable ["A3UE_FPV_linkState",          "OK",                true];
_uav setVariable ["A3UE_FPV_spawnTime",          serverTime,          true];

if (_eventId isNotEqualTo "") then {
	_uav setVariable ["A3UE_FPV_rivalEventId",   _eventId, true];
	_uav setVariable ["A3UE_FPV_transientRival", true,     true];
};

// --- Step 4: Create crew through injected factory or default ------------------
private _crewGroup = grpNull;

if ("crewFactory" in _spec) then {
	_crewGroup = [_side, _uav] call (_spec get "crewFactory");
};

if (isNull _crewGroup) then {
	if (!isNil "A3A_fnc_createVehicleCrew") then {
		_crewGroup = [_side, _uav] call A3A_fnc_createVehicleCrew;
	} else {
		createVehicleCrew _uav;
		if (crew _uav isNotEqualTo []) then {
			_crewGroup = group ((crew _uav) select 0);
		};
	};
};

// --- Step 5: Run postCrewInit callback ----------------------------------------
if ("postCrewInit" in _spec) then {
	[_uav, _crewGroup] call (_spec get "postCrewInit");
};

// --- Step 6: Seed target and initial mode -------------------------------------
if ("seedTarget" in _spec) then {
	private _seedTarget = _spec get "seedTarget";
	if (!isNull _seedTarget && {alive _seedTarget}) then {
		_uav setVariable ["A3UE_FPV_targetNetId", netId _seedTarget, true];
		if (_initialMode isEqualTo "IDLE") then {
			_uav setVariable ["A3UE_FPV_mode", "TRACKING", true];
		};
	};
};

// --- Steps 7/8: Vehicle init by mode ------------------------------------------
switch (_vehicleInitMode) do {
	case "AIVEHINIT": {
		// Site stock path: AU vehicle bookkeeping fires AIVehInit which triggers
		// fn_fpv_onAIVehInit -> remoteExecCall bootstrapLocal.
		if (!isNil "A3A_fnc_AIVEHinit") then {
			[_uav, _side, _resourcePool] call A3A_fnc_AIVEHinit;
		};
		[_uav] call A3UE_fnc_fpv_applyCompatInit;
	};
	case "DIRECT_BOOTSTRAP": {
		// Transient rival path: bypass AU vehicle bookkeeping entirely.
		// applyCompatInit normalizes vendor AI state early; bootstrapLocal
		// installs locality/deleted handlers, stamps controller variables,
		// and spawns the controller.  bootstrapLocal calls applyCompatInit
		// again internally, which is intentional and guarded against double-spawn.
		[_uav] call A3UE_fnc_fpv_applyCompatInit;
		[_uav] remoteExecCall ["A3UE_fnc_fpv_bootstrapLocal", 0, _uav];
	};
	default {
		[_uav] call A3UE_fnc_fpv_applyCompatInit;
	};
};

_uav
