# Arma3-AI-FPV-Drones

- This repository contains an Arma 3 addon that integrates autonomous FPV threat drones into Antistasi Ultimate through Antistasi Extender event hooks.
- Treat the addon config as the source of truth for public identifiers. The active runtime namespace is `A3UE_fnc_fpv_*`, and replicated runtime state uses the `A3UE_FPV_*` prefix.
- The repo is built around Arma 3 addon config and SQF scripts. Core wiring lives in `config.cpp`; runtime behavior lives under `functions/fpv/`, especially the registrar, manager, bootstrap, controller, and detonation functions.
- FPV deployment is Antistasi-only and site-driven. Active `Airport`, `Outpost`, and `Resource` locations can spawn managed drones automatically; there is no Eden module workflow in the active addon.
- Autonomous attack behavior should be treated as suspended when the UAV is under direct player or Zeus control.
- Preserve compatibility with vanilla and modded Arma 3 UAVs and vehicles. Avoid adding hard dependencies unless explicitly requested; CBA is optional, not required.
- When changing or adding runtime functions, keep `config.cpp` `CfgFunctions` declarations and the matching SQF files in sync.
- Keep existing public names stable. Do not casually rename the patch class, exported function names, or prefix conventions such as `A3UE_FPV_*`.
- Match the existing SQF style: `params` blocks at the top, `private` locals, direct use of engine commands, and small focused changes over broad rewrites.
- For user-facing documentation, describe the Antistasi workflow clearly: active `Airport`, `Outpost`, and `Resource` sites can deploy doctrine-selected FPV drones through A3UE, with runtime soft-detection of supported FPV families.

---
## Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

---
## Implementation and Coding
When finished an implementation and coding phase, provide the user with a phase end summary.
- What was implemented
- The parts of the design/plan that are completed
- If the design/plan was followed or if there was any deviation
- What the user or next agent should do next

---
## Performance Awareness — Always Consider
**For every feature, fix, or code change, consider the performance implications before implementing.** This does not mean avoiding all potentially expensive patterns — sometimes there is no better option. It means:
- Consider alternative approaches and their relative cost.
- If a performance trade-off exists, raise it explicitly when presenting a plan or recommending a change — describe what the cost is, when it occurs, and whether a cheaper alternative exists.
- If the chosen approach has a known performance impact that cannot be avoided, note it in the implementation log entry.