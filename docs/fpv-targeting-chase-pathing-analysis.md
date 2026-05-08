# FPV Drone Targeting, Chasing, Pathing, and Impact-First Recommendations

Date: 2026-05-08

## Scope

This document analyzes the active A3UE FPV runtime in the current repo, with focus on:

- target acquisition and retention
- chase guidance and pathing
- terminal attack and terminal vector steering
- self-detonation and warhead delivery
- implementation quality and current gaps
- architecturally sound recommendations for moving from aerial self-detonation toward impact-driven explosions

The active runtime namespace is `A3UE_fnc_fpv_*` under `functions/fpv/`.

## Executive Summary

The current implementation is structurally solid. Spawn policy, locality, vendor compatibility, target selection, target-memory loss handling, and terminal steering are all separated cleanly enough that the system can evolve without a broad rewrite.

The observed behavior is not accidental. The current stack explicitly biases the drone toward approaching above the target and then detonating by proximity:

- the lead solver and terminal move target maintain an elevated attack point above the target
- the fuse is driven by 3D or 2D proximity rather than physical contact or predicted impact
- terminal vector steering improves closure, but it still feeds a proximity fuse instead of an impact-first warhead model
- the detonation implementation deletes the UAV and spawns the warhead at the drone's current position, so the explosion occurs where the drone decides to self-detonate rather than where it physically collides

That means the addon already has a credible autonomous chase controller, but its kill semantics are still airburst-first. If the design goal is to better simulate real FPV kamikaze behavior, the main work is not a new spawn system or a new controller ownership model. The main work is:

1. changing what point the drone tries to hit in the final seconds
2. changing when the fuse is allowed to fire
3. preserving self-detonation as a fallback when impact is no longer realistic

## End-to-End Runtime Flow

### 1. Registration, spawn, and bootstrap

`fn_addFPVEventListeners.sqf` initializes the FPV system during post-init. It:

- ensures the catalog, doctrine, registry, and debug state exist
- builds the compatibility catalog and doctrine
- registers Antistasi listeners for `locationSpawned` and `AIVehInit`
- refreshes already-managed drones so late registration and JIP clients can bootstrap active drones

`fn_fpv_managerEvaluateSite.sqf` and `fn_fpv_managerSpawnDrone.sqf` provide the server-owned spawn path. For each eligible `Airport`, `Outpost`, or `Resource` site, the server:

- resolves family and payload role from doctrine
- selects a compatible UAV class
- spawns the UAV near the site marker in the air
- stamps all `A3UE_FPV_*` metadata on the drone
- creates or initializes crew through Antistasi hooks when available
- runs compatibility normalization so vendor mods do not leave the drone AI-disabled

`fn_fpv_onAIVehInit.sqf` then remote-execs `fn_fpv_bootstrapLocal.sqf` to all machines with the UAV as the JIP key.

`fn_fpv_bootstrapLocal.sqf` is the key locality boundary. It:

- installs `Local`, `Deleted`, and `MPKilled` handlers
- restarts the controller when ownership changes
- applies compatibility normalization again locally
- seeds link-state cache and terminal-vector telemetry
- starts `fn_fpv_runController.sqf` only on the machine where the UAV is local

This ownership model is correct and should be preserved. The active chase controller is owner-local, while spawn and registry state remain server-owned.

### 2. State machine and control cadence

`fn_fpv_runController.sqf` drives the autonomous behavior. The active modes are:

- `IDLE`
- `SEARCHING`
- `TRACKING`
- `LOST_TARGET`
- `TERMINAL_ATTACK`
- `TERMINAL_VECTOR`

Every loop iteration does four high-level things:

1. refresh or reuse cached EW/link state through `fn_fpv_cacheLinkState.sqf`
2. suspend autonomy if the drone is externally controlled by player, UAV terminal, or Zeus
3. route behavior by the current mode
4. sleep until the next guidance, target-scan, or link-eval tick

Important details:

- link evaluation is cached at about `0.35s` and forced early if the UAV moved more than `150m`
- externally controlled drones are forced back to `IDLE` and lose autonomous target state
- radio-denied drones fall back to hold-pattern behavior rather than suicide blindly
- `TERMINAL_VECTOR` restores crew AI if the controller exits that state

The state machine is not the problem. It already has the right extension points for impact-first behavior.

## Targeting, Chasing, and Pathing

### 3. Search behavior

Search behavior is implemented by `fn_fpv_holdPattern.sqf`.

This is not a waypoint graph or obstacle-aware route planner. The search model is intentionally simple:

- choose a center from the site marker, otherwise the UAV position
- choose a search height by site type
  - `Airport`: `45m`
  - `Outpost`: `35m`
  - `Resource`: `25m`
- choose a hold radius by site type
  - `Airport`: `300m`
  - `Outpost`: `180m`
  - `Resource`: `120m`
- every `5` seconds, issue a new random `doMove` point on that ring

This is intentionally coarse, cheap, and compatible with multiple UAV families. It works well enough as a patrol or waiting behavior, but it is not meant to look like terminal attack logic.

### 4. Target acquisition

`fn_fpv_selectTarget.sqf` is the owning target-selection function.

The function builds a candidate pool from two overlapping searches:

- a site-centered scan radius from doctrine or site fallback
- a UAV-centered local scan radius

Candidates are drawn from:

- `Man`
- `LandVehicle`
- `Air`
- `Ship`
- `StaticWeapon`

It then filters and normalizes candidates:

- embarked infantry are normalized to their parent vehicle
- self and other managed FPV drones are rejected
- empty non-static vehicles are rejected
- dead targets are rejected
- optional lost-target cone filtering can be applied during reacquisition

Scoring is payload-aware:

- `AT` prefers tanks, APCs, vehicles, ships, and air targets, and penalizes infantry heavily
- `AP` prefers infantry first, then cars and static weapons, and penalizes heavy armor
- `RECON` still prefers infantry and softer targets, with a smaller tank penalty

The function also includes target stickiness and a local line-of-sight or obstruction penalty by calling `fn_fpv_isTargetObstructed.sqf`.

Two important design notes:

- target selection is already better than a naive nearest-target query because it includes sticky target memory and obstruction penalties
- hostility is intentionally biased toward `teamPlayer` when available, which fits Antistasi's player-centered threat model but makes the drone logic less general as a battlefield AI

### 5. Target retention and lost-target recovery

The controller stores the current target as a netId and resolves it through `fn_fpv_resolveTarget.sqf`.

When a target breaks track or dies, the drone does not instantly forget everything. `fn_fpv_runController.sqf` stores:

- last known target netId
- last known target position in ASL
- last known target velocity
- the expiry time for the current lost-target memory window

`fn_fpv_runLostTarget.sqf` uses that information to:

- predict a short forward position from the stored velocity
- climb to a lost-target search altitude
- guide the UAV toward that predicted point
- run a tighter cone-based reacquisition scan around the last known direction of travel

This is a meaningful strength in the current implementation. The drone already has a useful intermediate predatory state between clean tracking and blind search.

### 6. Intercept calculation

`fn_fpv_computeIntercept.sqf` uses a lead-pursuit solver based on relative position, relative velocity, and an assumed chase speed.

In simplified form, the solver is computing an intercept point such that:

- the target position is projected forward by the chosen time-to-impact
- the time-to-impact is limited by adaptive lead caps derived from the current doctrine profile

This is good control architecture for the problem. The main issue is not the lead solver itself. The issue is what the solver does with the vertical axis.

After computing the intercept, the function forces the intercept altitude to remain at least `attackHeightASL` above the target:

- family defaults in doctrine currently set `attackHeightASL` to `8m`
- terminal fallback uses `6m` in `fn_fpv_runTerminal.sqf`

That is the first hard reason the drone prefers aerial detonation over impact. The computed intercept is not the target's body, hull, roof, ground contact point, or nearby object. It is an elevated attack point.

### 7. Tracking pathing

`fn_fpv_applyGuidance.sqf` turns the intercept into flight instructions during `TRACKING`.

The current pathing model is intentionally conservative and AI-driven:

- convert the intercept ASL position to ATL
- set `CARELESS`, `BLUE`, and `FULL`
- apply `flyInHeight` using the intercept altitude with a profile floor
- apply `forceSpeed`
- issue a fresh `doMove` only when the target point changed enough or enough time has passed

This is not true geometric path planning. In practice it is repeated destination-point steering.

That choice is reasonable for coarse chase behavior because it:

- remains compatible with multiple vendor UAVs
- keeps the AI crew and engine flight model doing most of the work
- avoids overusing high-cost custom steering outside the terminal window

It is not enough by itself to produce a true impact dive, but it is fine as the long-range guidance layer.

### 8. Terminal attack handoff

`fn_fpv_shouldEnterTerminal.sqf` triggers `TERMINAL_ATTACK` based on distance gates.

The current doctrine-derived gates are large by design. Depending on site, family, and role, `terminalGateDistance` is roughly in the `68m` to `100m` range, with a derived 2D gate at about `55%` of that value.

Once terminal mode begins, `fn_fpv_runTerminal.sqf` tightens the movement loop:

- compute a terminal intercept with the same lead solver
- use a smaller but still positive final height offset
- continue using AI `doMove`, `flyInHeight`, and `forceSpeed`
- refresh movement more often than in `TRACKING`

This is still not impact-first. It is a faster, closer, more aggressive version of the same elevated pursuit model.

### 9. Terminal vector steering

Inside `terminalSteeringDistance`, the controller hands off to `fn_fpv_runTerminalVector.sqf`.

This is the most aggressive guidance stage in the addon. It is owner-local and uses direct steering primitives:

- compute a terminal lead point
- build an aim vector from UAV to lead point
- amplify the vertical component through `terminalVerticalGain`
- blend current direction and desired direction based on alignment
- compute a speed budget with doctrine-authored acceleration and deceleration limits
- call `setVectorDirAndUp` and `setVelocity`
- disable crew `PATH`, `FSM`, and `AUTOCOMBAT` while vector steering is active

This is a major improvement over pure `doMove` and is why the current system already looks better than the older chase implementation described in the existing plan docs.

However, even this stage is still centered on a lead point above the target and still feeds the same proximity-based fuse. So terminal vector control improves closure quality, but it does not change the kill model from airburst-first to impact-first.

## How Self-Detonation Works Today

### 10. Detonation gating

`fn_fpv_shouldDetonateNow.sqf` decides whether the drone should explode.

The logic is currently proximity-based and role-tuned:

- use total 3D distance to the target
- use 2D horizontal distance to the target
- use a vertical separation window
- return true if either:
  - the 3D distance is inside `detonationDistance`, or
  - the horizontal distance is inside `detonationDistance2D` and the height separation is inside `detonationVerticalWindow`

This means the fuse does not currently care about:

- whether the UAV is actually descending into the target
- whether it is still closing rather than sliding laterally or overshooting
- whether there is a predicted physical contact in the next few frames
- whether it is above the target, next to the target, or moving away from the target

If the drone is close enough, it is allowed to explode.

### 11. Warhead delivery

`fn_fpv_detonateCompat.sqf` performs the actual strike.

The sequence is:

1. guard against duplicate detonation with `A3UE_FPV_detonating`
2. choose a compatible ammo class by payload role
3. unregister the drone from the server registry
4. preserve KVN fiber visual state when applicable
5. clear or restore captive state on the killer if needed
6. create the ammo object at the drone's current world position
7. align the ammo object's vector direction and up vector to the UAV
8. delete the UAV and its crew
9. trigger the ammo

This is intentionally compatibility-friendly and avoids requiring real collision with the target. It also means the explosion happens where the drone chose to self-detonate, not where the drone physically impacted.

That is the second hard reason the current effect feels like a self-detonating airburst rather than a kamikaze hit.

## Why Drones Detonate Above the Player

The current above-target behavior is produced by several layers reinforcing the same outcome.

### Root cause 1: elevated intercept geometry

Both `fn_fpv_computeIntercept.sqf` and `fn_fpv_runTerminal.sqf` keep the final approach point above the target.

That means the guidance stack is not aiming for:

- the infantry body center
- the vehicle hull or roof surface
- the terrain point at the target's feet
- a nearby object surface if direct line is obstructed

It is aiming for a positive altitude offset above the target.

### Root cause 2: fuse semantics are proximity-only

`fn_fpv_shouldDetonateNow.sqf` has no concept of contact, closure rate, or impact prediction. If distance thresholds are met, the drone may explode immediately.

This is especially permissive because:

- the derived `detonationDistance2D` is about half of `detonationDistance`
- the default `detonationVerticalWindow` is `10m` to `12m`
- the positive attack-height bias already places the UAV inside that vertical band during the final seconds

### Root cause 3: terminal vector still feeds the same fuse

`fn_fpv_runTerminalVector.sqf` is better steering, not different strike semantics. It can reduce misses, but it still chases an elevated lead point and hands control to the same proximity fuse.

### Root cause 4: the explosion is spawned at UAV position

Even if the drone visually looks close to the target, `fn_fpv_detonateCompat.sqf` deletes the UAV and spawns the warhead at the UAV position. There is no final inertial carry-through to a collision point.

### Root cause 5: no impact proxy or surface selection exists

There is currently no function that resolves a final impact point such as:

- closest vehicle-hull point
- target pelvis or torso point
- ground point at the target's feet
- obstacle surface nearest the target if line of sight is blocked

The controller knows how to select a target and how to detect occlusion penalties, but it does not know how to choose a concrete physical impact surface.

## Quality Review

### What is good

The current implementation has several strong qualities:

- server-side spawn management and owner-local control are separated correctly
- locality transfer is handled through `Local` event bootstrap rather than assuming ownership is static
- vendor compatibility is explicit instead of hidden behind brittle assumptions
- the doctrine and profile layer is real and is now populated with behavior data, not just spawn weights
- lost-target recovery is present and materially improves pursuit behavior
- terminal vector steering already exists as a dedicated high-authority endgame stage
- link-state evaluation is cached rather than recomputed on every high-rate steering tick
- debug snapshot support already exposes useful tuning and validation data

In short, the architecture is not the problem. It is already a good base for an impact-first redesign.

### Gaps and issues that matter for impact-first behavior

#### 1. Impact semantics are missing entirely

The controller chooses a target object, not a final impact point on that object or near it. There is no impact-resolution layer between target selection and fuse logic.

This is the biggest functional gap relative to the observation.

#### 2. The vertical attack model is hard-coded toward overflight

Positive `attackHeightASL` defaults and terminal height offsets are still embedded in the current profile contract. That makes aerial approach the normal case, not the exception.

#### 3. The fuse is too permissive for close-above cases

The current OR condition in `fn_fpv_shouldDetonateNow.sqf` allows detonation on distance alone. It does not require:

- positive closing velocity
- a short predicted time-to-contact
- active descent when above the target
- physical contact or near-contact with a chosen impact point

#### 4. No direct-impact fallback target exists for infantry or ground strike

Real FPV drones often do not need a perfect body hit. Hitting the ground, curb, wall, or vehicle surface next to the target is still a mission success. The current system has no explicit representation of that idea.

#### 5. Obstruction knowledge is not reused for warhead placement

`fn_fpv_isTargetObstructed.sqf` can already tell the controller that line of sight is blocked, but that information is only used as a selection penalty. It is not used to choose an alternate strike surface.

#### 6. The current self-detonation path is all-or-nothing

Once detonation is approved, the UAV is removed and the ammo is triggered. There is no distinction between:

- direct impact achieved
- predicted impact within a few frames
- fallback proximity burst because the drone is about to overshoot
- fallback burst because control or guidance quality collapsed at the last instant

That makes debugging and future tuning harder than it needs to be.

#### 7. Impact-first additions must be controlled for performance

The current chase stack is relatively efficient because expensive geometric reasoning is mostly limited to selection, obstruction checks, and cached EW evaluation. If impact prediction is added, it should be restricted to terminal phases so the repo does not trade realism for runaway per-frame cost.

## Architecturally Sound Recommendations

The right design is not to remove self-detonation entirely. The right design is to make self-detonation a fallback while the default behavior tries to achieve a direct impact on the target, vehicle, ground, or nearby object.

### Recommendation 1: Add an explicit impact-point resolver

Create a new terminal helper that resolves a concrete aimpoint, not just a target object.

Suggested resolution order:

1. direct target surface or body point
2. vehicle hull or roof point closest to the incoming vector
3. ground point at or just ahead of the target's feet or wheels
4. nearby obstruction or cover surface adjacent to the target

This would let the controller distinguish between:

- direct impact on infantry
- direct impact on a vehicle
- deliberate ground strike near infantry
- deliberate wall or cover strike when the target ducks behind an object

Why this is sound:

- it fits naturally between `resolveTarget` and terminal guidance
- it does not require changing the spawn or locality model
- it gives the fuse a concrete impact reference instead of a generic target center

Performance note:

- keep the expensive surface-resolution logic out of `SEARCHING` and most of `TRACKING`
- resolve or refresh impact points only during `TERMINAL_ATTACK` and `TERMINAL_VECTOR`, or when the target or obstruction state changes materially

### Recommendation 2: Replace fixed positive attack height with a distance-shaped descent profile

Do not force a positive `attackHeightASL` all the way into the target.

Recommended model:

- `TRACKING`: allow positive altitude offset for stable pursuit and obstacle clearance
- `TERMINAL_ATTACK`: progressively reduce that offset as distance closes
- `TERMINAL_VECTOR`: drive toward the chosen impact point with an explicit minimum descent component instead of a positive altitude floor

That preserves the good part of the current guidance stack while removing the bias that causes airburst over infantry.

Performance note:

- this is mostly a math and profile change, not a query-heavy change
- it should be cheap compared to adding new per-frame geometry scans

### Recommendation 3: Refactor the fuse from proximity-first to impact-first

`fn_fpv_shouldDetonateNow.sqf` should become a layered decision instead of a single distance gate.

Suggested decision order:

1. direct contact or predicted impact within a very short time-to-contact window
2. impact-point proximity with positive closing velocity and descent when required
3. fallback proximity burst if impact is no longer realistic but the drone is still inside an effective kill envelope

The fuse should inspect at least:

- closing dot product between velocity and target or impact-point direction
- short predicted time-to-contact
- altitude above ground and altitude above the impact point
- whether the drone is moving toward or away from the impact solution

This change is the single most important fix for the observed problem.

### Recommendation 4: Keep `fn_fpv_detonateCompat.sqf` as the fallback delivery path, not the primary intent

The compatibility detonation helper is still valuable because Arma collision behavior is not reliable enough to trust alone across all UAV families.

Use it in these situations:

- direct impact is confirmed or predicted within the immediate next instant
- the drone is about to overshoot but remains inside an effective kill radius
- the target is behind thin cover and a nearby wall or ground strike is acceptable
- control quality collapses during the final armed window and a guaranteed fallback burst is preferable to a harmless fly-through

This preserves compatibility while changing the behavior goal from self-detonate near target to impact if possible, otherwise self-detonate intelligently.

### Recommendation 5: Add phase-specific impact modes by target class

One impact policy will not be equally good for infantry, vehicles, and statics.

Recommended defaults:

- `Man`: aim for torso or pelvis if unobstructed, otherwise strike ground at feet or just ahead of movement vector
- `LandVehicle`: aim for hull or roof point closest to approach vector; if geometry is unreliable, aim for vehicle centerline at roof or hood height and fuse only on confirmed closure
- `StaticWeapon`: aim for weapon center or crew position, otherwise ground beside emplacement
- `Air`: keep fallback proximity burst semantics longer, because direct collision with another air target is less reliable and may not be worth the risk

This keeps the behavior believable without overfitting every case to the exact same geometry rule.

### Recommendation 6: Reuse obstruction data to choose fallback strike surfaces

The current system already computes terrain and object obstruction through `fn_fpv_isTargetObstructed.sqf`.

Use that information in the terminal phase to decide whether the best strike is:

- direct target impact
- a wall, vehicle side, or rooftop face
- terrain at the base of the target or object

That would make the drones feel much more purposeful when a player ducks behind a low wall or near a vehicle, because the drone can still choose an explosion point that makes tactical sense.

### Recommendation 7: Add doctrine keys specifically for impact-first behavior

The current doctrine is good enough to author this behavior cleanly. Add explicit keys rather than overloading older ones.

Suggested additions:

- `terminalImpactMode`
- `terminalImpactOffsetNear`
- `terminalImpactOffsetFar`
- `terminalDescentMinRate`
- `detonationMaxTimeToContact`
- `detonationMinClosingDot`
- `detonationMaxAltitudeAGL`
- `impactFallbackRadius`
- `impactFallbackGroundOffset`
- `impactProbeDistance`
- `impactAbortTimeout`

This keeps the design data-driven and lets different families or site types behave differently without code branching everywhere.

### Recommendation 8: Add terminal telemetry for impact diagnostics

`fn_fpv_debugSnapshot.sqf` already exposes useful controller state. Extend it further for impact-first tuning.

Suggested telemetry:

- resolved impact point ASL
- impact mode selected for the current target
- last closing dot product
- predicted time-to-contact
- detonation reason
- last impact surface type or object
- last fallback reason if direct impact was abandoned

This will matter once the fuse stops being a simple distance gate, because debugging impact logic without telemetry becomes guesswork.

## Suggested Implementation Order

The safest sequence is incremental.

### Phase 1: Introduce impact semantics without changing spawn or locality

- add an impact-point resolver helper
- add debug output for impact point, impact mode, and detonation reason
- keep current detonation as a fallback path

### Phase 2: Change terminal guidance to chase the impact solution

- replace fixed positive terminal offset with a shrinking offset curve
- add explicit descent enforcement in `TERMINAL_VECTOR`
- keep `TRACKING` largely as-is

### Phase 3: Refactor the fuse

- require closure or very short predicted time-to-contact for primary fuse approval
- demote raw proximity-only detonation to fallback status
- tune by target class

### Phase 4: Add near-ground and near-object fallback strikes

- for infantry and cover cases, allow deliberate ground or nearby surface impact
- use obstruction information to pick alternate strike surfaces

### Phase 5: Tune and validate per family

- ArmaFPV can remain the sharpest attacker
- KVN can preserve its current smoother feel but still hit physically
- fpv_ua may need tighter fallback rules because of lower airframe performance

This sequence preserves the existing architecture while directly addressing the observed problem.

## Bottom Line

The current addon is not failing because the chase controller is weak. It is failing the realism goal because the final strike model is still built around self-detonation near the target rather than impact with the target or a nearby surface.

Today the system does this well:

- spawn and bootstrap autonomous drones safely
- acquire and retain targets
- chase using lead pursuit and owner-local terminal steering
- detonate reliably across supported vendor families

Today it does not yet do this:

- resolve a physical impact point
- enforce direct-impact or ground-impact semantics in the final seconds
- reserve aerial self-detonation for fallback conditions only

The good news is that the codebase is already set up for the right fix. The path forward is an impact-resolution and impact-aware fuse layer on top of the current controller, not a rewrite of the controller itself.