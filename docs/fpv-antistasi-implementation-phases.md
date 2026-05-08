# FPV Antistasi Implementation Phases

Date: 2026-05-07
Primary design reference: `docs/fpv-antistasi-implementation-plan.md`
Purpose: Break the FPV redesign into implementation phases that can be executed sequentially or in parallel, with explicit dependencies, deliverables, validation gates, and a final in-game local-LAN validation runbook.

## 1. Delivery Goal

This phase plan is complete when all of the following are true:

- the Antistasi Extender feature is implemented end-to-end;
- the runtime has zero hard dependency on ArmaFPV, fpv_ua, or frtz_fiberoptic_kvn;
- the manager deploys supported FPV drones only from active `Airport`, `Outpost`, and `Resource` sites;
- exactly one drone controller runs per managed drone on the current locality owner;
- pre-impact detonation works reliably and does not depend on physical collision;
- radio-link families handle degraded or denied link states correctly;
- KVN is supported as a fiber-visual family without pretending the stock mod provides a true autonomous tether-loss model;
- multiplayer and local-LAN validation passes, including JIP and cleanup behavior.

## 2. Recommended Delivery Model

The safest delivery model is a sequential backbone with two controlled parallel branches.

### Sequential backbone

1. Phase 1: Foundation and registration baseline
2. Phase 2: Compatibility catalog and doctrine layer
3. Phase 3: Site manager and lifecycle registry
4. Phase 4: Spawn pipeline and compatibility bootstrap
5. Phase 5: Locality-safe controller skeleton
6. Phase 6: Targeting, guidance, terminal attack, and detonation
7. Phase 8: Multiplayer hardening and final acceptance

### Parallel-capable branches

- After Phase 1, Phase 2 and Phase 3 can proceed in parallel if the team agrees on namespace and function surfaces first.
- After Phase 5, Phase 7A and Phase 7B can proceed in parallel because radio EW and KVN fiber visuals are separate compatibility tracks.

### Final integration order

- Phase 6 must be integrated before final acceptance.
- Both Phase 7 tracks must merge before the feature is considered production-ready.
- Phase 8 is the release gate. Do not treat the feature as complete until Phase 8 passes.

## 3. Dependency Summary

| Phase | Title | Depends On | Can Run In Parallel With | Completion Outcome |
| --- | --- | --- | --- | --- |
| 1 | Foundation and Registration Baseline | None | None | A3UE FPV scaffolding loads cleanly and registers nothing incorrectly |
| 2 | Compatibility Catalog and Doctrine Layer | 1 | 3 | Runtime soft-dependency catalog and doctrine data are available |
| 3 | Site Manager and Lifecycle Registry | 1 | 2 | Site events create and clean registry state correctly |
| 4 | Spawn Pipeline and Compatibility Bootstrap | 2, 3 | None | Managed drones spawn, tag, and initialize correctly |
| 5 | Locality-Safe Controller Skeleton | 4 | None | One controller runs per local drone and handles external control safely |
| 6 | Targeting, Guidance, Terminal Attack, and Detonation | 5 | 7B partially | Autonomous strike behavior works end-to-end |
| 7A | Radio EW Compatibility | 5, 6 | 7B | Radio families respond correctly to link degradation or denial |
| 7B | KVN Fiber Visual Compatibility | 5 | 7A, part of 6 | Autonomous KVN drones optionally render vendor-compatible fiber trails |
| 8 | Multiplayer Hardening and Final Acceptance | 6, 7A, 7B | None | Feature is fully implemented, validated, and ready for local-LAN acceptance |

## 4. Phase Standards

Every phase should end with these artifacts:

- implemented code or documentation for the phase scope;
- a short completion note describing what changed;
- a list of known limitations still expected before later phases;
- a validation record showing the phase gate passed.

Every phase should also respect these engineering rules:

- no hard dependency may be added for any external drone family;
- all runtime names must stay prefixed with `A3UE_FPV_` unless they intentionally mirror vendor variables for compatibility;
- external mod sources remain read-only;
- no phase should silently change the public design contract established in the main redesign plan.

## 5. Phase 1: Foundation and Registration Baseline

### Goal

Create the A3UE FPV feature skeleton so the extension can load cleanly, register future listeners, and expose a consistent namespace and function surface.

### Why this phase exists

All later phases depend on stable registration, naming, and initialization behavior. If this base is inconsistent, parallel work will drift quickly.

### In scope

- post-init entry point for FPV listener registration;
- function declarations and folder structure for planned FPV functions;
- base namespace variables and debug flags;
- no-op behavior when the mission is not Antistasi;
- no-op behavior when none of the supported FPV families are loaded.

### Implementation tasks

1. Add the A3UE FPV function declarations and folder structure.
2. Add a post-init registrar function that exits cleanly when the mission is not Antistasi.
3. Reserve the runtime namespace variables for:
   - `A3UE_FPV_loadedMods`
   - `A3UE_FPV_catalog`
   - `A3UE_FPV_doctrine`
   - `A3UE_FPV_registry`
   - optional debug switch such as `A3UE_FPV_debug`
4. Stub the listener functions:
   - `fn_addFPVEventListeners.sqf`
   - `fn_fpv_onLocationSpawned.sqf`
   - `fn_fpv_onAIVehInit.sqf`
5. Stub the core runtime functions so later phases can work against stable names.

### Expected artifacts

- post-init registration surface
- empty or stubbed FPV function set
- clean addon load with no script errors

### Validation gate

- the addon loads with no script errors;
- Antistasi missions register the FPV listener bootstrap exactly once;
- non-Antistasi missions do nothing and log nothing noisy;
- no drone spawns yet.

### Parallelization note

Phase 2 and Phase 3 may start once this phase locks the function names and namespace conventions.

### Exit criteria

- the FPV feature is visible in code structure;
- no runtime behavior is active yet beyond safe registration;
- all teams agree on the finalized function names and namespace keys.

## 6. Phase 2: Compatibility Catalog and Doctrine Layer

### Goal

Implement the runtime discovery and doctrine data layer that maps loaded mods, sides, roles, and site types into valid drone pools.

### Why this phase exists

The manager cannot spawn safely until it knows exactly which drone families are present and which `CfgVehicles` classes are valid for each side and role.

### In scope

- `CfgPatches` soft-detection;
- class pool construction by side and role;
- doctrine tables for `Airport`, `Outpost`, and `Resource`;
- helper functions for profile lookup and weighted selection;
- validation that only real classes are kept in the catalog.

### Implementation tasks

1. Implement `fn_fpv_buildCompatCatalog.sqf`.
2. Validate each candidate class through `isClass (configFile >> "CfgVehicles" >> _className)` before keeping it.
3. Normalize family metadata:
   - patch name
   - signal model
   - role pools
   - retranslator class
   - jammer classes
4. Implement doctrine selection helpers such as:
   - `fn_fpv_buildDoctrine.sqf`
   - `fn_fpv_selectFamilyForSite.sqf`
   - `fn_fpv_selectClassForRole.sqf`
5. Normalize `RECON` as a doctrine role rather than a native vehicle class category.
6. Encode the KVN range tiers as fuel and endurance bias only, not as separate behavior models.

### Expected artifacts

- populated `A3UE_FPV_loadedMods`
- populated `A3UE_FPV_catalog`
- populated `A3UE_FPV_doctrine`
- helper functions for weighted class selection

### Validation gate

- with each supported mod loaded individually, the catalog reports the correct patch and class pools;
- with multiple supported mods loaded together, the catalog resolves all loaded families without collisions;
- with no supported mod loaded, the catalog stays empty and no runtime errors occur;
- `RECON` pools contain only valid doctrine surrogates.

### Suggested debug-console checks

```sqf
hint str (missionNamespace getVariable ["A3UE_FPV_loadedMods", createHashMap]);
```

```sqf
hint str (missionNamespace getVariable ["A3UE_FPV_catalog", createHashMap]);
```

### Parallelization note

This phase can run in parallel with Phase 3 once the namespace surface from Phase 1 is frozen.

### Exit criteria

- all runtime detection is soft and data-driven;
- all doctrine pools are side-aware and role-aware;
- invalid classes are filtered out before the manager uses them.

## 7. Phase 3: Site Manager and Lifecycle Registry

### Goal

Implement the server-owned manager that reacts to `locationSpawned`, decides whether a site should have FPV coverage, and tracks active site state without spawning drones yet.

### Why this phase exists

The feature must be site-driven, not unit-driven. This phase establishes the authoritative runtime model before drone behavior is introduced.

### In scope

- `locationSpawned` event handling;
- site-type filtering;
- owner-side site registry;
- duplicate-spawn prevention;
- despawn cleanup on `_isSpawning = false`.

### Implementation tasks

1. Implement `fn_fpv_onLocationSpawned.sqf`.
2. Confirm only these site types are handled:
   - `Airport`
   - `Outpost`
   - `Resource`
3. Implement `A3UE_FPV_registry = createHashMap` if it does not exist.
4. Define registry entries with at least:
   - `siteType`
   - `profileId`
   - `drones`
   - `lastRoll`
   - `status`
5. Add duplicate suppression so a spawned site cannot be evaluated twice while already active.
6. Add deregistration logic on `locationSpawned` despawn.
7. Leave the drone list empty or placeholder-only until Phase 4 is integrated.

### Expected artifacts

- working site event handler
- working registry create, update, and delete behavior
- no drone spawns yet

### Validation gate

- approaching an active Antistasi site creates a single registry entry for that marker;
- leaving the area and forcing site despawn removes the registry entry;
- unsupported site types are ignored cleanly;
- no duplicate registry entries are created.

### Suggested debug-console checks

```sqf
hint str (missionNamespace getVariable ["A3UE_FPV_registry", createHashMap]);
```

### Parallelization note

Can run alongside Phase 2. Integration with actual drone spawning should wait until both phases are merged.

### Exit criteria

- the manager has authoritative site state;
- the feature is event-driven and free of polling loops;
- no site can accidentally double-register.

## 8. Phase 4: Spawn Pipeline and Compatibility Bootstrap

### Goal

Turn site registry decisions into real managed FPV drones using Antistasi vehicle initialization, then normalize each spawned drone for autonomous use.

### Why this phase exists

This is the bridge between site doctrine and real world objects. It must stamp the compatibility metadata and undo the vendor assumption that all FPV drones are player-driven AI-disabled UAVs.

### In scope

- drone spawn helper;
- side-aware class resolution;
- Antistasi vehicle crew and init integration;
- managed metadata stamping;
- compatibility bootstrap for ArmaFPV, fpv_ua, and KVN.

### Implementation tasks

1. Implement `fn_fpv_managerSpawnDrone.sqf`.
2. Resolve exact class, role, and family from doctrine.
3. Spawn the UAV through Antistasi-compatible vehicle init flow.
4. Stamp all required replicated variables.
5. Implement `fn_fpv_applyCompatInit.sqf`.
6. Re-enable AI after vendor init disables it.
7. Reset vendor compatibility state as needed:
   - `DB_fpv_isDetonating`
   - `DB_fpv_isUAVsignalLost`
   - `UA_fpv_isUAVsignalLost`
   - KVN fiber path state
8. Register each spawned drone into the manager registry.

### Expected artifacts

- managed drone objects spawn from site decisions
- correct family, role, and side tagging
- vendor AI-disable behavior is normalized for autonomous use

### Validation gate

- drones spawn only from loaded families;
- spawned drones have the expected `A3UE_FPV_*` metadata;
- drones do not remain permanently AI-disabled after spawn;
- the registry contains real drone object references.

### Suggested debug-console checks

```sqf
allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }
```

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    typeOf _d,
    _d getVariable ["A3UE_FPV_vendorId", ""],
    _d getVariable ["A3UE_FPV_payloadRole", ""],
    _d getVariable ["A3UE_FPV_linkModel", ""]
];
```

### Exit criteria

- site evaluation now produces valid managed drones;
- spawned drones are correctly tagged and registry-owned;
- no family-specific init path blocks autonomous use.

## 9. Phase 5: Locality-Safe Controller Skeleton

### Goal

Implement the locality handoff model and the controller skeleton so each drone has exactly one owner-side controller and suspends correctly under player or Zeus control.

### Why this phase exists

Before targeting and terminal attack are added, the runtime must already be safe in multiplayer and headless-client scenarios.

### In scope

- `AIVehInit` listener filtering for managed drones;
- locality event handler;
- controller lock and stop/start semantics;
- hold pattern;
- target clear logic;
- external-control suspend path.

### Implementation tasks

1. Implement `fn_fpv_onAIVehInit.sqf`.
2. Ignore every vehicle that is not tagged `A3UE_FPV_managed`.
3. Implement `fn_fpv_bootstrapLocal.sqf`.
4. Implement `Local` EH handoff behavior.
5. Implement controller-local variables such as:
   - `A3UE_FPV_controllerRunning`
   - `A3UE_FPV_localityEH`
6. Implement skeleton controller loop with:
   - `IDLE`
   - `SEARCHING`
   - `TRACKING`
   - `TERMINAL_ATTACK`
7. Implement `fn_fpv_isExternallyControlled.sqf` and `fn_fpv_clearTarget.sqf`.
8. Keep search and attack logic minimal or stubbed until Phase 6.

### Expected artifacts

- one controller per local drone
- safe restart on locality migration
- safe suspension under direct control

### Validation gate

- only one machine at a time owns the active controller for a drone;
- controller stops when locality leaves the machine;
- controller restarts on the new owner;
- player UAV terminal takeover or Zeus remote control forces mode back to `IDLE`.

### Suggested debug-console checks

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    local _d,
    _d getVariable ["A3UE_FPV_mode", ""],
    _d getVariable ["A3UE_FPV_controllerRunning", false]
];
```

### Exit criteria

- controller ownership is locality-safe;
- the MP duplication problem is solved before any heavy strike logic is added;
- external control cannot fight the autonomous controller.

## 10. Phase 6: Targeting, Guidance, Terminal Attack, and Detonation

### Goal

Implement the real combat behavior: bounded target acquisition, intercept guidance, terminal attack, and pre-impact detonation.

### Why this phase exists

This phase turns the safe runtime skeleton into the actual autonomous FPV threat system.

### In scope

- bounded hostile acquisition
- target resolution
- lead-pursuit intercept
- guidance updates
- terminal attack gating
- pre-impact detonation wrapper

### Implementation tasks

1. Implement `fn_fpv_selectTarget.sqf` with bounded searches only.
2. Use site envelope and doctrine radius instead of whole-world scans.
3. Implement `fn_fpv_resolveTarget.sqf`.
4. Implement `fn_fpv_computeIntercept.sqf` using the approved lead-pursuit solver.
5. Implement `fn_fpv_applyGuidance.sqf`.
6. Implement `fn_fpv_shouldEnterTerminal.sqf` and `fn_fpv_shouldDetonateNow.sqf`.
7. Implement `fn_fpv_runTerminal.sqf`.
8. Implement `fn_fpv_detonateCompat.sqf`.
9. Keep vendor `hit` handlers as fallback only.

### Expected artifacts

- real autonomous search-track-terminal behavior
- correct AT or AP warhead conversion
- clean detonation before bounce-off can occur

### Validation gate

- drones acquire only valid hostile targets;
- guidance converges on moving targets without obvious late-turn circling;
- drones detonate before physical bounce-off;
- shot attribution is preserved on the replacement munition.

### Suggested debug-console checks

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    _d getVariable ["A3UE_FPV_mode", ""],
    _d getVariable ["A3UE_FPV_targetNetId", ""],
    _d getVariable ["A3UE_FPV_lastInterceptASL", []]
];
```

### Exit criteria

- the feature can autonomously kill targets end-to-end;
- the bounce-off problem is solved by design, not by luck;
- targeting and guidance remain bounded and MP-safe.

## 11. Phase 7A: Radio EW Compatibility

### Goal

Complete the radio-link behavior for ArmaFPV and fpv_ua families without inheriting their player-control loops.

### Why this phase exists

The feature must respect the thematic behavior of radio FPV families, but it must do so through A3UE-owned logic that works for AI-controlled drones.

### In scope

- radio link evaluation for `RADIO` families
- optional retranslator support
- optional jammer support
- degraded and denied link states
- controller response to `EW_DENIED`

### Implementation tasks

1. Implement `fn_fpv_evaluateLinkState.sqf` for `RADIO` families.
2. Base the result on A3UE-owned logic, not vendor UI loops.
3. Support these compatibility inputs where present:
   - `FPV_Retranslator`
   - `Sania`
   - `Sania_with_tripod`
   - `DB_jammer_isActive`
4. Define thresholds for:
   - `OK`
   - `DEGRADED`
   - `EW_DENIED`
5. Define controller fallback behavior when denied:
   - hold pattern
   - return to `IDLE`
   - later reacquisition when link recovers

### Expected artifacts

- radio drones have meaningful link-state behavior
- denied-link handling is autonomous and MP-safe

### Validation gate

- radio drones can enter `DEGRADED` or `EW_DENIED`;
- denied drones stop advancing terminal attack and hold or orbit instead;
- recovered drones can resume autonomous behavior.

### Exit criteria

- radio family behavior matches the design intent without copying vendor control loops;
- link denial no longer requires a human operator path.

## 12. Phase 7B: KVN Fiber Visual Compatibility

### Goal

Optionally reproduce KVN-style fiber visuals for autonomous drones by writing the vendor-compatible fiber state that the KVN renderer expects.

### Why this phase exists

KVN support is incomplete if the extension claims fiber compatibility but never produces the visual trail. At the same time, this must remain clearly separated from true guidance or signal-loss logic.

### In scope

- autonomous fiber trail writer
- KVN render-compatible variable updates
- dead-fiber archival on detonation
- optional respect for KVN visual settings

### Implementation tasks

1. Implement `fn_fpv_startFiberTrailCompat.sqf`.
2. Implement owner-side trail updates mirroring:
   - `kvn_fiber_path`
   - `kvn_fiber_length`
   - `kvn_fiber_length_count`
   - `kvn_lastSync`
3. Replicate the path to observers using the same semantics the KVN renderer expects.
4. Reuse the dead-fiber archival logic already designed in `fn_fpv_detonateCompat.sqf`.
5. Treat this as a visual layer only. Do not convert it into a fake signal-loss model unless explicitly approved later.

### Expected artifacts

- autonomous KVN drones can optionally display the vendor-style fiber trail
- detonation leaves a temporary dead-fiber trail when enabled

### Validation gate

- KVN drones show a visible fiber trail while under autonomous control if the feature is enabled;
- observers and JIP clients can see the replicated path;
- the trail archives into dead fiber after detonation when `kvn_fiberTTL > 0`.

### Exit criteria

- KVN compatibility is visually complete;
- the implementation does not misrepresent KVN as a true stock tether-loss system.

## 13. Phase 8: Multiplayer Hardening and Final Acceptance

### Goal

Run the complete MP validation matrix, close the remaining edge cases, and leave the user with a final local-LAN validation runbook.

### Why this phase exists

The feature is not complete until multiplayer safety, cleanup behavior, JIP, and mod-detection edge cases are validated together.

### In scope

- JIP verification
- cleanup and despawn verification
- no-hard-dependency boot verification
- optional HC migration verification
- final acceptance documentation

### Implementation tasks

1. Verify site despawn cleanup removes registry state immediately.
2. Verify moved drones are still deregistered even if Antistasi despawns them asynchronously later.
3. Verify JIP clients see replicated mode, link state, site marker, and target state.
4. Verify mixed mod-load combinations still behave safely.
5. Verify no drone-spawn attempts occur when no supported families are loaded.
6. Add any final debug or admin helpers needed for acceptance testing.
7. Finalize the user validation instructions and expected pass conditions.

### Expected artifacts

- release-ready feature state
- acceptance documentation
- validated local-LAN runbook

### Validation gate

- all scenarios in the local-LAN validation runbook pass;
- no blocking defects remain in controller ownership, site cleanup, or detonation;
- no unsupported mod combination causes runtime failure.

### Exit criteria

- the feature is considered fully implemented and validated;
- the user can reproduce the full acceptance matrix without tribal knowledge.

## 14. Final File and Function Target List

The exact folder layout may vary depending on whether implementation lands in a dedicated A3UE addon or is mirrored inside this repo first. The logical function set should still match the design.

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

## 15. Local-LAN Validation Runbook

This runbook is the final user-facing validation guide. It is written for a developer validating the feature on a local network with debug console access.

### 15.1 Recommended local-LAN setup

Minimum setup:

- one server host running Antistasi Ultimate with the extension loaded;
- one client joining over LAN;
- at least one supported drone family loaded.

Recommended setup:

- one local dedicated server;
- two LAN clients;
- optional headless client for locality migration testing;
- all three supported drone families available for full compatibility coverage.

### 15.2 Required mod combinations

Run these combinations at minimum:

1. Antistasi Ultimate + Extender + ArmaFPV
2. Antistasi Ultimate + Extender + fpv_ua
3. Antistasi Ultimate + Extender + frtz_fiberoptic_kvn
4. Antistasi Ultimate + Extender + all three drone families
5. Antistasi Ultimate + Extender only, with no supported drone mod loaded

### 15.3 Mission preparation

1. Start an Antistasi mission over LAN.
2. Ensure the extension is loaded on server and clients.
3. Use admin controls or normal travel to move close enough to activate spawner coverage for:
   - one `Airport`
   - one `Outpost`
   - one `Resource`
4. Keep debug console access available for validation snippets.

### 15.4 Core validation snippets

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

Inspect site registry:

```sqf
hint str (missionNamespace getVariable ["A3UE_FPV_registry", createHashMap]);
```

### 15.5 Acceptance scenarios

#### Scenario 1: Soft-dependency boot safety

Steps:

1. Launch with Antistasi Ultimate and the extension only.
2. Start the mission and trigger at least one supported site type.

Expected result:

- no script errors occur;
- no FPV drones spawn;
- the manager stays idle because no supported family is loaded.

#### Scenario 2: Site-triggered spawn once per site

Steps:

1. Launch with one supported drone family.
2. Move into spawner range of an `Outpost`.
3. Inspect the registry.
4. Leave and re-enter range without fully despawning the site.

Expected result:

- the site registers exactly once;
- drones are not duplicated for the same active site.

#### Scenario 3: Correct family and class resolution

Steps:

1. Trigger one `Airport`, one `Outpost`, and one `Resource`.
2. Inspect the spawned drone classes.

Expected result:

- spawned classes belong only to loaded families;
- class choice matches the configured doctrine role bias for the site type.

#### Scenario 4: Managed metadata correctness

Steps:

1. Inspect one spawned drone with the debug snippet.

Expected result:

- the drone has valid values for vendor, site marker, mode, and link model;
- the drone is tagged `A3UE_FPV_managed = true`.

#### Scenario 5: Single-controller locality

Steps:

1. Observe the same drone from server and client.
2. If a headless client is available, force locality migration.

Expected result:

- only one owner runs the controller at a time;
- controller state migrates cleanly on locality change;
- no duplicate strike behavior appears.

#### Scenario 6: Search, track, and terminal attack

Steps:

1. Bring hostile player or AI targets into the site envelope.
2. Observe a managed drone from detection through attack.

Expected result:

- mode transitions follow `IDLE -> SEARCHING -> TRACKING -> TERMINAL_ATTACK`;
- the drone acquires a valid target and commits to attack.

#### Scenario 7: Pre-impact detonation

Steps:

1. Observe terminal attack on a vehicle or infantry target.

Expected result:

- the drone detonates before obvious physical bounce-off;
- the replacement munition detonates cleanly;
- strike attribution remains correct.

#### Scenario 8: External control suspension

Steps:

1. Take direct UAV terminal control of a managed drone, if practical.
2. If Zeus is available, test remote control.

Expected result:

- the drone returns to `IDLE`;
- autonomous targeting clears;
- autonomous control resumes only after external control ends.

#### Scenario 9: Site despawn cleanup

Steps:

1. Force a site to despawn by leaving the area or changing spawner state.
2. Inspect the registry immediately.

Expected result:

- the registry entry is removed immediately;
- managed drones are deregistered even if Antistasi cleans some moved vehicles asynchronously later.

#### Scenario 10: JIP replication

Steps:

1. Spawn at least one managed drone and let it enter `TRACKING` or `TERMINAL_ATTACK`.
2. Join a second client after the drone is already active.
3. Inspect the drone state from the joining client.

Expected result:

- the joining client sees replicated mode, site marker, target state, and link state;
- the joining client does not run guidance locally.

#### Scenario 11: Radio EW behavior

Steps:

1. Use ArmaFPV or fpv_ua.
2. If jammer classes are available, place an active jammer inside the drone operating area.
3. If no jammer is available, test with extreme range or obstructed terrain as a degraded-link fallback.

Expected result:

- the drone can enter `DEGRADED` or `EW_DENIED`;
- denied drones hold or abort rather than blindly continue terminal attack;
- recovery returns the drone to normal autonomous behavior.

#### Scenario 12: KVN fiber visual compatibility

Steps:

1. Use frtz_fiberoptic_kvn.
2. Spawn a managed KVN drone and observe it from another client.

Expected result:

- if KVN visual compatibility is enabled, the fiber path renders during autonomous movement;
- after detonation, a dead-fiber trail remains temporarily when `kvn_fiberTTL > 0`.

#### Scenario 13: Mixed-family runtime safety

Steps:

1. Launch with all three drone families loaded.
2. Trigger multiple site types.

Expected result:

- no class-name collisions or registry corruption occur;
- doctrine selection remains stable;
- family-specific behavior stays correct.

### 15.6 Final acceptance rule

The feature is accepted only when:

- all mandatory scenarios pass;
- optional scenarios pass if the corresponding feature was implemented;
- no blocking MP-safe, cleanup, or detonation defects remain.

## 16. User Handoff Summary

When all phases are complete, the user should be left with:

- the implemented extension feature;
- the main redesign plan as the architectural reference;
- this phase document as the execution and validation reference;
- the local-LAN validation runbook above as the final in-game acceptance procedure.

At that point, the feature should be fully implemented and validated rather than merely prototyped.