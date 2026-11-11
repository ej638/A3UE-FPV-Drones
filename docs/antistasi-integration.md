# Antistasi integration

How the mod plugs into Antistasi Ultimate (AU): site defence, enemy supports, scheduled attacks and Rivals. For the overall structure see the [architecture overview](architecture.md).

## How it connects

The mod doesn't edit any AU file, and it doesn't need A3UExtender. It connects in four ways, all set up at mission start on the server:

| Mechanism | Used for |
|---|---|
| **AU events.** It subscribes to `locationSpawned` and `AIVehInit` through AU's own event API: the legacy listener API on AU 12.0–12.3, CBA events on 12.4+ | Knowing when a site becomes active or inactive; bootstrapping drones that AU creates |
| **A wrapper round AU's site scheduler** | Marking the site spawns this mod deployed drones for, so activation can be confirmed on the server (see [Headless clients](#headless-clients)) |
| **Runtime patches to AU's support tables and Rivals selector** | Adding the FPV support and the Rivals FPV event |
| **Six replaced AU functions** (`CfgFunctions` overrides) | Scheduled attacks and the intercepted-radio messages that need an FPV branch |

**The six replaced functions** are copies of AU's own code with an FPV branch added:
- `A3A_fnc_singleAttack`, `A3A_fnc_wavedAttack`, `A3A_fnc_attackHQ` and `A3A_fnc_invaderPunish`;
- `A3A_fnc_showInterceptedSetupCall` and `A3A_fnc_showInterceptedSupportCall`.

The AU code they were reviewed against is pinned by hash in [`compat/`](../compat/). `tools/verify_au_adapter.py` reports any drift when AU updates.

**At start-up** the server logs an `A3UE FPV AU adapter SUMMARY` line with the AU version and the state of every hook.
- A hook that can't be installed is reported, and AU keeps its normal behaviour for that feature.
- A newer, untested AU version does not switch anything off; the summary only notes it.

## Site defence

### Which sites

Sites held by the **Occupants or Invaders** (the sides at war with the players) can deploy drones. AU raises `Airport`, `Outpost` and `Resource` events. The mod tells them apart by marker, which gives six site types:

| Site type | Chance of drones | Stock | Role mix (AT / AP / thermal) |
|---|---|---|---|
| Airport | 60% | 2–4 | 60 / 20 / 20 |
| Military base | 50% | 2–3 | 45 / 35 / 20 |
| Seaport | 45% | 1–3 | 25 / 40 / 35 |
| Outpost | 35% | 1–2 | 30 / 50 / 20 |
| Factory | 30% | 1–2 | 20 / 40 / 40 |
| Resource | 25% | 1 | 15 / 45 / 40 |

Bigger sites also favour longer-range KVN and thermal anti-tank classes. See [Drone packs](drone-packs.md#detection-the-compatibility-catalog).

### Stock

- A site rolls its chance and stock **once per side holding it, per session.**
  - Re-activating the same site doesn't re-roll.
  - Drones that were destroyed or spent don't come back at once.
- **Intact drones return** to the stock when the site despawns.
- **Refill:** one drone every 15 minutes (`A3UE_FPV_siteStockRefillSeconds`), up to the rolled maximum.
- **Capture clears the stock.** A site that changes hands starts fresh for its new owner. Drones already in flight from a captured site are fenced so they can't strike for the old owner.
- **Nothing is saved.** The stock lives only for the mission run; nothing is written to the AU save. After a load, every site rolls again.

### Activation and despawn

1. AU's scheduler spawns the site's garrison, on the server or a headless client. The mod's wrapper marks that spawn.
2. AU raises `locationSpawned`. The server records the site as active and queues it.
3. The server queue handles one site per pass:
   - opens the stock;
   - finds launch points at least 800 m from hostile players;
   - spawns the drones (see [A drone's life](architecture.md#a-drones-life)).
4. When AU despawns the site, the server retires its intact drones and cleans up their crews, groups and markers.

A site monitor logs a line if the queue ever looks stuck. It reports; it doesn't restart anything.

## Headless clients

AU can run site garrisons on a headless client (HC):

- **Drones stay on the server.** The site's drones are still spawned, owned and flown by the server. The frame director, attack board and payload all run there.
- **Activation is confirmed on the server.** When AU runs a site on an HC, the activation event fires on the HC, not the server. The HC's notice reaches the server without a verifiable sender, so the server doesn't trust it. Instead:
  - the server reads AU's own record of which sites are active;
  - it promotes a site the wrapper scheduled once AU shows it active, after a short grace period (about 5 s);
  - no HC or client input is needed, so the security checks stay strict.
- **The HC sends nothing.** Since 1.0.6 the HC doesn't send its notice at all. On a hosted game or a server without an HC, AU's own event often arrives after the server has already handled the site; that late duplicate is ignored quietly.

Tested on a dedicated server with one HC and one player (1.0.5): every site's drones deployed, all drones ran on the server, and turn-taking and paid supports worked.

## Enemy supports: the FPV strike

The mod adds an `FPV` support type to AU's Occupant and Invader support tables, next to AU's own UAV, CAS and artillery supports.

- **When it's offered:**
  - from war tier 3, when at least one drone pack is loaded;
  - when the side holds a site that can launch it.
- **Where it launches from:** a nearby site or base the side holds.
  - AU's own rules decide which bases are eligible (cooldown, garrison, spawn positions).
  - The launch point keeps the 800 m standoff from the target and from hostile players.
  - A reach check makes sure the drone can fly out, find the target and attack with fuel to spare.
- **What it costs:** AU charges it from the side's normal support resources, like any other support.
  - A drone that strikes is consumed.
  - A drone that comes home intact is refunded as AU would refund any surviving asset.
- **Safety:** an engagement is refused when units the strike must not hit are too close to the target. Every vehicle occupant is checked.
- **Refusals are logged.** Each refused FPV support call writes one RPT line naming why (war tier, no launch point, unsafe engagement, no visible target, ...).
- **Radio intercepts.** When players intercept enemy radio traffic, FPV support calls show up with their own message and map marker.

## Scheduled attacks

AU's own attack scripts get an FPV option through the replaced functions:

| AU attack | FPV behaviour |
|---|---|
| Counterattack (`singleAttack`) | Tries an FPV support first, within the same budget. The conventional force is reduced only if the FPV is actually committed |
| Major attack waves (`wavedAttack`) | FPV counts in the same air-support lane as UAV and CAS and launches from the wave's origin. From war tier 7 it can send two drones |
| HQ attack (`attackHQ`) | Tries an FPV support first, then falls back to AU's normal UAV support |
| Invader punishment (`invaderPunish`) | Adds an FPV support without removing anything from AU's normal punishment package |

## Rivals

Rivals (AU's third hostile faction) don't use the support system. They pick events from their own random event loop, including a drone attack (`UAVGRENADE`). The mod wraps that selector and the drone event handler:

- If the Rivals faction has its own drones, AU's normal drone event runs unchanged.
- If it has none and a drone pack is loaded, the drone event stays in the pool and launches a managed FPV, which uses the same flight model and turn-taking as site drones.
- If neither is available, the event is re-rolled cleanly instead of failing.

## Accounting

AU tracks what each side spends. The mod keeps that consistent:

- **Site drones** come from the site's free stock. They don't cost the side resources, and AU never refunds them.
- **Support and attack drones** are prepaid through AU.
  - A drone that **strikes** is consumed: it is switched out of AU's refund path before the airframe and crew are retired, so the side doesn't get its money back.
  - A drone that **survives** (despawn or expiry) keeps AU's normal refund.
- **Exactly once.** Every drone is settled exactly once (stock, support state, AU accounting), even when a kill, a native detonation and a deletion race each other.

## When AU updates

- The mod checks AU's functions at start-up and logs what it found. It never refuses to run just because AU is newer.
- The six replaced functions are the part most sensitive to AU changes.
  - With no drone pack loaded, AU's own current version of each function runs.
  - With a pack loaded, the mod's copy runs. If AU changes one of them, the game uses the mod's older copy until this mod is updated.
  - That is why `compat/` pins their hashes and the drift check exists.
- Tested AU versions: 12.0.3 and 12.4.1.
