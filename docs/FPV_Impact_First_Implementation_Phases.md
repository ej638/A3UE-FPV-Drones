# FPV Impact-First Strike Implementation Phases

Date: 2026-05-08
Primary design references: `docs/fpv-targeting-chase-pathing-analysis.md`, `docs/FPV_Aggression_Implementation_Phases.md`, `docs/FPV_Terminal_Vector_Smoothing_Implementation_Phases.md`
Purpose: Break the impact-first FPV strike redesign into implementation phases that can be executed sequentially or in parallel, with explicit dependencies, deliverables, validation gates, and a final local-LAN in-game validation runbook for the user.

## 1. Delivery Goal

This phase plan is complete only when all of the following are true:

- the final strike path resolves an explicit impact solution rather than defaulting to an elevated target-center overflight;
- infantry, vehicles, statics, and cover-adjacent targets can all be attacked using a believable impact policy;
- `TERMINAL_ATTACK` and `TERMINAL_VECTOR` no longer treat positive altitude above the target as the default final approach geometry;
- primary fuse approval requires direct contact or short-horizon impact logic rather than raw proximity alone;
- self-detonation remains available as a fallback, but only as a reasoned secondary path with recorded detonation reason;
- obstruction-aware fallback surfaces are available for wall, ground, or nearby-object strikes when direct body or hull impact is not the best solution;
- doctrine authors the impact behavior contract per site type, family, and payload role;
- debug snapshot and runtime telemetry expose impact point, impact mode, closure quality, time-to-contact, and detonation reason;
- performance remains locality-safe by limiting expensive impact-surface work to terminal phases and cached refresh windows;
- multiplayer safety, cleanup behavior, JIP, ownership migration, and external-control suspension remain intact;
- the user is left with a detailed local-LAN validation procedure that can confirm the feature in game without tribal knowledge.

## 2. Current-State Diagnosis

The current runtime already has the right broad control architecture, but it still solves the kill problem as a proximity burst instead of a physical strike problem.

### What the current code is doing

- `fn_fpv_computeIntercept.sqf` computes lead pursuit and then clamps the intercept height above the target using `attackHeightASL`.
- `fn_fpv_runTerminal.sqf` keeps a smaller but still positive final height offset above the target.
- `fn_fpv_runTerminalVector.sqf` improves steering authority, but it still chases a lead point that remains above the target.
- `fn_fpv_shouldDetonateNow.sqf` decides entirely by distance and height window, not by confirmed contact, closure quality, or impact prediction.
- `fn_fpv_detonateCompat.sqf` deletes the UAV and spawns the warhead at UAV position, which means the explosion occurs where the drone self-detonates rather than where it physically impacts.

### Why the current behavior feels like an airburst

The current result comes from four design choices reinforcing one another:

1. the target solution is elevated above the target;
2. the final approach remains elevated rather than descending all the way into a surface or body;
3. the fuse is proximity-only;
4. the warhead is delivered at current UAV position.

### Why this needs phased delivery

This is not one code change. The redesign spans:

- doctrine contract
- terminal impact geometry
- impact-point resolution
- fuse semantics
- fallback delivery semantics
- telemetry and validation

Those changes can be parallelized safely, but only after the team freezes the impact contract and the impact telemetry contract.

## 3. Solution Summary

The intended redesign is:

- keep the current spawn, registry, and owner-local controller model intact;
- add an explicit impact-solution layer that resolves a strike point and strike mode;
- reshape terminal guidance so the final armed window tries to hit that impact solution instead of hovering above it;
- make the primary fuse impact-aware by using contact, closure, and short-horizon impact prediction;
- keep `fn_fpv_detonateCompat.sqf` as the fallback delivery mechanism when direct physical impact cannot be trusted or is no longer realistic;
- expose enough telemetry that the user can validate the behavior in a local LAN session.

## 4. Recommended Delivery Model

The safest delivery model is a sequential backbone with one controlled parallel split.

### Sequential backbone

1. Phase 1: Impact Contract, Doctrine, and Telemetry Foundation
2. Phase 2: Impact-Point Resolution Backbone
3. Phase 4: Surface-Aware Integration, Delivery Semantics, and Multiplayer Hardening
4. Phase 5: Local-LAN Acceptance and User Handoff

### Parallel-capable branches

After Phase 2, the work can split into two parallel branches:

- Phase 3A: Impact-First Guidance and Descent Conversion
- Phase 3B: Closure-Gated Fuse and Reasoned Fallbacks

These branches can proceed in parallel only if the team freezes the following contracts first:

- the resolved doctrine keys returned by `fn_fpv_getProfile.sqf` for impact behavior;
- the structure of the impact-solution result returned by the new resolver helper;
- the runtime variable names written on the UAV for impact telemetry;
- the detonation-reason names and fallback-reason names;
- the rule that expensive impact resolution stays owner-local and terminal-phase-only.

### Final integration order

- Phase 3A and Phase 3B must both merge before Phase 4 is treated as complete.
- Phase 4 must merge before final LAN acceptance begins.
- Phase 5 is the release gate. Do not treat the feature as complete until Phase 5 passes.

## 5. Dependency Summary

| Phase | Title | Depends On | Can Run In Parallel With | Completion Outcome |
| --- | --- | --- | --- | --- |
| 1 | Impact Contract, Doctrine, and Telemetry Foundation | None | None | A stable impact-behavior and telemetry contract exists for all later phases |
| 2 | Impact-Point Resolution Backbone | 1 | None | Terminal phases can resolve and cache a concrete impact solution instead of only a target object |
| 3A | Impact-First Guidance and Descent Conversion | 2 | 3B | Terminal guidance chases resolved impact points and enforces a believable descent profile |
| 3B | Closure-Gated Fuse and Reasoned Fallbacks | 2 | 3A | Fuse logic prefers contact and impact prediction, while recording fallback reasons |
| 4 | Surface-Aware Integration, Delivery Semantics, and Multiplayer Hardening | 3A, 3B | None | Target-class impact policies, fallback delivery, performance guardrails, and MP safety are integrated |
| 5 | Local-LAN Acceptance and User Handoff | 4 | None | Feature is fully implemented, validated, and documented for local-LAN acceptance |

## 6. Phase Standards

Every phase should end with these artifacts:

- implemented code or documentation for the phase scope;
- a short completion note describing what changed;
- a list of known limitations still expected before later phases;
- a validation record showing the phase gate passed.

Every phase should also respect these engineering rules:

- no hard dependency may be added for ArmaFPV, fpv_ua, or frtz_fiberoptic_kvn;
- runtime public names must remain under the `A3UE_fnc_fpv_*` and `A3UE_FPV_*` conventions;
- `config.cpp` `CfgFunctions` must stay in sync with any new helper files;
- external mod sources remain read-only;
- no phase may silently change the one-controller-per-local-owner rule;
- no phase may move expensive surface or geometry resolution into `SEARCHING` or long-range `TRACKING` hot paths;
- no phase should remove self-detonation fallback before impact-first behavior is proven to work reliably;
- parallel branches must not invent incompatible impact-mode names, telemetry names, or doctrine keys.

## 7. Phase 1: Impact Contract, Doctrine, and Telemetry Foundation

### Goal

Create the stable runtime contract for impact-first behavior before any terminal guidance or fuse logic is rewritten.

### Why this phase exists

The guidance branch and fuse branch cannot run safely in parallel unless they both consume the same impact-solution schema, the same doctrine keys, and the same telemetry names.

### In scope

- doctrine keys for impact-first behavior;
- backward-compatible fallback rules for old profiles;
- impact-solution schema definition;
- impact telemetry variable names on the UAV;
- debug snapshot exposure for the new contract;
- bootstrap seeding for any new impact-state variables.

### Recommended doctrine keys

At minimum, add support for these keys:

- `terminalImpactMode`
- `terminalImpactOffsetFar`
- `terminalImpactOffsetNear`
- `terminalDescentMinRate`
- `terminalDescentEnforceDistance`
- `detonationMaxTimeToContact`
- `detonationMinClosingDot`
- `detonationMaxAltitudeAGL`
- `impactFallbackRadius`
- `impactFallbackGroundOffset`
- `impactProbeDistance`
- `impactAbortTimeout`

Optional but useful keys:

- `terminalImpactHoldoffDistance`
- `impactSurfaceRefreshDistance`
- `impactSurfaceRefreshTTL`
- `detonationVehicleHullBias`
- `detonationInfantryGroundLead`
- `impactFallbackAllowObstructionSurface`

### Recommended impact-solution contract

Freeze one stable result shape for the terminal impact resolver. Recommended contract:

```sqf
createHashMapFromArray [
    ["valid", false],
    ["impactMode", "NONE"],
    ["impactPointASL", []],
    ["surfaceType", "none"],
    ["surfaceObject", objNull],
    ["targetNetId", ""],
    ["reason", "NONE"],
    ["fallbackAllowed", true],
    ["fallbackRadius", 0],
    ["updatedAt", time]
]
```

Recommended `impactMode` values:

- `DIRECT_BODY`
- `DIRECT_HULL`
- `DIRECT_STATIC`
- `GROUND_NEAR_TARGET`
- `OBSTRUCTION_SURFACE`
- `AIR_PROXIMITY`
- `NONE`

### Recommended telemetry variables

At minimum, reserve these on the UAV:

- `A3UE_FPV_terminalImpactMode`
- `A3UE_FPV_lastImpactPointASL`
- `A3UE_FPV_lastImpactSurfaceType`
- `A3UE_FPV_lastImpactSurfaceObjectNetId`
- `A3UE_FPV_lastImpactReason`
- `A3UE_FPV_lastClosingDot`
- `A3UE_FPV_lastTimeToContact`
- `A3UE_FPV_lastDetonationReason`
- `A3UE_FPV_lastFallbackReason`
- `A3UE_FPV_lastImpactTelemetryAt`

### Recommended starting baselines

These are starting points, not final tuned values.

| Family | terminalImpactOffsetFar | terminalImpactOffsetNear | terminalDescentMinRate | detonationMaxTimeToContact | detonationMinClosingDot |
| --- | ---: | ---: | ---: | ---: | ---: |
| `armafpv` | `10 - 12` | `0 - 1.5` | `6 - 10` | `0.15 - 0.30` | `0.78 - 0.90` |
| `kvn` | `8 - 10` | `0 - 1.5` | `5 - 8` | `0.18 - 0.35` | `0.72 - 0.86` |
| `fpv_ua` | `6 - 8` | `0 - 2.0` | `4 - 7` | `0.20 - 0.40` | `0.68 - 0.82` |

The main point is not the exact numbers. The main point is that the final armed window is no longer authored as "stay above target and burst by distance".

### Implementation tasks

1. Extend `fn_fpv_buildDoctrine.sqf` to resolve the new impact-first keys.
2. Preserve existing behavior keys as temporary fallbacks so current doctrine remains valid during rollout.
3. Define and freeze the impact-solution result schema.
4. Seed the new impact telemetry variables in `fn_fpv_bootstrapLocal.sqf`.
5. Extend `fn_fpv_debugSnapshot.sqf` so the new fields are visible even before all later phases are complete.
6. Decide and document target-class defaults for `terminalImpactMode`:
   - infantry: direct body, then ground-near-target fallback;
   - vehicles: direct hull, then nearby ground or obstruction fallback;
   - statics: direct static surface, then nearby ground fallback;
   - air: retain controlled proximity fallback unless a stronger impact model is added later.
7. Add backward-compatible fallback rules so missing doctrine keys do not produce script errors.

### Expected artifacts

- a stable authored impact contract;
- debug-visible impact telemetry fields;
- no branch ambiguity about mode names, telemetry names, or doctrine keys.

### Validation gate

- supported site-family-role profiles resolve the new keys or derive safe defaults cleanly;
- bootstrap initializes the new UAV variables without nil or type errors;
- debug snapshot shows the new impact contract fields even before behavior changes are complete.

### Suggested debug-console checks

Inspect one managed drone profile:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
private _profile = [_d] call A3UE_fnc_fpv_getProfile;
hint str [
    _profile getOrDefault ["terminalImpactMode", ""],
    _profile getOrDefault ["terminalImpactOffsetFar", -1],
    _profile getOrDefault ["terminalImpactOffsetNear", -1],
    _profile getOrDefault ["terminalDescentMinRate", -1],
    _profile getOrDefault ["detonationMaxTimeToContact", -1],
    _profile getOrDefault ["detonationMinClosingDot", -1]
];
```

Inspect one managed drone telemetry block:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    _d getVariable ["A3UE_FPV_terminalImpactMode", ""],
    _d getVariable ["A3UE_FPV_lastImpactPointASL", []],
    _d getVariable ["A3UE_FPV_lastDetonationReason", ""],
    _d getVariable ["A3UE_FPV_lastFallbackReason", ""]
];
```

### Parallelization note

No parallel work should start before this phase completes. It defines the contract for all later impact behavior.

### Exit criteria

- the impact contract is explicit and stable;
- later phases can consume the same doctrine and telemetry surface without inventing conflicting names.

## 8. Phase 2: Impact-Point Resolution Backbone

### Goal

Add a terminal-only helper that resolves a concrete impact solution instead of treating the target object center as the only final answer.

### Why this phase exists

The system cannot become impact-first until it can answer one concrete question: "What exact point or surface is the drone trying to hit right now?"

### In scope

- one owner-local impact resolver helper;
- target-class-specific resolution policy;
- terminal-only evaluation and caching rules;
- obstruction-aware surface sampling;
- UAV impact-solution caching;
- fallback to the current target position when no better solution exists.

### Recommended target-class resolution order

| Target kind | Primary solution | Secondary solution | Fallback |
| --- | --- | --- | --- |
| `Man` | torso or pelvis point | ground at feet or slight movement lead | nearby obstruction surface |
| `LandVehicle` | hull or roof point along approach vector | vehicle centerline at hood or roof height | ground or obstruction beside vehicle |
| `StaticWeapon` | weapon or crew center | nearby hard surface on emplacement | nearby ground |
| `Air` | current target center | short-horizon predicted point | controlled proximity fallback |

### Performance policy

Freeze these rules before implementation:

- impact resolution does not run in `SEARCHING`;
- long-range `TRACKING` may reuse the current target center and should not pay full surface-query cost;
- full surface or obstruction resolution is allowed only in `TERMINAL_ATTACK`, `TERMINAL_VECTOR`, or an armed near-terminal pre-window;
- impact solution refresh should be TTL-based and movement-threshold-based, not every single tick.

### Implementation tasks

1. Add `fn_fpv_resolveImpactPoint.sqf` and register it in `config.cpp`.
2. Implement the impact-solution contract defined in Phase 1.
3. Use existing geometry where possible:
   - target class and role data;
   - `fn_fpv_isTargetObstructed.sqf`;
   - `lineIntersectsSurfaces` and terrain checks;
   - target position and velocity.
4. Add target-class resolution order and fallback rules.
5. Cache the last impact solution on the UAV with at least:
   - impact mode;
   - impact point ASL;
   - surface object netId or empty string;
   - update time;
   - target netId the solution was built for.
6. Integrate the resolver into `fn_fpv_runController.sqf` so terminal phases can request and reuse the result.
7. Keep a safe compatibility fallback: if no valid impact point exists, return a valid fallback solution using the target position or a conservative surface near the target.

### Expected artifacts

- terminal phases can resolve a concrete aimpoint;
- impact resolution is target-class-aware;
- no branch needs to invent its own local impact geometry logic.

### Validation gate

- infantry targets can return a direct body or ground-near-target solution;
- vehicle targets can return a hull or adjacent-surface solution;
- the helper returns stable fallback output instead of nil when resolution is ambiguous;
- impact queries occur only in terminal-eligible phases or cache refresh windows.

### Suggested debug-console checks

Inspect one drone's impact solution:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
private _target = [_d] call A3UE_fnc_fpv_resolveTarget;
private _impact = [_d, _target, [_d] call A3UE_fnc_fpv_getProfile] call A3UE_fnc_fpv_resolveImpactPoint;
hint str _impact;
```

Inspect cached impact telemetry:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    _d getVariable ["A3UE_FPV_terminalImpactMode", ""],
    _d getVariable ["A3UE_FPV_lastImpactPointASL", []],
    _d getVariable ["A3UE_FPV_lastImpactSurfaceType", ""],
    _d getVariable ["A3UE_FPV_lastImpactSurfaceObjectNetId", ""]
];
```

### Parallelization note

Once this phase is complete and the impact-solution contract is frozen, Phase 3A and Phase 3B can proceed in parallel.

### Exit criteria

- the runtime can resolve and cache impact solutions;
- later phases can guide and fuse against a concrete impact solution instead of a generic target center.

## 9. Phase 3A: Impact-First Guidance and Descent Conversion

### Goal

Convert terminal guidance from elevated pursuit into an impact-first descent profile that still preserves stable long-range chase behavior.

### Why this phase exists

Even with a good impact resolver, the drones will still airburst if terminal guidance keeps treating a point above the target as the final line.

### In scope

- distance-shaped vertical offset policy;
- terminal guidance against resolved impact points;
- descent enforcement in `TERMINAL_VECTOR`;
- compatibility with current missed-pass logic and owner-local vector control;
- preservation of coarse AI guidance outside the final strike window.

### Recommended guidance policy

Use a shaped transition rather than a hard switch:

- long-range `TRACKING`: keep a positive offset for obstacle clearance and stable pursuit;
- `TERMINAL_ATTACK`: collapse the offset toward `terminalImpactOffsetNear` as distance closes;
- `TERMINAL_VECTOR`: steer directly into the resolved impact solution with a minimum descent requirement.

Recommended distance-shaped offset model:

```sqf
private _impactOffset = linearConversion [
    _terminalGateDistance,
    0,
    _distanceToImpactPoint,
    _terminalImpactOffsetFar,
    _terminalImpactOffsetNear,
    true
];
```

### Implementation tasks

1. Update `fn_fpv_computeIntercept.sqf` so terminal guidance can use a resolved impact point and a shaped offset rather than an always-positive `attackHeightASL` clamp.
2. Preserve coarse positive offset behavior for long-range tracking where it still makes sense.
3. Update `fn_fpv_runTerminal.sqf` so it chases the impact solution instead of always forcing a positive final height offset above the target.
4. Update `fn_fpv_runTerminalVector.sqf` so it uses the impact solution as its aimpoint.
5. Enforce a minimum descent component inside `terminalDescentEnforceDistance` using `terminalDescentMinRate`.
6. Ensure terminal vector logic does not silently reintroduce a positive altitude floor near the end of the strike.
7. Re-check missed-pass behavior so a failed direct hit still exits into `LOST_TARGET` or a reasoned fallback state cleanly.

### Expected artifacts

- terminal approach visibly descends into the impact solution;
- infantry and vehicle strikes no longer default to a several-meter overflight;
- the final attack remains aggressive rather than floaty or hesitant.

### Validation gate

- terminal guidance can reduce altitude offset all the way into a near-contact or direct-impact solution;
- owner-local terminal vector steering still works with the impact point instead of the old elevated lead point;
- no new oscillation or hover-above-target behavior appears in the final seconds.

### Suggested debug-console checks

Inspect one drone's current impact geometry:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
private _impact = _d getVariable ["A3UE_FPV_lastImpactPointASL", []];
private _uavPos = getPosASL _d;
hint str [
    _d getVariable ["A3UE_FPV_mode", ""],
    _impact,
    _uavPos,
    if (_impact isEqualTo []) then {-1} else {(_uavPos vectorDistance _impact)}
];
```

### Parallelization note

This phase can run in parallel with Phase 3B once the impact-solution contract is frozen.

### Exit criteria

- terminal guidance is no longer overflight-first;
- direct or near-direct physical approach is the normal endgame path.

## 10. Phase 3B: Closure-Gated Fuse and Reasoned Fallbacks

### Goal

Refactor detonation approval so the primary fuse path prefers direct impact or imminent impact, while retaining self-detonation as a reasoned fallback.

### Why this phase exists

If the fuse remains proximity-only, the drones can still explode above the target even after guidance improves.

### In scope

- short-horizon impact or contact gating;
- closing-dot and time-to-contact logic;
- phase-specific detonation thresholds;
- detonation reasons and fallback reasons;
- preservation of `fn_fpv_detonateCompat.sqf` as the fallback delivery mechanism.

### Recommended detonation reason contract

Freeze one stable reason set for telemetry and debugging. Recommended reasons:

- `DIRECT_CONTACT`
- `PREDICTED_IMPACT`
- `CLOSURE_QUALIFIED`
- `MISSED_PASS_FALLBACK`
- `OBSTRUCTION_FALLBACK`
- `PROXIMITY_FAILSAFE`
- `NONE`

Recommended fallback reasons:

- `NO_VALID_IMPACT_POINT`
- `IMPACT_WINDOW_COLLAPSED`
- `TARGET_DUCKED_BEHIND_OBSTRUCTION`
- `OVERSHOOT_IMMINENT`
- `GUIDANCE_QUALITY_DEGRADED`
- `AIR_TARGET_PROXIMITY_POLICY`
- `NONE`

### Recommended fuse policy

Use a layered decision order:

1. confirmed direct contact or extremely short predicted impact;
2. impact-point proximity with valid closure quality and altitude envelope;
3. reasoned fallback burst if direct impact is no longer realistic but the drone remains inside a lethal envelope;
4. otherwise hold fire.

The primary fuse should inspect at least:

- `timeToContact`
- `closingDot`
- impact-point distance
- altitude above ground
- altitude above impact point
- whether the drone is moving toward or away from the solution

### Implementation tasks

1. Add `fn_fpv_evaluateImpactWindow.sqf` and register it in `config.cpp`, or implement the same logic cleanly inside `fn_fpv_shouldDetonateNow.sqf` if a new helper is not justified.
2. Compute and cache on the UAV:
   - last closing dot;
   - last time to contact;
   - last detonation reason;
   - last fallback reason.
3. Replace the current raw OR distance gate with the layered approval order above.
4. Use doctrine keys from Phase 1 for closure quality, TTC, and altitude limits.
5. Keep self-detonation fallback available, but make it impossible for a stationary or lateral-above drone to trigger the same result as a real closing strike.
6. Update `fn_fpv_detonateCompat.sqf` so detonation reason and fallback reason can be passed through or recorded.

### Expected artifacts

- proximity-only airburst above the target is no longer the default behavior;
- the fuse can distinguish a real closing strike from a hover-above or lateral pass;
- fallback bursts remain available and explainable.

### Validation gate

- drones that are above the target but not closing do not detonate by primary fuse logic;
- closing direct or near-direct runs still detonate reliably;
- fallback reasons are populated when detonation occurs without a clean direct-impact solution.

### Suggested debug-console checks

Inspect one drone's terminal fuse telemetry:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    _d getVariable ["A3UE_FPV_lastClosingDot", -2],
    _d getVariable ["A3UE_FPV_lastTimeToContact", -1],
    _d getVariable ["A3UE_FPV_lastDetonationReason", ""],
    _d getVariable ["A3UE_FPV_lastFallbackReason", ""]
];
```

### Parallelization note

This phase can run in parallel with Phase 3A once the impact-solution contract is frozen.

### Exit criteria

- the fuse is no longer proximity-first;
- fallback detonation is preserved, but it is explicit and reasoned.

## 11. Phase 4: Surface-Aware Integration, Delivery Semantics, and Multiplayer Hardening

### Goal

Merge the guidance and fuse branches into one target-class-aware, obstruction-aware, performance-controlled, multiplayer-safe feature.

### Why this phase exists

After the parallel branches land, the project still needs one integration phase to unify delivery semantics, fallback surfaces, telemetry, performance rules, and multiplayer behavior.

### In scope

- target-class-specific impact policy integration;
- obstruction-driven fallback surfaces;
- delivery semantics in `fn_fpv_detonateCompat.sqf`;
- performance guardrails for surface resolution;
- debug snapshot validation warnings;
- JIP, locality, and cleanup hardening.

### Integration policy

Recommended target-class behavior once this phase is complete:

- `Man`: body hit if clear, otherwise ground-near-target or nearby wall or cover surface;
- `LandVehicle`: hull or roof hit when clear, otherwise obstruction or ground beside the vehicle;
- `StaticWeapon`: weapon or emplacement hit, otherwise nearby ground;
- `Air`: maintain controlled proximity policy unless a dedicated air-impact model is added later.

### Delivery semantics policy

`fn_fpv_detonateCompat.sqf` should support optional impact-aware delivery semantics:

- if detonation reason is `DIRECT_CONTACT` or `PREDICTED_IMPACT`, allow the helper to deliver the warhead at or extremely near the resolved impact point rather than always at current UAV position;
- if the strike is a fallback burst, preserve the current UAV-position fallback behavior when needed for safety and compatibility;
- always record the detonation reason and fallback reason for post-run validation.

### Performance policy

This phase should enforce concrete guardrails:

- impact-surface work remains terminal-only or armed-window-only;
- impact refresh is TTL-based and distance-threshold-based;
- no unbounded per-frame surface scans in broad search modes;
- telemetry replication stays lightweight;
- heavy geometry reasoning remains owner-local.

### Implementation tasks

1. Integrate target-class-specific impact-mode defaults with the resolver, guidance, and fuse paths.
2. Reuse obstruction data from `fn_fpv_isTargetObstructed.sqf` to select wall, cover, or nearby-surface fallback strikes.
3. Update `fn_fpv_detonateCompat.sqf` so it can consume detonation reason and optional impact solution information.
4. Decide and implement whether predicted-impact delivery should occur at the resolved impact point or a tiny offset along the final incoming vector.
5. Add performance guardrails for impact refresh cadence and movement thresholds.
6. Extend `fn_fpv_debugSnapshot.sqf` validation with at least:
   - impact telemetry missing;
   - stale impact solution;
   - invalid impact mode;
   - non-local impact controller activity;
   - controller-owner mismatch during terminal impact phases.
7. Re-test locality transfer, cleanup, JIP, and external-control suspension while impact telemetry is active.

### Expected artifacts

- target-class impact behavior is coherent and integrated;
- obstruction-aware fallback surfaces are usable;
- delivery semantics better match the resolved impact solution;
- impact feature remains multiplayer-safe and performance-controlled.

### Validation gate

- infantry, vehicle, and static strikes all choose believable impact modes;
- obstruction cases can strike wall, ground, or nearby hard surface when direct impact is not available;
- debug snapshot validation warnings stay empty during healthy runs;
- no duplicate controllers, cleanup regressions, or JIP ownership issues appear.

### Suggested debug-console checks

Inspect the full validation block:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
hint str (_snapshot get "validation");
```

Inspect impact-related fields for one drone:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
private _managed = _snapshot get "managedDrones";
hint str _managed;
```

### Exit criteria

- the feature behaves coherently across target classes and fallback cases;
- the integrated implementation is locality-safe, performance-controlled, and debug-visible.

## 12. Phase 5: Local-LAN Acceptance and User Handoff

### Goal

Run the final acceptance matrix, finalize the user-facing validation runbook, and leave the user with a concrete LAN test procedure for confirming impact-first behavior in game.

### Why this phase exists

The feature is not complete until the user can reproduce the validation results in a real mission without hidden setup knowledge.

### In scope

- runbook finalization;
- acceptance criteria;
- debug and admin snippets;
- telemetry interpretation;
- user handoff notes.

### Implementation tasks

1. Finalize the local-LAN runbook below.
2. Confirm the runbook covers:
   - boot safety;
   - infantry direct impact;
   - vehicle and static strikes;
   - obstruction-driven fallback strikes;
   - no more premature aerial self-detonation above a stationary player;
   - missed-pass and fallback behavior;
   - external-control suspension;
   - JIP and locality during armed terminal runs.
3. Add final debug or admin snippets needed for repeatable local testing.
4. Confirm the user can inspect impact telemetry and validation warnings without editing code.

### Expected artifacts

- a release-ready validation guide for local-LAN testing;
- documented acceptance criteria;
- clear handoff notes for future tuning or follow-on work.

### Validation gate

- the user can follow the runbook and reproduce the impact-first checks on a local LAN;
- all mandatory acceptance scenarios pass;
- no blocking defects remain in impact resolution, descent behavior, fuse approval, fallback behavior, or locality safety.

### Exit criteria

- the feature is fully implemented and validated;
- the user can verify it end-to-end using the documented LAN procedure.

## 13. Final File and Function Target List

### Existing files expected to change

- `functions/fpv/fn_fpv_buildDoctrine.sqf`
- `functions/fpv/fn_fpv_getProfile.sqf`
- `functions/fpv/fn_fpv_bootstrapLocal.sqf`
- `functions/fpv/fn_fpv_runController.sqf`
- `functions/fpv/fn_fpv_computeIntercept.sqf`
- `functions/fpv/fn_fpv_runTerminal.sqf`
- `functions/fpv/fn_fpv_runTerminalVector.sqf`
- `functions/fpv/fn_fpv_shouldDetonateNow.sqf`
- `functions/fpv/fn_fpv_detonateCompat.sqf`
- `functions/fpv/fn_fpv_debugSnapshot.sqf`
- `functions/fpv/fn_fpv_isTargetObstructed.sqf`
- `config.cpp`

### Existing files that may change depending on implementation detail

- `functions/fpv/fn_fpv_applyGuidance.sqf`
- `functions/fpv/fn_fpv_selectTarget.sqf`
- `functions/fpv/fn_fpv_runLostTarget.sqf`
- `functions/fpv/fn_fpv_profileValue.sqf`

### New files likely to be added

- `functions/fpv/fn_fpv_resolveImpactPoint.sqf`
- `functions/fpv/fn_fpv_evaluateImpactWindow.sqf`

Optional helper if the resolver becomes too large:

- `functions/fpv/fn_fpv_resolveImpactSurface.sqf`

## 14. Local-LAN Validation Runbook

This is the final user-facing validation guide. When all phases are complete, the user should be able to follow this section directly and determine whether the impact-first redesign passes.

### 14.1 Recommended local-LAN setup

Minimum setup:

- one local dedicated server running Antistasi Ultimate with the extender loaded;
- one LAN client joining the server;
- at least one supported FPV family loaded.

Recommended setup:

- one local dedicated server;
- two LAN clients;
- optional headless client for ownership migration testing;
- all three supported drone families available for full coverage.

### 14.2 Required mod combinations

Run these combinations at minimum:

1. Antistasi Ultimate + Extender + ArmaFPV
2. Antistasi Ultimate + Extender + fpv_ua
3. Antistasi Ultimate + Extender + frtz_fiberoptic_kvn
4. Antistasi Ultimate + Extender + all three supported drone families
5. Antistasi Ultimate + Extender only, with no supported FPV family loaded

### 14.3 Mission preparation

1. Start an Antistasi mission over LAN.
2. Ensure the extender is loaded on server and all clients.
3. Move close enough to activate spawner coverage for:
   - one `Airport`
   - one `Outpost`
   - one `Resource`
4. Keep debug console access available on the host for state inspection.
5. Prepare at least these test subjects if practical:
   - one exposed infantry target;
   - one moving infantry target;
   - one wheeled or tracked vehicle;
   - one static weapon or emplacement;
   - one cover object or low wall near an infantry target.

### 14.3.1 Recommended debug-spawn distances

Use these starting ranges when spawning debug sites for impact-first validation:

- `Airport`: `600m` to `800m`
- `Outpost`: `450m` to `650m`
- `Resource`: `300m` to `500m`

These distances usually leave enough room to observe `TRACKING`, `TERMINAL_ATTACK`, `TERMINAL_VECTOR`, impact resolution, and the final fuse behavior.

### 14.3.2 Repeatable admin snippets

Spawn a debug site marker behind the player at a chosen distance:

```sqf
missionNamespace setVariable ["A3UE_FPV_debug", true];

private _siteType = "Airport";
private _distance = 700;
private _bearing = (getDir player) + 180;

if !(isNil "A3UE_FPV_debugMarker") then {
   deleteMarker A3UE_FPV_debugMarker;
};

A3UE_FPV_debugMarker = format ["A3UE_FPV_DEBUG_%1", floor (diag_tickTime * 1000)];
createMarker [A3UE_FPV_debugMarker, player getPos [_distance, _bearing]];

[A3UE_FPV_debugMarker, _siteType, true] call A3UE_fnc_fpv_managerEvaluateSite;
```

Inspect the current debug marker and registry state:

```sqf
hint str [
   missionNamespace getVariable ["A3UE_FPV_debugMarker", ""],
   missionNamespace getVariable ["A3UE_FPV_registry", createHashMap]
];
```

Remove the current debug marker after a test pass:

```sqf
if !(isNil "A3UE_FPV_debugMarker") then {
   deleteMarker A3UE_FPV_debugMarker;
};
```

### 14.4 Core validation snippets

Find all managed drones:

```sqf
allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }
```

Inspect one managed drone with impact telemetry:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    typeOf _d,
    _d getVariable ["A3UE_FPV_mode", ""],
    _d getVariable ["A3UE_FPV_terminalImpactMode", ""],
    _d getVariable ["A3UE_FPV_lastImpactPointASL", []],
    _d getVariable ["A3UE_FPV_lastImpactSurfaceType", ""],
    _d getVariable ["A3UE_FPV_lastImpactSurfaceObjectNetId", ""],
    _d getVariable ["A3UE_FPV_lastClosingDot", -2],
    _d getVariable ["A3UE_FPV_lastTimeToContact", -1],
    _d getVariable ["A3UE_FPV_lastDetonationReason", ""],
    _d getVariable ["A3UE_FPV_lastFallbackReason", ""]
];
```

Inspect the combined snapshot:

```sqf
hint str (call A3UE_fnc_fpv_debugSnapshot);
```

Inspect the validation block directly:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
hint str (_snapshot get "validation");
```

Inspect the impact summary directly:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
hint str (_snapshot get "impactSummary");
```

Inspect recent detonation records directly:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
hint str (_snapshot get "recentDetonations");
```

### 14.4.1 Telemetry interpretation

Use the impact telemetry fields as follows:

- `terminalImpactMode`: the currently selected strike policy for the target.
- `lastImpactPointASL`: the resolved physical strike point or fallback strike point.
- `lastImpactSurfaceType`: the kind of surface currently being used, such as `body`, `vehicle`, `ground`, `wall`, or `air`.
- `lastImpactSurfaceObjectNetId`: the netId of the chosen surface object when relevant.
- `lastClosingDot`: the alignment of current velocity with the impact solution direction, from `-1` to `1`.
- `lastTimeToContact`: the short-horizon predicted time to contact in seconds.
- `lastDetonationReason`: the reason the drone was allowed to detonate.
- `lastFallbackReason`: why the drone fell back from direct-impact semantics when it did.

Because a successful strike deletes the UAV, post-strike review should use `recentDetonations` from `A3UE_fnc_fpv_debugSnapshot` rather than only trying to inspect a now-destroyed drone object.

Healthy impact-first behavior should generally look like this:

- `terminalImpactMode` changes to a believable target-class mode in terminal phases;
- `lastImpactPointASL` sits on or extremely near the actual desired target surface or fallback surface;
- `lastClosingDot` trends positive and high during committed final closure;
- `lastTimeToContact` falls toward a small positive value before primary detonation approval;
- `lastDetonationReason` is usually `DIRECT_CONTACT`, `PREDICTED_IMPACT`, or `CLOSURE_QUALIFIED` for clean runs;
- fallback reasons only appear when the direct-impact path legitimately collapses.

Healthy recent detonation records should generally look like this:

- `deliveryMode` is `IMPACT_POINT` for `DIRECT_CONTACT` and `PREDICTED_IMPACT` strikes.
- `deliveryMode` remains `UAV_POSITION` for fallback bursts.
- `deliveryPosASL` should sit on or extremely near the selected impact surface for impact-point delivery.
- `impactMode`, `surfaceType`, `detonationReason`, and `fallbackReason` should match the behavior observed in game.

### 14.4.2 Validation block interpretation

The `validation` block in `A3UE_fnc_fpv_debugSnapshot` should become the fast acceptance summary for impact-first behavior.

Recommended expectations after implementation:

- `impactTelemetryMissing` stays empty.
- `staleImpactSolutions` stays empty.
- `invalidImpactModes` stays empty.
- `nonLocalImpactControllers` stays empty.
- `impactControllerOwnerMismatches` stays empty.
- `warnings` should normally be empty during healthy runs.

### 14.4.3 Impact summary interpretation

The `impactSummary` block in `A3UE_fnc_fpv_debugSnapshot` is the fast operational summary for active impact-first behavior.

- `activeNetIds` lists drones currently in `TERMINAL_ATTACK` or `TERMINAL_VECTOR`.
- `localNetIds` lists the active impact drones local to the current machine.
- `telemetryReadyNetIds` lists active impact drones with the expected impact telemetry fields populated.
- `activeVendors` and `activeSites` summarize the families and sites currently feeding impact-capable terminal runs.
- `recentDetonationCount` gives the number of retained post-strike records in `recentDetonations`.

### 14.5 Acceptance scenarios

#### Scenario 1: Soft-dependency boot safety unchanged

Steps:

1. Launch with Antistasi Ultimate and the extender only.
2. Start the mission and activate at least one supported site type.

Expected result:

- no script errors occur;
- no FPV drones spawn;
- the impact-first redesign does not create behavior when no supported family is loaded.

#### Scenario 2: Infantry direct-impact strike

Steps:

1. Place or expose a stationary infantry target in open ground.
2. Allow a managed FPV drone to progress into `TERMINAL_ATTACK` and `TERMINAL_VECTOR`.
3. Observe the final seconds and inspect impact telemetry.

Expected result:

- the drone descends into the target rather than detonating several meters above them;
- `terminalImpactMode` resolves to a direct infantry mode or equivalent;
- `recentDetonations` shows a direct-impact or predicted-impact path, not a generic proximity fallback.

#### Scenario 3: Infantry ground-near-target fallback strike

Steps:

1. Use a moving infantry target or a target whose body point is hard to strike cleanly.
2. Observe whether the drone chooses a nearby ground impact solution when a direct body hit is not the best option.

Expected result:

- the drone can intentionally strike ground or a nearby surface close to the target instead of airbursting above them;
- `terminalImpactMode` or `recentDetonations` reflects the ground-near-target choice clearly.

#### Scenario 4: Vehicle hull or roof strike

Steps:

1. Present a car, APC, or tank in open terrain.
2. Allow the drone to run the full terminal sequence.

Expected result:

- the drone aims at a believable hull or roof solution rather than hovering above vehicle center;
- direct-hit semantics or predicted-impact semantics are used when closure is good;
- `recentDetonations.deliveryMode` becomes `IMPACT_POINT` for direct or predicted strikes;
- `recentDetonations.deliveryPosASL` occurs at or very near the selected vehicle surface.

#### Scenario 5: Static weapon or emplacement strike

Steps:

1. Present a static weapon with or without crew.
2. Observe impact resolution and final strike behavior.

Expected result:

- the drone chooses a believable static-emplacement strike point;
- if the geometry is ambiguous, nearby ground fallback still looks intentional rather than random.

#### Scenario 6: Cover or obstruction fallback strike

Steps:

1. Place infantry behind a low wall, vehicle, sandbag line, or other obvious obstruction.
2. Allow the drone to enter terminal phases.

Expected result:

- the drone can choose a wall, nearby hard surface, or ground-near-target fallback strike rather than simply airbursting above cover;
- `recentDetonations.fallbackReason` and `recentDetonations.surfaceType` explain the chosen behavior.

#### Scenario 7: Above-player regression check

Steps:

1. Present a stationary infantry player on open ground.
2. Observe the final armed window closely.

Expected result:

- the drone does not detonate several meters above the player just because a height window and distance threshold are satisfied;
- it either continues descending into the resolved impact solution or holds fire until a valid fallback condition exists.

#### Scenario 8: Moving vehicle closure and TTC check

Steps:

1. Use a moving vehicle crossing the drone's approach line.
2. Observe whether detonation is gated by real closure rather than raw distance.

Expected result:

- a valid strike occurs only when the drone is actually closing into the impact solution;
- a lateral or drifting-above pass does not trigger the same approval path as a real intercept.

#### Scenario 9: Missed-pass behavior and fallback reasoning

Steps:

1. Force a bad terminal entry or a missed pass if practical.
2. Observe whether the drone falls back cleanly into `LOST_TARGET`, fallback detonation, or continued terminal logic.

Expected result:

- the drone does not get stuck hovering or endlessly circling in armed state;
- any fallback burst records a valid `fallbackReason` in `recentDetonations`.

#### Scenario 10: External control suspension during armed terminal run

Steps:

1. Take direct UAV control or Zeus remote control while the drone is in `TERMINAL_ATTACK` or `TERMINAL_VECTOR`.
2. Observe state changes and telemetry.

Expected result:

- autonomous impact logic stops cleanly;
- the controller returns to safe suspension behavior;
- no stale armed impact state persists after player or Zeus control takes over.

#### Scenario 11: JIP and locality during terminal impact behavior

Steps:

1. Let a drone enter an armed terminal run.
2. Join a second LAN client while terminal impact behavior is already active.
3. If available, force ownership migration to a headless client.

Expected result:

- only the current owner continues owner-local impact resolution and steering;
- late joiners observe telemetry and state but do not drive control;
- validation warnings stay empty for non-local controller activity and owner mismatch.

#### Scenario 12: Mixed-family safety and tuning sanity

Steps:

1. Launch with all supported families loaded.
2. Trigger multiple site types.
3. Observe impact behavior across different families.

Expected result:

- `armafpv` remains the sharpest attacker;
- `kvn` remains aggressive but slightly smoother or more conservative in fallback use;
- `fpv_ua` remains limited but still purposeful;
- none of the families revert to the old above-target airburst as their default clean-strike behavior.

### 14.6 Final acceptance rule

The impact-first redesign is accepted only when:

- all mandatory scenarios above pass;
- no blocking defects remain in impact resolution, terminal descent, fuse approval, fallback behavior, or ownership safety;
- the user can reproduce the checks on a local LAN using the documented telemetry and runbook.

## 15. User Handoff Summary

When all phases are complete, the user should be left with:

- the implemented impact-first strike redesign in code;
- `docs/fpv-targeting-chase-pathing-analysis.md` as the analysis and recommendation reference;
- this document as the execution and validation reference for phased delivery;
- a local-LAN runbook that proves the drones try to impact the target, vehicle, ground, or nearby surface before falling back to aerial self-detonation.

At that point, the feature should be fully implemented and validated rather than left as a monolithic plan or an informal tuning idea.