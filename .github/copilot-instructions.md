## Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.


# Arma3-AI-FPV-Drones

- This repository contains an Arma 3 addon that adds autonomous FPV kamikaze drones. In gameplay terms, mission makers place an Eden module, sync it to a UAV, configure targeting and attack settings, and the drone then searches for and attacks valid enemy targets.
- Treat the addon config as the source of truth for names and public identifiers. The current module names are `FPV AI Drones`, `FPV AI Drones - Anti-Tank`, and `FPV AI Drones - Anti-Personnel`.
- The repo is built around Arma 3 addon config and SQF scripts. Core wiring lives in `config.cpp`; runtime behavior lives in `functions/fn_initModule.sqf` and `functions/fn_fpvLogic.sqf`.
- Module settings cover target unit kinds, target source, search height, detection range, attack distance, horizontal attack distance, attack height, allowed vehicle occupants, ammo type, and stuck-recovery timing.
- Autonomous attack behavior should be treated as suspended when the UAV is under direct player or Zeus control.
- Preserve compatibility with vanilla and modded Arma 3 UAVs and vehicles. Avoid adding hard dependencies unless explicitly requested; CBA is optional, not required.
- When changing or adding a module attribute, keep `config.cpp` property definitions, default values, and the matching SQF `getVariable` lookups in sync.
- Keep existing public names stable. Do not casually rename config classes, exported function names, module properties, or prefix conventions such as `FPV_AI_Drones_*`.
- Match the existing SQF style: `params` blocks at the top, `private` locals, direct use of engine commands, and small focused changes over broad rewrites.
- For user-facing documentation, describe the Eden Editor workflow clearly: place the module, sync it to a UAV, configure target and attack parameters, and let the drone engage matching targets automatically.