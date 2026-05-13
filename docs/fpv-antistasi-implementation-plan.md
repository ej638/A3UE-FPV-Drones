# Updated FPV Drone Redesign & Integration Plan

Date: 2026-05-07
Scope: Production-ready Antistasi Ultimate integration of autonomous FPV threat drones through Antistasi Extender, grounded in source discovery across ArmaFPV, fpv_ua, frtz_fiberoptic_kvn, Antistasi Ultimate, and Antistasi Extender.

## 1. Executive Summary

The original redesign direction remains correct: the legacy Eden module has been replaced by a server-owned, event-driven FPV manager that reacts to Antistasi site lifecycle events and runs one controller per drone on the current locality owner.

The source discovery changed three important design details.

- ArmaFPV and fpv_ua are radio-link mods. Their player-control code models retranslators, jammer objects, and signal loss, but those scripts assume a human operator and are not suitable as-is for server-owned AI drones.
- frtz_fiberoptic_kvn is not a radio-link implementation. Its fiber system is primarily a rendered cable trail plus UI dressing. The stock mod does not implement a true jammer-driven or spool-break signal-loss state for autonomous drones.
- None of the three mods ship a dedicated reconnaissance-only airframe. Recon must be treated as a doctrine role built from the least-cost TI-capable or TI-equivalent kamikaze classes, not as a native `CfgVehicles` category.

Native support therefore requires:

- zero hard dependencies in our addon config, with runtime discovery through `CfgPatches`;
- an A3UE-owned compatibility catalog that resolves exact class names per mod and side;
- an A3UE-owned bootstrap path that overrides vendor init assumptions made for player-operated drones;
- an A3UE-owned detonation wrapper that detonates before physical collision and preserves mod-specific side effects where they matter;
- a radio-only EW branch in the controller, with KVN explicitly bypassing jammer and retranslator logic unless we add an optional custom tether model.

## 2. Verified Source Anchors

### Antistasi Ultimate

- `A3A\addons\events\Events.hpp` defines `AIVehInit` with arguments `[vehicle, side]` and `locationSpawned` with arguments `[marker, locationType, isSpawning]`.
- `A3A\addons\core\functions\CREATE\fn_AIVEHinit.sqf` triggers `AIVehInit` at the end of vehicle initialization.
- `A3A\addons\core\functions\CREATE\fn_createAIOutposts.sqf` triggers `locationSpawned` with `"Outpost"` after site vehicles and groups have already been initialized.
- `A3A\addons\core\functions\CREATE\fn_createAIResources.sqf` triggers `locationSpawned` with `"Resource"` after site initialization.
- `A3A\addons\core\functions\CREATE\fn_createAIAirplane.sqf` triggers `locationSpawned` with `"Airport"` after airport vehicles have already been spawned and initialized.
- `A3A\addons\core\functions\CREATE\fn_createAIMilbase.sqf` triggers `locationSpawned` with `"Milbase"` after the base vehicles and groups are initialized.
- `A3A\addons\core\functions\Base\fn_distance.sqf` schedules `factories` through `A3A_fnc_createAIresources` and `seaports` through `A3A_fnc_createAIOutposts`, so the raw `locationSpawned` strings for those sites remain `"Resource"` and `"Outpost"` unless the addon reclassifies them by marker membership.

### Antistasi Extender

- `A3UE\addons\functions\cfgFunctions.hpp` uses `postInit = 1` registration.
- `A3UE\addons\functions\Events\fn_addExampleEventListener.sqf` shows the intended listener pattern through `A3A_Events_fnc_addEventListener`.

### External FPV Mods

- ArmaFPV patch name: `ArmaFPV_Data`.
- fpv_ua patch name: `FPV_UA`.
- frtz_fiberoptic_kvn patch name: `frtz_KVN`.
- All three families define drone `CfgVehicles` with `hit` event handlers that call a vendor `fpv_onDestroy` function.
- All three families also run a vendor `fpv_droneInit` path that disables AI, because the stock mods are built around player remote control rather than autonomous AI guidance.

## 3. Verified Antistasi Hook Model

`locationSpawned` is the correct primary deployment hook.

- It gives the manager the site marker, the exact Antistasi location type string, and a spawn or despawn transition.
- The relevant raw Antistasi strings are `Airport`, `Milbase`, `Outpost`, and `Resource`.
- `Seaport` and `Factory` need marker-based normalization inside the addon because Antistasi routes them through the outpost and resource creators.
- The event fires after Antistasi has already created and initialized the site's normal vehicles and groups.

`AIVehInit` remains the correct secondary hook.

- It is ideal for locality-safe bootstrap of drones that have already been tagged as managed FPV assets.
- It must stay cheap and must ignore unrelated Antistasi vehicles.

Recommended registration remains:

```sqf
if !(isClass (missionConfigFile / "A3A")) exitWith {};

["locationSpawned", "A3UE_FPV_locationSpawned", A3UE_fnc_fpv_onLocationSpawned] call A3A_Events_fnc_addEventListener;
["AIVehInit", "A3UE_FPV_aivehInit", A3UE_fnc_fpv_onAIVehInit] call A3A_Events_fnc_addEventListener;
```

Important cleanup note:

- `locationSpawned` with `_isSpawning = false` is the authoritative site cleanup signal.
- Antistasi may still despawn moved vehicles asynchronously after that signal, so the FPV manager should deregister immediately on despawn and not wait for `Deleted` alone.

## 4. Runtime Soft-Dependency Layer

The addon config must not require any of the drone mods. Detection belongs in SQF and must use `isClass` against `CfgPatches`.

```sqf
/*
    File: fn_fpv_buildCompatCatalog.sqf
    Purpose: Discover loaded FPV families without hard dependencies.
*/

private _loaded = createHashMapFromArray [
    ["armafpv", isClass (configFile >> "CfgPatches" >> "ArmaFPV_Data")],
    ["fpv_ua",  isClass (configFile >> "CfgPatches" >> "FPV_UA")],
    ["kvn",     isClass (configFile >> "CfgPatches" >> "frtz_KVN")]
];

private _buildArmaFPVClassMap = {
    params ["_sidePrefix"];

    createHashMapFromArray [
        ["AT", [
            format ["%1_Crocus_AT", _sidePrefix],
            format ["%1_Crocus_AT_TI", _sidePrefix]
        ]],
        ["AP", [
            format ["%1_Crocus_AP", _sidePrefix],
            format ["%1_Crocus_AP_TI", _sidePrefix]
        ]],
        ["RECON", [
            format ["%1_Crocus_AT_TI", _sidePrefix],
            format ["%1_Crocus_AP_TI", _sidePrefix]
        ]]
    ]
};

private _buildUAClassMap = {
    params ["_sidePrefix"];

    createHashMapFromArray [
        ["AT", [format ["%1_UAFPV_PG7VL_AT", _sidePrefix]]],
        ["AP", [
            format ["%1_UAFPV_IED_AP", _sidePrefix],
            format ["%1_UAFPV_RKG_AP", _sidePrefix],
            format ["%1_UAFPV_OG7V_AP", _sidePrefix]
        ]],
        ["RECON", [
            format ["%1_UAFPV_RKG_AP", _sidePrefix],
            format ["%1_UAFPV_OG7V_AP", _sidePrefix]
        ]]
    ]
};

private _buildKVNClassMap = {
    params ["_sidePrefix"];

    createHashMapFromArray [
        ["AT", ["AT", "AT_20KM", "AT_25KM"] apply { format ["frtz_%1_KVN_%2", _sidePrefix, _x] }],
        ["AP", ["AP", "AP_20KM", "AP_25KM"] apply { format ["frtz_%1_KVN_%2", _sidePrefix, _x] }],
        ["RECON", [
            "AT_TI", "AP_TI",
            "AT_TI_20KM", "AP_TI_20KM",
            "AT_TI_25KM", "AP_TI_25KM"
        ] apply { format ["frtz_%1_KVN_%2", _sidePrefix, _x] }]
    ]
};

private _catalog = createHashMap;

if (_loaded get "armafpv") then {
    _catalog set ["armafpv", createHashMapFromArray [
        ["patch", "ArmaFPV_Data"],
        ["signalModel", "RADIO"],
        ["nativeRecon", false],
        ["retranslatorClass", "FPV_Retranslator"],
        ["jammerClasses", ["Sania", "Sania_with_tripod"]],
        ["classesBySide", createHashMapFromArray [
            [east, ["O"] call _buildArmaFPVClassMap],
            [west, ["B"] call _buildArmaFPVClassMap],
            [independent, ["I"] call _buildArmaFPVClassMap]
        ]]
    ]];
};

if (_loaded get "fpv_ua") then {
    _catalog set ["fpv_ua", createHashMapFromArray [
        ["patch", "FPV_UA"],
        ["signalModel", "RADIO"],
        ["nativeRecon", false],
        ["retranslatorClass", "FPV_Retranslator"],
        ["jammerClasses", ["Sania", "Sania_with_tripod"]],
        ["classesBySide", createHashMapFromArray [
            [east, ["O"] call _buildUAClassMap],
            [west, ["B"] call _buildUAClassMap],
            [independent, ["I"] call _buildUAClassMap]
        ]]
    ]];
};

if (_loaded get "kvn") then {
    _catalog set ["kvn", createHashMapFromArray [
        ["patch", "frtz_KVN"],
        ["signalModel", "FIBER_VISUAL"],
        ["nativeRecon", false],
        ["retranslatorClass", ""],
        ["jammerClasses", []],
        ["classesBySide", createHashMapFromArray [
            [east, ["O"] call _buildKVNClassMap],
            [west, ["B"] call _buildKVNClassMap],
            [independent, ["I"] call _buildKVNClassMap]
        ]]
    ]];
};

missionNamespace setVariable ["A3UE_FPV_loadedMods", _loaded];
missionNamespace setVariable ["A3UE_FPV_catalog", _catalog];
```

This keeps `config.cpp` free of `requiredAddons[]` references to any drone family while still giving the manager exact, validated runtime knowledge.

## 5. External Drone Family Findings

### 5.1 ArmaFPV

- Patch: `ArmaFPV_Data`
- Role classes:
  - AT: `O_Crocus_AT`, `B_Crocus_AT`, `I_Crocus_AT`
  - AP: `O_Crocus_AP`, `B_Crocus_AP`, `I_Crocus_AP`
  - TI variants: `*_AT_TI`, `*_AP_TI`
  - Recon equivalent: TI variants only; there is no pure recon airframe
- Support object: `FPV_Retranslator`
- Init behavior: `fpv_droneInit` disables AI and sets `DB_jammer_customUavBehavior = true`
- Radio model:
  - looks for `FPV_Retranslator` near the player or UAV;
  - looks for jammers of classes `Sania` and `Sania_with_tripod` with `DB_jammer_isActive = true`;
  - uses `FPV_MaxFlightDistance` with a default of 4000;
  - tracks `DB_timeInJammerZone`, `DB_fpv_signal_obstacles`, and `DB_fpv_signal_terrainMask`
- Detonation behavior:
  - guarded by `DB_fpv_isDetonating`;
  - converts AT classes into `FPV_RPG42_AT` and AP classes into `R_TBG32V_F`;
  - sets shot parents and calls `triggerAmmo` on the replacement munition

### 5.2 fpv_ua

- Patch: `FPV_UA`
- Role classes:
  - AT: `O_UAFPV_PG7VL_AT`, `B_UAFPV_PG7VL_AT`, `I_UAFPV_PG7VL_AT`
  - AP: `O_UAFPV_IED_AP`, `O_UAFPV_RKG_AP`, `O_UAFPV_OG7V_AP`, and the BLUFOR and INDFOR equivalents
  - Recon equivalent: doctrine-only; all base view optics already include thermal vision, but there is no dedicated recon class
- Support object: `FPV_Retranslator`
- Init behavior: `fpv_droneInit` disables AI and sets `DB_jammer_customUavBehavior = true`
- Radio model:
  - uses the same retranslator and jammer object conventions as ArmaFPV;
  - sets `UA_fpv_isUAVsignalLost` on signal loss;
  - client control loops are hardcoded and should not be reused for autonomous AI
- Detonation behavior:
  - no double-detonation guard;
  - all classes whose name contains `"at"` detonate as `FPV_RPG42_AT`;
  - all classes whose name contains `"ap"` detonate as `R_TBG32V_F`

Important fpv_ua finding:

- The payload-specific class names are mostly cosmetic and model-driven in the stock scripts. Runtime detonation is still reduced to the same AT or AP warhead split.

### 5.3 frtz_fiberoptic_kvn

- Patch: `frtz_KVN`
- Role classes:
  - AT: `frtz_[O|B|I]_KVN_AT`, `_AT_20KM`, `_AT_25KM`
  - AP: `frtz_[O|B|I]_KVN_AP`, `_AP_20KM`, `_AP_25KM`
  - TI equivalents: `*_AT_TI`, `*_AP_TI`, and their `_20KM` and `_25KM` variants
  - Recon equivalent: TI variants only; there is no dedicated non-warhead recon class
- Range finding:
  - `_20KM` and `_25KM` classes only override `displayName`, `fuelCapacity`, and backpack assembly targets;
  - there is no separate function-side behavior keyed to those suffixes
- Init behavior: `fpv_droneInit` disables AI and sets `DB_jammer_customUavBehavior = true`
- Fiber behavior:
  - the mod maintains `kvn_fiber_path`, `kvn_fiber_length`, `kvn_fiber_length_count`, and `kvn_lastSync` for rendering;
  - the stock update path keeps only a capped trail and does not enforce actual operator tether loss for autonomous drones;
  - `kvn_allowBotsShoot`, `kvn_showFiber`, and `kvn_fiberTTL` are CBA settings
- Detonation behavior:
  - converts AT and AP classes into the same AT and AP munitions used by the other mods;
  - archives `kvn_fiber_path` into `kvn_deadFibers` before deleting the UAV so clients can keep rendering a dead fiber trail

Important KVN finding:

- The stock fiber system is visual-first. It does not provide a real EW-resistant signal-loss mechanic we can directly adopt for autonomous Antistasi drones.
- The stock `fn_fpv_fiberTick.sqf` only updates the path while a player is remotely controlling the drone. Autonomous AI drones will not generate fiber trails unless A3UE writes the same variables itself.

## 6. Master Mod & Doctrine Matrix

### 6.1 Native role mapping

| Family | Patch | AT pool | AP pool | Recon pool | Notes |
| --- | --- | --- | --- | --- | --- |
| ArmaFPV | `ArmaFPV_Data` | `*_Crocus_AT`, `*_Crocus_AT_TI` | `*_Crocus_AP`, `*_Crocus_AP_TI` | TI variants only | True radio-link family with retranslator and jammer hooks |
| fpv_ua | `FPV_UA` | `*_UAFPV_PG7VL_AT` | `*_UAFPV_IED_AP`, `*_UAFPV_RKG_AP`, `*_UAFPV_OG7V_AP` | AP classes used as thermal recon surrogates | All base optics are TI-capable; no separate recon class |
| KVN | `frtz_KVN` | `frtz_*_KVN_AT[_20KM|_25KM]` | `frtz_*_KVN_AP[_20KM|_25KM]` | TI variants only | Fiber trail is visual compatibility, not a stock autonomous tether model |

### 6.2 Site doctrine weights

| Site Type | Spawn Chance | Stock | Role Weights | Family Bias |
| --- | --- | --- | --- | --- |
| `Airport` | 0.60 | 2-4 | `AT 60`, `AP 20`, `RECON 20` | Favor KVN `_25KM`, UAFPV `PG7VL_AT`, Crocus `AT_TI` |
| `Milbase` | 0.50 | 2-3 | `AT 45`, `AP 35`, `RECON 20` | Favor long-endurance KVN with stronger AT presence than outposts |
| `Seaport` | 0.45 | 1-3 | `AT 25`, `AP 40`, `RECON 35` | Favor KVN long-endurance classes and mixed AP/recon harassment |
| `Outpost` | 0.35 | 1-2 | `AT 30`, `AP 50`, `RECON 20` | Favor AP-heavy Crocus and fpv_ua, with KVN `_20KM` support |
| `Factory` | 0.30 | 1-2 | `AT 20`, `AP 40`, `RECON 40` | Favor fpv_ua and mixed recon harassment slightly above resources |
| `Resource` | 0.25 | 1 | `AT 15`, `AP 45`, `RECON 40` | Favor TI-capable AP harassment and short-range KVN base classes |

### 6.3 Resolved east-side example pools

The manager should resolve the same pattern for BLUFOR and INDFOR by switching the side prefixes (`O/B/I` and `frtz_O/frtz_B/frtz_I`).

```sqf
/*
    File: fn_fpv_buildDoctrine.sqf
    Purpose: Example resolved pools for east-side Occupants or Invaders.
*/

A3UE_FPV_doctrine = createHashMapFromArray [
    ["Airport", createHashMapFromArray [
        ["spawnChance", 0.60],
        ["stock", [2, 4]],
        ["pool", [
            ["AT", [
                ["frtz_O_KVN_AT_25KM", 18],
                ["frtz_O_KVN_AT_TI_25KM", 12],
                ["O_UAFPV_PG7VL_AT", 18],
                ["O_Crocus_AT_TI", 12],
                ["O_Crocus_AT", 6]
            ]],
            ["AP", [
                ["frtz_O_KVN_AP_20KM", 8],
                ["O_UAFPV_RKG_AP", 6],
                ["O_Crocus_AP", 6]
            ]],
            ["RECON", [
                ["frtz_O_KVN_AT_TI_20KM", 8],
                ["frtz_O_KVN_AP_TI_20KM", 6],
                ["O_Crocus_AT_TI", 4],
                ["O_UAFPV_OG7V_AP", 2]
            ]]
        ]]
    ]],
    ["Outpost", createHashMapFromArray [
        ["spawnChance", 0.35],
        ["stock", [1, 2]],
        ["pool", [
            ["AT", [
                ["O_UAFPV_PG7VL_AT", 8],
                ["frtz_O_KVN_AT_20KM", 6],
                ["O_Crocus_AT", 6]
            ]],
            ["AP", [
                ["O_Crocus_AP", 14],
                ["O_Crocus_AP_TI", 8],
                ["O_UAFPV_RKG_AP", 10],
                ["O_UAFPV_OG7V_AP", 10],
                ["frtz_O_KVN_AP_20KM", 8]
            ]],
            ["RECON", [
                ["O_Crocus_AP_TI", 8],
                ["frtz_O_KVN_AP_TI", 6],
                ["O_UAFPV_OG7V_AP", 4],
                ["frtz_O_KVN_AT_TI", 2]
            ]]
        ]]
    ]],
    ["Resource", createHashMapFromArray [
        ["spawnChance", 0.25],
        ["stock", [1, 1]],
        ["pool", [
            ["AT", [
                ["O_UAFPV_PG7VL_AT", 4],
                ["O_Crocus_AT", 3],
                ["frtz_O_KVN_AT", 3]
            ]],
            ["AP", [
                ["O_Crocus_AP", 8],
                ["O_UAFPV_RKG_AP", 8],
                ["O_UAFPV_IED_AP", 6],
                ["frtz_O_KVN_AP", 4]
            ]],
            ["RECON", [
                ["O_Crocus_AP_TI", 10],
                ["frtz_O_KVN_AP_TI", 8],
                ["frtz_O_KVN_AT_TI", 6],
                ["O_UAFPV_OG7V_AP", 6]
            ]]
        ]]
    ]]
];
```

Design rule:

- Use KVN `_25KM` primarily at airports, `_20KM` primarily at outposts, and base 15 km classes primarily at resources because those suffixes only change `fuelCapacity` and not script behavior.

## 7. Unified Lifecycle & Arming Compatibility

### 7.1 Spawn and registration

The manager should spawn through Antistasi's normal vehicle path, then immediately stamp compatibility metadata onto the drone object.

Required replicated variables:

- `A3UE_FPV_managed`: `BOOL`
- `A3UE_FPV_mode`: `STRING`
- `A3UE_FPV_siteMarker`: `STRING`
- `A3UE_FPV_siteType`: `STRING`
- `A3UE_FPV_profileId`: `STRING`
- `A3UE_FPV_vendorId`: `STRING` in `armafpv`, `fpv_ua`, `kvn`
- `A3UE_FPV_payloadRole`: `STRING` in `AT`, `AP`, `RECON`
- `A3UE_FPV_linkModel`: `STRING` in `RADIO`, `FIBER_VISUAL`
- `A3UE_FPV_rangeTier`: `STRING` such as `STD`, `20KM`, `25KM`
- `A3UE_FPV_targetNetId`: `STRING`
- `A3UE_FPV_lastInterceptASL`: `ARRAY`
- `A3UE_FPV_linkState`: `STRING`
- `A3UE_FPV_spawnTime`: `NUMBER`

Recommended spawn block:

```sqf
private _uav = createVehicle [_uavClass, _spawnPos, [], 0, "FLY"];
[_side, _uav] call A3A_fnc_createVehicleCrew;
{ [_x, _markerX, false, "defence"] call A3A_fnc_NATOinit } forEach crew _uav;
[_uav, _side, "defence"] call A3A_fnc_AIVEHinit;

_uav setVariable ["A3UE_FPV_managed", true, true];
_uav setVariable ["A3UE_FPV_mode", "IDLE", true];
_uav setVariable ["A3UE_FPV_siteMarker", _markerX, true];
_uav setVariable ["A3UE_FPV_siteType", _locationType, true];
_uav setVariable ["A3UE_FPV_profileId", _profileId, true];
_uav setVariable ["A3UE_FPV_vendorId", _vendorId, true];
_uav setVariable ["A3UE_FPV_payloadRole", _role, true];
_uav setVariable ["A3UE_FPV_linkModel", _linkModel, true];
_uav setVariable ["A3UE_FPV_rangeTier", _rangeTier, true];
_uav setVariable ["A3UE_FPV_linkState", "OK", true];
_uav setVariable ["A3UE_FPV_spawnTime", serverTime, true];
```

### 7.2 Compatibility bootstrap

Do not rely on vendor init scripts as the final behavior.

Reason:

- all three vendor `fpv_droneInit` functions disable AI;
- that is correct for player remote-control drones but wrong for A3UE's AI-guided autonomous threat controller.

The A3UE bootstrap must therefore normalize the drone after vendor init has fired.

```sqf
/*
    File: fn_fpv_applyCompatInit.sqf
    Purpose: Restore AI behavior needed for autonomous control while preserving vendor variables.
*/

params ["_uav"];

if (isNull _uav) exitWith {};
if (!local _uav) exitWith {};

_uav enableAI "ALL";
_uav setVariable ["DB_jammer_customUavBehavior", true, true];
_uav setVariable ["A3UE_FPV_linkState", "OK", true];

switch (_uav getVariable ["A3UE_FPV_vendorId", ""]) do {
    case "armafpv": {
        _uav setVariable ["DB_fpv_isDetonating", false, true];
        _uav setVariable ["DB_fpv_isUAVsignalLost", false, true];
    };

    case "fpv_ua": {
        _uav setVariable ["UA_fpv_isUAVsignalLost", false, true];
    };

    case "kvn": {
        _uav setCaptive false;
        _uav setVariable ["kvn_fiber_path", [], false];
        _uav setVariable ["kvn_fiber_length", 0, false];
        _uav setVariable ["kvn_fiber_length_count", 0, false];
        _uav setVariable ["kvn_lastSync", time, false];
    };
};
```

### 7.3 Radio EW compatibility

The A3UE controller must not call the vendor radio signal loops directly.

Reason:

- ArmaFPV and fpv_ua `getSignal` functions both assume a player operator object.
- Their client control loops are UI and remote-control driven, not server-owned AI driven.

Recommended compatibility rule:

- `RADIO` families may optionally honor hostile jammer objects and doctrine site radius through an A3UE-owned `fn_fpv_evaluateLinkState.sqf`.
- `FIBER_VISUAL` families skip retranslator and jammer evaluation entirely.

Recommended behavior split:

- `RADIO` and link denied: set `A3UE_FPV_linkState = "EW_DENIED"`, hold or orbit, and temporarily return to `IDLE`.
- `FIBER_VISUAL`: keep `A3UE_FPV_linkState = "OK"` unless a separate A3UE-only tether mechanic is intentionally implemented later.

### 7.4 KVN fiber compatibility

If autonomous KVN drones should display a fiber trail for clients, A3UE must update the same object variables the vendor renderer expects.

Required compatibility path:

- owner-side periodic update mirroring the stock `kvn_fiber_path` write pattern;
- replicated trail through `DB_kvn_fnc_fpv_receivePath` semantics or equivalent `setVariable` writes;
- dead-fiber archival on detonation through `kvn_deadFibers` if `kvn_fiberTTL > 0`.

Without that A3UE-owned trail writer, autonomous KVN drones will behave correctly but will not show the vendor fiber effect.

### 7.5 Arming and detonation

The extension must not wait for a physical collision to trigger the strike.

Reason:

- the user requirement is to prevent bounce-off behavior;
- vendor `hit` handlers are fallback safety nets, not a reliable terminal guidance end state.

Recommended design:

- enter `TERMINAL_ATTACK` once intercept is stable and the target is inside the final gate;
- call A3UE's detonation wrapper when the drone is inside a pre-impact threshold or collision corridor;
- leave vendor `hit` event handlers in place only as fallback when the drone is shot down or otherwise damaged before terminal release.

Normalized detonation wrapper:

```sqf
/*
    File: fn_fpv_detonateCompat.sqf
    Purpose: Detonate managed FPV drones before impact while preserving family-specific side effects.
*/

params ["_uav", ["_target", objNull]];

if (isNull _uav) exitWith {};
if (_uav getVariable ["A3UE_FPV_detonating", false]) exitWith {};

_uav setVariable ["A3UE_FPV_detonating", true];
_uav setVariable ["DB_fpv_isDetonating", true, true];

private _vendorId = _uav getVariable ["A3UE_FPV_vendorId", ""];
private _payloadRole = _uav getVariable ["A3UE_FPV_payloadRole", "AP"];
private _missileType = switch (_payloadRole) do {
    case "AT": { "FPV_RPG42_AT" };
    default { "R_TBG32V_F" };
};

if (_vendorId isEqualTo "kvn") then {
    private _path = _uav getVariable ["kvn_fiber_path", []];
    if !(_path isEqualTo []) then {
        private _ttl = missionNamespace getVariable ["kvn_fiberTTL", 20];
        if (_ttl > 0) then {
            private _now = time;
            missionNamespace setVariable [
                "kvn_deadFibers",
                (missionNamespace getVariable ["kvn_deadFibers", []]) + [[_path, _now + _ttl, _now, +_path]],
                true
            ];
        };
    };
};

private _killer = driver _uav;
private _instigator = (UAVControl _uav) # 0;

if (!isNull _killer) then {
    if (local _killer) then {
        _killer setCaptive false;
    } else {
        [_killer, false] remoteExec ["setCaptive", 2];
    };
};

private _missile = createVehicle [_missileType, _uav modelToWorld [0, 0, 0]];
_missile setVectorDirAndUp [vectorDir _uav, vectorUp _uav];

[_missile, [_killer, _instigator]] remoteExec ["setShotParents", 2];
[_missile, true] remoteExec ["hideObjectGlobal", 2];

{ _uav deleteVehicleCrew _x } forEach crew _uav;
deleteVehicle _uav;

[
    {
        _this params ["_missile", "_shotParents"];
        (getShotParents _missile) isEqualTo _shotParents
    },
    {
        _this params ["_missile"];
        triggerAmmo _missile;
    },
    [_missile, [_killer, _instigator]]
] call CBA_fnc_waitUntilAndExecute;
```

This wrapper keeps the only cross-family behavior that actually matters:

- correct AT or AP munition selection;
- correct kill attribution through `setShotParents`;
- KVN dead-fiber archiving when a trail exists.

## 8. Completed Architecture & State Machine

### 8.1 Component split

1. `FPV_Manager`
   - server-owned;
   - listens to `locationSpawned`;
   - selects a loaded drone family and exact class from doctrine;
   - spawns, tags, and registers FPV drones per site.

2. `FPV_CompatCatalog`
   - built during post-init;
   - stores soft-detected patches, class maps, signal model, and role equivalence.

3. `FPV_BootstrapLocal`
   - runs only when the managed UAV becomes local;
   - restores AI after vendor init disables it;
   - starts KVN fiber trail compatibility when needed;
   - starts the controller exactly once per locality owner.

4. `FPV_Controller`
   - runs only where `local _uav` is true;
   - evaluates link model, targeting, intercept, and detonation;
   - writes public state for JIP observers.

5. `FPV_Targeting`
   - performs bounded hostile queries near the site and drone;
   - avoids whole-world scans.

6. `FPV_Detonation`
   - converts managed drones to munitions before impact;
   - preserves KVN dead-fiber behavior when a trail exists.

### 8.2 Runtime state model

Use `A3UE_FPV_mode` for the strike controller and `A3UE_FPV_linkState` for transport or EW compatibility.

Controller modes:

- `IDLE`
- `SEARCHING`
- `TRACKING`
- `TERMINAL_ATTACK`

Link states:

- `OK`
- `DEGRADED`
- `EW_DENIED`

Important compatibility rule:

- `EW_DENIED` is meaningful only for `RADIO` families.
- `FIBER_VISUAL` families should stay in `OK` by default because the stock KVN implementation does not supply a real autonomous signal-loss mechanic.

### 8.3 Locality-safe bootstrap

```sqf
/*
    File: fn_fpv_bootstrapLocal.sqf
    Purpose: Start the FPV controller only on the machine where the drone is local.
*/

params ["_uav"];

if (isNull _uav) exitWith {};
if !(_uav getVariable ["A3UE_FPV_managed", false]) exitWith {};

private _ehId = _uav getVariable ["A3UE_FPV_localityEH", -1];
if (_ehId < 0) then {
    _ehId = _uav addEventHandler ["Local", {
        params ["_vehicle", "_isLocal"];

        if !(_vehicle getVariable ["A3UE_FPV_managed", false]) exitWith {};

        if (_isLocal) then {
            [_vehicle] spawn A3UE_fnc_fpv_bootstrapLocal;
        } else {
            _vehicle setVariable ["A3UE_FPV_controllerRunning", false];
            _vehicle setVariable ["A3UE_FPV_fiberTrailRunning", false];
        };
    }];

    _uav setVariable ["A3UE_FPV_localityEH", _ehId];
};

if (!local _uav) exitWith {};
if (_uav getVariable ["A3UE_FPV_controllerRunning", false]) exitWith {};

[_uav] call A3UE_fnc_fpv_applyCompatInit;

if ((_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) isEqualTo "FIBER_VISUAL") then {
    [_uav] call A3UE_fnc_fpv_startFiberTrailCompat;
};

_uav setVariable ["A3UE_FPV_controllerRunning", true];

if ((_uav getVariable ["A3UE_FPV_mode", ""]) isEqualTo "") then {
    _uav setVariable ["A3UE_FPV_mode", "IDLE", true];
};

[_uav] spawn A3UE_fnc_fpv_runController;
```

### 8.4 State machine

```sqf
/*
    File: fn_fpv_runController.sqf
    Purpose: Drone-local state machine for search, track, and terminal attack.
*/

params ["_uav"];

if (isNull _uav) exitWith {};

private _profile = [_uav] call A3UE_fnc_fpv_getProfile;
private _target = objNull;

while {
    alive _uav &&
    local _uav &&
    (_uav getVariable ["A3UE_FPV_controllerRunning", false])
} do {
    private _mode = _uav getVariable ["A3UE_FPV_mode", "IDLE"];
    private _sleepTime = 0.25;
    private _linkState = [_uav, _profile] call A3UE_fnc_fpv_evaluateLinkState;

    _uav setVariable ["A3UE_FPV_linkState", _linkState, true];

    if ([_uav] call A3UE_fnc_fpv_isExternallyControlled) then {
        if (_mode != "IDLE") then {
            _uav setVariable ["A3UE_FPV_mode", "IDLE", true];
            [_uav] call A3UE_fnc_fpv_clearTarget;
        };
        sleep 1;
    } else {
        if ((_uav getVariable ["A3UE_FPV_linkModel", "RADIO"]) isEqualTo "RADIO" && {_linkState == "EW_DENIED"}) then {
            [_uav, _profile] call A3UE_fnc_fpv_holdPattern;
            _uav setVariable ["A3UE_FPV_mode", "IDLE", true];
            _sleepTime = 1;
        } else {
            switch (_mode) do {
                case "IDLE": {
                    [_uav, _profile] call A3UE_fnc_fpv_holdPattern;
                    _uav setVariable ["A3UE_FPV_mode", "SEARCHING", true];
                    _sleepTime = 1;
                };

                case "SEARCHING": {
                    _target = [_uav, _profile] call A3UE_fnc_fpv_selectTarget;

                    if (isNull _target) then {
                        [_uav, _profile] call A3UE_fnc_fpv_holdPattern;
                        _sleepTime = 1;
                    } else {
                        _uav setVariable ["A3UE_FPV_targetNetId", netId _target, true];
                        _uav setVariable ["A3UE_FPV_mode", "TRACKING", true];
                        _sleepTime = 0.1;
                    };
                };

                case "TRACKING": {
                    _target = [_uav] call A3UE_fnc_fpv_resolveTarget;

                    if (isNull _target || {!alive _target}) then {
                        [_uav] call A3UE_fnc_fpv_clearTarget;
                        _uav setVariable ["A3UE_FPV_mode", "SEARCHING", true];
                        _sleepTime = 0.5;
                    } else {
                        private _intercept = [_uav, _target, _profile] call A3UE_fnc_fpv_computeIntercept;
                        _uav setVariable ["A3UE_FPV_lastInterceptASL", _intercept, true];

                        [_uav, _intercept, _profile] call A3UE_fnc_fpv_applyGuidance;

                        if ([_uav, _target, _profile] call A3UE_fnc_fpv_shouldEnterTerminal) then {
                            _uav setVariable ["A3UE_FPV_mode", "TERMINAL_ATTACK", true];
                            _sleepTime = 0.05;
                        } else {
                            _sleepTime = 0.1;
                        };
                    };
                };

                case "TERMINAL_ATTACK": {
                    _target = [_uav] call A3UE_fnc_fpv_resolveTarget;

                    if (isNull _target || {!alive _target}) then {
                        [_uav] call A3UE_fnc_fpv_clearTarget;
                        _uav setVariable ["A3UE_FPV_mode", "SEARCHING", true];
                        _sleepTime = 0.25;
                    } else {
                        [_uav, _target, _profile] call A3UE_fnc_fpv_runTerminal;

                        if ([_uav, _target, _profile] call A3UE_fnc_fpv_shouldDetonateNow) then {
                            [_uav, _target] call A3UE_fnc_fpv_detonateCompat;
                        } else {
                            _sleepTime = 0.02;
                        };
                    };
                };

                default {
                    _uav setVariable ["A3UE_FPV_mode", "IDLE", true];
                    _sleepTime = 1;
                };
            };
        };

        sleep _sleepTime;
    };
};

_uav setVariable ["A3UE_FPV_controllerRunning", false];
```

This keeps the original four-state design while making the radio or fiber difference explicit through `A3UE_FPV_linkModel` and `A3UE_FPV_linkState`.

### 8.5 Lead-pursuit intercept

The intercept solver remains valid. The compatibility change is that per-family performance differences now live in the doctrine profile, not in the solver itself.

$$
\text{InterceptPos} = \text{TargetPos} + (\text{TargetVelocity} \times t)
$$

```sqf
/*
    File: fn_fpv_computeIntercept.sqf
    Purpose: Lead-pursuit intercept for all supported drone families.
*/

params ["_uav", "_target", "_profile"];

private _uavPos = getPosASL _uav;
private _targetPos = getPosASL _target;
private _uavVel = velocity _uav;
private _targetVel = velocity _target;

private _relPos = _targetPos vectorDiff _uavPos;
private _relVel = _targetVel vectorDiff _uavVel;
private _chaseSpeed = [_profile, "terminalSpeed", 70] call A3UE_fnc_fpv_profileValue;

private _a = (_relVel vectorDotProduct _relVel) - (_chaseSpeed * _chaseSpeed);
private _b = 2 * (_relPos vectorDotProduct _relVel);
private _c = _relPos vectorDotProduct _relPos;

private _timeToImpact = 0;

if (abs _a < 0.001) then {
    if (abs _b > 0.001) then {
        _timeToImpact = (-_c / _b) max 0;
    };
} else {
    private _disc = (_b * _b) - (4 * _a * _c);
    if (_disc >= 0) then {
        private _root = sqrt _disc;
        private _t1 = (-_b - _root) / (2 * _a);
        private _t2 = (-_b + _root) / (2 * _a);
        private _valid = [_t1, _t2] select { _x > 0 };

        if (_valid isNotEqualTo []) then {
            _timeToImpact = selectMin _valid;
        };
    };
};

if (_timeToImpact <= 0) then {
    _timeToImpact = ((vectorMagnitude _relPos) / _chaseSpeed) max 0.1;
};

_timeToImpact = _timeToImpact min ([_profile, "maxLeadTime", 3] call A3UE_fnc_fpv_profileValue);

private _intercept = _targetPos vectorAdd (_targetVel vectorMultiply _timeToImpact);
private _terminalHeight = [_profile, "attackHeightASL", 12] call A3UE_fnc_fpv_profileValue;

_intercept set [2, ((_intercept select 2) max _terminalHeight)];
_intercept
```

The solver remains family-agnostic. Family differences should be expressed through `terminalSpeed`, `maxLeadTime`, and attack-height values in the doctrine profile.

## 9. Implementation Sequence

1. Add the A3UE post-init listener registration for `locationSpawned` and `AIVehInit`.
2. Implement `fn_fpv_buildCompatCatalog.sqf` and `fn_fpv_buildDoctrine.sqf`.
3. Implement the server-side manager registry and site evaluation.
4. Implement drone spawn, tagging, and doctrine-based class selection.
5. Implement `fn_fpv_applyCompatInit.sqf` to undo vendor player-control assumptions.
6. Implement `fn_fpv_bootstrapLocal.sqf` and locality handoff.
7. Implement the four-state controller with `A3UE_FPV_linkModel` and `A3UE_FPV_linkState` support.
8. Implement KVN autonomous trail compatibility if visual fiber support is desired.
9. Implement normalized pre-impact detonation through `fn_fpv_detonateCompat.sqf`.
10. Add optional radio EW behavior only after the core MP-safe strike loop is stable.

## 10. Validation Checklist

- Dedicated server only: exactly one controller runs per drone.
- Dedicated server plus HC: controller stops on the old owner and restarts on the new owner.
- `Airport`, `Outpost`, and `Resource` all trigger the manager exactly once on site spawn.
- `locationSpawned` with `_isSpawning = false` deregisters FPV drones immediately.
- ArmaFPV drones re-enable AI after vendor init and still strike correctly.
- fpv_ua drones do not rely on vendor client loops and still detonate cleanly.
- KVN drones skip radio EW denial and can optionally render autonomous fiber trails if A3UE trail writing is enabled.
- JIP clients observe `A3UE_FPV_mode`, `A3UE_FPV_targetNetId`, and `A3UE_FPV_linkState` without running guidance.
- Terminal takeover or Zeus remote control forces `IDLE` and clears the autonomous target.
- Pre-impact detonation prevents bounce-off and does not require physical collision.
- Vendor `hit` handlers remain fallback-only and do not control the primary strike path.

## 11. Final Recommendation

The redesign should proceed as an Antistasi Extender feature with three explicit compatibility families discovered at runtime: `ArmaFPV_Data`, `FPV_UA`, and `frtz_KVN`.

The architecture should stay server-owned and event-driven, but the implementation must not treat the external mods as interchangeable. ArmaFPV and fpv_ua are radio-themed families whose stock signal code is tied to player control, while KVN is a fiber-themed family whose stock autonomous signal-loss mechanic is effectively absent. That means the extension should own the controller, own the link model, and own the terminal detonation path, while reusing only the stable compatibility surfaces from the vendor mods: class names, payload families, shared munition mapping, and KVN dead-fiber trail variables.

This plan fixes the original blockers and the newly discovered compatibility risks at the same time:

- locality remains authoritative and HC-safe;
- global module polling stays removed;
- no hard dependency is introduced for any drone mod;
- vendor player-control assumptions are overridden rather than inherited;
- KVN is represented accurately as fiber-visual rather than falsely modeled as a stock autonomous tether system.