# FPV Aggression Implementation Phases

Date: 2026-05-08
Primary design reference: `docs/FPV_Aggression_Implementation_Plan.md`
Purpose: Break the FPV aggression redesign into implementation phases that can be executed sequentially or in parallel, with explicit dependencies, deliverables, validation gates, and a final local-LAN in-game validation runbook for the user.

## 1. Delivery Goal

This phase plan is complete only when all of the following are true:

- the behavior doctrine layer is fully authored and no longer relies on chase-helper fallback defaults for core aggression tuning;
- the controller supports the expanded state model, including `LOST_TARGET` and `TERMINAL_VECTOR`;
- family aggression scales correctly across `armafpv`, `kvn`, and `fpv_ua` according to real airframe capability;
- coarse navigation remains locality-safe and AI-compatible;
- the final strike window uses owner-local high-authority steering rather than only broad AI `doMove` behavior;
- target selection includes stickiness and LOS-aware penalties;
- movement guidance is decoupled from lower-rate EW/link-state evaluation;
- multiplayer safety, cleanup behavior, JIP, and locality migration are verified;
- the user is left with a detailed local-LAN validation procedure that can be followed without tribal knowledge.

## 2. Recommended Delivery Model

The safest delivery model is a sequential backbone with one controlled parallel split in the middle.

### Sequential backbone

1. Phase 1: Behavior Doctrine Foundation
2. Phase 2: Controller Timing and State Expansion Backbone
3. Phase 4: High-Authority Terminal Steering and Detonation Integration
4. Phase 5: Multiplayer Hardening, Local-LAN Acceptance, and User Handoff

### Parallel-capable branches

After Phase 2, the work can split into two parallel branches:

- Phase 3A: Predatory Target Memory and Selection
- Phase 3B: Adaptive Intercept and Coarse Guidance Retune

These two branches can run in parallel only if the team freezes the following contracts first:

- the resolved profile keys returned by `fn_fpv_getProfile.sqf`;
- the controller mode names;
- the cache variable names for link-state timing;
- the target-memory variable names written on the UAV.

### Final integration order

- Phase 3A and Phase 3B must both merge before Phase 4 is treated as complete.
- Phase 4 must merge before the full multiplayer and user-validation pass begins.
- Phase 5 is the release gate. Do not treat the feature as complete until Phase 5 passes.

## 3. Dependency Summary

| Phase | Title | Depends On | Can Run In Parallel With | Completion Outcome |
| --- | --- | --- | --- | --- |
| 1 | Behavior Doctrine Foundation | None | None | Authored aggression profiles exist and can be resolved per site, family, and role |
| 2 | Controller Timing and State Expansion Backbone | 1 | None | Controller timing lanes, mode expansion, and link-state caching contract are stable |
| 3A | Predatory Target Memory and Selection | 2 | 3B | `LOST_TARGET`, target memory, stickiness, and LOS-aware selection are implemented |
| 3B | Adaptive Intercept and Coarse Guidance Retune | 2 | 3A | Adaptive lead and doctrine-driven coarse chase tuning are implemented |
| 4 | High-Authority Terminal Steering and Detonation Integration | 3A, 3B | None | Final strike window uses direct owner-local steering and integrates cleanly with lost-target logic |
| 5 | Multiplayer Hardening, Local-LAN Acceptance, and User Handoff | 4 | None | Feature is fully implemented, validated, and documented for local-LAN testing |

## 4. Phase Standards

Every phase should end with these artifacts:

- implemented code or documentation for the phase scope;
- a short completion note describing what changed;
- a list of known limitations still expected before later phases;
- a validation record showing the phase gate passed.

Every phase should also respect these engineering rules:

- no hard dependency may be added for ArmaFPV, fpv_ua, or frtz_fiberoptic_kvn;
- runtime public names must stay under the `A3UE_fnc_fpv_*` and `A3UE_FPV_*` conventions;
- `config.cpp` `CfgFunctions` must stay in sync with new or renamed runtime files;
- external mod sources remain read-only;
- no phase may silently change the controller ownership model;
- parallel branches must not invent incompatible variable names or profile keys.

## 5. Phase 1: Behavior Doctrine Foundation

### Goal

Replace the current spawn-only doctrine with an authored behavior layer that resolves aggression values per site type, family, and role.

### Why this phase exists

The rest of the redesign cannot be tuned or validated correctly while the controller continues to run on fallback defaults. This phase turns the profile abstraction into a real runtime contract.

### In scope

- doctrine restructuring to separate spawn data from behavior data;
- authored behavior tables for `Airport`, `Outpost`, and `Resource`;
- family-aware and role-aware aggression values;
- derived distance rules and search/lost-target tables;
- profile resolution for site type, family, and role;
- airframe capability clamp logic.

### Implementation tasks

1. Expand `fn_fpv_buildDoctrine.sqf` so each site entry carries both spawn and behavior submaps.
2. Author per-site, per-family, per-role values for at least:
   - `trackingSpeed`
   - `terminalSpeed`
   - `terminalGateDistance`
   - `detonationDistance`
3. Add the derived behavior keys documented in the main plan, including:
   - `terminalGateDistance2D`
   - `detonationDistance2D`
   - `dropTargetDistance`
   - `trackBreakDistance`
   - `searchRadius`
   - `localSearchRadius`
   - `lostTargetRadius`
   - `lostTargetTTL`
4. Decide and implement the airframe capability clamp strategy:
   - either resolve representative max speeds from the selected class config at runtime;
   - or store a trusted family capability map and clamp authored values against it.
5. Update `fn_fpv_getProfile.sqf` so it resolves the effective behavior profile for the UAV's `siteType`, `vendorId`, and `payloadRole`.
6. Keep `fn_fpv_profileValue.sqf` stable as the generic lookup helper unless a stronger typed layer becomes necessary.
7. Add a simple debug path so resolved behavior profiles can be inspected in-game.

### Expected artifacts

- doctrine entries that contain authored aggression values;
- resolved behavior profiles for every supported site-family-role combination;
- no core chase parameter depending on fallback defaults during normal supported operation.

### Validation gate

- each supported family returns a non-empty resolved profile when spawned from a supported site;
- `armafpv` resolves materially faster tracking and terminal speeds than `fpv_ua`;
- site-specific search and lost-target envelopes differ across `Airport`, `Outpost`, and `Resource` as designed;
- no script errors occur when a family is absent.

### Suggested debug-console checks

Inspect one managed drone profile:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str ([_d] call A3UE_fnc_fpv_getProfile);
```

Inspect the full doctrine:

```sqf
hint str (missionNamespace getVariable ["A3UE_FPV_doctrine", createHashMap]);
```

### Parallelization note

No parallel work should start before this phase completes. It defines the data contract for all later chase logic.

### Exit criteria

- the behavior profile layer is real and authored;
- family aggression is data-driven;
- later phases can consume resolved profile keys without inventing fallback-only behavior.

## 6. Phase 2: Controller Timing and State Expansion Backbone

### Goal

Refactor the controller so high-rate movement updates, lower-rate target scans, and lower-rate EW/link evaluation operate as separate timing lanes, while expanding the state machine safely for later phases.

### Why this phase exists

Predatory logic and high-authority steering are not safe to add on top of the current monolithic loop. The controller needs stable timing contracts and recognized new states first.

### In scope

- timing-lane refactor inside `fn_fpv_runController.sqf`;
- cached link-state update helper;
- controller recognition of `LOST_TARGET` and `TERMINAL_VECTOR` modes;
- preserved external-control and locality-safe behavior;
- minimal placeholder logic for new states until later phases fill them in.

### Implementation tasks

1. Refactor `fn_fpv_runController.sqf` so it separates:
   - guidance cadence;
   - target-scan cadence;
   - link-evaluation cadence;
   - optional debug cadence.
2. Add `fn_fpv_cacheLinkState.sqf` or equivalent cached-link helper.
3. Add the new cache variables on the UAV, including:
   - `A3UE_FPV_cachedLinkState`
   - `A3UE_FPV_cachedSignalStrength`
   - `A3UE_FPV_nextLinkEvalAt`
   - `A3UE_FPV_lastLinkEvalPosATL`
4. Expand the state machine so the following modes are valid and non-crashing:
   - `IDLE`
   - `SEARCHING`
   - `TRACKING`
   - `LOST_TARGET`
   - `TERMINAL_ATTACK`
   - `TERMINAL_VECTOR`
5. Preserve the existing control rules:
   - only one controller per local UAV;
   - external control forces autonomous suspension;
   - `EW_DENIED` still aborts active pursuit for radio families.
6. Add temporary placeholder behavior for `LOST_TARGET` and `TERMINAL_VECTOR` if their full logic is not yet merged.

### Expected artifacts

- controller loop no longer reevaluates link state on every hot movement tick;
- recognized expanded mode set;
- stable backbone for parallel implementation of pursuit intelligence and guidance retuning.

### Validation gate

- one controller still runs per local UAV only;
- link-state evaluation occurs on cache cadence rather than every guidance tick;
- new mode values do not break controller execution or replication;
- external control still forces clean suspension across all active modes.

### Suggested debug-console checks

Inspect controller cadence-related state:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    _d getVariable ["A3UE_FPV_mode", ""],
    _d getVariable ["A3UE_FPV_cachedLinkState", ""],
    _d getVariable ["A3UE_FPV_nextLinkEvalAt", -1],
    _d getVariable ["A3UE_FPV_controllerRunning", false]
];
```

### Parallelization note

Once this phase is complete and the mode names plus cache contract are frozen, Phase 3A and Phase 3B can proceed in parallel.

### Exit criteria

- the controller is no longer monolithic;
- later pursuit logic can plug into stable state and timing lanes;
- movement aggression can be increased without paying full EW cost on every tick.

## 7. Phase 3A: Predatory Target Memory and Selection

### Goal

Implement target memory, `LOST_TARGET`, target stickiness, and LOS-aware target scoring so drones hunt persistently instead of dropping immediately back to generic search.

### Why this phase exists

The current system is too binary. Once the target breaks contact, the drone forgets too much and becomes easy to evade.

### In scope

- `LOST_TARGET` runtime behavior;
- target memory persistence on track break;
- cone-based reacquisition behavior;
- target stickiness and switch margin;
- LOS and obstruction penalties;
- target-score debug instrumentation.

### Implementation tasks

1. Add `functions/fpv/fn_fpv_runLostTarget.sqf`.
2. Update `fn_fpv_runController.sqf` to enter `LOST_TARGET` instead of dropping directly to `SEARCHING` on:
   - temporary target nulls;
   - range breaks;
   - LOS breaks beyond grace period;
   - terminal overshoot without detonation.
3. Persist target memory on the UAV:
   - `A3UE_FPV_lastKnownTargetNetId`
   - `A3UE_FPV_lastKnownTargetPosASL`
   - `A3UE_FPV_lastKnownTargetVel`
   - `A3UE_FPV_lastKnownTargetTime`
   - `A3UE_FPV_lostTargetExpireAt`
4. Add `functions/fpv/fn_fpv_isTargetObstructed.sqf`.
5. Update `fn_fpv_selectTarget.sqf` to support:
   - sticky bonus for the current target;
   - partial sticky bonus for the last lost target;
   - switch margin before replacing an existing target;
   - LOS or obstruction penalties.
6. Add optional target-score breakdown instrumentation for debug snapshot output.

### Expected artifacts

- drones attempt short-duration reacquisition instead of instantly forgetting the target;
- target churn is reduced in crowded scenes;
- blocked targets are penalized instead of selected blindly.

### Validation gate

- a target that briefly moves behind cover causes `TRACKING -> LOST_TARGET -> TRACKING` rather than immediate `SEARCHING`;
- two near-equal candidates no longer cause rapid target swapping;
- LOS penalties suppress obviously bad picks without breaking reacquisition of the sticky target;
- `LOST_TARGET` returns to `SEARCHING` cleanly after TTL expiry.

### Suggested debug-console checks

Inspect target memory state:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    _d getVariable ["A3UE_FPV_mode", ""],
    _d getVariable ["A3UE_FPV_lastKnownTargetNetId", ""],
    _d getVariable ["A3UE_FPV_lastKnownTargetPosASL", []],
    _d getVariable ["A3UE_FPV_lostTargetExpireAt", -1]
];
```

### Parallelization note

This phase can run in parallel with Phase 3B if it does not rename or reinterpret the profile keys and state names frozen by Phase 2.

### Exit criteria

- target reacquisition is predatory instead of binary;
- target-selection quality is tactically better than the current proximity-only model;
- the controller can preserve pressure through short target breaks.

## 8. Phase 3B: Adaptive Intercept and Coarse Guidance Retune

### Goal

Replace the fixed lead clamp with adaptive lead and retune the coarse chase layer to use doctrine-authored aggression values consistently.

### Why this phase exists

Even with better target memory, the drones will still feel soft if long-range interception and coarse pursuit stay conservative.

### In scope

- adaptive lead in `fn_fpv_computeIntercept.sqf`;
- doctrine-driven chase speed use in tracking and terminal closure;
- move-delta retuning for more responsive AI guidance;
- profile-driven terminal and detonation gates;
- lead-time debug instrumentation.

### Implementation tasks

1. Update `fn_fpv_computeIntercept.sqf` to use:
   - `maxLeadTimeNear`
   - `maxLeadTimeFar`
   - `nearLeadDistance`
   - `maxLeadDistance`
2. Preserve the quadratic intercept solver, but clamp lead time adaptively by distance.
3. Update `fn_fpv_applyGuidance.sqf` to consume doctrine-authored:
   - `trackingSpeed`
   - `trackingMoveDelta`
   - `trackingHeightASL` or equivalent height logic
4. Update `fn_fpv_runTerminal.sqf` so it becomes coarse terminal closure only, not the final steering solution.
5. Update `fn_fpv_shouldEnterTerminal.sqf` and `fn_fpv_shouldDetonateNow.sqf` so they read doctrine-authored gate and detonation distances consistently.
6. Add `A3UE_FPV_lastLeadTime` debug state on the UAV.

### Expected artifacts

- long-range chase behavior uses adaptive lead instead of one fixed cap;
- family aggression becomes visibly different in tracking and closure behavior;
- coarse guidance becomes more responsive before terminal vector handoff exists.

### Validation gate

- `armafpv` closes faster and more aggressively than `fpv_ua` in open-ground pursuit;
- adaptive lead decreases as distance closes;
- guidance turns are materially less late than the current fallback controller;
- terminal and detonation gates match authored doctrine values.

### Suggested debug-console checks

Inspect intercept tuning state:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    _d getVariable ["A3UE_FPV_mode", ""],
    _d getVariable ["A3UE_FPV_lastLeadTime", -1],
    _d getVariable ["A3UE_FPV_lastInterceptASL", []]
];
```

### Parallelization note

This phase can run in parallel with Phase 3A if `fn_fpv_runController.sqf` merge boundaries are agreed in advance.

### Exit criteria

- coarse chase behavior is profile-driven and materially more aggressive;
- adaptive lead is live and inspectable;
- later terminal vector work can build on a stronger approach path.

## 9. Phase 4: High-Authority Terminal Steering and Detonation Integration

### Goal

Implement the owner-local terminal steering mode that replaces broad final-turn AI behavior with direct vector and velocity shaping in the last strike window.

### Why this phase exists

This is the phase that actually removes the "broad arcing turns" problem. Everything before it improves pursuit pressure, but this phase changes the character of the final attack.

### In scope

- `TERMINAL_VECTOR` behavior;
- owner-local direct steering helper;
- handoff from coarse terminal closure into vector steering;
- AI suppression and restoration on the crew;
- missed-pass recovery back into `LOST_TARGET`;
- detonation integration with the existing compatibility path.

### Implementation tasks

1. Add `functions/fpv/fn_fpv_runTerminalVector.sqf`.
2. Update `fn_fpv_runController.sqf` so it transitions:
   - `TRACKING -> TERMINAL_ATTACK`
   - `TERMINAL_ATTACK -> TERMINAL_VECTOR`
   - `TERMINAL_VECTOR -> DETONATE` or `LOST_TARGET`
3. Enter vector steering only when:
   - the UAV is local;
   - the target is still valid;
   - external control is not active;
   - radio families are not `EW_DENIED`.
4. Suppress crew AI path behavior during the steering window and restore it if the drone exits vector control alive.
5. Use direct `setVectorDirAndUp` and `setVelocity` shaping as described in the main plan.
6. Preserve `fn_fpv_detonateCompat.sqf` as the strike finalizer so warhead compatibility and attribution stay normalized.
7. Expose `A3UE_FPV_terminalSteeringActive` for debug and acceptance testing.

### Expected artifacts

- final strike path is driven by direct terminal steering rather than only AI pathing;
- late-stage jinks are materially harder to evade;
- missed passes recover into `LOST_TARGET` rather than collapsing into generic search.

### Validation gate

- drones enter `TERMINAL_VECTOR` only inside the authored `terminalSteeringDistance` window;
- final attack paths are visibly more direct than the current AI-only closure;
- crew AI suppression does not strand the UAV in a broken state if detonation does not occur;
- detonation still happens through the compatibility wrapper and not through collision luck.

### Suggested debug-console checks

Inspect terminal steering state:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    _d getVariable ["A3UE_FPV_mode", ""],
    _d getVariable ["A3UE_FPV_terminalSteeringActive", false],
    _d getVariable ["A3UE_FPV_targetNetId", ""]
];
```

### Exit criteria

- the final strike window is no longer dependent on broad AI turns alone;
- missed passes recover sensibly;
- the core aggressive behavior is functionally complete.

## 10. Phase 5: Multiplayer Hardening, Local-LAN Acceptance, and User Handoff

### Goal

Run the full validation matrix, harden remaining multiplayer edge cases, and leave the user with a detailed local-LAN runbook that verifies the redesigned behavior in game.

### Why this phase exists

The feature is not complete until locality, JIP, cleanup, mixed-family behavior, and real in-game validation pass together.

### In scope

- JIP verification;
- locality and optional HC migration verification;
- site cleanup verification;
- mixed-family and no-supported-family boot safety;
- debug snapshot extension;
- final user-facing validation instructions.

### Implementation tasks

1. Extend `fn_fpv_debugSnapshot.sqf` to include the new aggression and target-memory variables.
2. Verify that late-joining clients see replicated state but do not run guidance locally.
3. Verify locality migration across server, LAN client, and optional headless client.
4. Verify site cleanup and drone deregistration on despawn.
5. Verify the no-supported-family boot path remains safe.
6. Verify mixed-family selection and behavior with all supported packs loaded together.
7. Finalize the local-LAN validation runbook and user handoff notes.

### Expected artifacts

- release-ready runtime behavior;
- updated debug snapshot output for tuning and support;
- final user validation guide that exercises all redesigned behaviors.

### Validation gate

- all scenarios in the local-LAN runbook pass;
- no blocking issues remain in controller ownership, target reacquisition, terminal steering, or cleanup;
- feature state is reproducible by the user without custom developer knowledge.

### Exit criteria

- the redesign is fully implemented and validated;
- the user can verify the feature end-to-end on a local LAN by following the runbook in this document.

## 11. Final File and Function Target List

### Existing files expected to change

- `functions/fpv/fn_fpv_buildDoctrine.sqf`
- `functions/fpv/fn_fpv_getProfile.sqf`
- `functions/fpv/fn_fpv_profileValue.sqf`
- `functions/fpv/fn_fpv_runController.sqf`
- `functions/fpv/fn_fpv_selectTarget.sqf`
- `functions/fpv/fn_fpv_computeIntercept.sqf`
- `functions/fpv/fn_fpv_applyGuidance.sqf`
- `functions/fpv/fn_fpv_runTerminal.sqf`
- `functions/fpv/fn_fpv_shouldEnterTerminal.sqf`
- `functions/fpv/fn_fpv_shouldDetonateNow.sqf`
- `functions/fpv/fn_fpv_debugSnapshot.sqf`
- `config.cpp`

### New files expected to be added

- `functions/fpv/fn_fpv_runLostTarget.sqf`
- `functions/fpv/fn_fpv_runTerminalVector.sqf`
- `functions/fpv/fn_fpv_cacheLinkState.sqf`
- `functions/fpv/fn_fpv_isTargetObstructed.sqf`

## 12. Local-LAN Validation Runbook

This is the final user-facing validation guide. When all phases are complete, the user should be able to follow this section directly and determine whether the redesigned feature passes.

### 12.1 Recommended local-LAN setup

Minimum setup:

- one local dedicated server running Antistasi Ultimate with the extender loaded;
- one LAN client joining the server;
- at least one supported FPV family loaded.

Recommended setup:

- one local dedicated server;
- two LAN clients;
- optional headless client for locality migration testing;
- all three supported drone families available for full compatibility coverage.

### 12.2 Required mod combinations

Run these combinations at minimum:

1. Antistasi Ultimate + Extender + ArmaFPV
2. Antistasi Ultimate + Extender + fpv_ua
3. Antistasi Ultimate + Extender + frtz_fiberoptic_kvn
4. Antistasi Ultimate + Extender + all three drone families
5. Antistasi Ultimate + Extender only, with no supported FPV family loaded

### 12.3 Mission preparation

1. Start an Antistasi mission over LAN.
2. Ensure the extender is loaded on server and all clients.
3. Move close enough to activate spawner coverage for:
   - one `Airport`
   - one `Outpost`
   - one `Resource`
4. Keep debug console access available on the host for state inspection.
5. Prepare at least one player-controlled test subject and, if possible, one scripted or AI-driven moving vehicle for crossing tests.

### 12.4 Core validation snippets

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
    _d getVariable ["A3UE_FPV_vendorId", ""],
    _d getVariable ["A3UE_FPV_payloadRole", ""],
    _d getVariable ["A3UE_FPV_targetNetId", ""],
    _d getVariable ["A3UE_FPV_lastLeadTime", -1],
    _d getVariable ["A3UE_FPV_terminalSteeringActive", false],
    _d getVariable ["A3UE_FPV_cachedLinkState", ""]
];
```

Inspect the site registry:

```sqf
hint str (missionNamespace getVariable ["A3UE_FPV_registry", createHashMap]);
```

Inspect the combined debug snapshot:

```sqf
hint str (call A3UE_fnc_fpv_debugSnapshot);
```

Inspect the environment and validation blocks directly:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
hint str [
   _snapshot get "environment",
   _snapshot get "validation"
];
```

### 12.4.1 Validation block interpretation

The `validation` block in `A3UE_fnc_fpv_debugSnapshot` is the fast acceptance summary for multiplayer hardening.

- `warnings` should normally be empty during a healthy test run.
- `duplicateManagedNetIds` should stay empty.
- `orphanManagedDroneNetIds` should stay empty.
- `missingManagedDroneNetIds` should stay empty.
- `nonLocalControllers` should stay empty.
- `controllerOwnerMismatches` should stay empty.
- `activeEmptySites` should stay empty unless the site is in the middle of cleanup.
- `bootSafetyViolation` must remain `false` in the no-supported-family scenario.

The `environment` block is the fast acceptance summary for boot and catalog state.

- `registrationComplete` should be `true` after initialization settles.
- `loadedFamilies` should match the currently loaded FPV family mods.
- `catalogFamilies` should match the families actually discovered and cataloged.
- `registryEntryCount` and `managedDroneCount` should track the live mission state.

### 12.5 Acceptance scenarios

#### Scenario 1: Soft-dependency boot safety

Steps:

1. Launch with Antistasi Ultimate and the extender only.
2. Start the mission and trigger at least one supported site type.

Expected result:

- no script errors occur;
- no FPV drones spawn;
- the manager remains safe and idle because no supported family is loaded;
- `environment.loadedFamilies` is empty and `validation.bootSafetyViolation` remains `false`.

#### Scenario 2: Behavior profile resolution

Steps:

1. Launch with one supported family loaded.
2. Trigger one `Airport`, one `Outpost`, and one `Resource`.
3. Inspect one managed drone profile from each site type.

Expected result:

- each drone resolves a non-empty behavior profile;
- site-specific search and lost-target envelopes differ as authored;
- terminal and detonation distances match the phase plan data.

#### Scenario 3: Family aggression differentiation

Steps:

1. Launch with all three supported families.
2. Trigger similar sites until at least one drone from each family is active.
3. Compare pursuit speed and terminal closure behavior in open ground.

Expected result:

- `armafpv` behaves as the fastest and most punishing family;
- `kvn` is aggressive but slightly less knife-edge than `armafpv`;
- `fpv_ua` remains slower but is still materially more aggressive than the old fallback controller.

#### Scenario 4: Tracking responsiveness against open-ground infantry

Steps:

1. Use a player or AI target running laterally across open terrain.
2. Allow a managed drone to acquire and chase from medium range.

Expected result:

- the drone uses adaptive lead rather than obviously chasing only the current position;
- turns are less delayed than the old controller;
- the target has a noticeably harder time escaping by simple sidestep movement.

#### Scenario 5: LOST_TARGET reacquisition behind cover

Steps:

1. Let a player or AI target break line of sight behind a building or terrain fold for `2s` to `3s`.
2. Observe the same drone through the break and reacquisition window.

Expected result:

- the drone enters `LOST_TARGET` instead of falling directly to `SEARCHING`;
- the drone searches near the predicted last-known path;
- the original target is reacquired if it reappears inside TTL.

#### Scenario 6: Sticky target and LOS penalty validation

Steps:

1. Place two valid hostile targets near each other.
2. Let the current target briefly move behind cover while the second remains visible.

Expected result:

- the drone does not churn instantly to the second target;
- the sticky target remains favored during the sticky window unless the challenger clearly exceeds the switch margin;
- obviously blocked low-quality picks are penalized.

#### Scenario 7: Adaptive lead against crossing vehicle

Steps:

1. Use a vehicle moving across the drone's approach path at moderate speed.
2. Observe the drone's intercept path and lead-time state.

Expected result:

- `A3UE_FPV_lastLeadTime` is higher at range and decreases as distance closes;
- the coarse chase path cuts ahead of the vehicle more effectively than before;
- detonation happens in a believable proximity window.

#### Scenario 8: High-authority terminal steering jink resistance

Steps:

1. Let a drone close to the final `60m` to `100m` strike window.
2. Perform a late hard sidestep or turn with the target.

Expected result:

- the drone enters `TERMINAL_VECTOR`;
- the final path is visibly more direct than the old broad AI arc;
- late-stage evasion is materially harder than before.

#### Scenario 9: Missed-pass recovery

Steps:

1. Force a terminal miss if practical by making a sharp final movement or by temporarily denying the drone an approach line.
2. Observe the behavior after the miss.

Expected result:

- the drone does not collapse straight to generic site orbit;
- it transitions into `LOST_TARGET` and attempts one meaningful reacquisition pass before giving up.

#### Scenario 10: External control suspension

Steps:

1. Take UAV terminal control of a managed drone, if practical.
2. If Zeus is available, test remote control as well.

Expected result:

- the drone returns to `IDLE`;
- autonomous target state clears;
- autonomous behavior resumes only after external control ends.

#### Scenario 11: Link-state cache and performance behavior

Steps:

1. Run several active drones simultaneously.
2. Observe cached link-state variables and server responsiveness.
3. If jammers or retranslators are available, test with them present.

Expected result:

- link-state values update on TTL cadence rather than every terminal movement tick;
- movement responsiveness remains high during terminal closure;
- radio families still respond to degradation or denial correctly.

#### Scenario 12: Single-controller locality and JIP

Steps:

1. Observe one managed drone from server and LAN client.
2. Join a second client after the drone is already active.
3. If available, force locality migration to a headless client.

Expected result:

- only one machine owns the active controller at a time;
- joining clients see replicated state but do not run guidance locally;
- locality migration does not produce duplicate terminal behavior;
- `validation.nonLocalControllers` and `validation.controllerOwnerMismatches` remain empty.

#### Scenario 13: Site despawn cleanup and registry hygiene

Steps:

1. Force a site to despawn by leaving the area or altering spawner state.
2. Inspect the registry immediately and again after any delayed mission cleanup.

Expected result:

- the registry entry is removed immediately;
- managed drones are deregistered cleanly;
- no stale aggression-state variables remain attached to deleted drones;
- `validation.activeEmptySites`, `validation.orphanManagedDroneNetIds`, and `validation.missingManagedDroneNetIds` settle back to empty after cleanup completes.

#### Scenario 14: Mixed-family runtime safety

Steps:

1. Launch with all supported families loaded.
2. Trigger multiple supported site types and observe several drones concurrently.

Expected result:

- no class-pool collisions or registry corruption occur;
- family-specific aggression remains distinct;
- the runtime stays stable under mixed-family operation.

### 12.6 Final acceptance rule

The redesign is accepted only when:

- all mandatory scenarios above pass;
- optional locality-migration scenarios pass if a headless client is used;
- no blocking defects remain in controller ownership, target reacquisition, terminal steering, or cleanup;
- the user can repeat the runbook without developer-only intervention.

## 13. User Handoff Summary

When all phases are complete, the user should be left with:

- the implemented FPV aggression redesign in code;
- `docs/FPV_Aggression_Implementation_Plan.md` as the architectural reference;
- this phase document as the execution and validation reference;
- a local-LAN runbook that verifies the redesigned behaviors in game;
- `call A3UE_fnc_fpv_debugSnapshot` as the primary runtime inspection and validation surface for boot state, ownership, cleanup, and live drone behavior.

At that point, the feature should be fully implemented and validated rather than partially tuned or prototype-only.