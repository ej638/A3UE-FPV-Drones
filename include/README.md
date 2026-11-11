# Build-only include snapshots

HEMTT resolves absolute includes through this root-level `include/` tree. These files are build inputs, outside `addons/`, and are never packed. Builds work without the ignored `external/` references, a P drive, or a CBA installation. This does not add a CBA runtime dependency.

The six reviewed AU override scripts include `\x\A3A\addons\core\script_component.hpp`. The snapshots retain that include hierarchy and all nested paths; [AU-04's compatibility gate](../compat/antistasi-12.0.3/README.md) now pins their hashes:

| Build header | Copied from the local reference tree |
|---|---|
| `x/A3A/addons/core/script_component.hpp` | `external/A3-Antistasi-Ultimate-12.0.3/A3A/addons/core/script_component.hpp` |
| `x/A3A/addons/core/Includes/script_mod.hpp` | The same Antistasi core's `Includes/script_mod.hpp` |
| `x/A3A/addons/core/Includes/script_version.hpp` | The same Antistasi core's `Includes/script_version.hpp` (12.0.3) |
| `x/A3A/addons/core/Includes/script_macros.hpp` | The same Antistasi core's `Includes/script_macros.hpp` |
| `x/A3A/addons/core/Includes/cba_events.hpp` | The same Antistasi core's `Includes/cba_events.hpp` |
| `x/A3A/addons/core/Includes/common.inc` | The same Antistasi core's `Includes/common.inc`, with the compatibility change below |
| `x/A3A/addons/core/Includes/LogMacros.inc` | The same Antistasi core's `Includes/LogMacros.inc` |
| `x/cba/addons/main/script_macros_common.hpp` | `external/A3UExtender-master/A3UE/addons/core/Includes/script_macros_common.hpp` (existing CBA header copy) |

All copies are unchanged except `common.inc`: `FIX_LINE_NUMBERS()` is empty in the build snapshot. The upstream macro emits a `#line` directive through macro expansion that HEMTT 1.22.0's SQF parser rejects. HEMTT already records source locations in compiled SQF. Original runtime SQF remains unchanged and still resolves the loaded Antistasi header when preprocessed in Arma; compiled SQFC uses the build snapshot.

`.hemtt/project.toml` enables HEMTT's runtime macros so the upstream `__A3_DEBUG__` condition can be evaluated for a normal release. When upgrading supported Antistasi versions, review these snapshots and validate the compiled override behavior in game. Do not automatically synchronize from `external/` or edit that reference folder.

Upstream notices are retained in [LICENSE-Antistasi.txt](LICENSE-Antistasi.txt) and [LICENSE-CBA.md](LICENSE-CBA.md). The Antistasi license was copied from the same 12.0.3 reference tree. The CBA license came from the official [LICENSE.md at revision 07f39d70267f6f71d15124f9b72be24193198948](https://github.com/CBATeam/CBA_A3/blob/07f39d70267f6f71d15124f9b72be24193198948/LICENSE.md); it does not assign a new license to this addon.
