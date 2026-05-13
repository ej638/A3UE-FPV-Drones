# FPV Antistasi Integration

Date: 2026-05-12

## Scope

This document is the single design, delivery, and validation reference for the Antistasi Ultimate FPV integration. It replaces the earlier split between an architectural plan and a separate implementation phases document.

The feature scope is:

- site-driven FPV deployment through Antistasi Extender events;
- soft detection of supported FPV families at runtime;
- server-owned spawning and registry management;
- owner-local autonomous control and detonation;
- radio-link and fiber-visual compatibility tracks;
- multiplayer, JIP, locality, and cleanup validation.

## Executive Summary

The correct architecture is a server-owned, event-driven FPV manager that reacts to Antistasi site lifecycle events and runs exactly one autonomous controller per managed drone on the current locality owner.

Three design conclusions anchor the implementation:

1. ArmaFPV and fpv_ua are radio-link families whose stock control code assumes a human operator, retranslators, jammers, and client UI loops.
2. frtz_fiberoptic_kvn is a fiber-visual family. Its stock fiber system is primarily a rendered cable trail and does not provide a reliable autonomous tether-loss model.
3. None of the supported packs provide a dedicated recon-only airframe, so `RECON` must be treated as doctrine-level use of TI-capable or recon-surrogate strike classes.

The addon therefore owns the compatibility catalog, behavior doctrine, bootstrap normalization, link-state model, and pre-impact detonation path, while reusing only the stable compatibility surfaces from the vendor mods.

## Verified Source Anchors

### Antistasi Ultimate

- `A3A\addons\events\Events.hpp` defines `AIVehInit` and `locationSpawned`.
- `A3A_fnc_AIVEHinit` triggers `AIVehInit` after vehicle initialization.
- `fn_createAIAirplane.sqf` emits `locationSpawned` with `Airport`.
- `fn_createAIOutposts.sqf` emits `locationSpawned` with `Outpost`.
- `fn_createAIResources.sqf` emits `locationSpawned` with `Resource`.
- `fn_createAIMilbase.sqf` emits `locationSpawned` with `Milbase`.
- Antistasi routes factories through the resource creator and seaports through the outpost creator, so raw event payloads still appear as `Resource` or `Outpost` unless the addon normalizes them by marker membership.

### Antistasi Extender

- A3UE listener registration is intended to happen through post-init.
- The event listener pattern matches the existing `A3A_Events_fnc_addEventListener` usage demonstrated in A3UE's example listener.

### External FPV Families

| Family | Patch | Signal model | Core findings |
| --- | --- | --- | --- |
| ArmaFPV | `ArmaFPV_Data` | `RADIO` | Uses retranslators and jammer classes, disables AI in vendor init, detonates through AT or AP munition conversion |
| fpv_ua | `FPV_UA` | `RADIO` | Uses the same retranslator and jammer conventions, disables AI in vendor init, treats payload classes mostly as cosmetic AT or AP variants |
| KVN | `frtz_KVN` | `FIBER_VISUAL` | Disables AI in vendor init, archives dead-fiber paths on detonation, and needs A3UE to write fiber variables for autonomous trail rendering |

Common findings across all supported families:

- vendor `fpv_droneInit` paths disable AI because the stock mods are built around player remote control;
- vendor `hit` handlers remain useful as fallback behavior only;
- autonomous compatibility must be restored by A3UE after spawn and after locality bootstrap.

## Design Rules

- Keep zero hard dependencies on external FPV packs in addon config.
- Discover supported families at runtime through `CfgPatches` and validate UAV classes through `CfgVehicles`.
- Keep public runtime names under `A3UE_fnc_fpv_*` and `A3UE_FPV_*`.
- Treat `locationSpawned` as the primary deployment hook and `AIVehInit` as the locality-safe bootstrap hook.
- Treat KVN as a fiber-visual family, not as a stock autonomous tether-loss family.
- Preserve vendor-compatible warhead mapping and KVN dead-fiber archival while keeping A3UE in control of the actual strike path.

## Hook Model and Site Normalization

`locationSpawned` is the correct deployment hook because it provides the site marker, the raw Antistasi location string, and the spawn or despawn transition after Antistasi has already initialized the site's normal units.

The site model should normalize to these supported site types:

- `Airport`
- `Milbase`
- `Seaport`
- `Outpost`
- `Factory`
- `Resource`

Important cleanup rule:

- `locationSpawned` with `_isSpawning = false` is the authoritative site cleanup signal.
- The FPV registry should deregister immediately on site despawn rather than waiting for delayed vehicle deletion.

Recommended listener registration:

```sqf
if !(isClass (missionConfigFile / "A3A")) exitWith {};

["locationSpawned", "A3UE_FPV_locationSpawned", A3UE_fnc_fpv_onLocationSpawned] call A3A_Events_fnc_addEventListener;
["AIVehInit", "A3UE_FPV_aivehInit", A3UE_fnc_fpv_onAIVehInit] call A3A_Events_fnc_addEventListener;
```

## Compatibility Catalog and Doctrine Baseline

### Runtime catalog contract

The compatibility catalog should publish:

- loaded patch state in `A3UE_FPV_loadedMods`;
- family metadata and class pools in `A3UE_FPV_catalog`;
- site doctrine in `A3UE_FPV_doctrine`.

Each family entry should capture:

- patch name;
- signal model;
- validated class pools by side and payload role;
- whether the family has a native recon airframe;
- retranslator class, if any;
- jammer classes, if any.

### Native role mapping

| Family | AT pool | AP pool | Recon pool |
| --- | --- | --- | --- |
| ArmaFPV | `*_Crocus_AT`, `*_Crocus_AT_TI` | `*_Crocus_AP`, `*_Crocus_AP_TI` | TI variants only |
| fpv_ua | `*_UAFPV_PG7VL_AT` | `*_UAFPV_IED_AP`, `*_UAFPV_RKG_AP`, `*_UAFPV_OG7V_AP` | AP or TI-capable surrogates only |
| KVN | `frtz_*_KVN_AT[_20KM|_25KM]` | `frtz_*_KVN_AP[_20KM|_25KM]` | TI variants only |

Range-tier rule:

- KVN `_25KM` classes should be favored at airports;
- KVN `_20KM` classes should be favored at outposts and seaports;
- base range tiers should be favored at resources and factories.

### Site doctrine baseline

| Site Type | Spawn chance | Stock | Role weights | Family bias |
| --- | ---: | --- | --- | --- |
| `Airport` | `0.60` | `2-4` | `AT 60`, `AP 20`, `RECON 20` | Favor long-endurance KVN, `PG7VL_AT`, and TI-capable AT classes |
| `Milbase` | `0.50` | `2-3` | `AT 45`, `AP 35`, `RECON 20` | Favor stronger AT and endurance than outposts |
| `Seaport` | `0.45` | `1-3` | `AT 25`, `AP 40`, `RECON 35` | Favor mixed AP and recon harassment |
| `Outpost` | `0.35` | `1-2` | `AT 30`, `AP 50`, `RECON 20` | Favor AP-heavy Crocus and fpv_ua with medium KVN support |
| `Factory` | `0.30` | `1-2` | `AT 20`, `AP 40`, `RECON 40` | Favor mixed recon harassment and shorter-range strike assets |
| `Resource` | `0.25` | `1` | `AT 15`, `AP 45`, `RECON 40` | Favor TI-capable AP harassment and short-range KVN base classes |

## Runtime Architecture

### Components

1. `FPV_Manager`
   - server-owned;
   - reacts to `locationSpawned`;
   - selects family, role, and class from doctrine;
   - creates registry entries and manages site cleanup.

2. `FPV_CompatCatalog`
   - built during initialization;
   - stores supported family metadata and validated class pools.

3. `FPV_BootstrapLocal`
   - runs only when the UAV becomes local;
   - restores AI after vendor init;
   - starts fiber compatibility when needed;
   - starts exactly one local controller.

4. `FPV_Controller`
   - runs only on the current owner;
   - evaluates link state, targeting, guidance, and detonation;
   - publishes state for JIP observers.

5. `FPV_Detonation`
   - converts the managed drone to the appropriate warhead before impact;
   - preserves KVN dead-fiber behavior when relevant;
   - keeps kill attribution through shot parents.

### Managed drone metadata

Required replicated state includes at minimum:

- `A3UE_FPV_managed`
- `A3UE_FPV_mode`
- `A3UE_FPV_siteMarker`
- `A3UE_FPV_siteType`
- `A3UE_FPV_profileId`
- `A3UE_FPV_vendorId`
- `A3UE_FPV_payloadRole`
- `A3UE_FPV_linkModel`
- `A3UE_FPV_rangeTier`
- `A3UE_FPV_targetNetId`
- `A3UE_FPV_lastInterceptASL`
- `A3UE_FPV_linkState`
- `A3UE_FPV_spawnTime`

### Runtime modes

Controller modes:

- `IDLE`
- `SEARCHING`
- `TRACKING`
- `TERMINAL_ATTACK`

Link-state modes:

- `OK`
- `DEGRADED`
- `EW_DENIED`

Compatibility rule:

- `EW_DENIED` is meaningful only for `RADIO` families.
- `FIBER_VISUAL` families remain `OK` by default unless A3UE deliberately authors an additional tether-loss mechanic.

## Compatibility Behavior

### Bootstrap normalization

A3UE must re-enable AI after vendor initialization and restore compatibility variables locally. The local bootstrap should:

- install `Local`, `Deleted`, and `MPKilled` handlers;
- apply compatibility normalization when the drone becomes local;
- start KVN fiber trail compatibility when required;
- set controller guard variables such as `A3UE_FPV_controllerRunning` and `A3UE_FPV_localityEH`.

### Radio EW behavior

For radio families:

- use A3UE-owned link evaluation rather than vendor UI control loops;
- optionally honor `FPV_Retranslator`, `Sania`, `Sania_with_tripod`, and `DB_jammer_isActive`;
- return `DEGRADED` or `EW_DENIED` through A3UE logic;
- force hold-pattern and temporary `IDLE` when denied.

### KVN fiber behavior

For KVN:

- treat the vendor fiber system as a visual compatibility track;
- write `kvn_fiber_path`, `kvn_fiber_length`, `kvn_fiber_length_count`, and `kvn_lastSync` from A3UE when autonomous trail rendering is desired;
- archive dead-fiber trails on detonation when `kvn_fiberTTL > 0`.

### Detonation behavior

The integration must not rely on physical collision. The normalized detonation path should:

- choose the proper AT or AP ammo class by payload role;
- preserve KVN dead-fiber archival when a trail exists;
- keep shot-parent attribution;
- delete the UAV only after the warhead delivery path is established.

## Delivery Model and Phases

### Delivery goal

The feature is complete only when all of the following are true:

- the A3UE integration runs end-to-end in Antistasi;
- no hard dependency on ArmaFPV, fpv_ua, or KVN exists;
- only active supported site types deploy managed drones;
- exactly one controller runs per local managed drone;
- pre-impact detonation works reliably;
- radio and fiber compatibility behave correctly;
- JIP, cleanup, and ownership transfer behave correctly.

### Phase summary

| Phase | Title | Depends on | Outcome |
| --- | --- | --- | --- |
| 1 | Foundation and registration baseline | None | FPV scaffolding loads cleanly and registers safely |
| 2 | Compatibility catalog and doctrine layer | 1 | Runtime family catalog and doctrine are available |
| 3 | Site manager and lifecycle registry | 1 | Site events create and clean registry state correctly |
| 4 | Spawn pipeline and compatibility bootstrap | 2, 3 | Managed drones spawn, tag, and normalize correctly |
| 5 | Locality-safe controller skeleton | 4 | Exactly one local controller runs per managed drone |
| 6 | Targeting, guidance, terminal attack, and detonation | 5 | Autonomous strike behavior works end to end |
| 7A | Radio EW compatibility | 5, 6 | Radio families respond to degradation and denial |
| 7B | KVN fiber visual compatibility | 5 | Autonomous KVN drones can render vendor-style trails |
| 8 | Multiplayer hardening and final acceptance | 6, 7A, 7B | Feature is ready for LAN validation and handoff |

### Parallelization rules

- After Phase 1, Phase 2 and Phase 3 may proceed in parallel.
- After Phase 5, Phase 7A and Phase 7B may proceed in parallel.
- Phase 8 is the release gate and should not be skipped.

### Phase standards

Every phase should finish with:

- implemented code or completed documentation for the phase scope;
- a short completion note;
- known remaining limitations;
- a validation record showing the gate passed.

## Final File and Function Targets

### Core registration and data

- `fn_addFPVEventListeners.sqf`
- `fn_fpv_buildCompatCatalog.sqf`
- `fn_fpv_buildDoctrine.sqf`
- `fn_fpv_getProfile.sqf`
- `fn_fpv_profileValue.sqf`

### Manager and lifecycle

- `fn_fpv_onLocationSpawned.sqf`
- `fn_fpv_onAIVehInit.sqf`
- `fn_fpv_managerEvaluateSite.sqf`
- `fn_fpv_managerSpawnDrone.sqf`
- `fn_fpv_cleanupDrone.sqf`

### Bootstrap and controller

- `fn_fpv_applyCompatInit.sqf`
- `fn_fpv_bootstrapLocal.sqf`
- `fn_fpv_runController.sqf`
- `fn_fpv_isExternallyControlled.sqf`
- `fn_fpv_clearTarget.sqf`
- `fn_fpv_holdPattern.sqf`

### Targeting and attack

- `fn_fpv_selectTarget.sqf`
- `fn_fpv_resolveTarget.sqf`
- `fn_fpv_computeIntercept.sqf`
- `fn_fpv_applyGuidance.sqf`
- `fn_fpv_shouldEnterTerminal.sqf`
- `fn_fpv_runTerminal.sqf`
- `fn_fpv_shouldDetonateNow.sqf`
- `fn_fpv_detonateCompat.sqf`

### Compatibility tracks

- `fn_fpv_evaluateLinkState.sqf`
- `fn_fpv_startFiberTrailCompat.sqf`
- `fn_fpv_updateFiberTrailCompat.sqf`

## Local-LAN Validation Runbook

### Recommended setup

Minimum:

- one local dedicated server running Antistasi Ultimate with the extender loaded;
- one LAN client;
- at least one supported FPV family.

Recommended:

- one local dedicated server;
- two LAN clients;
- optional headless client for locality migration tests;
- all three supported FPV families.

### Required mod combinations

1. Antistasi Ultimate + Extender + ArmaFPV
2. Antistasi Ultimate + Extender + fpv_ua
3. Antistasi Ultimate + Extender + frtz_fiberoptic_kvn
4. Antistasi Ultimate + Extender + all three drone families
5. Antistasi Ultimate + Extender only, with no supported FPV family loaded

### Mission preparation

1. Start an Antistasi mission over LAN.
2. Ensure the extender is loaded on server and clients.
3. Activate at least one `Airport`, one `Outpost`, and one `Resource`.
4. Keep debug console access available.

### Core validation snippets

Find all managed drones:

```sqf
allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }
```

Inspect one managed drone:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    typeOf _d,
    _d getVariable ["A3UE_FPV_mode", ""],
    _d getVariable ["A3UE_FPV_linkState", ""],
    _d getVariable ["A3UE_FPV_targetNetId", ""],
    _d getVariable ["A3UE_FPV_siteMarker", ""],
    _d getVariable ["A3UE_FPV_vendorId", ""]
];
```

Inspect the registry:

```sqf
hint str (missionNamespace getVariable ["A3UE_FPV_registry", createHashMap]);
```

Inspect the combined snapshot:

```sqf
hint str (call A3UE_fnc_fpv_debugSnapshot);
```

### Acceptance scenarios

1. Soft-dependency boot safety: no supported family loaded, no script errors, no drone spawns.
2. Site-triggered spawn once per site: registry entry appears once and does not duplicate.
3. Correct family and class resolution: spawned drones come only from loaded families and match doctrine bias.
4. Managed metadata correctness: managed drones expose the expected `A3UE_FPV_*` fields.
5. Single-controller locality: only one machine owns the live controller at a time.
6. Search, track, and terminal attack: mode transitions progress correctly into the strike path.
7. Pre-impact detonation: strikes occur before visible bounce-off and preserve attribution.
8. External control suspension: player or Zeus control forces a safe autonomous stop.
9. Site despawn cleanup: registry entries and managed drones deregister immediately.
10. JIP replication: late joiners see replicated state but do not run guidance.
11. Radio EW behavior: radio drones degrade or deny correctly.
12. KVN fiber visuals: autonomous KVN drones render trails and dead fibers when enabled.
13. Mixed-family runtime safety: loaded families coexist without collisions or registry corruption.

## User Handoff

When this feature is complete, the user should be left with:

- the implemented Antistasi FPV integration in code;
- this document as the single architecture, delivery, and validation reference;
- `call A3UE_fnc_fpv_debugSnapshot` as the primary runtime inspection surface;
- a repeatable local-LAN runbook that covers boot safety, site deployment, ownership, detonation, EW, fiber visuals, and cleanup.