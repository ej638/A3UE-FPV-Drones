# FPV Terminal Vector Smoothing Implementation Phases

Date: 2026-05-08
Primary design references: `docs/FPV_Aggression_Implementation_Plan.md`, `docs/FPV_Aggression_Implementation_Phases.md`
Purpose: Break the terminal-vector acceleration smoothing redesign into implementation phases that can be executed sequentially or in parallel, with explicit dependencies, deliverables, validation gates, and a final local-LAN in-game validation runbook for the user.

## 1. Delivery Goal

This focused phase plan is complete only when all of the following are true:

- `TERMINAL_VECTOR` no longer snaps instantly to full speed on entry;
- the final strike window still feels aggressive and predatory rather than passive or floaty;
- terminal vector steering remains owner-local and locality-safe;
- doctrine separates AI terminal closure speed from direct vector-control speed policy;
- direct velocity control uses acceleration-limited speed changes rather than full-speed jumps;
- handoff from `TERMINAL_ATTACK` into `TERMINAL_VECTOR` is visibly continuous in speed and heading;
- missed-pass recovery and `LOST_TARGET` behavior still work after the smoothing refactor;
- debug snapshot output exposes enough telemetry to validate entry speed, target speed, acceleration clamp behavior, and ownership state;
- multiplayer safety, cleanup behavior, JIP, and locality migration remain intact;
- the user is left with a detailed local-LAN validation procedure that can confirm the smoothing fix in game.

## 2. Current-State Diagnosis

The current final-dive behavior is not just a tuning issue. It is a control-law issue.

### What the current code is doing

- `TERMINAL_ATTACK` uses AI-guided closure in `fn_fpv_runTerminal.sqf` with `forceSpeed` and `doMove`.
- the controller hands off to `TERMINAL_VECTOR` once the target is inside `terminalSteeringDistance`.
- `TERMINAL_VECTOR` updates at `0.01s` cadence.
- `fn_fpv_runTerminalVector.sqf` computes a desired direction and then immediately applies:
  - `forceSpeed _terminalSpeed`
  - `setVectorDirAndUp`
  - `setVelocity _desiredVelocity`

### Why the dive feels like an instant lunge

The visible "zoom" effect is caused by the stack of these design choices:

1. vector steering begins close to the target;
2. the update loop runs at very high frequency;
3. direction is re-vectorized immediately;
4. speed is set directly to the full terminal target rather than ramped;
5. the same `terminalSpeed` value is being used across:
   - terminal intercept prediction;
   - AI terminal closure;
   - raw vector-control velocity magnitude.

### Architectural conclusion

The correct fix is not "just lower terminal speed".

The correct fix is:

- preserve the current state split between `TERMINAL_ATTACK` and `TERMINAL_VECTOR`;
- separate speed semantics by control regime;
- keep direct vector steering, but make it acceleration-limited;
- optionally gate acceleration by alignment and distance so the drone still feels deliberate and aggressive.

## 3. Solution Summary

The intended redesign is:

- keep `TERMINAL_ATTACK` as coarse AI closure;
- keep `TERMINAL_VECTOR` as owner-local direct steering;
- split the current one-number `terminalSpeed` concept into regime-specific keys;
- replace direct full-speed velocity assignment with a speed command that ramps from current speed toward a target speed using configured acceleration and deceleration limits;
- preserve aggressive turn authority while smoothing speed buildup.

## 4. Recommended Delivery Model

The safest delivery model is a sequential backbone with one controlled parallel split.

### Sequential backbone

1. Phase 1: Terminal Speed Contract and Doctrine Scaffolding
2. Phase 2: Acceleration-Limited Terminal Vector Core
3. Phase 4: Family Tuning, Multiplayer Hardening, and Integration
4. Phase 5: Local-LAN Acceptance and User Handoff

### Parallel-capable branches

After Phase 2, the work can split into two parallel branches:

- Phase 3A: Handoff and Speed-Schedule Integration
- Phase 3B: Telemetry and Validation Surfaces

These branches can proceed in parallel only if the team freezes the following contracts first:

- the doctrine keys for terminal vector speed and acceleration behavior;
- the telemetry variable names written on the UAV;
- the owner-local control contract for `TERMINAL_VECTOR`;
- the handoff variable names used when entering and exiting vector mode.

### Final integration order

- Phase 3A and Phase 3B must both merge before Phase 4 is treated as complete.
- Phase 4 must merge before final LAN acceptance begins.
- Phase 5 is the release gate. Do not treat the smoothing feature as complete until Phase 5 passes.

## 5. Dependency Summary

| Phase | Title | Depends On | Can Run In Parallel With | Completion Outcome |
| --- | --- | --- | --- | --- |
| 1 | Terminal Speed Contract and Doctrine Scaffolding | None | None | Separate doctrine keys exist for AI closure speed, vector entry speed, vector max speed, and accel or decel policy |
| 2 | Acceleration-Limited Terminal Vector Core | 1 | None | `TERMINAL_VECTOR` no longer snaps instantly to max speed and instead ramps speed using current velocity and configured limits |
| 3A | Handoff and Speed-Schedule Integration | 2 | 3B | Entry into vector mode is smooth, alignment-aware, and distance-aware |
| 3B | Telemetry and Validation Surfaces | 2 | 3A | Debug snapshot and UAV telemetry can prove whether speed continuity and clamp behavior are working |
| 4 | Family Tuning, Multiplayer Hardening, and Integration | 3A, 3B | None | The smoothing behavior is tuned per family and site and remains locality-safe in MP |
| 5 | Local-LAN Acceptance and User Handoff | 4 | None | The feature is fully implemented, validated, and documented for local-LAN acceptance |

## 6. Phase Standards

Every phase should end with these artifacts:

- implemented code or documentation for the phase scope;
- a short completion note describing what changed;
- a list of known limitations still expected before later phases;
- a validation record showing the phase gate passed.

Every phase should also respect these engineering rules:

- no hard dependency may be added for ArmaFPV, fpv_ua, or frtz_fiberoptic_kvn;
- owner-local vector steering remains the source of truth during `TERMINAL_VECTOR`;
- `config.cpp` `CfgFunctions` must stay in sync with any new helper files;
- existing public names must remain stable unless a rename is explicitly approved;
- `terminalSpeed` should remain a backward-compatible fallback until migration to the new regime-specific keys is complete;
- no phase should solve the issue by only reducing aggression globally;
- no phase should remove direct vector steering and fall back entirely to AI `doMove`.

## 7. Phase 1: Terminal Speed Contract and Doctrine Scaffolding

### Goal

Create a stable doctrine contract that separates AI terminal closure speed from direct vector-control speed and acceleration policy.

### Why this phase exists

The current architecture reuses one `terminalSpeed` key across multiple control regimes that behave differently. That makes tuning brittle and makes terminal-vector snap almost impossible to solve cleanly.

### In scope

- new terminal-vector doctrine keys;
- backward-compatible fallback rules;
- profile resolution support for the new keys;
- explicit speed-domain policy;
- no behavior change yet beyond resolving new keys.

### Recommended doctrine keys

At minimum, add support for these keys:

- `terminalAttackSpeed`
- `terminalVectorEntrySpeed`
- `terminalVectorMaxSpeed`
- `terminalVectorAccel`
- `terminalVectorDecel`
- `terminalVectorFullAccelAlignment`
- `terminalVectorMinAccelAlignment`
- `terminalVectorInnerFuseSlowdownDistance`
- `terminalVectorInnerFuseMinSpeed`

Optional but useful keys:

- `terminalVectorRampDistance`
- `terminalVectorTurnBlendMin`
- `terminalVectorTurnBlendMax`
- `terminalVectorSpeedLagTolerance`

### Speed-domain policy

Use this rule consistently:

- doctrine should continue authoring speed values in the same airframe-speed budget domain currently used by `trackingSpeed` and `terminalSpeed`;
- raw physics velocity should be derived from those values only at the vector-control boundary;
- no direct control function should interpret an authored doctrine speed as an instruction to jump immediately to that speed on the first frame.

### Recommended starting baselines

These are starting points, not final tuned values.

| Family | terminalAttackSpeed | terminalVectorEntrySpeed | terminalVectorMaxSpeed | terminalVectorAccel | terminalVectorDecel |
| --- | ---: | ---: | ---: | ---: | ---: |
| `armafpv` | `150 - 170` | `118 - 132` | `170 - 182` | `32 - 42` | `40 - 52` |
| `kvn` | `120 - 136` | `102 - 114` | `128 - 140` | `24 - 32` | `30 - 40` |
| `fpv_ua` | `98 - 112` | `88 - 98` | `104 - 116` | `18 - 26` | `22 - 30` |

The main point is not the exact numbers. The main point is that `terminalVectorEntrySpeed` and `terminalVectorMaxSpeed` are not the same thing.

### Implementation tasks

1. Extend `fn_fpv_buildDoctrine.sqf` to resolve the new terminal-vector keys.
2. Preserve the existing `terminalSpeed` key as a temporary fallback.
3. Define fallback rules so old doctrine does not break during rollout:
   - if `terminalAttackSpeed` is missing, fall back to `terminalSpeed`;
   - if `terminalVectorEntrySpeed` is missing, derive it from `terminalAttackSpeed`;
   - if `terminalVectorMaxSpeed` is missing, fall back to `terminalSpeed`;
   - if accel or decel keys are missing, derive safe family defaults.
4. Update `fn_fpv_getProfile.sqf` and any profile-resolution logic needed to surface the new keys.
5. Decide whether `terminalSteeringDistance` should remain unchanged for initial rollout or receive a temporary conservative increase to create more visible ramp distance.

### Expected artifacts

- a doctrine contract that distinguishes AI closure speed from vector speed behavior;
- backward-compatible profile resolution;
- no functional change yet to terminal-vector motion law.

### Validation gate

- all supported site-family-role combinations resolve the new keys or derive them cleanly;
- legacy doctrine still resolves without script errors;
- the debug console can inspect the resolved profile and show the new speed keys.

### Suggested debug-console checks

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
private _profile = [_d] call A3UE_fnc_fpv_getProfile;
hint str [
    _profile getOrDefault ["terminalAttackSpeed", -1],
    _profile getOrDefault ["terminalVectorEntrySpeed", -1],
    _profile getOrDefault ["terminalVectorMaxSpeed", -1],
    _profile getOrDefault ["terminalVectorAccel", -1],
    _profile getOrDefault ["terminalVectorDecel", -1]
];
```

### Parallelization note

No parallel work should start before this phase completes. It defines the data contract for the rest of the smoothing redesign.

### Exit criteria

- the doctrine contract is explicit and backward-compatible;
- the codebase no longer relies on a single overloaded `terminalSpeed` concept for future terminal-vector tuning.

## 8. Phase 2: Acceleration-Limited Terminal Vector Core

### Goal

Replace the current instant full-speed vector controller with an acceleration-limited vector controller that ramps from current velocity toward a desired speed.

### Why this phase exists

This is the actual root-cause fix. Without this phase, the system still behaves like a velocity snap controller, even if doctrine numbers are moved around.

### In scope

- speed ramping inside `TERMINAL_VECTOR`;
- current-speed capture and time-step handling;
- acceleration and deceleration clamping;
- direct vector steering preserved;
- AI suppression and restoration preserved.

### Recommended control-law shape

Per vector tick:

1. compute the desired aim direction;
2. compute the desired speed from doctrine and state;
3. measure current speed from the current velocity vector;
4. clamp speed change using `terminalVectorAccel` or `terminalVectorDecel` multiplied by `dt`;
5. apply the smoothed velocity instead of an immediate max-speed jump.

Conceptually:

$$
v_{next} = v_{current} + \operatorname{clamp}(v_{desired} - v_{current}, -a_{decel} \cdot dt, a_{accel} \cdot dt)
$$

### Implementation tasks

1. Refactor `fn_fpv_runTerminalVector.sqf` so it measures current velocity magnitude rather than assuming target speed is already valid.
2. Introduce a helper such as `fn_fpv_computeTerminalVectorSpeedCommand.sqf` if the logic becomes large enough to justify isolation.
3. Add `dt` handling using the last vector update time written on the UAV.
4. Clamp positive and negative speed changes separately using `terminalVectorAccel` and `terminalVectorDecel`.
5. Keep direct steering aggressive:
   - continue using owner-local steering;
   - continue using heading blending or directional pursuit;
   - do not replace vector steering with AI-only motion.
6. Preserve current crew AI suppression and restoration semantics.
7. Keep the current high-rate tick initially. Do not try to solve the speed snap by only slowing the update rate.

### Expected artifacts

- the first vector-control frame no longer jumps instantly to max terminal speed;
- the drone still commits aggressively, but builds speed over multiple vector ticks;
- the motion law becomes physically smoother without losing terminal authority.

### Validation gate

- the first vector tick speed is close to the entry speed or current speed rather than immediately matching vector max speed;
- speed rises progressively over time when there is room to accelerate;
- no script errors or locality regressions occur.

### Suggested debug-console checks

After Phase 3B lands, the validation should focus on telemetry rather than only feel, but even here the first manual check is visual: the final dive should look like a committed acceleration instead of a velocity teleport.

### Parallelization note

Once the acceleration-limited vector core is stable, Phase 3A and Phase 3B can proceed in parallel.

### Exit criteria

- terminal vector no longer uses full-speed snap as its primary motion law;
- the control law is compatible with later handoff tuning and telemetry.

## 9. Phase 3A: Handoff and Speed-Schedule Integration

### Goal

Make the transition from `TERMINAL_ATTACK` into `TERMINAL_VECTOR` smooth, aggressive, and distance-aware.

### Why this phase exists

Even with an acceleration-limited vector core, the handoff can still feel abrupt if entry speed, entry distance, and acceleration permission are not managed explicitly.

### In scope

- vector entry bookkeeping;
- entry speed capture;
- distance-aware speed scheduling;
- alignment-conditioned acceleration;
- optional handoff-distance refinement;
- preserved detonation and missed-pass logic.

### Implementation tasks

1. Capture vector entry state on the UAV:
   - `A3UE_FPV_terminalVectorEntrySpeed`
   - `A3UE_FPV_terminalVectorEntryDistance`
   - `A3UE_FPV_terminalVectorEnteredAt`
2. Build a speed schedule for vector mode:
   - begin near entry speed or `terminalVectorEntrySpeed`;
   - ramp toward `terminalVectorMaxSpeed` over distance or time;
   - optionally slow slightly inside `terminalVectorInnerFuseSlowdownDistance`.
3. Make acceleration alignment-aware:
   - when the drone is poorly aligned with the lead vector, limit acceleration;
   - when alignment improves, allow full configured acceleration.
4. Decide whether the current `terminalSteeringDistance` values provide enough room for a visible speed buildup.
5. If current distances are too short, author a modestly earlier handoff rather than compensating by flattening aggression.
6. Re-check missed-pass detection after the smoother speed ramp lands.

### Expected artifacts

- vector entry is visibly smoother;
- the drone accelerates with intent rather than instantly lunging;
- terminal steering remains decisive and threatening.

### Validation gate

- the first `0.20s - 0.40s` of vector mode show visible speed buildup instead of an immediate max-speed snap;
- off-axis entries turn first and accelerate harder only after alignment improves;
- earlier handoff tuning, if applied, does not make the drone feel hesitant.

### Suggested debug-console checks

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    _d getVariable ["A3UE_FPV_mode", ""],
    _d getVariable ["A3UE_FPV_terminalVectorEntrySpeed", -1],
    _d getVariable ["A3UE_FPV_terminalVectorEntryDistance", -1],
    _d getVariable ["A3UE_FPV_terminalVectorEnteredAt", -1]
];
```

### Parallelization note

This phase can run in parallel with Phase 3B if the team freezes the telemetry variable names and speed-schedule contract first.

### Exit criteria

- handoff is no longer where the speed shock is introduced;
- vector mode still feels aggressive, but its aggression now has readable buildup.

## 10. Phase 3B: Telemetry and Validation Surfaces

### Goal

Expose enough runtime data to validate speed continuity, acceleration clamping, and ownership behavior without relying only on subjective observation.

### Why this phase exists

This fix is easy to misjudge by feel alone. Telemetry is necessary to prove the motion law changed in the intended way.

### In scope

- vector-speed telemetry variables;
- debug snapshot expansion;
- acceptance-oriented warning fields;
- validation snippets for local testing.

### Recommended telemetry variables

At minimum, expose these on the UAV:

- `A3UE_FPV_terminalVectorCurrentSpeed`
- `A3UE_FPV_terminalVectorTargetSpeed`
- `A3UE_FPV_terminalVectorEntrySpeed`
- `A3UE_FPV_terminalVectorEntryDistance`
- `A3UE_FPV_terminalVectorAccelApplied`
- `A3UE_FPV_terminalVectorAlignment`
- `A3UE_FPV_terminalVectorDt`
- `A3UE_FPV_terminalVectorSpeedJump`

### Implementation tasks

1. Extend `fn_fpv_runTerminalVector.sqf` to record the telemetry variables above.
2. Extend `fn_fpv_debugSnapshot.sqf` to surface those fields cleanly.
3. Add optional validation warnings if any of these conditions occur:
   - vector entry speed jump exceeds the configured accel envelope;
   - vector mode starts with an impossible `dt`;
   - a local terminal-vector drone is missing required telemetry fields.
4. Document the telemetry interpretation in the runbook.

### Expected artifacts

- a debug surface that can prove whether the speed snap is fixed;
- acceptance checks that can be repeated consistently across families and sites.

### Validation gate

- the debug snapshot shows vector entry speed, target speed, current speed, and accel values;
- telemetry can distinguish a healthy ramp from an instant velocity step;
- telemetry remains safe under JIP and locality transfer.

### Suggested debug-console checks

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
hint str (_snapshot get "managedDrones");
```

### Parallelization note

This phase can run in parallel with Phase 3A after the Phase 2 control-law contract is stable.

### Exit criteria

- validation no longer depends only on subjective feel;
- the user can measure the behavior with runtime data.

## 11. Phase 4: Family Tuning, Multiplayer Hardening, and Integration

### Goal

Tune the smoothing behavior across supported families and site types, then verify that the refactor remains safe in multiplayer and ownership-transfer scenarios.

### Why this phase exists

The control-law fix can be correct and still feel wrong if family tuning and ownership behavior are not revalidated afterward.

### In scope

- family and site tuning of new vector keys;
- locality verification during vector control;
- JIP replication verification;
- missed-pass and cleanup regression checks;
- no-supported-family boot safety recheck.

### Implementation tasks

1. Tune the new vector speed and acceleration keys per family and site type.
2. Confirm `armafpv` remains the sharpest attacker without reverting to instant lunge behavior.
3. Confirm `kvn` remains aggressive but slightly smoother than `armafpv`.
4. Confirm `fpv_ua` remains physically limited, but still builds speed with intent.
5. Verify the controller remains owner-local during vector mode.
6. Verify late joiners see replicated telemetry but do not drive terminal steering.
7. Verify missed-pass recovery still returns to `LOST_TARGET` cleanly.
8. Verify cleanup and registry behavior are unchanged or improved.

### Expected artifacts

- tuned per-family smoothing behavior;
- multiplayer-safe vector steering behavior;
- no regressions in cleanup, missed-pass recovery, or boot safety.

### Validation gate

- all supported families retain distinct personalities;
- the smoothing fix survives JIP and locality transfer;
- no duplicate controllers or cleanup regressions appear.

### Exit criteria

- the fix is not only correct in isolation, but also tuned and MP-safe;
- the broader aggression system still behaves coherently after the smoothing refactor.

## 12. Phase 5: Local-LAN Acceptance and User Handoff

### Goal

Run the final acceptance matrix, document the validation procedure, and leave the user with a concrete LAN runbook for verifying the smoothing fix in game.

### Why this phase exists

The feature is not complete until the user can reproduce the validation in a real mission without tribal knowledge.

### In scope

- runbook finalization;
- acceptance criteria;
- guidance on interpreting vector telemetry;
- user handoff notes.

### Implementation tasks

1. Finalize the local-LAN runbook below.
2. Ensure `A3UE_fnc_fpv_debugSnapshot` exposes the required vector telemetry.
3. Confirm the runbook covers:
   - boot safety;
   - speed continuity;
   - aggressive tone retention;
   - missed-pass recovery;
   - ownership and JIP behavior.
4. Add any final debug or admin snippets needed for validation.

### Expected artifacts

- a release-ready validation guide for the smoothing fix;
- telemetry-backed acceptance criteria;
- clear handoff instructions for future tuning.

### Validation gate

- the user can follow the runbook and reproduce the smoothing checks on a local LAN;
- all acceptance scenarios pass;
- no blocking defects remain in vector entry, acceleration ramping, locality, or cleanup.

### Exit criteria

- the smoothing redesign is fully implemented and validated;
- the user can verify the behavior end-to-end using the documented LAN procedure.

## 13. Final File and Function Target List

### Existing files expected to change

- `functions/fpv/fn_fpv_buildDoctrine.sqf`
- `functions/fpv/fn_fpv_getProfile.sqf`
- `functions/fpv/fn_fpv_runController.sqf`
- `functions/fpv/fn_fpv_runTerminalVector.sqf`
- `functions/fpv/fn_fpv_debugSnapshot.sqf`
- `config.cpp`

### Existing files that may change depending on implementation detail

- `functions/fpv/fn_fpv_runTerminal.sqf`
- `functions/fpv/fn_fpv_profileValue.sqf`
- `functions/fpv/fn_fpv_computeIntercept.sqf`

### New files likely to be added

- `functions/fpv/fn_fpv_computeTerminalVectorSpeedCommand.sqf`

If the team prefers not to add a new helper, the speed-command logic can stay in `fn_fpv_runTerminalVector.sqf`, but the architectural boundary should still exist conceptually.

## 14. Local-LAN Validation Runbook

This is the final user-facing validation guide. When all phases are complete, the user should be able to follow this section directly and determine whether the smoothing redesign passes.

### 14.1 Recommended local-LAN setup

Minimum setup:

- one local dedicated server running Antistasi Ultimate with the extender loaded;
- one LAN client joining the server;
- at least one supported FPV family loaded.

Recommended setup:

- one local dedicated server;
- two LAN clients;
- optional headless client for locality migration testing;
- all three supported drone families available for full compatibility coverage.

### 14.2 Required mod combinations

Run these combinations at minimum:

1. Antistasi Ultimate + Extender + ArmaFPV
2. Antistasi Ultimate + Extender + fpv_ua
3. Antistasi Ultimate + Extender + frtz_fiberoptic_kvn
4. Antistasi Ultimate + Extender + all three drone families
5. Antistasi Ultimate + Extender only, with no supported FPV family loaded

### 14.3 Mission preparation

1. Start an Antistasi mission over LAN.
2. Ensure the extender is loaded on server and all clients.
3. Move close enough to activate spawner coverage for:
   - one `Airport`
   - one `Outpost`
   - one `Resource`
4. Keep debug console access available on the host for state inspection.
5. Prepare at least one player-controlled test subject and, if possible, one moving vehicle for crossing tests.

### 14.3.1 Recommended debug-spawn distances

Use these starting ranges when spawning debug sites for smoothing validation:

- `Airport`: `600m` to `800m`
- `Outpost`: `450m` to `650m`
- `Resource`: `300m` to `500m`

These ranges usually leave enough room to observe `TERMINAL_ATTACK`, the handoff into `TERMINAL_VECTOR`, and the subsequent speed ramp.

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

Inspect one managed drone with vector telemetry:

```sqf
private _d = (allUnitsUAV select { _x getVariable ["A3UE_FPV_managed", false] }) param [0, objNull];
hint str [
    typeOf _d,
    _d getVariable ["A3UE_FPV_mode", ""],
    _d getVariable ["A3UE_FPV_terminalSteeringActive", false],
    _d getVariable ["A3UE_FPV_terminalVectorCurrentSpeed", -1],
    _d getVariable ["A3UE_FPV_terminalVectorTargetSpeed", -1],
    _d getVariable ["A3UE_FPV_terminalVectorEntrySpeed", -1],
    _d getVariable ["A3UE_FPV_terminalVectorAccelApplied", -1],
    _d getVariable ["A3UE_FPV_terminalVectorAlignment", -1],
    _d getVariable ["A3UE_FPV_terminalVectorDt", -1]
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

Inspect the terminal-vector summary directly:

```sqf
private _snapshot = call A3UE_fnc_fpv_debugSnapshot;
hint str (_snapshot get "terminalVectorSummary");
```

### 14.4.1 Telemetry interpretation

Use the vector telemetry fields as follows:

- `terminalVectorEntrySpeed`: the speed budget at the moment vector control begins.
- `terminalVectorEntryDistance`: the target distance at the moment vector control begins.
- `terminalVectorCurrentSpeed`: the current speed budget before this tick's speed step is applied.
- `terminalVectorTargetSpeed`: the scheduled target speed after applying ramp-distance and inner-fuse logic.
- `terminalVectorAccelApplied`: the effective acceleration rate applied this tick after alignment scaling.
- `terminalVectorAlignment`: the dot-product alignment between current direction and desired aim direction, from `-1` to `1`.
- `terminalVectorDt`: the terminal-vector time step used for this update.
- `terminalVectorSpeedJump`: the actual per-tick speed step applied during this update.

Healthy terminal-vector behavior should generally look like this:

- `terminalVectorCurrentSpeed` starts near `terminalVectorEntrySpeed`.
- `terminalVectorTargetSpeed` rises ahead of `terminalVectorCurrentSpeed` as the ramp builds.
- `terminalVectorSpeedJump` stays small per tick rather than showing one large jump.
- `terminalVectorAccelApplied` increases as alignment improves.
- `terminalVectorDt` stays stable in the expected range.

### 14.4.2 Validation block interpretation

The `validation` block in `A3UE_fnc_fpv_debugSnapshot` is the fast acceptance summary for the smoothing redesign.

- `vectorJumpViolations` should stay empty.
- `vectorDtViolations` should stay empty.
- `vectorTelemetryMissing` should stay empty.
- `nonLocalControllers` should stay empty.
- `controllerOwnerMismatches` should stay empty.
- `warnings` should normally be empty during a healthy run.

### 14.4.3 Terminal-vector summary interpretation

The `terminalVectorSummary` block is the fast operational summary for active smoothing behavior.

- `activeNetIds` lists the drones currently in `TERMINAL_VECTOR`.
- `localNetIds` lists the drones that are both in `TERMINAL_VECTOR` and local to the current machine.
- `telemetryReadyNetIds` lists the active terminal-vector drones that already have the required smoothing telemetry populated.
- `activeVendors` gives the currently active vendor families in terminal vector mode.
- `activeSites` gives the site markers currently feeding terminal vector attacks.

On the machine currently owning a vector attack, `localNetIds` should normally match the active local vector drones, and `telemetryReadyNetIds` should cover those same drones.

### 14.5 Acceptance scenarios

#### Scenario 1: Soft-dependency boot safety unchanged

Steps:

1. Launch with Antistasi Ultimate and the extender only.
2. Start the mission and activate at least one supported site type.

Expected result:

- no script errors occur;
- no FPV drones spawn;
- the smoothing refactor does not introduce any behavior when no supported family is loaded.

#### Scenario 2: Vector entry speed continuity

Steps:

1. Spawn a managed drone and allow it to enter `TERMINAL_ATTACK`.
2. Observe the first `0.20s` of `TERMINAL_VECTOR`.
3. Inspect vector telemetry immediately after handoff.

Expected result:

- `TERMINAL_VECTOR` begins without a visible instant lunge;
- `terminalVectorCurrentSpeed` starts near entry speed, not immediately at vector max speed;
- the first vector tick does not look like a speed teleport;
- `validation.vectorJumpViolations` remains empty.

#### Scenario 3: Acceleration ramp shape

Steps:

1. Use a target with enough distance to observe the final approach.
2. Watch the drone through vector entry and the next few tenths of a second.

Expected result:

- speed increases progressively across multiple vector ticks;
- `terminalVectorCurrentSpeed` approaches `terminalVectorTargetSpeed` over time rather than matching it instantly;
- `terminalVectorAccelApplied` stays inside the authored accel envelope;
- `validation.vectorDtViolations` remains empty.

#### Scenario 4: Aggressive tone retained

Steps:

1. Use open-ground infantry as the target.
2. Observe the final approach after the smoothing fix.

Expected result:

- the drone still feels dangerous and committed;
- it does not become floaty or obviously delayed;
- the visual change is smoother acceleration, not timid behavior.

#### Scenario 5: Alignment-conditioned acceleration

Steps:

1. Force an off-axis entry into vector mode, such as a target crossing at an angle.
2. Observe heading correction and acceleration behavior.

Expected result:

- the drone turns into the line first and then accelerates harder as alignment improves;
- the approach looks deliberate rather than magical.

#### Scenario 6: Inner-fuse behavior

Steps:

1. Observe the final few meters before detonation.
2. Compare speed behavior near the fuse window.

Expected result:

- if an inner-fuse slowdown policy is implemented, it should slightly tame the last few meters without removing lethality;
- detonation timing should still occur cleanly inside the authored window.

#### Scenario 7: Missed-pass recovery still works

Steps:

1. Force a terminal miss if practical.
2. Observe the behavior after the overshoot.

Expected result:

- the drone returns to `LOST_TARGET` cleanly;
- smoothing does not strand the drone in an invalid vector-control state;
- crew AI restore behavior still works if vector mode exits alive.

#### Scenario 8: External control suspension during vector mode

Steps:

1. Take direct UAV control or Zeus remote control while the drone is in `TERMINAL_VECTOR` if practical.
2. Observe state changes.

Expected result:

- terminal vector control stops cleanly;
- the drone returns to `IDLE` or otherwise suspends autonomous attack according to the main aggression design;
- no stuck vector-control telemetry remains after suspension.

#### Scenario 9: JIP and locality during vector mode

Steps:

1. Let a drone enter `TERMINAL_VECTOR`.
2. Join a second LAN client while the vector phase is already active.
3. If available, force locality migration to a headless client.

Expected result:

- only the current owner runs terminal vector steering;
- late joiners see telemetry and state but do not drive control;
- locality transfer does not reintroduce a speed snap or duplicate steering;

- `validation.vectorTelemetryMissing`, `validation.nonLocalControllers`, and `validation.controllerOwnerMismatches` remain empty.

- `terminalVectorSummary.localNetIds` only lists vector drones local to the machine currently owning them.

#### Scenario 10: Mixed-family tuning safety

Steps:

1. Launch with all supported families loaded.
2. Trigger multiple site types.
3. Observe terminal behavior across family types.

Expected result:

- `armafpv` remains the sharpest attacker without reverting to instant snap behavior;
- `kvn` remains aggressive but smoother;
- `fpv_ua` remains limited but still purposeful;
- the smoothing model behaves consistently across all supported families;
- `terminalVectorSummary.activeVendors` reflects the family or families currently observed in terminal vector mode.

### 14.6 Final acceptance rule

The smoothing redesign is accepted only when:

- all mandatory scenarios above pass;
- no blocking defects remain in vector entry speed continuity, acceleration ramping, or ownership behavior;
- the user can reproduce the checks on a local LAN using the documented telemetry and runbook.

## 15. User Handoff Summary

When all phases are complete, the user should be left with:

- the implemented terminal-vector smoothing redesign in code;
- `docs/FPV_Aggression_Implementation_Plan.md` as the broader aggression reference;
- `docs/FPV_Aggression_Implementation_Phases.md` as the parent feature execution plan;
- this document as the focused execution and validation reference for the final-dive smoothing fix;
- a local-LAN runbook that proves the final attack no longer snaps instantly to full speed while preserving aggressive behavior.

At that point, the feature should be fully implemented and validated rather than left as an unstructured tuning idea.