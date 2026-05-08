# Mod Quality Assessment Document (MQAD)

Date: 2026-05-07
Scope: Static review of `config.cpp`, `functions/fn_initModule.sqf`, and `functions/fn_fpvLogic.sqf`.

## 1. Executive Summary

Stability Score: 4/10

Performance Impact: High in multiplayer. Static estimate: once multiple drones and multiple peers are present, the current ownership model can multiply the control loops per drone and push mission-side scripting cost into the visible range.

MP Readiness: Not headless-client compatible and not JIP-safe in its current form.

Structural audit snapshot:

- Dependency bloat is low. `requiredAddons[] = {"A3_Modules_F"};` is lean and does not introduce avoidable hard dependencies (config.cpp:11).
- Class inheritance is correct. The module chain stays on vanilla `Module_F`, and the AT/AP variants inherit from the base FPV module as expected (config.cpp:25-26, 38, 151, 256).
- Resource paths are clean in the reviewed surface. The module icons use absolute vanilla paths, and no addon-owned PAA, sound, or RVMAT resources were found in the repo (config.cpp:41, 154, 259).
- `CfgFunctions` is wired correctly. The file root is absolute and the functions compile into the `FPV_AI_Drones_fnc_*` namespace (config.cpp:15-21).
- Scheduled vs. unscheduled audit is mostly clean. `sleep` is only used inside spawned scheduled code, and there is no `waitUntil`, `onEachFrame`, or event-handler payload doing heavy work.

The foundation is acceptable, but the runtime ownership model is not. The addon currently launches long-lived polling loops globally, scopes control by UAV class instead of synchronized instance, and contains at least one invalid control-flow statement in the main flight script. Those three issues are enough to block a production MP release.

## 2. Critical Issues (Blockers)

### Blocker A: Global module execution without locality ownership

Evidence: config.cpp:46; functions/fn_initModule.sqf:70-90; functions/fn_fpvLogic.sqf:106-113; functions/fn_fpvLogic.sqf:341-368.

Why it matters:

- The Eden module is marked `isGlobal = 1`, so the init function is expected to run on every peer.
- The init function then starts a perpetual `while {true}` watchdog that scans UAVs every 2 seconds and spawns control logic for each matching drone.
- No server gate, locality gate, owner handoff, or `remoteExec` path exists anywhere in the reviewed SQF.
- The per-UAV guard uses `_uavInstance setVariable ["initialized", true];` without network propagation, so each machine tracks its own local copy of that state.

Impact:

- Multiple machines can believe they own the same drone logic.
- Local-only AI commands such as `setBehaviour`, `enableAI`, `flyInHeight`, `forceSpeed`, and `doMove` may execute on non-owning peers and silently fail or fight the owning machine.
- Global commands later in the attack path, especially `createVehicle` and `setDamage`, can be triggered from duplicated logic instances and produce duplicate explosives or inconsistent outcomes.
- If a UAV is local to a headless client, the current code does not adapt. It is therefore not HC compatible.
- Join-in-progress clients can start their own scheduler and re-enter the control path, so the implementation is not JIP-safe.

Recommendation:

- Move ownership to one authority: server or current vehicle owner.
- Gate `fn_initModule.sqf` early with an authority check.
- Run the control loop only where `local _uavInstance` is true, and transfer or restart logic when locality changes.
- Replace the non-public `initialized` flag with a properly prefixed ownership state that is set and cleared on the controlling machine only.

### Blocker B: The module controls all UAVs of a class, not the synchronized instance(s)

Evidence: functions/fn_initModule.sqf:25-36; functions/fn_initModule.sqf:70-90.

Why it matters:

- The module reads the first synchronized UAV only to capture its type name.
- After that, it scans `allUnitsUAV` and controls every UAV whose `typeOf` matches that class.

Impact:

- A mission maker cannot reliably scope the module to one synchronized drone.
- Any other UAV of the same class becomes eligible, even if it was never synced to the module.
- Multiple modules for the same UAV class can conflict with each other.
- The AT/AP variants can accidentally fight over the same airframe if their class filters overlap by mission setup.

Recommendation:

- Build the managed set from synchronized objects, not from `allUnitsUAV` by class match.
- If dynamic discovery is needed, tag only the explicitly synced UAVs and track those tags.

### Blocker C: Invalid `continue` in `fn_fpvLogic.sqf`

Evidence: functions/fn_fpvLogic.sqf:135-138.

Why it matters:

- The `continue;` statement sits outside any enclosing loop.
- In SQF, that is invalid control flow and can terminate the script path exactly when the drone fails to acquire a target.

Impact:

- No-target scenarios are unstable.
- The cleanup path at the end of the script may never run, leaving the drone's local `initialized` flag in a bad state on that machine.

Recommendation:

- Replace the `continue` with an explicit `exitWith` or a structured retry loop that owns the full lifecycle.

### Blocker D: Global namespace pollution from helper closures and state names

Evidence: functions/fn_fpvLogic.sqf:19; 34; 78; 84; 102; 110; 161; 174; 368.

Why it matters:

- `isUnitOfKind`, `findNearestEnemyOfType`, `is_dead`, `isExternallyControlled`, `isStuck`, and `handleStuckPos` are assigned without `private` and without an addon prefix.
- The state key `initialized` is likewise generic and unprefixed.

Impact:

- These globals can be overwritten by mission scripts or other mods.
- Generic names make debugging difficult and increase the risk of cross-mod behavior corruption.
- Repeated spawns keep reassigning the same global symbols.

Recommendation:

- Make the closures private locals or convert them into properly namespaced `CfgFunctions` entries.
- Rename state keys to a tagged form such as `FPV_AI_Drones_initialized`.

## 3. Optimization Gaps

### Gap A: Whole-world scans for target acquisition

Evidence: functions/fn_fpvLogic.sqf:34-68; functions/fn_fpvLogic.sqf:120-134; functions/fn_fpvLogic.sqf:315-324.

Current behavior:

- The target finder starts from either `allUnits` or `vehicles`, filters by side and class, and then loops again to determine the nearest valid target.
- This happens during initial acquisition and again during periodic retarget checks.

Why it is expensive:

- The cost scales with total mission population, not with local tactical relevance.
- The AP preset defaults to `allUnits`, which is the worst-case scan set.

Recommendation:

- Keep target search owner-side, and bound it by detection radius before doing class checks.
- A capped sphere query every few seconds is cheaper than walking the entire mission entity list for every drone.
- If the mod needs persistence at scale, maintain a server-side target registry keyed by side and coarse grid instead of re-scanning world arrays.

### Gap B: Polling architecture instead of instance registration

Evidence: functions/fn_initModule.sqf:70-90.

Current behavior:

- Every active module spins forever and re-discovers drones every 2 seconds.

Why it is expensive:

- The work repeats even when no new drones exist.
- In multiplayer, the duplicated schedulers multiply this cost across peers.

Recommendation:

- Register only the synchronized UAVs once.
- Use object lifecycle or locality-change handling to start or stop logic, rather than a permanent watchdog loop.
- This is the primary "loop bloat" hotspot in the addon.

### Gap C: High-frequency movement loop with repeated expensive state pulls

Evidence: functions/fn_fpvLogic.sqf:209-329.

Current behavior:

- The attack loop runs with a base sleep of `0.05`, repeatedly pulling position, velocity, distance, and altitude values and issuing `doMove` plus `forceSpeed`.

Why it is expensive:

- The loop cadence is close to 20 Hz before additional sleeps are applied.
- The same drone can have this logic duplicated on multiple peers under the current MP model.

Recommendation:

- After fixing locality, profile whether the loop can run at a coarser interval.
- Cache values that do not change inside the same iteration.
- Only reissue `doMove` when the requested move point meaningfully changes.

### Gap D: Runtime chat spam in live code paths

Evidence: functions/fn_initModule.sqf:19-23; functions/fn_initModule.sqf:34; functions/fn_fpvLogic.sqf:114; functions/fn_fpvLogic.sqf:126-132.

Current behavior:

- The addon emits `systemChat` diagnostics during normal module initialization and no-target handling.

Why it is expensive and noisy:

- In MP, each peer can receive duplicate local chat spam due to duplicated script ownership.
- `systemChat` is suitable for debugging, not for persistent release telemetry.

Recommendation:

- Gate these messages behind a debug flag or switch them to `diag_log`/structured logging.

## 4. Technical Debt & Maintainability

### Structural and config notes

- The addon config is generally lean and sane. There is no dependency bloat beyond the required vanilla modules package (config.cpp:11).
- The inheritance chain is straightforward and should not break vanilla module behavior (config.cpp:25-26, 38, 151, 256).
- Asset paths are already absolute, which is the correct dedicated-server-safe form for Arma resources (config.cpp:18, 41, 154, 259).

### Attribute binding drift risk

Evidence: config.cpp:53-137; config.cpp:158-242; config.cpp:263-347; functions/fn_initModule.sqf:5-17.

- The config declares namespaced attribute properties such as `FPV_AI_Drones_AttackDistance`.
- The script reads short keys such as `AttackDistance`, `UnitKinds`, and `TargetSource`.
- One fallback already diverges from config defaults: the base module exposes `AttackDistance = 10`, while the SQF fallback is `7` (config.cpp:87; functions/fn_initModule.sqf:7).

Assessment:

- This is a maintainability risk at minimum, and potentially a functional bug if the runtime variable names do not alias the short keys in practice.
- Even if Eden currently resolves the short keys correctly, the config and SQF are not using one obvious shared source of truth.

Recommendation:

- Normalize attribute reads through one helper or use a single naming convention everywhere.
- Keep fallback defaults identical to the config defaults so variant behavior does not silently drift.

### Comment and naming quality

- The overall intent is understandable, but the file mixes active logic with stale development comments such as "Add this new function at the top" even though the function is already in place (functions/fn_fpvLogic.sqf:160, 200, 206).
- Several locals are declared and never used, including `_uniqueTypes`, `_lastPos`, and `_lastPosTime` (functions/fn_fpvLogic.sqf:54; functions/fn_fpvLogic.sqf:200-201).
- The write to `jac_bonusStealth` introduces an undocumented foreign namespace and should either be documented as compatibility glue or moved behind an explicit integration switch (functions/fn_fpvLogic.sqf:113).

### Refactoring direction

- Split responsibilities into three pieces: module registration, owner-side drone controller, and target-selection utility.
- Convert helper closures into formal `CfgFunctions` entries or private locals.
- Replace repeated polling with explicit state transitions: searching, tracking, terminal attack, externally controlled, cleanup.

### Final verdict

The addon is close to usable in single-player testing, but it is not ready for reliable multiplayer deployment. The config layer is acceptable; the runtime layer needs an ownership rewrite, synchronized-instance scoping, and a control-flow fix before further tuning work is worthwhile.