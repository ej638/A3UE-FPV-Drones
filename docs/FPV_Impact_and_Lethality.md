# FPV Impact and Lethality

Date: 2026-05-12

## Scope

This document is the single analysis, design, execution, and validation reference for the FPV terminal strike stack. It combines:

- the runtime analysis of targeting, chasing, pathing, and self-detonation behavior;
- the impact-first redesign plan;
- the direct-contact lethality follow-on;
- the RCA and final acceptance evidence for exposed-infantry direct-body strikes.

The combined feature scope is:

- explicit impact-point resolution;
- impact-first terminal guidance and descent;
- mode-aware fuse policy and reasoned fallback behavior;
- direct-hit versus fallback-surface delivery semantics;
- debug telemetry, recent detonation evidence, and LAN acceptance criteria.

## Executive Summary

The current A3UE FPV runtime already had a good controller architecture. Spawn policy, ownership, vendor compatibility, target selection, and terminal vector steering were structurally sound.

The realism gap came from the kill model:

1. final approach geometry stayed above the target;
2. detonation approval remained largely proximity-driven;
3. warhead delivery often occurred at UAV position rather than at a resolved strike point.

The correct fix was not a new spawn system or a new ownership model. The correct fix was to add an impact-resolution and impact-aware fuse layer on top of the existing controller, then harden direct-contact lethality for exposed infantry, vehicles, and statics.

## Current Runtime Analysis

### End-to-end flow that was already healthy

- `fn_addFPVEventListeners.sqf` builds the catalog and doctrine, registers Antistasi listeners, and refreshes already-managed drones.
- `fn_fpv_managerEvaluateSite.sqf` and `fn_fpv_managerSpawnDrone.sqf` create managed drones at eligible sites and stamp `A3UE_FPV_*` metadata.
- `fn_fpv_onAIVehInit.sqf` remote-execs `fn_fpv_bootstrapLocal.sqf` with the drone as a JIP key.
- `fn_fpv_bootstrapLocal.sqf` installs locality handlers, repairs vendor AI assumptions, seeds telemetry, and starts the local controller.
- `fn_fpv_runController.sqf` drives `IDLE`, `SEARCHING`, `TRACKING`, `LOST_TARGET`, `TERMINAL_ATTACK`, and `TERMINAL_VECTOR` with cached link-state handling and locality-safe steering.

### Why the original strike model felt like an airburst

The old system explicitly biased the drone toward approaching above the target and bursting by proximity:

- `fn_fpv_computeIntercept.sqf` and `fn_fpv_runTerminal.sqf` maintained a positive attack point above the target;
- `fn_fpv_shouldDetonateNow.sqf` approved detonation from distance and height windows rather than confirmed impact quality;
- `fn_fpv_detonateCompat.sqf` deleted the UAV and spawned the warhead at the drone position, so the explosion happened where the drone chose to self-detonate;
- no impact resolver existed for body points, hull points, ground strike points, or nearby obstruction surfaces.

### Quality review of the underlying stack

What was already good:

- server-side spawn management and owner-local control were separated correctly;
- locality transfer used the `Local` event instead of assuming static ownership;
- vendor compatibility was explicit;
- doctrine and profile resolution already existed;
- lost-target recovery was already present;
- terminal vector steering already existed as a dedicated endgame stage;
- link-state evaluation was cached rather than recomputed every steering tick.

What had to change:

- introduce impact semantics;
- remove the hard overflight bias from the final seconds of the attack;
- replace proximity-first fuse logic with impact-aware approval;
- add reasoned fallback-surface behavior and better delivery semantics;
- keep the heavier geometry work terminal-only for performance.

## Design Goals

1. Resolve a concrete impact solution instead of only a target object.
2. Guide terminal closure into that impact solution rather than hovering above it.
3. Prefer direct impact or very short-horizon predicted impact over generic proximity approval.
4. Keep self-detonation as a reasoned fallback, not as the primary behavior model.
5. Separate direct-hit modes from fallback-surface modes.
6. Align delivery semantics with the selected strike mode.
7. Expose enough telemetry and retained evidence to validate the behavior after detonation deletes the drone.

## Impact Contract

### Required doctrine keys

The impact-first stack needs doctrine support for:

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
- `terminalImpactHoldoffDistance`
- `impactSurfaceRefreshDistance`
- `impactSurfaceRefreshTTL`
- `fallbackSurfaceHoldoffDistance`

### Impact-solution schema

The terminal impact resolver should return a single stable result shape:

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

### Telemetry contract

At minimum, the UAV should expose:

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

## Impact-First Architecture

### Target-class resolution policy

| Target kind | Primary solution | Secondary solution | Fallback |
| --- | --- | --- | --- |
| `Man` | torso or pelvis point | body-adjacent point or ground at feet | nearby obstruction surface |
| `LandVehicle` | hull or roof point along approach vector | centerline hood or roof height | ground or obstruction near vehicle |
| `StaticWeapon` | weapon or crew center | nearby hard surface | nearby ground |
| `Air` | current target center | short-horizon predicted point | controlled proximity policy |

### Guidance policy

Use a shaped descent rather than a hard altitude floor:

- long-range `TRACKING`: allow a positive offset for stability and clearance;
- `TERMINAL_ATTACK`: collapse toward `terminalImpactOffsetNear` as distance closes;
- `TERMINAL_VECTOR`: steer directly into the resolved impact solution while enforcing a minimum descent component.

Recommended family baselines:

| Family | terminalImpactOffsetFar | terminalImpactOffsetNear | terminalDescentMinRate | detonationMaxTimeToContact | detonationMinClosingDot |
| --- | ---: | ---: | ---: | ---: | ---: |
| `armafpv` | `10 - 12` | `0 - 1.5` | `6 - 10` | `0.15 - 0.30` | `0.78 - 0.90` |
| `kvn` | `8 - 10` | `0 - 1.5` | `5 - 8` | `0.18 - 0.35` | `0.72 - 0.86` |
| `fpv_ua` | `6 - 8` | `0 - 2.0` | `4 - 7` | `0.20 - 0.40` | `0.68 - 0.82` |

### Performance guardrails

- impact resolution does not run in `SEARCHING`;
- long-range `TRACKING` reuses the current target center and should not pay full surface-query cost;
- full surface resolution is restricted to `TERMINAL_ATTACK`, `TERMINAL_VECTOR`, or an armed near-terminal pre-window;
- impact refresh is TTL-based and movement-threshold-based rather than every tick;
- heavy geometry work remains owner-local.

## Fuse and Delivery Policy

### Detonation reason contract

Recommended detonation reasons:

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

### Direct-hit versus fallback-surface policy matrix

| impactMode | Allowed primary approvals | Allowed fallback approvals | Delivery expectation |
| --- | --- | --- | --- |
| `DIRECT_BODY` | `DIRECT_CONTACT`, very short `PREDICTED_IMPACT` | explicit emergency fallback only | `IMPACT_POINT` |
| `DIRECT_HULL` | `DIRECT_CONTACT`, short `PREDICTED_IMPACT` | explicit emergency fallback only | `IMPACT_POINT` |
| `DIRECT_STATIC` | `DIRECT_CONTACT`, short `PREDICTED_IMPACT` | explicit emergency fallback only | `IMPACT_POINT` |
| `GROUND_NEAR_TARGET` | surface-qualified `CLOSURE_QUALIFIED` inside holdoff | explicit fallback reasons | `IMPACT_POINT` |
| `OBSTRUCTION_SURFACE` | surface-qualified `OBSTRUCTION_FALLBACK` inside holdoff | explicit fallback reasons | `IMPACT_POINT` |
| `AIR_PROXIMITY` | controlled proximity policy | air-policy fallback | `UAV_POSITION` or authored air policy |

Key rule:

- direct-hit modes must not share the same permissive generic closure envelope used by fallback-surface modes.

### Delivery semantics

`fn_fpv_detonateCompat.sqf` should select delivery position from strike mode plus approval reason:

- `DIRECT_CONTACT` and `PREDICTED_IMPACT` use impact-point delivery;
- intentional surface strikes such as `GROUND_NEAR_TARGET` and `OBSTRUCTION_SURFACE` use impact-point delivery when approved by their own valid surface-qualified logic;
- emergency or failsafe bursts may retain `UAV_POSITION` delivery.

## Delivery Model

### Impact-first backbone

| Phase | Title | Outcome |
| --- | --- | --- |
| 1 | Impact contract, doctrine, and telemetry foundation | Stable impact keys, telemetry names, and target-class defaults exist |
| 2 | Impact-point resolution backbone | Terminal phases can resolve and cache a concrete impact solution |
| 3A | Impact-first guidance and descent conversion | Terminal guidance chases resolved impact points and descends credibly |
| 3B | Closure-gated fuse and reasoned fallbacks | Fuse logic prefers direct or predicted impact and records fallback reasons |
| 4 | Surface-aware integration, delivery semantics, and MP hardening | Target-class policies, fallback surfaces, and delivery semantics work together |
| 5 | LAN acceptance and user handoff | Feature is validated and documented for local testing |

### Direct-contact lethality backbone

| Phase | Title | Outcome |
| --- | --- | --- |
| 1 | Direct-hit policy freeze, telemetry contract, and debug evidence backbone | The remaining problem is formalized as a direct-hit fuse and delivery issue |
| 2 | Mode-aware fuse hardening backbone | Direct-hit approval is separated from fallback-surface approval |
| 3A | Infantry and direct-hit resolution hardening | Open-ground infantry resolves `DIRECT_BODY` more reliably |
| 3B | Delivery-semantics alignment for direct and fallback-surface strikes | Intentional surface strikes no longer silently burst at UAV position |
| 4 | Integrated tuning, locality hardening, and delivery semantics finalization | Doctrine, resolver, fuse, and delivery semantics are coherent |
| 5 | LAN acceptance and user handoff | Corrected lethality behavior is validated end to end |

Parallelization rules:

- impact-first Phase 3A and 3B can run in parallel after Phase 2 freezes the impact-solution contract;
- direct-contact Phase 3A and 3B can run in parallel after Phase 2 freezes the policy and delivery matrix.

## RCA Follow-Up and Accepted Outcome

### Failure signature that drove the follow-on work

Observed `recentDetonations` evidence showed a consistent bad pattern:

- `impactMode = GROUND_NEAR_TARGET`
- `detonationReason = CLOSURE_QUALIFIED`
- `deliveryMode = UAV_POSITION`

That proved:

1. guidance was no longer the main problem;
2. direct-hit modes were not staying on a true direct-hit fuse path;
3. delivery semantics still leaked back to UAV-position bursts.

### Resolver RCA findings

The final RCA established two concrete resolver control-flow bugs in `fn_fpv_resolveImpactPoint.sqf`:

1. a successful `DIRECT_BODY` result could be computed but then discarded by later fallback flow;
2. `_resolveDirectBodySolution` used `exitWith` inside the candidate `forEach`, which exited the loop body without persisting the winning result.

The important classification result was:

- body traces were hitting infantry geometry;
- obstruction state was clean in flat-field cases;
- the controlling defect was resolver fallthrough, not a geometry or obstruction false positive.

### Final accepted evidence

The final single-resource-drone rerun cleared the acceptance gate:

- live terminal telemetry reached `DIRECT_BODY`;
- `recentDetonations` recorded `strikePathClass = DIRECT_HIT`, `impactMode = DIRECT_BODY`, `deliveryMode = IMPACT_POINT`, `approvalPolicyClass = DIRECT_HIT_PRIMARY`, and `detonationReason = PREDICTED_IMPACT`;
- `phase5AcceptanceSummary` reported `acceptanceGateClear = true`, `directBodyEvidenceAvailable = true`, `directBodyPrimaryEvidenceAvailable = true`, and `status = ACCEPTANCE_EVIDENCE_HEALTHY`;
- no FPV script errors, locality issues, or telemetry-integrity failures were observed in the accepted review segment.

### Resource-site note

The slower turn-in seen during the accepted rerun is consistent with doctrine, not with a defect:

- `Resource` sites use a smaller acquisition envelope than `Airport`;
- drones stay in `SEARCHING` and `holdPattern` until the target enters that smaller envelope.

## Debug Snapshot Interpretation

### `validation`

Structural health summary. Healthy runs should keep these empty or false:

- `impactTelemetryMissing`
- `staleImpactSolutions`
- `invalidImpactModes`
- `nonLocalImpactControllers`
- `impactControllerOwnerMismatches`
- `warnings`

### `impactSummary`

Operational summary for active impact-capable terminal runs:

- `activeNetIds` lists drones in `TERMINAL_ATTACK` or `TERMINAL_VECTOR`;
- `localNetIds` lists active impact drones local to the current machine;
- `telemetryReadyNetIds` lists active impact drones with the expected fields populated;
- `activeVendors` and `activeSites` summarize the live distribution;
- `recentDetonationCount` tracks retained evidence in `recentDetonations`.

### `directContactPolicy`

The explicit policy-freeze block for the lethality follow-on:

- direct-hit modes versus fallback-surface modes;
- allowed primary and fallback approval classes;
- holdoff contract key and enforcement status;
- supported tuning keys;
- the known bad pattern this work had to eliminate.

### `phase1EvidenceSummary`

Evidence rollup for the remaining failure mode:

- `recentKnownBadPatternCount`
- `recentDeliveryPolicyMismatchCount`
- `recentClosureQualifiedDirectHitCount`
- `recentClosureQualifiedFallbackSurfaceCount`
- `holdoffConfiguredActiveCount`

### `phase4IntegrationSummary`

Acceptance-facing integration rollup for tuned direct-hit and fallback-surface behavior:

- active direct-hit and fallback-surface net IDs;
- invalid tuning relationships;
- recent direct-body counts;
- direct-hit impact-delivery counts versus UAV-delivery counts;
- fallback-surface impact-delivery counts versus UAV-delivery counts.

### `phase5AcceptanceSummary`

Final handoff block for LAN validation:

- `status`
- `readyForLanAcceptanceRuns`
- `acceptanceGateClear`
- `validationHealthy`
- `recentEvidenceAvailable`
- `knownBadPatternCleared`
- `directHitDeliveryHealthy`
- `surfaceDeliveryHealthy`
- `directBodyEvidenceAvailable`
- `directBodyPrimaryEvidenceAvailable`
- `focusAreas`

## File and Function Targets

### Existing files expected to change

- `functions/fpv/fn_fpv_buildDoctrine.sqf`
- `functions/fpv/fn_fpv_getProfile.sqf`
- `functions/fpv/fn_fpv_bootstrapLocal.sqf`
- `functions/fpv/fn_fpv_runController.sqf`
- `functions/fpv/fn_fpv_computeIntercept.sqf`
- `functions/fpv/fn_fpv_runTerminal.sqf`
- `functions/fpv/fn_fpv_runTerminalVector.sqf`
- `functions/fpv/fn_fpv_resolveImpactPoint.sqf`
- `functions/fpv/fn_fpv_evaluateImpactWindow.sqf`
- `functions/fpv/fn_fpv_shouldDetonateNow.sqf`
- `functions/fpv/fn_fpv_detonateCompat.sqf`
- `functions/fpv/fn_fpv_debugSnapshot.sqf`
- `functions/fpv/fn_fpv_isTargetObstructed.sqf`
- `config.cpp`

### Optional helpers if the implementation grows

- `functions/fpv/fn_fpv_resolveImpactSurface.sqf`
- `functions/fpv/fn_fpv_resolveBodyImpactPoint.sqf`
- `functions/fpv/fn_fpv_selectImpactDeliveryMode.sqf`

## Local-LAN Validation Runbook

### Recommended setup

Minimum:

- one local dedicated server running Antistasi Ultimate with the extender loaded;
- one LAN client;
- at least one supported FPV family.

Recommended:

- one local dedicated server;
- two LAN clients;
- optional headless client;
- all three supported drone families.

### Mission preparation

1. Start an Antistasi mission over LAN.
2. Activate at least one `Airport`, one `Outpost`, and one `Resource`.
3. Keep debug console access available.
4. Prepare exposed stationary infantry, moving infantry, a vehicle, a static weapon, and one cover object if practical.

### Repeatable admin snippets

Spawn a debug site marker behind the player:

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

Run live-flight inspection while drones are active:

```sqf
private _managed = allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] };
private _d = _managed param [0, objNull];
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;

diag_log format ["A3UE_FPV_VALIDATION managed_drones=%1", str (_managed apply { _x getVariable ["A3UE_FPV_netId", netId _x] })];
diag_log format ["A3UE_FPV_VALIDATION drone_telemetry=%1", str [
    typeOf _d,
    _d getVariable ["A3UE_FPV_mode", ""],
    _d getVariable ["A3UE_FPV_terminalImpactMode", ""],
    _d getVariable ["A3UE_FPV_lastImpactPointASL", []],
    _d getVariable ["A3UE_FPV_lastImpactSurfaceType", ""],
    _d getVariable ["A3UE_FPV_lastClosingDot", -2],
    _d getVariable ["A3UE_FPV_lastTimeToContact", -1],
    _d getVariable ["A3UE_FPV_lastDetonationReason", ""],
    _d getVariable ["A3UE_FPV_lastFallbackReason", ""]
]];
diag_log format ["A3UE_FPV_VALIDATION validation=%1", str (_snapshot get "validation")];
diag_log format ["A3UE_FPV_VALIDATION impactSummary=%1", str (_snapshot get "impactSummary")];
diag_log format ["A3UE_FPV_VALIDATION directContactPolicy=%1", str (_snapshot get "directContactPolicy")];
diag_log format ["A3UE_FPV_VALIDATION phase1EvidenceSummary=%1", str (_snapshot get "phase1EvidenceSummary")];
diag_log format ["A3UE_FPV_VALIDATION phase4IntegrationSummary=%1", str (_snapshot get "phase4IntegrationSummary")];
diag_log format ["A3UE_FPV_VALIDATION phase5AcceptanceSummary=%1", str (_snapshot get "phase5AcceptanceSummary")];
```

Run post-strike inspection after detonation evidence exists:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;

diag_log format ["A3UE_FPV_VALIDATION validation=%1", str (_snapshot get "validation")];
diag_log format ["A3UE_FPV_VALIDATION impactSummary=%1", str (_snapshot get "impactSummary")];
diag_log format ["A3UE_FPV_VALIDATION recentDetonations=%1", str (_snapshot get "recentDetonations")];
diag_log format ["A3UE_FPV_VALIDATION phase1EvidenceSummary=%1", str (_snapshot get "phase1EvidenceSummary")];
diag_log format ["A3UE_FPV_VALIDATION phase4IntegrationSummary=%1", str (_snapshot get "phase4IntegrationSummary")];
diag_log format ["A3UE_FPV_VALIDATION phase5AcceptanceSummary=%1", str (_snapshot get "phase5AcceptanceSummary")];
```

### Core validation scenarios

#### Impact-first scenarios

1. Infantry direct-impact strike: no several-meter airburst above a stationary exposed player.
2. Infantry ground-near-target fallback strike: fallback surfaces remain intentional rather than random.
3. Vehicle hull or roof strike: direct or predicted impact uses `IMPACT_POINT` delivery near the chosen surface.
4. Static weapon or emplacement strike: the resolver chooses a believable static strike point or a justified ground fallback.
5. Cover or obstruction fallback strike: wall, cover, or ground fallback remains explainable in telemetry.
6. Above-player regression check: distance and height windows alone do not reintroduce early airbursts.
7. Moving vehicle closure and TTC check: real closure quality matters more than raw distance.
8. Missed-pass behavior: failed terminal entries return to a reasoned fallback or reacquisition path.

#### Direct-contact lethality scenarios

1. Exposed infantry direct-hit lethality: clean open-ground runs produce `DIRECT_BODY` evidence and lethal direct-hit delivery.
2. Moving-target fallback discipline: the resolver degrades to surface strikes only when the direct-body path is not credible.
3. Vehicle and static direct-hit behavior: direct-hit modes no longer use the permissive fallback-surface approval envelope.
4. Fallback-surface delivery alignment: intentional `GROUND_NEAR_TARGET` and `OBSTRUCTION_SURFACE` strikes use `IMPACT_POINT` delivery when designed to do so.
5. Above-player regression check: the old `GROUND_NEAR_TARGET + CLOSURE_QUALIFIED + UAV_POSITION` signature does not recur on clean direct-hit runs.
6. External control, JIP, and locality during armed terminal behavior: only the current owner drives impact logic and delivery approval.

### Acceptance rules

The combined feature is accepted only when:

- all mandatory scenarios pass;
- no blocking defects remain in impact resolution, direct-hit approval, fallback-surface delivery, or ownership safety;
- clean exposed-infantry runs stop producing the old `GROUND_NEAR_TARGET + CLOSURE_QUALIFIED + UAV_POSITION` signature;
- recent evidence supports `DIRECT_BODY` plus direct-hit primary approval on the accepted open-ground path.

## User Handoff

When this feature is complete, the user should be left with:

- the implemented impact and lethality redesign in code;
- this document as the single analysis, phase, RCA, and validation reference;
- `A3UE_fnc_fpv_debugSnapshot` and `recentDetonations` as the primary acceptance surfaces;
- a LAN runbook that proves the drones try to hit the target or a sensible fallback surface before using aerial self-detonation as a fallback.