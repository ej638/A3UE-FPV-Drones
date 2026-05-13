# A3UE FPV Drones

A3UE FPV Drones is an Arma 3 addon source tree that adds autonomous FPV threat drones to Antistasi Ultimate through Antistasi Extender event hooks. The addon is site-driven rather than module-driven: it listens for Antistasi site lifecycle events, spawns managed drones from eligible sites, and runs one owner-local autonomous controller per active drone.

The runtime stays under the A3UE namespace:

- functions: `A3UE_fnc_fpv_*`
- replicated state: `A3UE_FPV_*`

## What it does

- Hooks Antistasi `locationSpawned` and `AIVehInit` events through post-init registration.
- Builds a runtime compatibility catalog for supported FPV families.
- Soft-detects ArmaFPV, fpv_ua, and KVN at runtime with no hard config dependency on those mods.
- Spawns and manages doctrine-selected FPV drones from active Antistasi sites.
- Restores AI behavior on vendor drones that assume direct player control.
- Runs autonomous search, tracking, terminal attack, terminal vector, impact, and compatibility detonation logic.
- Supports radio-link and fiber-visual compatibility behavior, including jammer and retranslator handling for radio families and fiber trail replication for KVN.
- Suspends autonomous attack behavior while a drone is under direct player or Zeus control.

## Scope

- This addon is for Antistasi Ultimate integration only.
- There is no Eden module workflow in the active addon.
- Deployment is site-driven. Antistasi raw hooks arrive from Airport, Outpost, and Resource creation paths, and the addon normalizes those into Airport, Milbase, Seaport, Outpost, Factory, and Resource doctrine contexts where applicable.

## Requirements

### Runtime

- Arma 3
- Antistasi Ultimate
- Antistasi Extender (A3UE)

### Optional FPV family mods

- ArmaFPV (`ArmaFPV_Data`)
- fpv_ua (`FPV_UA`)
- frtz_fiberoptic_kvn (`frtz_KVN`)

If none of the supported FPV family mods are loaded, the addon can still initialize but will not have compatible drone families to deploy.

## Packaging and local testing

This repository is a source tree, not a launcher-ready local mod. The root contains the addon sources (`config.cpp`, `functions/`, `mod.cpp`) rather than a packaged `@modname/addons/*.pbo` layout.

For normal Arma 3 launcher or LAN testing:

1. Package the addon as `fpv_ai_drones.pbo`.
2. Place it under a local mod folder such as `@A3UE-FPV-Drones/addons/fpv_ai_drones.pbo`.
3. Load it alongside Antistasi Ultimate, A3UExtender, and any supported FPV family mods you want available at runtime.
4. Start an Antistasi mission and validate site-driven drone deployment from active enemy sites.

Notes:

- The `CfgFunctions` paths expect the packaged addon root to be `\fpv_ai_drones\functions\fpv`.
- Unpacked testing is only practical in a file-patching workflow. Packaged PBO testing is the safe baseline.
- Any Arma-compatible packaging workflow is fine; Arma 3 Tools or the VS Code Arma Dev extension are the usual options.

## Repository layout

- `config.cpp`: addon config and `CfgFunctions` registrations
- `functions/fpv/`: runtime FPV manager, bootstrap, controller, guidance, impact, and detonation logic
- `docs/`: consolidated design, implementation, and validation references
- `external/`: checked-in third-party source references used for integration work and compatibility validation
- `mod.cpp`: mod metadata for packaged distributions

## Documentation

- [FPV Antistasi Integration](docs/FPV_Antistasi_Integration.md)
- [FPV Aggression and Terminal Vector](docs/FPV_Aggression_and_Terminal_Vector.md)
- [FPV Impact and Lethality](docs/FPV_Impact_and_Lethality.md)
- [FPV Rivals Support Integration](docs/FPV_Rivals_Support_Integration.md)

## Development notes

- Keep `config.cpp` and `functions/fpv/*.sqf` in sync when adding or renaming runtime functions.
- Preserve the public `A3UE_fnc_fpv_*` and `A3UE_FPV_*` naming contract.
- Avoid adding hard dependencies on external FPV mods unless you intentionally want to change the soft-detection model.
- Prefer updating the consolidated docs under `docs/` instead of recreating split phase or RCA markdown files.