# FPV Drone Targeting, Chase, and Pathing Analysis

Date: 2026-05-08

## Scope

This document analyzes the active A3UE FPV chase stack in the current repo, with emphasis on:

- site-driven spawn and bootstrap
- target acquisition and retention
- chase guidance, movement commands, and terminal attack
- implementation quality, gaps, and improvement options

The relevant runtime surface is the `A3UE_fnc_fpv_*` namespace under `functions/fpv/`.

## Executive Summary

The current implementation is structurally solid. The spawn path is cleanly separated from the chase logic, ownership/locality is handled correctly, external player or Zeus control suspends autonomy, and terminal detonation is normalized across vendor families.

The main weakness is not the overall architecture. The weakness is that the actual chase behavior is still conservative and AI-driven:

- the controller relies almost entirely on repeated `doMove` updates rather than high-authority steering
- the behavior-tuning keys the controller reads are not populated in the doctrine, so almost all chase tuning falls back to hard-coded defaults
- those defaults are cautious enough that drones feel easy to outrun or sidestep
- several parts of the loop favor stability and compatibility over aggression, especially search cadence, target loss handling, and turn responsiveness

The practical result matches the observed playtest outcome: drones can acquire and pursue, but they do not yet behave like fast, committed FPV strike platforms.

## End-to-End Runtime Flow

### 1. Registration and site-driven spawn

`fn_addFPVEventListeners.sqf` initializes the FPV system during post-init. It:

- ensures the catalog, doctrine, registry, and debug variables exist
- builds the compatibility catalog and doctrine
- registers Antistasi event listeners for `locationSpawned` and `AIVehInit`
- refreshes already-managed drones for JIP and late registration support

`fn_fpv_onLocationSpawned.sqf` is a thin wrapper that forwards Antistasi site events into `fn_fpv_managerEvaluateSite.sqf`.

`fn_fpv_managerEvaluateSite.sqf` is the server-side site manager. For each active `Airport`, `Outpost`, or `Resource` site it:

- validates the site side
- picks a drone family using `fn_fpv_selectFamilyForSite.sqf`
- rolls `spawnChance`
- derives a stock count from the doctrine
- spawns one or more drones through `fn_fpv_managerSpawnDrone.sqf`
- stores the result in `A3UE_FPV_registry`

This is a good architectural boundary. Spawn policy lives on the server, while chase execution is pushed to whichever machine owns the UAV.

### 2. Drone construction and bootstrap

`fn_fpv_managerSpawnDrone.sqf` chooses a class by family, role, side, and site type. It then:

- spawns the UAV in the air near the site marker
- stamps all A3UE management variables on the vehicle
- creates vehicle crew through Antistasi when available
- runs Antistasi vehicle initialization hooks
- runs `fn_fpv_applyCompatInit.sqf`

The important metadata for the chase loop is:

- `A3UE_FPV_mode`
- `A3UE_FPV_siteMarker`
- `A3UE_FPV_siteType`
- `A3UE_FPV_profileId`
- `A3UE_FPV_vendorId`
- `A3UE_FPV_payloadRole`
- `A3UE_FPV_linkModel`
- `A3UE_FPV_targetNetId`

`fn_fpv_onAIVehInit.sqf` then remote-execs `fn_fpv_bootstrapLocal.sqf` to all machines with the drone as the JIP key.

`fn_fpv_bootstrapLocal.sqf` is one of the better pieces of the implementation. It:

- installs a `Local` event handler so the controller restarts when ownership changes
- installs `Deleted` and `MPKilled` cleanup handlers
- only starts the controller where the UAV is local
- applies compat normalization again locally before running the controller

That gives the project a correct ownership model: one active controller per drone, local to the machine that owns the vehicle AI.

### 3. Compatibility normalization

`fn_fpv_applyCompatInit.sqf` exists because the external FPV mods were built around player-operated drones rather than autonomous AI drones. The repo memory and the vendor addon code confirm that the vendor init functions disable AI for at least ArmaFPV, fpv_ua, and KVN.

This function re-enables AI and restores family-specific state. It also queues a delayed second normalization pass after about `1.25` seconds to override vendor init logic that fires after spawn.

Without this step, the rest of the chase system would not work reliably.

## The Chase and Pathing Process

### 4. State machine overview

`fn_fpv_runController.sqf` drives the entire chase loop. The controller runs while:

- the UAV is alive
- the UAV is local
- `A3UE_FPV_controllerRunning` is true

Each loop iteration does the following in order:

1. Resolve the current mode.
2. Evaluate link state with `fn_fpv_evaluateLinkState.sqf`.
3. Suspend autonomy if the drone is under external player/UAV terminal/Zeus control.
4. If radio-denied, hold pattern and go idle.
5. Otherwise execute one of four modes:
   - `IDLE`
   - `SEARCHING`
   - `TRACKING`
   - `TERMINAL_ATTACK`

The loop cadence is mode-dependent:

- `IDLE`: about `1.0s`
- `SEARCHING`: about `1.0s` when no target is found, `0.1s` after a target is acquired
- `TRACKING`: about `0.1s`
- `TERMINAL_ATTACK`: about `0.05s` initially, then about `0.02s`

### 5. Search behavior

`IDLE` and no-target `SEARCHING` both use `fn_fpv_holdPattern.sqf`.

This is not waypoint-based pathing in the classic Arma sense. There are no persistent waypoints and no waypoint graph. The system uses a periodic `doMove` toward a temporary point.

The hold pattern logic:

- chooses a center from the site marker if available, otherwise the UAV position
- sets a search height based on site type
  - `Airport`: `45m`
  - `Outpost`: `35m`
  - `Resource`: `25m`
- chooses a hold radius based on site type
  - `Airport`: `300m`
  - `Outpost`: `180m`
  - `Resource`: `120m`
- runs at `NORMAL` speed mode
- issues a fresh `doMove` only every `5` seconds

That means the baseline search behavior is a slow randomized orbit around the site, not an aggressive hunt.

### 6. Target acquisition

`fn_fpv_selectTarget.sqf` performs target search. It scans two areas:

- a site-centered radius driven by site type
  - `Airport`: `700m`
  - `Outpost`: `500m`
  - `Resource`: `350m`
- a UAV-centered local radius of `250m`

Candidate classes are:

- `Man`
- `LandVehicle`
- `Air`
- `Ship`
- `StaticWeapon`

The function then normalizes and filters candidates:

- passengers are normalized to their parent vehicle
- self-targeting is rejected
- managed A3UE drones are rejected
- dead candidates are rejected
- empty vehicles are rejected

Side resolution is derived from unit group side for infantry, or from commander, driver, or crew for vehicles.

Scoring is simple and readable:

- base score is proximity
- `AT` favors heavy armor and punishes infantry
- `AP` favors infantry, cars, and static weapons
- `RECON` also favors infantry and lighter targets

One important gameplay detail: when `teamPlayer` exists and differs from the site side, the hostile-side set collapses to `[teamPlayer]`. In Antistasi, that makes this system strongly player-faction-centric rather than a general hostile-selector.

### 7. Target retention

The chosen target is stored as `A3UE_FPV_targetNetId`. `fn_fpv_resolveTarget.sqf` converts that netId back into an object and rejects null or dead targets.

There is no real target memory beyond that single object reference. If the target dies, goes null, or moves beyond the drop distance, the controller clears the target and goes back to `SEARCHING`.

The default drop distance is `900m`, again read from the profile layer but currently supplied by fallback defaults.

### 8. Intercept calculation

`fn_fpv_computeIntercept.sqf` uses a quadratic lead-pursuit solver. Conceptually it solves:

$$
\text{InterceptPos} = \text{TargetPos} + (\text{TargetVelocity} \times t)
$$

The calculation uses:

- UAV position and velocity
- target position and velocity
- an assumed chase speed

The chase speed defaults are role-based:

- `AT`: `90`
- `RECON`: `80`
- `AP`: `85`

It then clamps the predicted intercept time to a default `maxLeadTime` of `3` seconds and adds a default vertical attack offset of `12m` above the target.

This is mathematically sound as a generic lead solver. The practical limitation is that the solver output is still fed into Arma AI flight through `doMove`, so the drone does not directly steer like a missile. It only receives a moving destination point.

### 9. Tracking guidance

`fn_fpv_applyGuidance.sqf` translates the intercept into actual movement orders. This is the main chase pathing implementation.

It does not use waypoints, vector steering, or any custom flight controller. Instead it does the following:

- converts intercept ASL to ATL
- uses the intercept height as the tracking flight height, with a floor of `10m`
- enables AI and forces:
  - `CARELESS` behavior
  - `BLUE` combat mode
  - `FULL` speed mode
- applies a role-based default tracking speed
  - `AT`: `95`
  - `RECON`: `85`
  - `AP`: `90`
- throttles `doMove` updates so a new move order is only issued when:
  - the target point moved more than `15m`, or
  - `0.25s` elapsed since the last move update

This is the most important reason the drones feel soft. The controller updates often enough to chase, but not aggressively enough to produce hard interception turns.

### 10. Terminal transition and terminal pathing

`fn_fpv_shouldEnterTerminal.sqf` moves the drone into `TERMINAL_ATTACK` when the target is close enough.

Default terminal gates are:

- `AT`: `120m` 3D or `60m` 2D
- `RECON`: `85m` 3D or `40m` 2D
- `AP`: `90m` 3D or `45m` 2D

`fn_fpv_runTerminal.sqf` then tightens the movement loop:

- default height offset becomes `6m` above the target
- `FULL` speed mode remains active
- default terminal speed becomes:
  - `AT`: `110`
  - `RECON`: `95`
  - `AP`: `100`
- `doMove` is refreshed when the target point shifts more than `5m`, or every `0.1s`

`fn_fpv_shouldDetonateNow.sqf` decides when to trigger the final strike. Default detonation windows are:

- `AT`: `18m` 3D or `9m` 2D
- `RECON`: `12m` 3D or `6m` 2D
- `AP`: `14m` 3D or `7m` 2D
- with a default vertical window of `12m`

Finally, `fn_fpv_detonateCompat.sqf` converts the drone into a role-appropriate ammo object, unregisters it, and triggers the payload without relying on a physical collision.

That terminal detonation design is good. The chase problem is not the final hit logic. The chase problem is getting the drone onto a convincing final line.

## What "Waypointing" and "Pathing" Actually Mean Here

The current project does not implement a real waypointing system for drones.

In practice, pathing is this:

- search mode: occasional random `doMove` orders around a site center
- tracking mode: repeated `doMove` orders toward a predicted intercept point
- terminal mode: repeated `doMove` orders toward a tighter point near the target

There are no:

- persistent waypoints
- path graphs
- obstacle-aware pursuit paths
- last-known-position search cones
- direct velocity or nose-vector steering
- high-authority terminal dive controller

So the UAV AI is doing most of the real flight behavior. A3UE is mainly supplying moving destinations, speed hints, and state transitions.

## Why the Drones Feel Slow and Easy to Evade

### 1. Behavior tuning is mostly running on fallback defaults

The controller reads a profile for values such as:

- `trackingSpeed`
- `terminalSpeed`
- `searchRadius`
- `localSearchRadius`
- `trackingMoveDelta`
- `terminalMoveDelta`
- `maxLeadTime`
- `attackHeightASL`
- `terminalGateDistance`
- `detonationDistance`
- `dropTargetDistance`

But `fn_fpv_buildDoctrine.sqf` currently builds site doctrine for:

- spawn chance
- stock counts
- family weights
- role weights
- class pools

It does not populate the behavior-tuning keys above. As a result, almost all chase behavior is currently driven by hard-coded fallback values in the controller helpers.

That is a real implementation gap. The architecture expects doctrine/profile-driven behavior, but the shipped doctrine only controls spawn composition.

### 2. The chase layer underdrives some airframes

The external vendor base classes show these representative max speeds:

| Family | External base max speed |
| --- | --- |
| ArmaFPV | `190` |
| KVN | `145` |
| fpv_ua | `120` |

Against that, the A3UE defaults are roughly:

| Phase | AT | AP | RECON |
| --- | --- | --- | --- |
| Tracking | `95` | `90` | `85` |
| Terminal | `110` | `100` | `95` |

For fpv_ua this is close to the airframe limit. For ArmaFPV and KVN it leaves a meaningful amount of performance unused.

So even before considering turn logic, the system is conservative on raw speed for at least two of the three supported families.

### 3. Turn authority is low because guidance is `doMove`-only

This is the largest gameplay factor.

The controller never directly controls:

- heading
- bank
- acceleration vector
- desired velocity vector
- high-rate terminal correction

It only sends periodic `doMove` targets and lets the UAV AI solve the rest. That is safe and compatible, but it produces broad turns and delayed corrections. Against a player who changes direction laterally, the drone can look like it is following rather than cutting off.

### 4. Search mode is intentionally relaxed

The no-target loop does not hunt aggressively. It:

- scans only once per second
- repositions the hold target only once every five seconds
- uses a random perimeter point rather than a sector sweep, spiral, or last-known-position search

That makes the drone easy to read and easy to bait through a site’s search ring.

### 5. There is no lost-target behavior

When tracking fails, the controller clears the target and drops back to generic `SEARCHING`. It does not:

- preserve the last good intercept area
- search a local cone around the last known heading
- climb for reacquisition
- tighten to a short-term aggressive search state

That makes evasion too binary. Once the player creates enough lateral or distance separation, the drone becomes forgetful.

### 6. Search radius, drop distance, and terminal thresholds are not coordinated

The defaults are individually reasonable, but they are not yet behaving like a single tuned pursuit model. For example:

- site search is `350` to `700m`
- local search is `250m`
- target drop is `900m`
- terminal gate is `85` to `120m`

This can produce awkward edge cases where the drone is allowed to keep a target long after the site-centered search logic would no longer reacquire it, but still lacks the steering authority to finish the chase cleanly.

### 7. Link-state evaluation is on the hot path

`fn_fpv_evaluateLinkState.sqf` is called every controller iteration, including in high-frequency hot modes. It performs:

- terrain tests
- surface intersection tests
- nearby object scans for retranslators and jammers

That is not the source of the slow turning you observed, but it is a quality concern. It raises the cost of increasing control-loop frequency, which is one of the most natural ways to make the drones more responsive.

## Quality Review

### What is good

The implementation has several strong design decisions:

- locality is handled correctly through `fn_fpv_bootstrapLocal.sqf`
- spawn and chase responsibilities are cleanly separated
- the four-state controller is simple and extendable
- external-control suspension is the right safety behavior
- vendor compatibility is treated explicitly instead of pretending the families are identical
- terminal detonation is normalized and does not depend on physics collision luck

Those are real strengths. The repo is not suffering from a broken architecture. It is suffering from an incomplete behavior layer.

### Gaps and issues that should be addressed

#### 1. Doctrine/profile behavior data is incomplete

This is the clearest implementation gap.

The codebase has a profile abstraction, but behavior values are not actually being authored in the doctrine. That makes the controller appear configurable while still behaving as a mostly hard-coded system.

#### 2. The guidance model is too passive for FPV strike behavior

Repeated `doMove` is enough for proof-of-function, but not enough for convincing strike-drone aggression. It yields broad turns, late corrections, and pursuit behavior that feels like helicopter AI rather than FPV attack logic.

#### 3. Target selection lacks LOS and tactical context

Current scoring does not consider:

- line of sight
- recent visibility
- target speed
- target heading relative to drone heading
- obstruction cost

That makes selection stable and cheap, but not especially smart.

#### 4. Target hostility is biased toward `teamPlayer`

This may be intentional for Antistasi gameplay, but it is still a real design constraint. When `teamPlayer` is present, drones become specialized anti-player-faction hunters instead of general hostile-site drones.

If that is intended, the behavior is fine. If the design goal is broader battlefield threat response, this should be revisited.

#### 5. The hot path is expensive enough to block finer control updates

Because link-state evaluation sits in the same loop as chase guidance, increasing chase responsiveness also increases EW and raycast cost. The system needs better separation between high-rate movement control and lower-rate link evaluation.

#### 6. There is no dedicated validation harness for chase behavior

The codebase has debug support and clear runtime state, but no behavior-focused automated validation for:

- acquisition timing
- time-to-impact
- reacquisition after jinks
- ownership handoff while tracking

That means future tuning will rely heavily on playtesting unless a lightweight harness is added.

## Architecturally Sound Recommendations

The right path is not a broad rewrite. The right path is to preserve the current ownership model and state machine, then strengthen the behavior layer in stages.

### 1. Complete the profile/doctrine behavior layer first

Highest-value, lowest-risk improvement:

- extend `fn_fpv_buildDoctrine.sqf` so each site profile also carries behavior keys
- optionally split doctrine into two explicit submaps:
  - `spawn`
  - `behavior`
- keep `profileId` meaningful by using it to resolve behavior presets rather than only tagging the UAV

At minimum, define and tune these keys per family or per site-role profile:

- `trackingSpeed`
- `terminalSpeed`
- `searchHeightAGL`
- `searchRadius`
- `localSearchRadius`
- `trackingMoveDelta`
- `terminalMoveDelta`
- `maxLeadTime`
- `attackHeightASL`
- `terminalGateDistance`
- `terminalGateDistance2D`
- `detonationDistance`
- `detonationDistance2D`
- `dropTargetDistance`

This change is foundational because every later recommendation depends on having an actual authored behavior model instead of implicit fallbacks.

### 2. Tune family aggression against real airframe capability

Current behavior flattens the families too much. The external classes are not equal, so the controller should stop treating them as if they are.

Suggested direction:

- ArmaFPV: highest aggression, highest track and terminal speed, fastest update cadence
- KVN: mid-to-high aggression, good speed, slightly more conservative terminal dive because of the fiber-themed presentation
- fpv_ua: lower top speed, but still more responsive than current tracking defaults

The important point is not the exact numbers. The important point is that family differences should be authored deliberately rather than emerging accidentally from vehicle class choice alone.

### 3. Separate coarse navigation from high-rate terminal steering

Keep the existing design for coarse navigation:

- `SEARCHING`: AI `doMove` is fine
- long-range `TRACKING`: AI `doMove` is acceptable

But add a higher-authority terminal layer for the final strike window. For example:

- use AI `doMove` outside a larger distance band
- switch to a dedicated owner-local terminal steering function inside roughly `60m` to `100m`
- drive the final dive with direct vector or velocity control instead of only moving the destination point

This is the single most effective architectural change if the goal is "harder to sidestep" rather than just "numerically faster".

It also limits risk because the more invasive steering logic is contained to the last part of the engagement.

### 4. Replace fixed lead clamping with adaptive lead

The current fixed `maxLeadTime = 3` is too blunt.

Better model:

- longer allowable lead at longer range
- shorter lead near the terminal window
- optional reduction when target angular change is high

In practice, the drone should not keep the same lead cap when the target is `600m` away and when it is `60m` away.

This should stay inside `fn_fpv_computeIntercept.sqf`, keeping the rest of the architecture unchanged.

### 5. Add a `LOST_TARGET` state instead of falling straight back to generic search

Recommended new state between `TRACKING` failure and normal `SEARCHING`:

- preserve last known target position and velocity
- search that area for a short time window
- tighten local search radius around the last-known point
- optionally climb slightly for reacquisition

This makes evasion less binary and gives the drones a more predatory feel without requiring global redesign.

### 6. Increase chase update authority without raising total hot-path cost

To make the drones turn harder, the controller needs more frequent movement correction. But that should not mean running the entire EW/link-state stack at the same higher rate.

Recommended split:

- movement guidance: high rate
- link-state evaluation: cached or lower rate
- expensive environment queries: evented or TTL-based

For example:

- cache link state for `0.25s` to `0.5s`
- invalidate on major position change, retranslator change, or jammer presence change
- let tracking and terminal guidance run more frequently than EW evaluation

### 7. Tighten the geometry of the final attack

The current tracking-to-terminal transition changes vertical behavior from roughly `12m` above target to `6m` above target. A more deliberate attack profile would improve perceived aggression.

Recommended approach:

- use a higher offset during far tracking
- reduce offset continuously with distance rather than switching abruptly
- keep the final terminal line very direct

That should reduce the current wide, arcing feel of the approach.

### 8. Improve target quality, not just chase speed

Add lightweight tactical quality to `fn_fpv_selectTarget.sqf`:

- LOS or occlusion penalty
- score bonus for recently seen targets
- score bonus for targets moving away from site or toward friendly assets
- target stickiness so the drone does not churn between near-equal candidates

This will improve both realism and practical lethality.

## Suggested Improvement Order

If the goal is to make the drones meaningfully more aggressive without destabilizing the whole addon, the best order is:

1. Complete the behavior profile layer in doctrine.
2. Raise family-specific tracking and terminal aggression to match real airframe capability.
3. Cache link-state evaluation so the movement loop can update faster.
4. Add a `LOST_TARGET` state with last-known-position search.
5. Add a high-authority terminal steering mode for the last segment.
6. Improve target scoring with LOS and stickiness.

## Bottom Line

The drones are working, but the current chase model is still a conservative compatibility controller rather than a mature FPV attack controller.

Right now the system proves that the drones can:

- spawn correctly
- pick targets
- chase a target
- respect control ownership
- detonate near the target

What it does not yet prove is that they can pursue like committed strike drones.

The key missing piece is a real behavior-tuning layer plus a more forceful terminal steering model. Once those are added, the existing architecture is good enough to support a much more aggressive result.