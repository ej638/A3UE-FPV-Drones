# FPV Direct-Contact Lethality RCA Follow-Up

Date: 2026-05-11
Source evidence: staged local-LAN RPT review through the final 2026-05-11 single-resource-drone rerun

## Summary

The initial validation runs showed that the fuse-hardening and delivery-alignment work was behaving correctly, but the exposed-infantry direct-hit acceptance gate was still failing. The final single-resource-drone rerun now clears that gate.

What the final rerun confirms:

- no FPV script errors were observed in the reviewed RPT segment;
- live terminal telemetry reached `DIRECT_BODY` during the attack run;
- `recentDetonations` now records a true direct-hit strike with `strikePathClass = DIRECT_HIT`, `impactMode = DIRECT_BODY`, `approvalPolicyClass = DIRECT_HIT_PRIMARY`, and `detonationReason = PREDICTED_IMPACT`;
- `phase5AcceptanceSummary` now reports `acceptanceGateClear = true`, `directBodyEvidenceAvailable = true`, `directBodyPrimaryEvidenceAvailable = true`, `focusAreas = []`, and `status = ACCEPTANCE_EVIDENCE_HEALTHY`.

What the final rerun also suggests about the Resource-site behavior you observed:

- yes, the delayed turn-in is consistent with the Resource doctrine using a smaller acquisition/search envelope than Airport;
- while no target is acquired, the controller remains in `SEARCHING` and `holdPattern`, which matches the drone circling its spawn area before you moved closer.

What is now confirmed healthy:

- no FPV script errors were observed in the reviewed RPT segment;
- `validation` remained structurally clean with empty warnings and no locality, ownership, or telemetry integrity failures;
- the old bad pattern `GROUND_NEAR_TARGET` + `CLOSURE_QUALIFIED` + `UAV_POSITION` did not recur;
- fallback-surface strikes are now delivered at the resolved impact point, not at UAV position;
- the post-strike summaries correctly retained four recent detonation records.

What is still failing acceptance:

- all recorded strikes remained on the fallback-surface path rather than a direct-hit path;
- `recentDirectHitCount = 0` and `recentDirectBodyCount = 0` for the reviewed session;
- `phase5AcceptanceSummary` remained `NEEDS_TARGETED_LAN_VERIFICATION` with `acceptanceGateClear = false`;
- the session produced lethality, but not through the intended exposed-infantry `DIRECT_BODY` path.

What the new Phase A and flat-field follow-up evidence now proves:

- the infantry body rays do hit the target geometry in open ground;
- obstruction state is clean in the flat-field case, with `blocked = false`, `terrainBlocked = false`, and `obstructionCount = 0`;
- the remaining failure is a resolver control-flow bug, not a failed body trace or a false obstruction classification.

Post-fix review result from the subsequent rerun:

- the first Phase D fix improved behavior but did not clear acceptance;
- early validation snapshots now show `DIRECT_BODY` in live telemetry, which means the original top-level resolver fallthrough was real and was partially corrected;
- the reviewed post-fix RPT still does not pass because active terminal snapshots and retained detonation records still end on `GROUND_NEAR_TARGET` with fallback-surface `CLOSURE_QUALIFIED` strikes;
- a second helper-level control-flow bug was identified in `_resolveDirectBodySolution` and has now been patched as the next local fix.

## Final Verification Outcome

The final single-resource-drone rerun passes acceptance.

Accepted evidence from the reviewed RPT:

- `marker_registry` shows a single `Resource` site with one managed drone and a clean transition to `depleted` after detonation;
- live snapshots progress from `SEARCHING` to `TRACKING` and then to `TERMINAL_VECTOR` with `terminalImpactMode = DIRECT_BODY`;
- `recentDetonations` records one strike with `strikePathClass = DIRECT_HIT`, `impactMode = DIRECT_BODY`, `deliveryMode = IMPACT_POINT`, `approvalPolicyClass = DIRECT_HIT_PRIMARY`, `fallbackReason = NONE`, and `detonationReason = PREDICTED_IMPACT`;
- `phase1EvidenceSummary` now reports `recentDirectHitCount = 1` and `recentClosureQualifiedFallbackSurfaceCount = 0`;
- `phase4IntegrationSummary` now reports `recentDirectBodyCount = 1`, `recentDirectBodyPrimaryCount = 1`, and `recentDirectHitImpactDeliveryCount = 1`;
- `phase5AcceptanceSummary` now reports `acceptanceGateClear = true` and `status = ACCEPTANCE_EVIDENCE_HEALTHY`.

This means the direct-body resolver path, fuse approval, and impact-point delivery are now aligned in the accepted exposed-infantry case.

### Resource-Site Search Behavior

The Resource-site behavior you described is consistent with the authored doctrine rather than a defect.

Relevant implementation details:

- [../functions/fpv/fn_fpv_runController.sqf](../functions/fpv/fn_fpv_runController.sqf#L251) keeps the drone in `SEARCHING` with `holdPattern` until `selectTarget` returns a hostile target;
- [../functions/fpv/fn_fpv_selectTarget.sqf](../functions/fpv/fn_fpv_selectTarget.sqf#L25) scans around the site marker using `searchRadius` and also around the UAV using `localSearchRadius`;
- [../functions/fpv/fn_fpv_buildDoctrine.sqf](../functions/fpv/fn_fpv_buildDoctrine.sqf#L241) gives `Resource` sites a smaller search envelope than `Airport`: `searchRadius = 500` and `localSearchRadius = 220` for `Resource`, versus `searchRadius = 900` and `localSearchRadius = 320` for `Airport`.

So yes: using a `Resource` site can require you to be closer before acquisition happens, and the initial loiter/search pattern you saw is expected until you enter that smaller search envelope.

## RPT Assessment

### Healthy validation surfaces

`marker_registry`

- Healthy.
- The debug site registered correctly.
- The site transitioned from `active` with live drone refs to `depleted` after all drones detonated.

`managed_drones`

- Healthy.
- During the live-flight capture, three managed drones were still active, which matches the registry state after one earlier detonation.

`validation`

- Healthy.
- No duplicate net IDs, orphaned drones, missing registry links, non-local controllers, stale impact telemetry, invalid impact modes, or owner mismatches were reported.
- This argues against a locality or synchronization defect being the reason for the remaining lethality issue.

`impactSummary`

- Healthy.
- In-flight capture showed `activeCount = 3`, `localCount = 3`, and `telemetryReadyCount = 3`.
- Post-strike capture correctly dropped to zero active impact drones and retained `recentDetonationCount = 4`.

`directContactPolicy`

- Healthy.
- The policy block confirms the intended contract is live: `holdoffEnforcedByFuse = true` and `holdoffContractStatus = ENFORCED_MODE_AWARE`.

`phase1EvidenceSummary`

- Mixed, but internally consistent.
- Good news: `recentKnownBadPatternCount = 0` and `recentDeliveryPolicyMismatchCount = 0`.
- Remaining issue: `recentDirectHitCount = 0` and `recentClosureQualifiedFallbackSurfaceCount = 4` after all detonations.

`phase4IntegrationSummary`

- Mixed.
- Good news: `phase4TuningInvalidNetIds = []`, `recentFallbackSurfaceUavDeliveryCount = 0`, and `recentSurfacePrimaryUavDeliveryCount = 0`.
- Remaining issue: `recentDirectBodyCount = 0`, `recentDirectBodyPrimaryCount = 0`, and `recentDirectHitImpactDeliveryCount = 0`.

`phase5AcceptanceSummary`

- Not accepted yet.
- Good news: `readyForLanAcceptanceRuns = true`, `validationHealthy = true`, `knownBadPatternCleared = true`, `directHitDeliveryHealthy = true`, and `surfaceDeliveryHealthy = true`.
- Failing acceptance conditions: `directBodyEvidenceAvailable = false`, `directBodyPrimaryEvidenceAvailable = false`, and `status = NEEDS_TARGETED_LAN_VERIFICATION`.

### Live-flight telemetry finding

The live telemetry sample already showed the problem before detonation:

- `mode = TERMINAL_ATTACK`
- `terminalImpactMode = GROUND_NEAR_TARGET`
- `lastImpactSurfaceType = ground`
- `lastDetonationReason = NONE`
- `lastFallbackReason = NONE`

That means the direct-hit path was already lost during impact resolution, before fuse approval and detonation delivery happened.

### Post-strike evidence finding

The retained detonation records show the new runtime pattern is:

- `strikePathClass = FALLBACK_SURFACE`
- `approvalPolicyClass = SURFACE_PRIMARY`
- `impactMode = GROUND_NEAR_TARGET`
- `detonationReason = CLOSURE_QUALIFIED`
- `deliveryMode = IMPACT_POINT`
- `knownBadPattern = false`

This is a meaningful improvement over the old failure signature because delivery semantics now match the fallback-surface path. It also explains why Petros and the player could still be killed even without a direct-body path.

## Interpretation

### What passed

The following problem appears solved in this run:

- direct/fallback policy wiring is active;
- the known bad UAV-position delivery regression is gone;
- structural multiplayer and telemetry validation passed;
- fallback-surface strikes can now be lethal because they burst at the resolved impact point.

### What did not pass

The exposed-infantry direct-hit acceptance target did not pass.

The evidence is now too consistent to treat this as random tuning noise:

- 4 of 4 retained strike records used `GROUND_NEAR_TARGET`;
- 4 of 4 retained strike records used `CLOSURE_QUALIFIED` as the fallback-surface primary approval;
- 0 of 4 retained strike records used `DIRECT_BODY`;
- 0 of 4 retained strike records used `DIRECT_CONTACT` or `PREDICTED_IMPACT`.

The remaining issue is therefore not “generic acceptance testing still needed”. The remaining issue is a specific technical failure to keep open-ground infantry on the direct-body resolution path.

## Likely Controlling Code Path

The most likely controlling failure is in [../functions/fpv/fn_fpv_resolveImpactPoint.sqf](../functions/fpv/fn_fpv_resolveImpactPoint.sqf#L203).

Current resolver behavior for infantry is:

1. For `Man` targets, the resolver selects `DIRECT_BODY` as the desired mode.
2. It builds torso, lead-torso, and pelvis candidate points.
3. It tries to confirm one of those candidates with `_resolveDirectBodySolution`.
4. If all candidates fail, it exits directly to `GROUND_NEAR_TARGET`.

The actual fallback exit is in [../functions/fpv/fn_fpv_resolveImpactPoint.sqf](../functions/fpv/fn_fpv_resolveImpactPoint.sqf#L263).

The fuse path in [../functions/fpv/fn_fpv_evaluateImpactWindow.sqf](../functions/fpv/fn_fpv_evaluateImpactWindow.sqf#L176) then behaves as designed:

- `GROUND_NEAR_TARGET` is allowed to detonate through fallback-surface `CLOSURE_QUALIFIED`;
- fallback-surface delivery is then written as `IMPACT_POINT`;
- this removes the old short-airburst behavior, but it does not prove the direct-body resolver is working.

## Phase B/C Result

The flat-field follow-up run is sufficient to complete Phase C.

The new resolver trace does not support the earlier geometry or obstruction hypotheses. For the same UAV and the same infantry target in open ground, the RPT now shows all of the following at once:

- `_desiredMode = DIRECT_BODY`;
- `blocked = false`, `terrainBlocked = false`, and `obstructionCount = 0`;
- all three body candidates record `TARGET_HIT` against the infantry target;
- the same UAV and target then still produce a later `GROUND_NEAR_TARGET` final solution and ultimately a `FALLBACK_SURFACE` detonation record.

That combination rules out the main earlier hypotheses for the flat-field case:

1. the body rays are not missing the infantry geometry;
2. open-ground obstruction classification is not suppressing the body path;
3. the candidate offsets are good enough to reach the infantry geometry.

The actual failure is a resolver control-flow bug in [../functions/fpv/fn_fpv_resolveImpactPoint.sqf](../functions/fpv/fn_fpv_resolveImpactPoint.sqf#L245).

Specifically:

1. the `DIRECT_BODY` branch successfully computes a direct-body solution;
2. the nested `if (_directBodyResolution param [0, false]) exitWith { ... };` exits only that local `then` scope;
3. the function then continues and later reaches the fallback branch at [../functions/fpv/fn_fpv_resolveImpactPoint.sqf](../functions/fpv/fn_fpv_resolveImpactPoint.sqf#L308);
4. that fallback branch overwrites the resolved direct-body result with `GROUND_NEAR_TARGET`.

The alternating Phase A trace lines from the same UAV and target make this visible directly: one line reports a valid `DIRECT_BODY` solution with `TARGET_HIT`, and the immediately following line reports `GROUND_NEAR_TARGET` for the same evaluation context.

For the flat-field case, the root cause is therefore classified. No additional Phase C testing is required before the code fix.

## Required Next Step

Phase D is now the required next step.

Reason:

- the new runtime now shows successful direct-body resolution being discarded by control flow;
- additional broad LAN testing before the fix would mostly reproduce more fallback-surface records without adding meaningful diagnostic value.

Additional LAN testing is still useful after the resolver control-flow fix lands.

## Post-Fix Review

The provided post-fix RPT does not pass the direct-body acceptance gate yet.

What improved:

- early validation snapshots now show `drone_telemetry` with `terminalImpactMode = DIRECT_BODY`;
- the Phase A resolver trace still shows clean `TARGET_HIT` results for all three infantry body candidates with `blocked = false` and no obstruction evidence.

What still fails:

- later live terminal snapshots still show `terminalImpactMode = GROUND_NEAR_TARGET`;
- retained `recentDetonations` still show `strikePathClass = FALLBACK_SURFACE`, `impactMode = GROUND_NEAR_TARGET`, and `detonationReason = CLOSURE_QUALIFIED`;
- `recentDirectHitCount`, `recentDirectBodyCount`, and `recentDirectBodyPrimaryCount` remain zero, so `phase5AcceptanceSummary` still reports `acceptanceGateClear = false`.

The new controlling defect found during this review is another local control-flow bug in [../functions/fpv/fn_fpv_resolveImpactPoint.sqf](../functions/fpv/fn_fpv_resolveImpactPoint.sqf).

Specifically:

1. `_resolveDirectBodySolution` used `exitWith` inside the `forEach` candidate loop;
2. that exited the loop body but still left the helper returning its default `[false, createHashMap]` result;
3. the outer resolver therefore continued into later logic, which could still oscillate between a later `DIRECT_BODY` primary-point hit and `GROUND_NEAR_TARGET` fallback;
4. the alternating `A3UE_FPV_RCA directBodyResolve=` lines in the reviewed RPT are consistent with that remaining helper-level fallthrough.

That helper-level bug has now been patched by storing the resolved candidate result in a local variable and returning it after the loop.

### Downed Player Note

The player being downed by the first drone is probably not the primary controlling cause of the failure shown in this RPT.

Reason:

- the alternating `DIRECT_BODY` and `GROUND_NEAR_TARGET` resolver outcomes already indicate a code-path inconsistency before acceptance can be claimed;
- even in the reviewed terminal traces, candidate body rays continue to report `TARGET_HIT`, which argues against the downed state being the sole explanation.

However, the downed state can still add noise to follow-up testing because stance, animation, and target presentation can change after the first blast. For the next rerun, use either a single-drone pass per reset or restore the target to a fresh standing state after each impact so the verification stays discriminating.

## RCA Plan

### Phase A: Instrument the resolver

Add temporary debug output in [../functions/fpv/fn_fpv_resolveImpactPoint.sqf](../functions/fpv/fn_fpv_resolveImpactPoint.sqf) for `Man` targets only.

Capture at minimum:

- chosen `_desiredMode`;
- `_targetObstructed`, `terrainBlocked`, and `obstructionCount` from [../functions/fpv/fn_fpv_isTargetObstructed.sqf](../functions/fpv/fn_fpv_isTargetObstructed.sqf#L1);
- the three direct-body candidate points;
- for each candidate, whether `_traceSurface` returned no hits, target hits, or third-party obstruction hits;
- the final resolver reason string, especially whether it ended as `DIRECT_BODY_HIT`, `DIRECT_BODY_CLEAR_PATH`, `OBSTRUCTION_PRIMARY`, `OBSTRUCTION_REUSED`, or `GROUND_NEAR_TARGET`.

### Phase B: Run a narrow discriminating test set

Do not rerun the full scenario matrix yet. Run only these targeted infantry cases:

1. Petros stationary in truly open ground.
2. Player stationary in truly open ground.
3. Player slightly masked by thin trees, matching the kill you observed.

The goal is to find whether the resolver fails even in the clean open-ground cases, or only when vegetation and partial occlusion are present.

### Phase C: Classify the actual failure mode

Phase C is complete for the flat-field exposed-infantry case.

Classification result:

1. target body rays are hitting the target geometry;
2. obstruction detection is not falsely blocking the flat-field case;
3. the remaining defect is a resolver fallthrough bug that discards the successful `DIRECT_BODY` result and replaces it with `GROUND_NEAR_TARGET`.

### Phase D: Fix the resolver, not the fuse

The immediate fix should be a resolver control-flow correction in [../functions/fpv/fn_fpv_resolveImpactPoint.sqf](../functions/fpv/fn_fpv_resolveImpactPoint.sqf).

Most likely fix direction:

- restructure the `DIRECT_BODY` success branch so a successful direct-body solution returns from the function rather than only exiting the nested local scope;
- preserve the later `GROUND_NEAR_TARGET` fallback only for true direct-body failure cases.

Follow-up fix that was also required after the post-fix review:

- make `_resolveDirectBodySolution` persist and return a successful candidate result after the `forEach` loop instead of always falling back to its default false result.

Do not broaden the direct-hit fuse envelope again to force acceptance. The fuse and delivery paths are already behaving consistently with the authored policy.

### Phase E: Revalidate with the same evidence surfaces

After the resolver fix, rerun the same three validation blocks and confirm:

- in-flight telemetry shows `terminalImpactMode = DIRECT_BODY` for clean open-ground infantry;
- `recentDetonations` includes `impactMode = DIRECT_BODY`;
- `detonationReason` becomes `DIRECT_CONTACT` or `PREDICTED_IMPACT` on those clean runs;
- `phase5AcceptanceSummary` clears its current direct-body focus areas.

## Secondary Note

The RPT also contains Antistasi warnings from `A3A_fnc_NATOinit` about the spawned `B_UAV_AI` FPV vehicle type not having an assigned type.

Current assessment:

- this did not correlate with the direct-body failure in the reviewed run;
- it is not the blocking issue for the current lethality acceptance gate;
- it can be tracked separately unless later evidence shows it affects target classification, side handling, or site-spawn behavior.

## Exit Criteria For This Follow-Up

This follow-up is now complete because the final validation run shows both of these:

1. structural validation remains clean as it is now;
2. clean exposed infantry runs produce recent `DIRECT_BODY` evidence and direct-hit primary approvals rather than only fallback-surface records.