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
//   payloadRole        - tactical task "AT", "AP", or "RECON" (not a warhead)
//
// Optional spec keys:
//   uavClass          - explicit UAV class override for pre-resolved support plans
//   controlPosATL      - [x, y, z] radio control node; defaults to spawnPosATL
//   fiberAnchorPos     - [x, y, z] KVN fiber visual origin; defaults to ground projection
//   launchDir          - initial heading (degrees); defaults to random
//   initialMode        - initial controller mode; defaults to "IDLE"
//   seedTarget         - object to pre-seed as tracking target
//   targetSide         - encounter faction restriction; sideUnknown allows live hostiles
//   supportSafetyRadius - selected support doctrine; absent/zero preserves other drones
//   crewFactory        - code {params ["_side", "_uav"]; returns GROUP}
//   postCrewInit       - code {params ["_uav", "_crewGroup", "_resourcePool"]; ...}
//   vehicleInitMode    - "AIVEHINIT" (default) or "DIRECT_BOOTSTRAP"
//   resourcePool       - AU resource pool for AIVEHINIT path; defaults to "defence"
//   eventId            - transient event identity string (stamps rivalry metadata)

params [["_spec", createHashMap]];

if (!isServer) exitWith {objNull};
// SUP_FPV grants this private scope only after validating AU dispatch/caller.
// Direct RPCs cannot supply it through spec keys or extra positional arguments.
private _supportAuthorized = !isNil "_A3UE_FPV_spawnAuthorized" && {_A3UE_FPV_spawnAuthorized isEqualTo true};
// Recheck the engine role as well: an untrusted callback elsewhere in the
// mission could manufacture a same-named private variable.
if (isRemoteExecuted && {remoteExecutedOwner != 2}
	&& {!_supportAuthorized || {!([true] call A3UE_fnc_fpv_isTrustedSupportCaller)}}) exitWith {objNull};
if (_supportAuthorized && {missionNamespace getVariable ["A3UE_FPV_debug", false]}) then {
	diag_log format ["[A3UE_FPV] supportSpawn remote=%1 sender=%2 scheduled=%3 authorized=%4", isRemoteExecuted, remoteExecutedOwner, canSuspend, _supportAuthorized];
};
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
private _uavClass        = _spec getOrDefault ["uavClass",        ""];

// --- Validate family in catalog -----------------------------------------------
private _catalog = missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap];
if (count _catalog == 0) then {
	_catalog = call A3UE_fnc_fpv_buildCompatCatalog;
};

private _familyData = _catalog getOrDefault [_familyId, createHashMap];
if (count _familyData == 0) exitWith {objNull};

// --- Step 1: Resolve UAV class from doctrine pools ----------------------------
if !(_uavClass isEqualType "") exitWith {objNull};

if (_uavClass isEqualTo "") then {
	_uavClass = [_familyId, _payloadRole, _side, _siteType] call A3UE_fnc_fpv_selectClassForRole;
};

if (_uavClass isEqualTo "") exitWith {objNull};
if !(isClass (configFile >> "CfgVehicles" >> _uavClass)) exitWith {objNull};

private _descriptor = [_uavClass, _familyId, _payloadRole, _side] call A3UE_fnc_fpv_getClassDescriptor;
if (count _descriptor == 0 || {!(_descriptor get "canDetonate")} || {(_descriptor get "ammoClass") == ""}) exitWith {objNull};

// Bind before creation: native init may request a forced replacement.
// Do not create managed UA stock unless both service entry points are guarded.
if (_familyId isEqualTo "fpv_ua" && {!(call A3UE_fnc_fpv_installUaPayloadAdapter)}) exitWith {objNull};

// --- Step 2: Create UAV -------------------------------------------------------
// F4-2 field fix: every drone gets its own launch slot. A shared point (site standoff,
// 4 m support spacing) made KVN pairs collide and detonate at launch.
private _launchSlot = [_spawnPosATL, _launchDir] call A3UE_fnc_fpv_launchSlot;
_spawnPosATL = _launchSlot # 0;
private _spawnHeight = _spawnPosATL param [2, 35];

private _uav = objNull;
private _lifecycleId = -1;
// F5-1b breadcrumbs (server-local, read by A3UE_fnc_fpv_siteQueueProbe): [step, id, tick, extra].
missionNamespace setVariable ["A3UE_FPV_spawnStage", ["create", [_searchAnchorMarker, _spec getOrDefault ["supportName", ""]], diag_tickTime, _uavClass]];
// EntityCreated schedules native KVN tracking. Keep only creation, the managed
// flag and server registration in one slice; crew/compatibility remain scheduled.
isNil {
    _uav = createVehicle [_uavClass, _spawnPosATL, [], 0, "FLY"];
    if (!isNull _uav) then {
        _uav setVariable ["A3UE_FPV_managed", true, true];
        _lifecycleId = [_uav, true, _spec getOrDefault ["supportName", ""],
            [_searchAnchorMarker, ""] select ((_spec getOrDefault ["supportName", ""]) != "" || {_eventId != ""}), _eventId] call A3UE_fnc_fpv_registerLifecycle;
    };
};
if (isNull _uav) exitWith {objNull};
if (_lifecycleId < 0) exitWith {deleteVehicle _uav; objNull};
missionNamespace setVariable ["A3UE_FPV_spawnStage", ["created", netId _uav, diag_tickTime, _lifecycleId]];

_uav setDir _launchDir;
_uav setPosATL _spawnPosATL;
_uav flyInHeight _spawnHeight;
_uav setVariable ["A3UE_FPV_launchSlot", _launchSlot # 1];

// --- Step 3: Stamp all A3UE_FPV_* metadata before any external init path -----
private _linkModel = _descriptor get "linkModel";

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

_uav setVariable ["A3UE_FPV_mode",               _initialMode,        true];
_uav setVariable ["A3UE_FPV_siteMarker",         _searchAnchorMarker, true];
_uav setVariable ["A3UE_FPV_siteType",           _siteType,           true];
_uav setVariable ["A3UE_FPV_profileId",          _profileId,          true];
_uav setVariable ["A3UE_FPV_vendorId",           _familyId,           true];
_uav setVariable ["A3UE_FPV_payloadRole",        _payloadRole,        true];
_uav setVariable ["A3UE_FPV_physicalPayload",    _descriptor get "physicalPayload", true];
_uav setVariable ["A3UE_FPV_ammoClass",          _descriptor get "ammoClass", true];
_uav setVariable ["A3UE_FPV_canDetonate",        _descriptor get "canDetonate", true];
_uav setVariable ["A3UE_FPV_sensorProfile",      _descriptor get "sensorProfile", true];
_uav setVariable ["A3UE_FPV_linkModel",          _linkModel,          true];
_uav setVariable ["A3UE_FPV_rangeTier",          _rangeTier,          true];
_uav setVariable ["A3UE_FPV_netId",              netId _uav,          true];
_uav setVariable ["A3UE_FPV_controlPosATL",      _controlPosATL,      true];
_uav setVariable ["A3UE_FPV_fiberAnchorPos",     _fiberAnchorPos,     false];
_uav setVariable ["A3UE_FPV_targetNetId",        "",                  true];
_uav setVariable ["A3UE_FPV_targetSide",         _spec getOrDefault ["targetSide", sideUnknown], true];
_uav setVariable ["A3UE_FPV_lastInterceptASL",   [],                  true];
_uav setVariable ["A3UE_FPV_linkState",          "OK",                true];
_uav setVariable ["A3UE_FPV_spawnTime",          serverTime,          true];

if ("supportSafetyRadius" in _spec) then {
	_uav setVariable ["A3UE_FPV_supportSafetyRadius", _spec get "supportSafetyRadius", true];
	_uav setVariable ["A3UE_FPV_supportSide", _side, true];
};

isNil {
	// Custom IDs do not inherit object-key deletion; install cleanup before any enqueue.
	private _bootstrapJipId = format ["A3UE_FPV_bootstrap_%1_%2", netId _uav, _lifecycleId];
	_uav setVariable ["A3UE_FPV_bootstrapJipIdServer", _bootstrapJipId];
	_uav setVariable ["A3UE_FPV_bootstrapJipId", _bootstrapJipId, true];
	private _bootstrapDeletedEhId = _uav addEventHandler ["Deleted", {
		params ["_vehicle"];
		if (!isServer) exitWith {};
		private _jipId = _vehicle getVariable ["A3UE_FPV_bootstrapJipIdServer", ""];
		if (_jipId isNotEqualTo "") then {
			remoteExec ["", _jipId];
		};
	}];
	_uav setVariable ["A3UE_FPV_bootstrapDeletedEH", _bootstrapDeletedEhId];
};

if (_eventId isNotEqualTo "") then {
	_uav setVariable ["A3UE_FPV_rivalEventId",   _eventId, true];
	_uav setVariable ["A3UE_FPV_transientRival", true,     true];
};

// --- Step 4: Create crew through injected factory or default ------------------
missionNamespace setVariable ["A3UE_FPV_spawnStage", ["crew", netId _uav, diag_tickTime, _lifecycleId]];
private _crewGroup = grpNull;

if ("crewFactory" in _spec) then {
	_crewGroup = [_side, _uav] call (_spec get "crewFactory");
};

if (isNull _crewGroup) then {
	if (unitIsUAV _uav) then {
		// F5: owned crew group; AU's UAV branch would leave an empty engine group behind.
		_crewGroup = [_side, _uav] call A3UE_fnc_fpv_createUavCrew;
	} else {
		if (!isNil "A3A_fnc_createVehicleCrew") then {
			_crewGroup = [_side, _uav] call A3A_fnc_createVehicleCrew;
		} else {
			createVehicleCrew _uav;
			if (crew _uav isNotEqualTo []) then {
				_crewGroup = group ((crew _uav) select 0);
			};
		};
	};
};

// LS-03: AU-initialised crew carry their actual class as unitType (NATOinit's own fallback),
// without NATOinit's missing-type warning. Rivals stamp their own crew type in their callback.
if (_vehicleInitMode isEqualTo "AIVEHINIT") then {
	{
		if (isNil {_x getVariable "unitType"}) then {_x setVariable ["unitType", typeOf _x, true];};
	} forEach (crew _uav);
};

// --- Step 5: Run postCrewInit callback ----------------------------------------
missionNamespace setVariable ["A3UE_FPV_spawnStage", ["postCrew", netId _uav, diag_tickTime, _lifecycleId, count (crew _uav)]];
if ("postCrewInit" in _spec) then {
	[_uav, _crewGroup, _resourcePool] call (_spec get "postCrewInit");
};

if (!isNull _crewGroup) then {
	_crewGroup deleteGroupWhenEmpty true;
};

// --- Step 6: Seed target and initial mode -------------------------------------
if ("seedTarget" in _spec) then {
	private _seedTarget = _spec get "seedTarget";
	private _hostileSides = [_side, _uav getVariable ["A3UE_FPV_targetSide", sideUnknown]] call A3UE_fnc_fpv_getHostileSides;
	_seedTarget = [_seedTarget, _hostileSides] call A3UE_fnc_fpv_filterTarget;
	if (!isNull _seedTarget) then {
		_uav setVariable ["A3UE_FPV_targetNetId", netId _seedTarget, true];
		if (_initialMode isEqualTo "IDLE") then {
			_uav setVariable ["A3UE_FPV_mode", "TRACKING", true];
		};
	};
};

// --- Steps 7/8: Vehicle init by mode ------------------------------------------
missionNamespace setVariable ["A3UE_FPV_spawnStage", ["vehInit", netId _uav, diag_tickTime, _lifecycleId, _vehicleInitMode]];
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
		isNil {
			if (!isNull _uav && {_uav getVariable ["A3UE_FPV_managed", false]}) then {
				[_uav] remoteExecCall ["A3UE_fnc_fpv_bootstrapLocal", 0, _uav getVariable ["A3UE_FPV_bootstrapJipId", ""]];
			};
		};
	};
	default {
		[_uav] call A3UE_fnc_fpv_applyCompatInit;
	};
};

// F5: record the crew and every group they are in after vehicle init (which can move them),
// so the sweep at deletion removes exactly these (registerLifecycle's Deleted handler).
private _crewGroups = (_uav getVariable ["A3UE_FPV_crewGroups", []]) select {!isNull _x};
if (!isNull _crewGroup) then {_crewGroups pushBackUnique _crewGroup;};
{
	private _group = group _x;
	if (!isNull _group) then {
		_crewGroups pushBackUnique _group;
		_group deleteGroupWhenEmpty true;
	};
} forEach (crew _uav);
_uav setVariable ["A3UE_FPV_crewUnits", crew _uav];
_uav setVariable ["A3UE_FPV_crewGroups", _crewGroups];
missionNamespace setVariable ["A3UE_FPV_spawnStage", ["recorded", netId _uav, diag_tickTime, _lifecycleId, count _crewGroups]];

_uav
