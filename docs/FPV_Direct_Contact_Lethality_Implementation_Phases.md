# FPV Direct-Contact Lethality Implementation Phases

Date: 2026-05-08
Primary design references: `docs/fpv-targeting-chase-pathing-analysis.md`, `docs/FPV_Impact_First_Implementation_Phases.md`, runtime evidence from `A3UE_fnc_fpv_debugSnapshot` `recentDetonations`
Purpose: Break the remaining direct-contact lethality and early-detonation corrections into implementation phases that can be delivered sequentially or in controlled parallel, with explicit dependencies, implementation scope, acceptance criteria, and a final local-LAN validation runbook for the user.

## 1. Delivery Goal

This phase plan is complete only when all of the following are true:

- direct-hit strike modes against exposed infantry, vehicles, and statics no longer detonate several meters short by generic proximity-style approval;
- a lone stationary infantry target in open ground can be killed reliably by a committed direct-hit run;
- `DIRECT_BODY`, `DIRECT_HULL`, and `DIRECT_STATIC` no longer use the same permissive detonation path as `GROUND_NEAR_TARGET`, `OBSTRUCTION_SURFACE`, or `AIR_PROXIMITY`;
- the fuse policy is explicitly mode-aware and separates direct-hit approval from intentional fallback-surface approval;
- `terminalImpactHoldoffDistance` or an equivalent direct-hit holdoff contract is actually used by the fuse rather than remaining authored but inactive;
- non-contact direct-hit detonation, when allowed at all, happens only at a very short predicted-impact horizon;
- intentional fallback strikes such as ground-near-target or obstruction-surface strikes still remain available and believable;
- delivery semantics align with approval semantics, so direct or intentional fallback strikes spawn at the resolved strike point rather than drifting back to a generic UAV-position burst;
- runtime telemetry and debug snapshot clearly show whether a strike was a direct-hit path, a predicted-impact path, or a fallback-surface path;
- multiplayer locality, cleanup, JIP, ownership transfer, and external-control suspension remain intact;
- the user is left with a detailed local-LAN validation procedure that can confirm the corrected lethality behavior in game without hidden setup knowledge.

## 2. Current-State Diagnosis

The impact-first redesign improved approach geometry, but the runtime still retains a meaningful proximity aspect in the final fuse and delivery path. That is why the drones now fly toward the player correctly but still explode early and often fail to kill an isolated player in open ground.

### What the current code is doing now

- `fn_fpv_resolveImpactPoint.sqf` can resolve `DIRECT_BODY`, `DIRECT_HULL`, `DIRECT_STATIC`, `GROUND_NEAR_TARGET`, `OBSTRUCTION_SURFACE`, or `AIR_PROXIMITY`, but infantry can still fall back to `GROUND_NEAR_TARGET` when a direct body surface is not confirmed cleanly.
- `fn_fpv_runTerminal.sqf` and `fn_fpv_runTerminalVector.sqf` now chase the resolved impact point, so the visible approach looks much better than before.
- `fn_fpv_evaluateImpactWindow.sqf` still approves detonation through several non-contact paths:
  - `DIRECT_CONTACT` is still a near-contact distance threshold, not true collision confirmation.
  - `PREDICTED_IMPACT` is still a short-horizon pre-impact approval.
  - `CLOSURE_QUALIFIED` is still a generic in-envelope approval using `detonationDistance`, `detonationDistance2D`, altitude, and closing-dot checks.
  - `PROXIMITY_FAILSAFE` still exists for fallback cases.
- `fn_fpv_detonateCompat.sqf` only uses impact-point delivery for `DIRECT_CONTACT` and `PREDICTED_IMPACT`. `CLOSURE_QUALIFIED` and fallback reasons still burst at UAV position.

### Observed runtime evidence

The user's `recentDetonations` output shows a consistent signature across multiple live strikes:

| Vendor / Role / Site | impactMode | detonationReason | deliveryMode | Observed result |
| --- | --- | --- | --- | --- |
| `kvn` / `AT` / airport | `GROUND_NEAR_TARGET` | `CLOSURE_QUALIFIED` | `UAV_POSITION` | burst occurs roughly `16m` short of the resolved impact point |
| `kvn` / `RECON` / resource | `GROUND_NEAR_TARGET` | `CLOSURE_QUALIFIED` | `UAV_POSITION` | burst occurs roughly `10m` short of the resolved impact point |
| `fpv_ua` / `RECON` / resource | `GROUND_NEAR_TARGET` | `CLOSURE_QUALIFIED` | `UAV_POSITION` | burst occurs roughly `8m` short of the resolved impact point |

That output matters because it proves four things:

1. guidance is no longer the main problem, because the drone is clearly committed toward the player;
2. the dominant approval path is still `CLOSURE_QUALIFIED`, not true direct contact;
3. the resolved strike mode is often `GROUND_NEAR_TARGET` rather than a clean `DIRECT_BODY` hit;
4. once approved by `CLOSURE_QUALIFIED`, the warhead still spawns at UAV position rather than the resolved strike point.

### Why the user is seeing low lethality in open ground

The current result comes from three design choices reinforcing one another:

1. the infantry resolver often degrades to `GROUND_NEAR_TARGET` rather than preserving a reliable direct-body strike point;
2. `CLOSURE_QUALIFIED` allows a strike to fire while still several meters from the resolved impact point;
3. `CLOSURE_QUALIFIED` still delivers at UAV position instead of the resolved ground or body strike point.

That combination is enough to explain the user's observation exactly: the drone visually attacks the player instead of orbiting overhead, but the explosion still happens early and often outside a reliably lethal radius.

## 3. Solution Summary

The intended redesign is not a new guidance system. The intended redesign is a direct-hit lethality correction on top of the existing impact-first stack:

- keep the current spawn, registry, controller ownership, and impact-first guidance model intact;
- separate direct-hit fuse policy from fallback-surface fuse policy;
- make `DIRECT_BODY`, `DIRECT_HULL`, and `DIRECT_STATIC` require true near-contact or very short predicted-impact approval;
- use `terminalImpactHoldoffDistance` as the main authored gate for non-contact direct-hit approval;
- improve infantry direct-body resolution so open-ground players do not collapse into `GROUND_NEAR_TARGET` unless there is a good reason;
- align delivery semantics with the selected strike mode and approval reason so intentional fallback-surface strikes can still burst at their resolved impact point;
- preserve explicit fallback behavior for missed-pass, degraded guidance, obstruction, and air-target policy;
- leave the user with a LAN validation runbook that can prove the corrected behavior end to end.

## 4. Recommended Delivery Model

The safest delivery model is a sequential backbone with one controlled parallel split.

### Sequential backbone

1. Phase 1: Direct-Hit Policy Freeze, Telemetry Contract, and Debug Evidence Backbone
2. Phase 2: Mode-Aware Fuse Hardening Backbone
3. Phase 4: Integrated Tuning, Locality Hardening, and Delivery Semantics Finalization
4. Phase 5: Local-LAN Acceptance and User Handoff

### Parallel-capable branches

After Phase 2, the work can split into two parallel branches:

- Phase 3A: Infantry and Direct-Hit Resolution Hardening
- Phase 3B: Delivery-Semantics Alignment for Direct and Fallback Surface Strikes

These branches can proceed in parallel only if the team freezes the following contracts first:

- the approved detonation-reason and fallback-reason names;
- the mode-aware fuse policy matrix for `DIRECT_BODY`, `DIRECT_HULL`, `DIRECT_STATIC`, `GROUND_NEAR_TARGET`, `OBSTRUCTION_SURFACE`, and `AIR_PROXIMITY`;
- the exact meaning of `terminalImpactHoldoffDistance` for direct-hit modes and fallback-surface modes;
- the rule that direct-hit modes cannot use the same permissive generic closure envelope as fallback-surface modes;
- the rule that delivery semantics must match the reasoned strike mode rather than only the legacy UAV position.

### Final integration order

- Phase 3A and Phase 3B must both merge before Phase 4 is treated as complete.
- Phase 4 must merge before final LAN acceptance begins.
- Phase 5 is the release gate. Do not treat the feature as complete until Phase 5 passes.

## 5. Dependency Summary

| Phase | Title | Depends On | Can Run In Parallel With | Completion Outcome |
| --- | --- | --- | --- | --- |
| 1 | Direct-Hit Policy Freeze, Telemetry Contract, and Debug Evidence Backbone | None | None | The remaining problem is formalized as a direct-hit lethality and delivery-policy issue with stable contracts for later phases |
| 2 | Mode-Aware Fuse Hardening Backbone | 1 | None | Direct-hit fuse policy is separated from fallback-surface policy and uses explicit holdoff and near-contact rules |
| 3A | Infantry and Direct-Hit Resolution Hardening | 2 | 3B | Open-ground infantry and other direct-hit targets resolve stable direct strike points more reliably |
| 3B | Delivery-Semantics Alignment for Direct and Fallback Surface Strikes | 2 | 3A | Delivery position matches the intended strike mode instead of silently falling back to UAV-position bursts |
| 4 | Integrated Tuning, Locality Hardening, and Delivery Semantics Finalization | 3A, 3B | None | Doctrine, fuse, resolver, and delivery semantics are coherent, performant, and multiplayer-safe |
| 5 | Local-LAN Acceptance and User Handoff | 4 | None | The feature is fully implemented, validated, and documented for local-LAN acceptance |

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
- no phase may move expensive surface or geometry work into `SEARCHING` or long-range `TRACKING` hot paths;
- no phase may remove self-detonation fallback entirely;
- direct-hit modes may not retain a permissive `CLOSURE_QUALIFIED` path unless that path is explicitly redefined into a true near-contact gate;
- delivery mode must be explainable from strike mode and detonation reason.

## 7. Phase 1: Direct-Hit Policy Freeze, Telemetry Contract, and Debug Evidence Backbone

### Goal

Freeze the remaining lethality problem as a direct-hit fuse and delivery issue, not a broad guidance rewrite, and make the runtime contracts explicit enough for safe implementation in later phases.

### Why this phase exists

The current code already contains the right concepts, including `terminalImpactHoldoffDistance`, impact-mode telemetry, detonation reasons, fallback reasons, and recent detonation history. The next phases should not start until the team agrees exactly which strike modes are allowed to use which approval paths and delivery paths.

### In scope

- mode-aware fuse-policy contract;
- direct-hit versus fallback-surface delivery-policy contract;
- debug evidence interpretation for the current failure mode;
- documentation of the known bad runtime signature;
- any missing debug summary fields needed to validate the later phases.

### Recommended policy freeze

Freeze a detonation-policy matrix like this:

| impactMode | Allowed primary approvals | Allowed fallback approvals | Delivery expectation |
| --- | --- | --- | --- |
| `DIRECT_BODY` | `DIRECT_CONTACT`, very short `PREDICTED_IMPACT` | only explicit emergency fallback reasons | normally `IMPACT_POINT` |
| `DIRECT_HULL` | `DIRECT_CONTACT`, short `PREDICTED_IMPACT` | only explicit emergency fallback reasons | normally `IMPACT_POINT` |
| `DIRECT_STATIC` | `DIRECT_CONTACT`, short `PREDICTED_IMPACT` | only explicit emergency fallback reasons | normally `IMPACT_POINT` |
| `GROUND_NEAR_TARGET` | `CLOSURE_QUALIFIED` or equivalent surface-qualified gate inside holdoff | explicit fallback reasons | `IMPACT_POINT` at ground point |
| `OBSTRUCTION_SURFACE` | `OBSTRUCTION_FALLBACK` or equivalent surface-qualified gate inside holdoff | explicit fallback reasons | `IMPACT_POINT` at obstruction surface |
| `AIR_PROXIMITY` | controlled proximity policy | air-specific fallback policy | `UAV_POSITION` or air-policy delivery as authored |

### Implementation tasks

1. Document the current bad runtime signature from the user's `recentDetonations` evidence.
2. Freeze the meaning of `terminalImpactHoldoffDistance` and specify that it becomes active in Phase 2.
3. Freeze the rule that direct-hit modes may not use the same permissive approval envelope as fallback-surface modes.
4. Decide whether `CLOSURE_QUALIFIED` remains a fallback-surface reason only or is retired for direct-hit modes entirely.
5. Decide whether fallback-surface strikes should use impact-point delivery in Phase 3B.
6. Confirm the debug surfaces needed for later phases:
   - `recentDetonations`
   - `directContactPolicy`
   - `phase1EvidenceSummary`
   - `validation`
   - `impactSummary`
   - active drone impact telemetry

### Expected artifacts

- a stable detonation-policy matrix;
- a stable delivery-policy matrix;
- a documented explanation of the current `GROUND_NEAR_TARGET` + `CLOSURE_QUALIFIED` + `UAV_POSITION` failure signature.

### Acceptance criteria

- the policy matrix is explicit enough that later phases do not have to guess whether a given mode may use early non-contact approval;
- the user or next agent can determine from one `recentDetonations` record whether the strike used a direct-hit or fallback-surface path;
- no ambiguity remains about whether `terminalImpactHoldoffDistance` is active design contract or dead authored data.

## 8. Phase 2: Mode-Aware Fuse Hardening Backbone

### Goal

Separate direct-hit approval from fallback-surface approval so exposed infantry, vehicles, and statics cannot still die by the same generic proximity-style closure envelope.

### Why this phase exists

The current early detonation happens because `fn_fpv_evaluateImpactWindow.sqf` still allows `CLOSURE_QUALIFIED` inside the generic impact envelope, and that envelope is still built from `detonationDistance`, `detonationDistance2D`, and altitude checks. That is still a proximity-shaped approval.

### In scope

- refactor of `fn_fpv_evaluateImpactWindow.sqf`;
- active use of `terminalImpactHoldoffDistance` or equivalent holdoff key;
- direct-hit near-contact policy;
- direct-hit predicted-impact policy;
- emergency fallback policy retained explicitly rather than implicitly.

### Recommended fuse-policy changes

- `DIRECT_BODY`, `DIRECT_HULL`, and `DIRECT_STATIC` should not approve through the current generic `CLOSURE_QUALIFIED` branch.
- direct-hit modes should use:
  - near-contact distance gate;
  - very short predicted-impact TTC gate;
  - explicit emergency fallback only when a defined fallback reason is present.
- fallback-surface modes may still use surface-qualified closure approval, but only inside `terminalImpactHoldoffDistance`.
- `PROXIMITY_FAILSAFE` should remain available only for explicit failsafe paths, not as the normal clean-strike path for direct-hit modes.

### Recommended doctrine additions or redefinitions

At minimum, consider adding or freezing support for:

- `directContactDistanceBody`
- `directContactDistanceHull`
- `predictedImpactMaxTimeToContactBody`
- `predictedImpactMaxTimeToContactHull`
- `directHitClosureQualifiedAllowed`
- `fallbackSurfaceHoldoffDistance`

If new keys are not justified, reuse existing keys with mode-aware semantics, especially `terminalImpactHoldoffDistance`.

### Implementation tasks

1. Refactor `fn_fpv_evaluateImpactWindow.sqf` into a mode-aware decision tree.
2. Wire `terminalImpactHoldoffDistance` into non-contact approval.
3. Remove or redefine `CLOSURE_QUALIFIED` for direct-hit modes.
4. Keep `OBSTRUCTION_FALLBACK`, `MISSED_PASS_FALLBACK`, and other explicit fallback reasons intact.
5. Ensure `recentDetonations` and live telemetry still reflect the selected detonation reason and fallback reason.
6. Verify that direct-hit modes no longer detonate early solely because they entered the broad impact envelope with good alignment.

### Expected artifacts

- a fuse that is no longer proximity-shaped for direct-hit modes;
- explicit use of the authored holdoff contract;
- no ambiguity between direct-hit approval and fallback-surface approval.

### Acceptance criteria

- exposed infantry direct-hit runs no longer detonate through the legacy generic closure envelope;
- direct-hit approvals only occur by near-contact or very short predicted-impact logic;
- fallback-surface approvals remain available when justified by strike mode or fallback reason;
- the user can inspect `recentDetonations` and see a meaningful change in detonation reason patterns.

## 9. Phase 3A: Infantry and Direct-Hit Resolution Hardening

### Goal

Make open-ground infantry and other direct-hit targets resolve stable direct strike points more reliably so the runtime does not degrade into `GROUND_NEAR_TARGET` unless there is a reason to do so.

### Why this phase exists

The debug output shows repeated `GROUND_NEAR_TARGET` strikes against isolated targets. That means the direct-hit resolver is still too eager to give up on a true body strike point, which weakens lethality even if the fuse becomes stricter.

### In scope

- infantry direct-body resolution improvements;
- direct-hit sampling improvements for vehicles and statics where useful;
- cleaner separation between primary direct-hit solutions and secondary fallback-surface solutions.

### Recommended resolution policy

For `Man` targets:

- primary: torso or pelvis point with a stronger direct-body confirmation path;
- secondary: nearby body-adjacent point if the exact torso ray is noisy;
- fallback: nearby ground or obstruction surface only when direct-body confirmation is not reliable.

For `LandVehicle` and `StaticWeapon` targets:

- preserve current hull or static preference;
- only fall back to ground or obstruction when the primary surface is ambiguous or obstructed.

### Implementation tasks

1. Refine `fn_fpv_resolveImpactPoint.sqf` so infantry direct-body resolution uses a stronger direct-hit probe strategy than a single elevated point.
2. Add a body-hit helper if the resolver becomes too large, such as `fn_fpv_resolveBodyImpactPoint.sqf`.
3. Keep obstruction reuse intact.
4. Ensure the resolver still returns stable fallback output instead of nil.
5. Confirm that open-ground infantry no longer collapse routinely into `GROUND_NEAR_TARGET`.

### Expected artifacts

- more stable `DIRECT_BODY` solutions for exposed infantry;
- fewer clean open-ground runs recorded as `GROUND_NEAR_TARGET`;
- fallback-surface modes used because of real geometry ambiguity rather than weak body probing.

### Acceptance criteria

- a stationary infantry target in open ground resolves `DIRECT_BODY` consistently during committed terminal runs;
- moving or obstructed infantry may still legitimately resolve `GROUND_NEAR_TARGET` or `OBSTRUCTION_SURFACE`;
- the user can inspect `recentDetonations` and see `impactMode = DIRECT_BODY` on clean exposed infantry strikes.

## 10. Phase 3B: Delivery-Semantics Alignment for Direct and Fallback Surface Strikes

### Goal

Make detonation delivery position match the selected strike mode so intentional fallback-surface strikes do not lose lethality by bursting back at the UAV instead of the resolved surface.

### Why this phase exists

Even if the fuse becomes correct, intentional `GROUND_NEAR_TARGET` or `OBSTRUCTION_SURFACE` strikes still underperform if the warhead spawns at UAV position instead of the resolved ground or wall impact point.

### In scope

- `fn_fpv_detonateCompat.sqf` delivery semantics;
- impact-point delivery for fallback-surface modes when appropriate;
- preservation of UAV-position delivery for true emergency or failsafe bursts.

### Recommended delivery-policy changes

- `DIRECT_CONTACT` and `PREDICTED_IMPACT` should continue to use impact-point delivery.
- intentional surface modes such as `GROUND_NEAR_TARGET` and `OBSTRUCTION_SURFACE` should also use impact-point delivery when approved by their own valid surface-qualified logic.
- emergency reasons such as `MISSED_PASS_FALLBACK`, `GUIDANCE_QUALITY_DEGRADED`, `IMPACT_WINDOW_COLLAPSED`, and air-target proximity policy may retain UAV-position delivery.

### Implementation tasks

1. Refactor `fn_fpv_detonateCompat.sqf` so delivery mode is chosen from strike mode plus detonation reason, not only from direct-contact versus predicted-impact.
2. Keep the recent detonation history intact and add any missing fields needed to validate the chosen delivery mode.
3. Decide whether surface strikes should use a tiny offset along the incoming vector or the exact resolved impact point.
4. Verify that intentional ground or obstruction strikes no longer record `deliveryMode = UAV_POSITION` unless a true fallback reason requires it.

### Expected artifacts

- delivery semantics that match the reasoned strike mode;
- fewer short bursts where the drone is still several meters from the resolved ground point;
- clearer `recentDetonations` evidence for intentional surface strikes.

### Acceptance criteria

- intentional `GROUND_NEAR_TARGET` strikes can record `deliveryMode = IMPACT_POINT`;
- intentional `OBSTRUCTION_SURFACE` strikes can record `deliveryMode = IMPACT_POINT`;
- genuine emergency fallback bursts still record `deliveryMode = UAV_POSITION` when designed to do so.

## 11. Phase 4: Integrated Tuning, Locality Hardening, and Delivery Semantics Finalization

### Goal

Tune the new direct-hit policy, fallback-surface policy, and delivery semantics into one coherent and multiplayer-safe feature.

### Why this phase exists

After the backbone and the parallel branches land, the project still needs one integration phase to tune doctrine values, re-check performance and ownership safety, and ensure the new behavior is actually coherent across vendors and target classes.

### In scope

- doctrine tuning for holdoff, TTC, and direct-contact thresholds;
- per-family tuning for `armafpv`, `kvn`, and `fpv_ua`;
- performance guardrails;
- locality and cleanup checks;
- debug snapshot expectations for the new behavior.

### Recommended tuning direction

- `armafpv` should remain the sharpest direct-hit attacker and use the tightest predicted-impact window.
- `kvn` should remain slightly smoother and may tolerate a slightly longer predicted-impact window, but not a broad closure envelope for direct-hit modes.
- `fpv_ua` may remain less aggressive overall, but clean exposed infantry strikes still need to be lethal.
- direct-hit holdoff distances should be noticeably tighter than fallback-surface holdoff distances.

### Implementation tasks

1. Tune doctrine values in `fn_fpv_buildDoctrine.sqf` for direct-hit modes separately from fallback-surface modes.
2. Confirm that `terminalImpactHoldoffDistance` is now actually affecting live behavior.
3. Verify that no unbounded per-frame geometry work was introduced outside terminal phases.
4. Re-check JIP, locality transfer, cleanup, and external-control suspension.
5. Extend `fn_fpv_debugSnapshot.sqf` if any additional acceptance-facing debug data is needed.

Implementation note for the active repo state:

- `terminalImpactHoldoffDistance` is now the tighter direct-hit non-contact gate.
- `fallbackSurfaceHoldoffDistance` is now expected to be equal to or looser than `terminalImpactHoldoffDistance`, not tighter.
- `phase4IntegrationSummary` in `A3UE_fnc_fpv_debugSnapshot` is the acceptance-facing integration rollup for these tuned relationships.

### Expected artifacts

- coherent direct-hit lethality across target classes and vendors;
- preserved fallback-surface behavior where appropriate;
- impact feature remains locality-safe and performance-controlled.

### Acceptance criteria

- open-ground infantry direct-hit runs are reliably lethal on committed clean strikes;
- vehicle and static direct-hit runs no longer detonate at the same permissive envelope as before;
- fallback-surface strikes remain believable and intentional;
- debug snapshot validation warnings remain empty during healthy runs.

## 12. Phase 5: Local-LAN Acceptance and User Handoff

### Goal

Run the final acceptance matrix, finalize the user-facing validation runbook, and leave the user with a concrete LAN test procedure for confirming the corrected direct-contact lethality behavior in game.

### Why this phase exists

The feature is not complete until the user can prove, in a real local-LAN mission, that exposed targets are no longer surviving because of early closure bursts and UAV-position delivery.

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
   - exposed infantry direct-hit lethality;
   - vehicle and static direct-hit lethality;
   - obstruction-driven fallback strikes;
   - the elimination of early `GROUND_NEAR_TARGET` + `CLOSURE_QUALIFIED` + `UAV_POSITION` patterns on clean open-ground infantry strikes;
   - missed-pass and emergency fallback behavior;
   - external-control suspension;
   - JIP and locality during armed terminal runs.
3. Add any final debug snippets needed for repeatable testing.
4. Confirm the user can inspect both active impact telemetry and post-strike `recentDetonations` without editing code.

Implementation note for the active repo state:

- `phase5AcceptanceSummary` in `A3UE_fnc_fpv_debugSnapshot` is the final handoff block for LAN validation.
- It compacts validation health, recent strike evidence, direct-body evidence, delivery-health checks, and concrete next focus areas into one acceptance-facing surface.

### Expected artifacts

- a release-ready validation guide for local-LAN testing;
- documented acceptance criteria;
- clear handoff notes for future tuning.

### Acceptance criteria

- the user can follow the runbook and reproduce the corrected lethality checks on a local LAN;
- all mandatory scenarios below pass;
- no blocking defects remain in direct-hit fuse approval, infantry direct-body resolution, fallback-surface delivery, or ownership safety.

## 13. Final File and Function Target List

### Existing files expected to change

- `functions/fpv/fn_fpv_buildDoctrine.sqf`
- `functions/fpv/fn_fpv_resolveImpactPoint.sqf`
- `functions/fpv/fn_fpv_evaluateImpactWindow.sqf`
- `functions/fpv/fn_fpv_shouldDetonateNow.sqf`
- `functions/fpv/fn_fpv_detonateCompat.sqf`
- `functions/fpv/fn_fpv_debugSnapshot.sqf`
- `functions/fpv/fn_fpv_runController.sqf`
- `config.cpp`

### Existing files that may change depending on implementation detail

- `functions/fpv/fn_fpv_computeIntercept.sqf`
- `functions/fpv/fn_fpv_runTerminal.sqf`
- `functions/fpv/fn_fpv_runTerminalVector.sqf`
- `functions/fpv/fn_fpv_profileValue.sqf`
- `functions/fpv/fn_fpv_isTargetObstructed.sqf`

### New files that may be justified

- `functions/fpv/fn_fpv_resolveBodyImpactPoint.sqf`
- `functions/fpv/fn_fpv_selectImpactDeliveryMode.sqf`

These helpers are optional. Use them only if the direct-hit resolver or delivery-selection logic becomes too large to maintain cleanly.

## 14. Local-LAN Validation Runbook

This is the final user-facing validation guide. When all phases are complete, the user should be able to follow this section directly and determine whether the direct-contact lethality correction passes.

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
   - one exposed stationary infantry target in open ground;
   - one exposed moving infantry target;
   - one wheeled or tracked vehicle;
   - one static weapon or emplacement;
   - one cover object or low wall near an infantry target.

### 14.3.1 Recommended debug-spawn distances

Use these starting ranges when spawning debug sites for direct-contact lethality validation:

- `Airport`: `600m` to `800m`
- `Outpost`: `450m` to `650m`
- `Resource`: `300m` to `500m`

These distances usually leave enough room to observe `TRACKING`, `TERMINAL_ATTACK`, `TERMINAL_VECTOR`, impact resolution, fuse approval, and final detonation delivery.

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
diag_log format [
   "A3UE_FPV_VALIDATION marker_registry=%1",
   str [
      missionNamespace getVariable ["A3UE_FPV_debugMarker", ""],
      missionNamespace getVariable ["A3UE_FPV_registry", createHashMap]
   ]
];
```

Remove the current debug marker after a test pass:

```sqf
if !(isNil "A3UE_FPV_debugMarker") then {
   deleteMarker A3UE_FPV_debugMarker;
};
```

### 14.3.3 Recommended grouped execution

Do not try to run the entire validation flow for spawn, live flight, and post-strike review in one one-shot debug execution. Those checks depend on different mission states.

- Run the debug-site-marker spawn block first as its own server-side execution.
- Run the in-flight inspection block as one local execution while at least one managed drone is still alive and closing.
- Run the post-strike review block as one local execution after at least one managed drone has actually detonated and written a `recentDetonations` record.

Copy-paste block 1: spawn a debug site marker behind the player. Keep this unchanged and run it in the same server-side context you already used successfully:

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

Copy-paste block 2: run this while drones are flying. It logs the live registry, managed drones, one drone's current terminal telemetry, and the live snapshot summaries that are meaningful before detonation:

```sqf
private _managed = allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] };
private _d = _managed param [0, objNull];
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;

diag_log format [
   "A3UE_FPV_VALIDATION marker_registry=%1",
   str [
      missionNamespace getVariable ["A3UE_FPV_debugMarker", ""],
      missionNamespace getVariable ["A3UE_FPV_registry", createHashMap]
   ]
];

diag_log format [
   "A3UE_FPV_VALIDATION managed_drones=%1",
   str (_managed apply { _x getVariable ["A3UE_FPV_netId", netId _x] })
];

if (isNull _d) then {
   diag_log "A3UE_FPV_VALIDATION drone_telemetry=NO_MANAGED_DRONE";
} else {
   diag_log format [
      "A3UE_FPV_VALIDATION drone_telemetry=%1",
      str [
         typeOf _d,
         _d getVariable ["A3UE_FPV_mode", ""],
         _d getVariable ["A3UE_FPV_terminalImpactMode", ""],
         _d getVariable ["A3UE_FPV_lastImpactPointASL", []],
         _d getVariable ["A3UE_FPV_lastImpactSurfaceType", ""],
         _d getVariable ["A3UE_FPV_lastClosingDot", -2],
         _d getVariable ["A3UE_FPV_lastTimeToContact", -1],
         _d getVariable ["A3UE_FPV_lastDetonationReason", ""],
         _d getVariable ["A3UE_FPV_lastFallbackReason", ""]
      ]
   ];
};

diag_log format ["A3UE_FPV_VALIDATION validation=%1", str (_snapshot get "validation")];
diag_log format ["A3UE_FPV_VALIDATION impactSummary=%1", str (_snapshot get "impactSummary")];
diag_log format ["A3UE_FPV_VALIDATION directContactPolicy=%1", str (_snapshot get "directContactPolicy")];
diag_log format ["A3UE_FPV_VALIDATION phase1EvidenceSummary=%1", str (_snapshot get "phase1EvidenceSummary")];
diag_log format ["A3UE_FPV_VALIDATION phase4IntegrationSummary=%1", str (_snapshot get "phase4IntegrationSummary")];
diag_log format ["A3UE_FPV_VALIDATION phase5AcceptanceSummary=%1", str (_snapshot get "phase5AcceptanceSummary")];
```

Copy-paste block 3: run this after drones explode. It logs the post-strike records and the acceptance summaries that consume recent evidence:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;

diag_log format [
   "A3UE_FPV_VALIDATION marker_registry=%1",
   str [
      missionNamespace getVariable ["A3UE_FPV_debugMarker", ""],
      missionNamespace getVariable ["A3UE_FPV_registry", createHashMap]
   ]
];

diag_log format ["A3UE_FPV_VALIDATION validation=%1", str (_snapshot get "validation")];
diag_log format ["A3UE_FPV_VALIDATION impactSummary=%1", str (_snapshot get "impactSummary")];
diag_log format ["A3UE_FPV_VALIDATION recentDetonations=%1", str (_snapshot get "recentDetonations")];
diag_log format ["A3UE_FPV_VALIDATION phase1EvidenceSummary=%1", str (_snapshot get "phase1EvidenceSummary")];
diag_log format ["A3UE_FPV_VALIDATION phase4IntegrationSummary=%1", str (_snapshot get "phase4IntegrationSummary")];
diag_log format ["A3UE_FPV_VALIDATION phase5AcceptanceSummary=%1", str (_snapshot get "phase5AcceptanceSummary")];
```

### 14.4 Core validation snippets

Find all managed drones:

```sqf
private _managed = allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] };
diag_log format [
   "A3UE_FPV_VALIDATION managed_drones=%1",
   str (_managed apply { _x getVariable ["A3UE_FPV_netId", netId _x] })
];
```

Inspect one managed drone with direct-hit telemetry:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
diag_log format [
   "A3UE_FPV_VALIDATION drone_telemetry=%1",
   str [
    typeOf _d,
    _d getVariable ["A3UE_FPV_mode", ""],
    _d getVariable ["A3UE_FPV_terminalImpactMode", ""],
    _d getVariable ["A3UE_FPV_lastImpactPointASL", []],
    _d getVariable ["A3UE_FPV_lastImpactSurfaceType", ""],
    _d getVariable ["A3UE_FPV_lastClosingDot", -2],
    _d getVariable ["A3UE_FPV_lastTimeToContact", -1],
    _d getVariable ["A3UE_FPV_lastDetonationReason", ""],
    _d getVariable ["A3UE_FPV_lastFallbackReason", ""]
   ]
];
```

Inspect the validation block directly:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
diag_log format ["A3UE_FPV_VALIDATION validation=%1", str (_snapshot get "validation")];
```

Inspect the impact summary directly:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
diag_log format ["A3UE_FPV_VALIDATION impactSummary=%1", str (_snapshot get "impactSummary")];
```

Inspect recent detonation records directly:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
diag_log format ["A3UE_FPV_VALIDATION recentDetonations=%1", str (_snapshot get "recentDetonations")];
```

Inspect the direct-contact policy contract directly:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
diag_log format ["A3UE_FPV_VALIDATION directContactPolicy=%1", str (_snapshot get "directContactPolicy")];
```

Inspect the phase 1 evidence summary directly:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
diag_log format ["A3UE_FPV_VALIDATION phase1EvidenceSummary=%1", str (_snapshot get "phase1EvidenceSummary")];
```

Inspect the phase 4 integration summary directly:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
diag_log format ["A3UE_FPV_VALIDATION phase4IntegrationSummary=%1", str (_snapshot get "phase4IntegrationSummary")];
```

Inspect the phase 5 acceptance summary directly:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
diag_log format ["A3UE_FPV_VALIDATION phase5AcceptanceSummary=%1", str (_snapshot get "phase5AcceptanceSummary")];
```

### 14.4.1 Telemetry interpretation

Use the active impact telemetry fields as follows:

- `terminalImpactMode`: the currently selected strike policy for the target.
- `lastImpactPointASL`: the resolved physical strike point or fallback strike point.
- `lastImpactSurfaceType`: the kind of surface currently being used, such as `body`, `vehicle`, `ground`, `obstruction`, or `air`.
- `lastClosingDot`: the alignment of current velocity with the impact solution direction, from `-1` to `1`.
- `lastTimeToContact`: the short-horizon predicted time to contact in seconds.
- `lastDetonationReason`: the reason the drone was allowed to detonate.
- `lastFallbackReason`: why the drone fell back from direct-hit or direct-surface semantics when it did.

Because a successful strike deletes the UAV, post-strike review should use `recentDetonations` from `A3UE_fnc_fpv_debugSnapshot` rather than only inspecting a destroyed UAV object.

Healthy direct-hit behavior should generally look like this:

- exposed infantry in open ground resolve `DIRECT_BODY` during clean runs;
- `lastClosingDot` trends strongly positive during committed final closure;
- `lastTimeToContact` falls toward a very small positive value before direct-hit approval;
- `lastDetonationReason` is usually `DIRECT_CONTACT` or a very short-horizon `PREDICTED_IMPACT` on clean exposed infantry strikes;
- `CLOSURE_QUALIFIED` is not the normal clean-strike reason for exposed infantry direct-hit runs.

Healthy recent detonation records should generally look like this:

- `impactMode` is `DIRECT_BODY` on clean exposed infantry direct-hit runs;
- `detonationReason` is `DIRECT_CONTACT` or `PREDICTED_IMPACT` on those same clean runs;
- `deliveryMode` is `IMPACT_POINT` for clean direct-hit runs;
- `strikePathClass` identifies whether the record is a `DIRECT_HIT`, `FALLBACK_SURFACE`, `AIR_POLICY`, or `EMERGENCY_FALLBACK` path;
- `approvalPolicyClass` shows whether the strike used a direct-hit primary path, a surface-primary path, or an emergency fallback path;
- `policyDeliveryMode` shows the frozen phase-1 delivery expectation for that strike path;
- `deliveryPolicyMatch` shows whether the current runtime behavior matches that frozen delivery expectation;
- `knownBadPattern` should be `false` on healthy direct-hit runs;
- `deliveryMode` only remains `UAV_POSITION` for explicit emergency or failsafe bursts;
- `deliveryPosASL` sits on or extremely near the intended strike point.

### 14.4.2 Validation block interpretation

The `validation` block in `A3UE_fnc_fpv_debugSnapshot` is the structural health summary for the lethality correction.

Recommended expectations after implementation:

- `impactTelemetryMissing` stays empty.
- `staleImpactSolutions` stays empty.
- `invalidImpactModes` stays empty.
- `nonLocalImpactControllers` stays empty.
- `impactControllerOwnerMismatches` stays empty.
- `warnings` should normally be empty during healthy runs.

### 14.4.3 Impact summary interpretation

The `impactSummary` block in `A3UE_fnc_fpv_debugSnapshot` is the fast operational summary for active direct-hit and fallback-surface behavior.

- `activeNetIds` lists drones currently in `TERMINAL_ATTACK` or `TERMINAL_VECTOR`.
- `localNetIds` lists the active impact drones local to the current machine.
- `telemetryReadyNetIds` lists active impact drones with the expected impact telemetry fields populated.
- `activeVendors` and `activeSites` summarize the families and sites currently feeding impact-capable terminal runs.
- `recentDetonationCount` gives the number of retained post-strike records in `recentDetonations`.

### 14.4.4 Direct-Contact Policy Interpretation

The `directContactPolicy` block in `A3UE_fnc_fpv_debugSnapshot` is the explicit phase-1 contract freeze for the remaining lethality correction.

- `directHitModes` lists the impact modes that are expected to become true direct-hit paths.
- `fallbackSurfaceModes` lists the impact modes that remain intentional fallback-surface paths.
- `directHitPrimaryReasons`, `fallbackSurfacePrimaryReasons`, and `emergencyFallbackReasons` describe the frozen approval categories for later phases.
- `holdoffContractKey` identifies the authored doctrine key to be activated in Phase 2.
- `holdoffContractStatus` shows whether the authored holdoff contract is still phase-1 authored-only or already phase-2 enforced by the fuse.
- `holdoffEnforcedByFuse = true` means the mode-aware fuse is now consuming the authored holdoff contract.
- `supportedTuningKeys` lists the optional doctrine keys that now influence direct-hit and fallback-surface fuse behavior.
- `knownBadPattern` is the exact runtime signature this follow-on lethality correction is intended to eliminate.

### 14.4.5 Phase 1 Evidence Summary Interpretation

The `phase1EvidenceSummary` block in `A3UE_fnc_fpv_debugSnapshot` is the fast evidence rollup for the remaining failure mode.

- `recentKnownBadPatternCount` counts how many recent strikes still match the known bad `GROUND_NEAR_TARGET` + `CLOSURE_QUALIFIED` + `UAV_POSITION` signature.
- `recentDeliveryPolicyMismatchCount` counts how many recent strikes disagree with the frozen phase-1 delivery policy.
- `recentClosureQualifiedDirectHitCount` shows whether direct-hit modes are still being approved by a generic closure envelope.
- `recentClosureQualifiedFallbackSurfaceCount` shows how much of the current history is still dominated by fallback-surface closure approval.
- `holdoffConfiguredActiveCount` shows how many currently active impact drones have a positive `terminalImpactHoldoffDistance` authored in doctrine and available to the live fuse.

### 14.4.6 Phase 4 Integration Summary Interpretation

The `phase4IntegrationSummary` block in `A3UE_fnc_fpv_debugSnapshot` is the fast acceptance summary for doctrine tuning, fallback-surface delivery alignment, and active integration health.

- `activeDirectHitNetIds` lists active impact drones currently running `DIRECT_BODY`, `DIRECT_HULL`, or `DIRECT_STATIC` policies.
- `activeFallbackSurfaceNetIds` lists active impact drones currently running `GROUND_NEAR_TARGET` or `OBSTRUCTION_SURFACE` policies.
- `phase4TuningInvalidNetIds` lists active impact drones whose tuned direct-hit or fallback-surface thresholds are internally inconsistent.
- `recentDirectBodyCount` and `recentDirectBodyPrimaryCount` show whether exposed infantry strikes are increasingly resolving into `DIRECT_BODY` and actually detonating through direct-hit primary paths.
- `recentDirectHitImpactDeliveryCount` versus `recentDirectHitUavDeliveryCount` shows whether direct-hit paths are still leaking back to UAV-position delivery.
- `recentFallbackSurfaceImpactDeliveryCount` versus `recentFallbackSurfaceUavDeliveryCount` shows whether intentional surface strikes are now being delivered at the resolved surface.
- `recentSurfacePrimaryUavDeliveryCount` should trend toward zero for healthy intentional surface-strike behavior.
- `recentKnownBadPatternCount` should stop increasing on new clean exposed infantry runs.

### 14.4.7 Phase 5 Acceptance Summary Interpretation

The `phase5AcceptanceSummary` block in `A3UE_fnc_fpv_debugSnapshot` is the final LAN handoff summary for acceptance readiness and outstanding work.

- `status` is the top-level handoff state. The expected progression is `READY_FOR_LAN_RUNS`, then `NEEDS_TARGETED_LAN_VERIFICATION` while evidence accumulates, and finally `ACCEPTANCE_EVIDENCE_HEALTHY` once the recent evidence looks clean.
- `readyForLanAcceptanceRuns` means the snapshot has no structural validation blockers and the environment is safe to use for LAN testing.
- `acceptanceGateClear` means the current recent evidence supports the acceptance gate: validation is healthy, recent evidence exists, the known bad pattern is absent, direct-hit delivery is healthy, surface-primary delivery is healthy, and direct-body primary evidence exists.
- `validationHealthy` mirrors whether the general `validation` warnings are empty.
- `validationWarningCount` gives the number of structural warnings still blocking or clouding acceptance review.
- `recentEvidenceAvailable` shows whether the user has actually generated recent detonation evidence in the current session.
- `knownBadPatternCleared` shows whether recent strikes have stopped matching the bad `GROUND_NEAR_TARGET` plus `CLOSURE_QUALIFIED` plus `UAV_POSITION` signature.
- `directHitDeliveryHealthy` shows whether recent direct-hit records are staying on impact-point delivery.
- `surfaceDeliveryHealthy` shows whether recent intentional surface-primary strikes are staying on impact-point delivery.
- `directBodyEvidenceAvailable` and `directBodyPrimaryEvidenceAvailable` show whether the session has recent exposed-infantry direct-body evidence, not just generic strike evidence.
- `phase4TuningInvalidCount` shows whether any currently active impact drones still have invalid phase-4 tuning relationships.
- `focusAreas` gives the concrete next checks to run if the acceptance gate is not yet clear.

### 14.5 Acceptance scenarios

#### Scenario 1: Soft-dependency boot safety unchanged

Steps:

1. Launch with Antistasi Ultimate and the extender only.
2. Start the mission and activate at least one supported site type.

Expected result:

- no script errors occur;
- no FPV drones spawn;
- the lethality correction does not create behavior when no supported family is loaded.

#### Scenario 2: Exposed infantry direct-hit lethality

Steps:

1. Place or expose a stationary infantry target in open ground.
2. Allow a managed FPV drone to progress into `TERMINAL_ATTACK` and `TERMINAL_VECTOR`.
3. Observe the final seconds and inspect `recentDetonations` after the strike.

Expected result:

- the drone descends into the target rather than detonating several meters short by a generic closure envelope;
- `impactMode` resolves to `DIRECT_BODY` or a clearly documented equivalent direct-hit mode;
- `detonationReason` is `DIRECT_CONTACT` or `PREDICTED_IMPACT` rather than the previous generic `CLOSURE_QUALIFIED` pattern;
- `deliveryMode` is `IMPACT_POINT`;
- the strike is reliably lethal against the exposed stationary player.

#### Scenario 3: Infantry moving-target fallback discipline

Steps:

1. Use a moving infantry target or one whose body point is difficult to strike cleanly.
2. Observe whether the runtime degrades to a ground or obstruction strike only when justified.

Expected result:

- the system may intentionally choose `GROUND_NEAR_TARGET` or `OBSTRUCTION_SURFACE` when the direct-body path is not credible;
- the chosen strike mode and delivery mode remain explainable in `recentDetonations`.

#### Scenario 4: Vehicle hull strike

Steps:

1. Present a car, APC, or tank in open terrain.
2. Allow the drone to run the full terminal sequence.

Expected result:

- the drone aims at a believable hull or roof solution rather than hovering above vehicle center;
- direct-hit semantics are used when closure is good;
- `deliveryMode` is `IMPACT_POINT` for clean direct or predicted hull strikes.

#### Scenario 5: Static weapon or emplacement strike

Steps:

1. Present a static weapon with or without crew.
2. Observe impact resolution and final strike behavior.

Expected result:

- the drone chooses a believable static-emplacement strike point;
- clean direct-static runs do not revert to the same permissive closure envelope used before.

#### Scenario 6: Cover or obstruction fallback strike

Steps:

1. Place infantry behind a low wall, vehicle, sandbag line, or other obvious obstruction.
2. Allow the drone to enter terminal phases.

Expected result:

- the drone can choose `OBSTRUCTION_SURFACE` or `GROUND_NEAR_TARGET` rather than simply airbursting above cover;
- `recentDetonations` shows an explicit fallback-surface path;
- if surface strikes are intended to be impact-delivered, `deliveryMode` becomes `IMPACT_POINT` there as well.

#### Scenario 7: Above-player regression check

Steps:

1. Present a stationary infantry player on open ground.
2. Observe the final armed window closely.

Expected result:

- the drone does not detonate several meters above or short of the player simply because a generic closure envelope is satisfied;
- if the strike is clean, it continues into a direct-hit near-contact or very short predicted-impact path.

#### Scenario 8: Missed-pass and emergency fallback behavior

Steps:

1. Force a bad terminal entry or a missed pass if practical.
2. Observe whether the drone falls back cleanly into an emergency burst or lost-target transition.

Expected result:

- the drone does not get stuck hovering or endlessly circling in armed state;
- emergency fallback bursts still work;
- `recentDetonations` records an explicit fallback reason and may still use `UAV_POSITION` delivery when designed to do so.

#### Scenario 9: External control suspension during armed terminal run

Steps:

1. Take direct UAV control or Zeus remote control while the drone is in `TERMINAL_ATTACK` or `TERMINAL_VECTOR`.
2. Observe state changes and telemetry.

Expected result:

- autonomous impact logic stops cleanly;
- the controller returns to safe suspension behavior;
- no stale armed direct-hit state persists after player or Zeus control takes over.

#### Scenario 10: JIP and locality during armed terminal impact behavior

Steps:

1. Let a drone enter an armed terminal run.
2. Join a second LAN client while terminal impact behavior is already active.
3. If available, force ownership migration to a headless client.

Expected result:

- only the current owner continues owner-local impact resolution, fuse evaluation, and steering;
- late joiners observe telemetry and detonation history but do not drive control;
- validation warnings stay empty for impact-locality and owner mismatch.

### 14.6 Final acceptance rule

The direct-contact lethality correction is accepted only when:

- all mandatory scenarios above pass;
- clean exposed infantry direct-hit runs no longer produce the repeated `GROUND_NEAR_TARGET` + `CLOSURE_QUALIFIED` + `UAV_POSITION` signature seen in the current debug evidence;
- no blocking defects remain in direct-hit fuse approval, infantry direct-body resolution, fallback-surface delivery, or ownership safety;
- the user can reproduce the checks on a local LAN using the documented telemetry and runbook.

## 15. User Handoff Summary

When all phases are complete, the user should be left with:

- the implemented direct-contact lethality correction in code;
- `docs/fpv-targeting-chase-pathing-analysis.md` as the broad analysis reference;
- `docs/FPV_Impact_First_Implementation_Phases.md` as the broader impact-first redesign reference;
- this document as the execution and validation reference for correcting the remaining early-detonation and low-lethality behavior;
- a local-LAN runbook that proves exposed infantry, vehicles, and statics are no longer surviving because of permissive closure bursts and UAV-position delivery.

At that point, the remaining lethality issue should be fully implemented and validated rather than left as an informal tuning concern.