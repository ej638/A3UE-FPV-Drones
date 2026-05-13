# FPV Rivals Support Integration

Date: 2026-05-12

## Scope

This document is the single analysis and design reference for adding FPV drones as a Rival support threat in Antistasi Ultimate.

It covers:

- how AU generic aggression and supports differ from the rivals subsystem;
- why FPV drones belong in the rivals event layer rather than the generic support registry;
- which parts of the current A3UE FPV runtime can be reused;
- the AU- and A3UE-side hooks needed for a clean implementation.

## Executive Summary

Antistasi Ultimate has two different hostile-response systems:

- Occupants and Invaders use the main aggression, attack-choice, and support-registry pipeline.
- Rivals do not. Rival attacks against players are selected from a separate discovery, inactivity, and random-event loop.

That split matters for FPV integration. The clean insertion point for FPV drones is the rivals event selector, not the generic AU support registry.

The recommended path is:

1. add FPV as a rival event available only at `INTRUSIVE_ACTIVITY` and `OMNIPRESENT_ACTIVITY`;
2. add a small AU-side hook or registry for custom rival events, or patch one explicit FPV event into the selector as a fast path;
3. reuse the current A3UE managed-drone bootstrap, controller, and compatibility stack once the rival drone exists;
4. add a rival-specific A3UE spawn path that uses `A3A_fnc_RivalsCreateVehicleCrew` rather than the standard crew helper.

## Relevant Code Anchors

### AU generic aggression and supports

- `A3A\addons\core\functions\Base\fn_addAggression.sqf`
- `A3A\addons\core\functions\Base\fn_calculateAggression.sqf`
- `A3A\addons\core\functions\Base\fn_aggressionUpdateLoop.sqf`
- `A3A\addons\core\functions\Base\fn_chooseAttack.sqf`
- `A3A\addons\core\functions\Supports\fn_initSupports.sqf`
- `A3A\addons\core\functions\Supports\fn_requestSupport.sqf`
- `A3A\addons\core\functions\Supports\fn_createSupport.sqf`
- `A3A\addons\core\functions\Supports\fn_showInterceptedSetupCall.sqf`
- `A3A\addons\core\functions\Supports\fn_SUP_UAVAttack.sqf`
- `A3A\addons\core\functions\Supports\fn_SUP_mortar.sqf`

### AU rivals subsystem

- `A3A\addons\scrt\Rivals\Constants.inc`
- `fn_rivals_activate.sqf`
- `fn_rivals_reduceActivity.sqf`
- `fn_rivals_calculateActivity.sqf`
- `fn_rivals_activityUpdateLoop.sqf`
- `fn_rivals_eventLoop.sqf`
- `fn_rivals_rollProbability.sqf`
- `fn_rivals_getEventCooldown.sqf`
- `fn_rivals_getOperationRadius.sqf`
- `fn_rivals_findSuitableEncounterPosition.sqf`
- `fn_rivals_selectAndExecuteEvent.sqf`
- `fn_rivals_encounter_uavFlyby.sqf`
- `fn_rivals_encounter_rovingMortar.sqf`
- `fn_rivals_encounter_heliRaid.sqf`

### AU and A3UE event surface

- `A3A\addons\events\Events.hpp`
- `A3A\addons\events\functions\fn_triggerEvent.sqf`
- `A3UE\addons\functions\Events\fn_addExampleEventListener.sqf`

### Current A3UE FPV runtime

- `functions/fpv/fn_addFPVEventListeners.sqf`
- `functions/fpv/fn_fpv_managerEvaluateSite.sqf`
- `functions/fpv/fn_fpv_managerSpawnDrone.sqf`
- `functions/fpv/fn_fpv_bootstrapLocal.sqf`
- `functions/fpv/fn_fpv_applyCompatInit.sqf`
- `functions/fpv/fn_fpv_selectTarget.sqf`
- `functions/fpv/fn_fpv_getProfile.sqf`

## AU Architecture Analysis

### Occupants and Invaders

The main AU hostile pipeline:

1. player actions push aggression deltas into occupant or invader aggression stacks;
2. `fn_aggressionUpdateLoop.sqf` decays those stacks, recalculates aggression, rescales resources, and triggers attack choice;
3. `fn_chooseAttack.sqf` selects the attack type;
4. support responses go through `fn_requestSupport.sqf` and `fn_createSupport.sqf`.

Key constraints:

- support maps exist only for Occupants and Invaders: `A3A_supportTypesOcc` and `A3A_supportTypesInv`;
- there is no `A3A_supportTypesRiv` and no rival support resource pool;
- the generic support pipeline is not where rival roving mortar or helicopter raids are chosen today.

### Rivals

Rivals use a separate discovery, inactivity, and event loop.

Important inversion:

- the key variable is `inactivityLevelRivals`, not aggression;
- lower numeric level means more rival pressure;
- positive calls to `SCRT_fnc_rivals_reduceActivity` calm rivals down immediately and then decay away.

Current activity labels:

| Level | Label | Meaning |
| --- | --- | --- |
| 5 | Insignificant | Lowest rival pressure |
| 4 | Moderate | Low pressure |
| 3 | Conspicuous | Mid pressure |
| 2 | Intrusive | High pressure |
| 1 | Omnipresent | Highest pressure |

Event cadence:

- the rivals activity loop ticks every 60 seconds;
- the rivals event loop ticks every 300 seconds, then waits for `rivalEventCooldown`, then rolls for an event.

Current roll probability:

| Inactivity level | Event chance |
| --- | ---: |
| 5 | `0%` |
| 4 | `20%` |
| 3 | `40%` |
| 2 | `60%` |
| 1 | `80%` |

Location rules by activity level:

| Level | Where rivals may target players |
| --- | --- |
| 5 | Nowhere |
| 4 | Off-site players only |
| 3 | Off-site players and players at outposts, resources, and factories |
| 2 | Anywhere except HQ |
| 1 | Any rebel player |

This means the user-facing rule "unlock FPV support at intrusive or omnipresent" should be implemented as an explicit availability gate in the rivals event layer.

## Why FPV Belongs in the Rival Event Layer

1. The desired behavior is keyed to rival activity labels, and that logic already exists in the rivals subsystem.
2. The existing rival threats the user wants to mirror, such as roving mortars and helicopter raids, are already implemented as rival events.
3. The generic AU support system has no rival support registry or rival support budget.
4. The current rivals warning UX through `RivalsActivityDetected` already matches the requested player experience more closely than the generic support warning path.

Trying to force FPV into the generic support map would require broader AU surgery than adding one rival event or one custom rival-event registry.

## What the Current A3UE Runtime Can Reuse

### Reusable directly

- `fn_fpv_bootstrapLocal.sqf` already installs locality, deletion, and MPKilled handlers and starts the owner-local controller.
- `fn_fpv_applyCompatInit.sqf` already repairs vendor mods that disable AI.
- `fn_fpv_selectTarget.sqf` already prefers `teamPlayer` when the drone side is hostile to rebels.
- `fn_fpv_getProfile.sqf` can resolve arbitrary doctrine keys if a new doctrine entry such as `RivalsSupport` exists.
- the current metadata-before-`AIVEHinit` ordering allows the existing bootstrap listener to recognize new managed drones automatically.

### What cannot be reused unchanged

1. The current hook surface is site-driven, not rival-event-driven.
2. `fn_fpv_managerEvaluateSite.sqf` expects site markers and persistent site lifecycle, which is the wrong model for one-shot rival pressure events.
3. `fn_fpv_managerSpawnDrone.sqf` uses the standard vehicle crew helper and should not be reused unchanged for rivals.
4. The current doctrine is site doctrine, not rival-support doctrine.

## Event and Extender Gap Analysis

The current AU event registry exposes events such as `AIVehInit`, `locationSpawned`, `AIInit`, `markerChange`, and `Undercover`, but no rival-event selection or rival-event registration hook.

That matters because `A3A_Events_fnc_triggerEvent` is an observer-style dispatcher. Existing listeners can consume an event that already exists, but they cannot cleanly append a new rival event into the local event array inside `SCRT_fnc_rivals_selectAndExecuteEvent` without at least one AU-side hook.

## Recommended Technical Design

### AU-side options

#### Option A: fast feature patch

- add a new rival event constant such as `FPVSTRIKE`;
- extend `SCRT_fnc_rivals_selectAndExecuteEvent` to include that event when A3UE says it is available and `inactivityLevelRivals <= INTRUSIVE_ACTIVITY`;
- schedule an A3UE-owned execute function.

This is the fastest path, but it hardcodes FPV knowledge into AU's selector.

#### Option B: preferred upstream-friendly design

- add a custom-rival-event registry helper such as `SCRT_fnc_rivals_registerCustomEvent`;
- let built-in rival events and extender events share one descriptor format;
- merge built-ins and registered custom events before weighting and execution.

Suggested descriptor:

```sqf
[
    "A3UE_FPV_STRIKE",
    1.0,
    A3UE_fnc_fpv_rivalsEventAvailable,
    A3UE_fnc_fpv_rivalsEventExecute
] call SCRT_fnc_rivals_registerCustomEvent;
```

### A3UE-side recommendations

#### 1. Extract a generic managed-drone spawn helper

Recommended helper:

- `A3UE_fnc_fpv_spawnManagedDrone`

Purpose:

- create the UAV at an explicit position;
- stamp managed metadata before `A3A_fnc_AIVEHinit`;
- choose the correct crew helper for the spawn context;
- rely on the existing bootstrap path for locality and compatibility.

This should be extracted from the common part of `fn_fpv_managerSpawnDrone.sqf` so site stock deployment and rival-event deployment do not diverge.

#### 2. Add rival-event availability logic

Recommended function:

- `A3UE_fnc_fpv_rivalsEventAvailable`

Recommended checks:

- the compat catalog is non-empty;
- at least one usable rival-side class pool exists;
- rivals are enabled, discovered, and not defeated;
- `inactivityLevelRivals <= INTRUSIVE_ACTIVITY`;
- optionally, at least one rebel player exists in a valid target context.

#### 3. Add rival-event execution logic

Recommended function:

- `A3UE_fnc_fpv_rivalsEventExecute`

Responsibilities:

1. choose a player cluster or seed player;
2. choose a spawn ring around that cluster, for example `900..1400m` away at `45..80m` AGL;
3. choose one or two drones based on rival activity level;
4. spawn managed drones through the generic helper using rival crew creation;
5. pre-seed target memory so the drones pursue immediately;
6. trigger a rival-style player warning;
7. clean up the event and update rival cooldown state.

Recommended spawn envelope:

- horizontal spawn ring: `900..1400m`;
- vertical spawn range: `45..80m` AGL;
- popup alert ring: roughly `500..700m` from the player cluster;
- hard timeout: `8..10` minutes.

#### 4. Add a rival doctrine entry

Recommended doctrine key:

- `RivalsSupport` or `RivalsFPV`

Suggested characteristics:

- larger acquisition envelope than normal site stock;
- faster, more aggressive pursuit tuning;
- stock of `[1, 2]` with activity-gated scaling.

#### 5. Use rival-specific crew creation

The rival path should use:

```sqf
private _crewGroup = [Rivals, _uav] call A3A_fnc_RivalsCreateVehicleCrew;
[_uav, Rivals, "event"] call A3A_fnc_AIVEHinit;
```

and not the standard `A3A_fnc_createVehicleCrew` path.

#### 6. Keep bootstrap ordering unchanged

The rival helper must preserve the existing order:

1. create vehicle;
2. stamp `A3UE_FPV_*` metadata;
3. create rival crew;
4. call `A3A_fnc_AIVEHinit`.

## Warning UX and Cleanup

### Player warning path

The new FPV rival event should reuse the existing rivals notification family:

- keep using `BIS_fnc_showNotification` with `RivalsActivityDetected`;
- add a dedicated stringtable description for FPV threat messaging;
- notify nearby rebel or civilian players once the first FPV drone crosses the alert ring.

### Cleanup and activity feedback

The event should mirror existing rival-event cleanup:

- set `isRivalEventInProgress = false` when the event ends;
- refresh `rivalEventCooldown` through the normal rivals helper;
- despawn surviving assets through standard cleanup paths;
- calm rivals down if players destroy all FPV drones before timeout, using the same style of positive `SCRT_fnc_rivals_reduceActivity` call used by roving mortars.

## Implementation Touch Points

### AU files that would need changes

Fast path minimum:

- `A3A\addons\scrt\Rivals\Constants.inc`
- `A3A\addons\scrt\Rivals\fn_rivals_selectAndExecuteEvent.sqf`
- `A3A\addons\scrt\Stringtable.xml`

Preferred extensible path:

- the files above;
- one new rivals registry/helper function and its `CfgFunctions` entry;
- optionally one new AU event definition if explicit rival-event telemetry is desired for extenders.

### A3UE files that would need changes

- `config.cpp`
- `functions/fpv/fn_addFPVEventListeners.sqf`
- `functions/fpv/fn_fpv_managerSpawnDrone.sqf`
- `functions/fpv/fn_fpv_buildDoctrine.sqf`
- new A3UE functions:
  - `fn_fpv_spawnManagedDrone.sqf`
  - `fn_fpv_rivalsEventAvailable.sqf`
  - `fn_fpv_rivalsEventExecute.sqf`
  - `fn_fpv_rivalsNotifyPlayers.sqf`

## Not Recommended Approaches

1. Stuff FPV classes into the existing rival UAV flyby event. That event is a payload-drop flyby, not a managed kamikaze controller.
2. Force rivals into AU's generic support registry. That requires a much broader AU rewrite.
3. Fake a site marker and reuse the current site registry path. Rival attacks are one-shot player-pressure events, not persistent site stock.

## Recommendation

The most coherent implementation path is:

1. add FPV drones as a rival event, not as a generic support type;
2. gate that event explicitly to `INTRUSIVE_ACTIVITY` and `OMNIPRESENT_ACTIVITY`;
3. add either a direct selector patch or, preferably, a small AU custom-rival-event registry;
4. add a rival-specific A3UE spawn and orchestration path that reuses the existing managed-drone bootstrap and controller stack while using rival-specific doctrine and crew creation.

That preserves the current A3UE runtime work, fits AU's existing rival architecture, and avoids a much larger rewrite of AU's generic support system.