# Archived Legacy Workflow Assessment

Date: 2026-05-07
Status: Archived after the Antistasi-only cleanup removed the old Eden-module workflow from the live addon.

## Scope

This document originally reviewed the legacy implementation that used `config.cpp`, `functions/fn_initModule.sqf`, and `functions/fn_fpvLogic.sqf` to drive FPV drones through Eden modules.

Those files and the associated module config surface are no longer part of the active runtime. The live addon now uses the A3UE Antistasi event-driven path under `functions/fpv/`.

## Historical Findings Preserved For Context

The redesign replaced the old workflow because it had four structural blockers:

- Global module execution without locality ownership.
- Class-wide UAV control instead of per-managed-drone ownership.
- Invalid control flow in the legacy flight script.
- Unprefixed helper closures and state keys in the global namespace.

## Current Runtime Direction

Use these documents for the active implementation instead of this archive:

- `docs/fpv-antistasi-implementation-plan.md`
- `docs/fpv-antistasi-implementation-phases.md`

The active addon surface is now:

- `config.cpp` with only the A3UE FPV `CfgFunctions` namespace.
- `functions/fpv/` for registrar, manager, controller, targeting, link-state, and detonation logic.
- `A3UE_FPV_*` replicated state for managed-drone coordination.