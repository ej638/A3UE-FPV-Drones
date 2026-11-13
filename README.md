# [A3UE] AI FPV Drones

FPV kamikaze drones for [Antistasi Ultimate](https://steamcommunity.com/sharedfiles/filedetails/?id=3020755032) (AU).

Enemy sites launch drones that fly out on their own, find a target and dive on it. You'll hear the buzz before you see them. Shoot them down, get under cover or keep moving.

**Status:** public beta, version 1.0.7. Available on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3839025629).

## Features

- **Enemy sites defend themselves with drones.** When an Occupant or Invader airport, outpost or resource site becomes active, it may launch a few FPV drones.
  - Each site has a limited stock per session. Lost drones are never replaced mid-fight; a site gets them back slowly, ready for the next time it spawns.
  - Not every site has drones; bigger sites are more likely to have them.
- **The drones fly themselves.** They take off out of sight, fly in above the trees, search the area, pick a target, chase it and dive.
  - Anti-tank drones prioritize vehicles and anti-personnel drones prioritize infantry. With no preferred target around, either will go after whatever it finds.
- **Attacks feel like a pilot is flying them.**
  - Each attack comes in on its own line: straight in, high and steep, or round the flank.
  - The aim is corrected on the way down, so the drone weaves slightly as it closes.
  - Sprinting sideways or changing direction late can make it miss.
  - Not every pass is a direct hit: some hit the ground beside you, and some just miss over your head.
  - A drone that only just misses can pull up, flip over and come back for one more try.
- **They take turns.** When several drones go after the same group, one attacks while the others circle at a distance, then the next one comes in.
- **FPV strikes as an enemy support.** Occupants and Invaders can call an FPV strike on you, launched from a nearby site they hold and paid from their normal resources.
- **Rivals use FPVs too.** If Rivals are on and their faction has no drones of its own, their drone attack launches a real FPV from a loaded pack instead of being skipped.
- **Each drone pack keeps its character.**
  - Ukraine FPV drones carry their own warhead types.
  - KVN fiber-optic drones trail their cable.
  - Radio drones (Ukraine FPV, Crocus) respect jammers and relays.
- **Player and Zeus control.** If a player or Zeus takes over a drone, its autopilot stops; when they let go, it carries on from where the drone actually is.

## Requirements

- [Antistasi Ultimate](https://steamcommunity.com/sharedfiles/filedetails/?id=3020755032). Tested on 12.0.3 and 12.4.1.
- [CBA_A3](https://steamcommunity.com/sharedfiles/filedetails/?id=450814997), which AU already needs.
- **At least one** of these drone packs:

| Pack | Drones |
|---|---|
| [Ukraine FPV Drone](https://steamcommunity.com/sharedfiles/filedetails/?id=3475006113) | Anti-tank and anti-personnel FPVs with several warheads |
| [Fiber-Optic FPV «Knyaz' Vandal Novgorodskiy» (KVN)](https://steamcommunity.com/sharedfiles/filedetails/?id=3715322527) | Fiber-optic anti-tank and anti-personnel FPVs |
| [FPV Drone Crocus](https://steamcommunity.com/sharedfiles/filedetails/?id=3045129955) | Crocus anti-tank and anti-personnel FPVs, a fictional vanilla-style drone |

Every pack is optional; the mod uses whichever packs are loaded. For a fictional setting, load Crocus only. With no pack loaded the mod stays idle and AU keeps its normal supports.

A3UExtender is **not** needed.

## Installation

### Players

1. Subscribe on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3839025629). The drone packs are listed as Required Items; untick any you don't want in the launcher.
2. Load it with Antistasi Ultimate, CBA and your drone packs.
3. Start or continue an Antistasi campaign. There is nothing to place in the editor and no menu to set up.

### Multiplayer and servers

- **Everyone needs the same drone packs as the host or server.**
- The mod runs on the host or server. Clients only need it loaded.
- **Servers that check signatures:** add this mod's `.bikey` from its `keys` folder, plus the keys of the drone packs.
  - This mod's key changes with every update, so replace it when you update.

**What has been tested:**

| Setup | Status |
|---|---|
| Player-hosted, with friends | Tested over many sessions on earlier versions |
| Player-hosted, two players (1.0.5) | Tested: separate and shared attacks, a player leaving mid-attack and rejoining, paid support, save and reload |
| Dedicated server | Tested (1.0.4 and 1.0.5, one player), including a check that players can't impersonate the server |
| Dedicated server with a headless client | Tested (1.0.5, one player) |
| Large groups (5+ players), long sessions on a dedicated server | Not tested yet |

## Settings

Open **Options → Addon Options → [A3UE] AI FPV Drones** (a CBA settings menu).

These are server settings: everyone in the game uses the server's values.
- **Player-hosted:** the host sets them, in the main menu or during the mission.
- **Dedicated server:** a logged-in admin sets them in-game, or the server sets them in CBA's settings file (`cba_settings.sqf`).

| Setting | Options (default in bold) | What it does | Takes effect |
|---|---|---|---|
| Site drone frequency | Off · Less · **Normal** · More · Always | How likely each enemy site is to have drones. Less halves the chance, More raises it by half, Always gives every site drones, Off stops site drones | For sites that haven't spawned yet (see below) |
| Drones per site | Fewer · **Normal** · More | One drone fewer or more at both ends of each site's range, never fewer than one | For sites that haven't spawned yet |
| Lost drone replacement | Never · **Every 15 minutes** · 30 · 60 | How quickly a site gets back drones it lost: one per interval, up to its starting number, for the next time it spawns (see below) | Straight away |
| Enemy FPV strikes | **On** · Off | FPV strikes as an Occupant and Invader support, and in their counterattacks, attack waves, HQ attacks and punishments. Off: AU uses its normal supports | Straight away |
| Earliest war level for FPV strikes | 1–10, **3** | The war level from which those strikes are available | Straight away |
| Rivals FPV drone | **On** · Off | The Rivals' drone attack launches a real FPV when their faction has no drones of its own. Off: normal AU behaviour | Straight away |
| Debug logging | **Off** · On | Extra `[A3UE_FPV]` lines in the server's RPT log for troubleshooting | Straight away |

**Why some settings only affect sites that haven't spawned yet:** each site decides whether it has drones, and how many, the first time its garrison spawns after the mission starts or loads (and again if it changes hands). A changed frequency or drones-per-site setting applies to sites that haven't spawned yet. A site that already spawned keeps its drones until the mission restarts or the site changes hands. Off is the exception: a site that spawned while it was Off decides the next time it spawns, once it's back on.

**How lost drones come back:** a site never gets new drones during a fight; it only launches drones when its garrison spawns. When the site despawns, its surviving drones go back to it. Lost ones come back one per interval, counted from when the site launched them, up to the number it started with, so they're there the next time it spawns.

Chance of drones per site type with each frequency:

| Site | Less | **Normal** | More | Always |
|---|---|---|---|---|
| Airport | 30% | **60%** | 90% | 100% |
| Military base | 25% | **50%** | 75% | 100% |
| Seaport | 22.5% | **45%** | 67.5% | 100% |
| Outpost | 17.5% | **35%** | 52.5% | 100% |
| Factory | 15% | **30%** | 45% | 100% |
| Resource | 12.5% | **25%** | 37.5% | 100% |

Server admins who want to tune flight and performance can find more variables in the [architecture overview](docs/architecture.md#tuning-advanced). Those are unsupported and may change between versions.

## Known limitations

- **Many drones diving at once.**
  - Each player (or group of players within 25 m) is attacked by one drone at a time; the rest wait their turn. This keeps the number of drones diving at once low.
  - A large group spread out near several drone sites can still face one dive per player at the same moment.
  - To protect server FPS, the mod gives diving drones a fixed amount of time each frame. With many dives at once, each drone is steered less often: on a dedicated server, roughly 5 at once is fine, but towards 10 at once the dives look rougher and miss more often.
  - Server FPS is protected, and drones won't freeze in mid-air the way they could before 1.0.4.
  - Up to two simultaneous dives have been tested; larger numbers are estimated from measured costs.
  - Server admins with spare headroom can raise `A3UE_FPV_frameBudgetMs` (see [Tuning](docs/architecture.md#tuning-advanced)).
- **Drones launched together may pick the same player first.** Drones that launch together choose targets at the same moment, so they often queue on the same player before spreading out.

## FAQ

**Does it work outside Antistasi Ultimate?**
No. It relies on AU's sites, supports and resources.

**Does it change AU's files or my save?**
It doesn't edit any AU files.
- It plugs into AU's events and support system while the game runs.
- It replaces six AU attack and support functions with copies that add the FPV option.
- Nothing is written to your save. Drone stock is per session.

See [Antistasi integration](docs/antistasi-integration.md).

**Will you add another drone mod?**
Probably not soon. Each pack needs its own integration work:
- switching off its own control scripts;
- making sure the warhead goes off exactly once and the kill is credited;
- handling its special features (fiber cable, radio link);
- tuning the flight to how it handles.

A pack that brings a genuinely new kind of drone or attack is the most likely to be considered. See [Drone packs](docs/drone-packs.md).

## Reporting a problem

Open an [issue](https://github.com/ej638/A3UE-FPV-Drones/issues) or comment on the Workshop page. Include:

- the mod version (shown in the launcher);
- player-hosted or dedicated (with or without a headless client), and how many players;
- your mod list;
- what happened and roughly when;
- the RPT log from the host or server (`%LOCALAPPDATA%\Arma 3` on a player's PC). Lines from this mod start with `[A3UE_FPV]`.

## How it works

The [architecture docs](docs/architecture.md) explain how the mod is put together:

- [Architecture overview](docs/architecture.md): the parts of the mod, a drone's life from launch to strike, multiplayer authority, performance and diagnostics.
- [Flight model](docs/flight-model.md): how a drone searches, takes its turn, approaches, dives, fuses and recovers from a miss.
- [Drone packs](docs/drone-packs.md): how the Ukraine FPV, KVN and Crocus packs are detected and adapted.
- [Antistasi integration](docs/antistasi-integration.md): sites, stock, enemy supports, scheduled attacks, Rivals and the headless client.

## Building from source

You need [HEMTT](https://github.com/BrettMayson/HEMTT) (1.22 or later) and, for the offline checks, Python 3.12.

```powershell
hemtt check
hemtt build                               # unsigned local mod in .hemttout/build/
python tools/verify_hemtt.py build        # packed contents match the source
python tools/verify_au_adapter.py         # AU override drift check
python -m unittest discover -s tools/tests -p "test_*.py"
```

- To test a local build, add `.hemttout/build/` as a local mod in the Arma 3 launcher. Disable the Workshop copy first, so only one copy is loaded.
- `hemtt release` builds a signed release and makes a new signing key every time.
- Some tests run SQF in [SQF-VM](https://github.com/SQFvm/runtime) when the `FPV_SQFVM` environment variable points to `sqfvm.exe`; without it they are skipped.

### Repository layout

| Path | What it holds |
|---|---|
| `addons/drones/config.cpp` | Addon config, function registration, the managed anti-tank warhead |
| `addons/drones/functions/fpv/` | All runtime code (`A3UE_fnc_fpv_*`) |
| `addons/drones/functions/fpv/au_overrides/`, `au_support/` | The AU functions this mod replaces or adds |
| `compat/` | Pinned hashes of the AU code the overrides were reviewed against |
| `include/` | Build-only AU and CBA headers (never packed) |
| `tools/` | Build verification, the AU drift check and the offline test suite |
| `docs/` | The architecture pages linked above |

## Credits

- The **Antistasi Ultimate** team.
- **Fritz** for Ukraine FPV Drone, **Fritz and Smoke** for KVN, and **DarkBall, Sam and contributors** for FPV Drone Crocus.

This mod includes none of the drone packs' files; it uses their drones when you load their mods.

## License notices

Six functions in this mod are modified copies of Antistasi Ultimate code, used under the MIT License:
- `singleAttack`, `wavedAttack`, `attackHQ` and `invaderPunish`;
- `showInterceptedSetupCall` and `showInterceptedSupportCall`.

Antistasi Ultimate's copyright and license notices, which also cover Antistasi Plus and the Antistasi Community Edition it descends from, are in [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt). That file also ships in the Workshop download.
