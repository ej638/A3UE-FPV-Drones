# Drone packs

The mod has no drones of its own. It flies the drones from other mods ("drone packs") when they are loaded. This page explains how a pack is detected, what is adapted, and why adding a pack takes real work.

## Supported packs

| Pack | Detected by (`CfgPatches`) | Family id | Link | Classes used |
|---|---|---|---|---|
| [FPV Drone Crocus](https://steamcommunity.com/sharedfiles/filedetails/?id=3045129955) | `ArmaFPV_Data` | `armafpv` | Radio | `O/B/I_Crocus_AT`, `_AP`, and their `_TI` thermal variants |
| [Ukraine FPV Drone](https://steamcommunity.com/sharedfiles/filedetails/?id=3475006113) | `FPV_UA` | `fpv_ua` | Radio | `O/B/I_UAFPV_PG7VL_AT`; `_IED_AP`, `_RKG_AP`, `_OG7V_AP` |
| [KVN fiber-optic FPV](https://steamcommunity.com/sharedfiles/filedetails/?id=3715322527) | `frtz_KVN` | `kvn` | Fiber | `frtz_O/B_KVN_AT`, `_AP`, with `_20KM`/`_25KM` range and `_TI` thermal variants |

None of them is a hard dependency: the addon's config doesn't require any of them.

## Detection: the compatibility catalog

At start-up `A3UE_fnc_fpv_buildCompatCatalog`:

1. checks which of the three packs are loaded;
2. checks that each expected drone class exists, per side;
3. builds a catalog of usable classes by side (Occupants, Invaders) and role:
   - anti-tank;
   - anti-personnel;
   - "recon", meaning thermal or longer-range strike variants, since no pack has a pure recon drone;
4. works out each class's warhead and link type, and finds the packs' relays and jammers.

**Doctrine** (`A3UE_fnc_fpv_buildDoctrine`) then sets, per site type:
- how likely a site is to have drones, and how many;
- which roles it favours;
- how the loaded packs are weighted. For example, airports favour long-range KVN classes and thermal anti-tank drones; outposts lean towards anti-personnel drones.

Packs that aren't loaded simply drop out of the weights.

If no pack is loaded, the catalog is empty:
- sites deploy nothing;
- the FPV support is not offered;
- Rivals keep their normal drone event.

## What every pack needs adapting

The packs are built for a **human pilot**. Their init scripts switch the drone's AI off, and their scripts assume a player with a UAV terminal. To fly them autonomously, the mod:

- **Restores the AI** after the pack's own init, on whichever machine owns the drone, and starts exactly one controller.
- **Wraps, never replaces wholesale.** Each adapter wraps one specific pack function and changes behaviour only for drones this mod manages.
  - Unmanaged drones (one a player launches themselves) still go to the pack's own code.
  - Adapters are installed at start-up and re-checked when a drone boots. They don't add a background loop.
- **Keeps the drone targetable.** Some packs make their drones invisible to enemy AI while a player flies them. Managed drones stay targetable, so AI can shoot them down.
- **Keeps the pack's player features.** If a player takes control of a managed drone, the pack's HUD, signal effects and controls work as normal. The autopilot steps aside (see [Flight model](flight-model.md#player-and-zeus-control)).

## Warheads

A strike must produce **exactly one** explosion with the correct kill credit. That is harder than it sounds:
- several packs detonate the drone from their own hit handlers;
- a drone can be shot, crash and be deleted in the same moment.

- **The managed strike.** When the fuse fires, the server creates the warhead and retires the airframe. While a managed strike is in progress, the pack's own detonation is blocked.
- **The warhead follows the airframe**, not the drone's tactical role:

  | Physical payload | Warhead |
  |---|---|
  | Anti-tank (`AT`, Ukraine `PG7VL`) | `A3UE_FPV_AT`, this mod's tandem HEAT charge, based on the vanilla Vorona missile |
  | Anti-personnel (`AP`, Ukraine `IED`, `OG7V`, `RKG`) | Vanilla `R_TBG32V_F` thermobaric charge |
  | Ukraine `TBG7L` | The pack's own `UA_TBG7L_HE` |

- **Native detonations still count.** If a pack's own hit handler blows the drone up (for example after a collision), the mod records the loss with the real killer. The drone is settled once, as consumed.

## Pack-specific behaviour

### Ukraine FPV

- The pack swaps the drone object when its payload is changed. The adapter keeps the managed state across that swap, and blocks payload and inventory changes on managed drones.
- Its config hit handler detonates the drone and deletes the crew. The adapter records the loss and the killer first, so AU doesn't refund the drone as if it survived.

### KVN (fiber-optic)

- **Fiber cable.** KVN draws a fiber cable behind the drone from a path its own pilot loop records. With no human pilot, the mod's controller writes that path.
  - Clients see the cable trail behind autonomous drones as they would behind a player's.
  - The adapter makes sure KVN's own path writers don't fight the controller.
- **Dead fiber.** When a KVN drone strikes, its cable is archived and stays visible for KVN's configured time, as KVN intends.
- **No jamming.** Fiber drones ignore radio jammers.
- **Range variants.** The `_20KM` and `_25KM` classes are preferred at bigger sites.

### Crocus and Ukraine FPV (radio)

- **Radio link.** The controller samples the link about once a second. It uses distance to the control point, terrain between them, the packs' relays (`FPV_Retranslator`) and jammers (`Sania`, `Sania_with_tripod`).
  - A weak link degrades the drone.
  - A jammed link makes it hold and wait until the link recovers.
- **Crocus signal.** Crocus shows signal effects on the player's screen when they fly a drone. The adapter feeds those effects from the same link model, so a player who takes over a managed Crocus sees the right signal. The controller and Crocus never both write the link state.

## Adding another pack

Loading another drone mod won't make it fly on its own. Each pack needs:

1. **Detection and catalog entries:** patch name, classes per side and role, and payload.
2. **A warhead mapping**, and a check that the pack's own detonation can't add a second explosion or a double settlement.
3. **Adapters** for anything that assumes a human pilot: disabled AI, HUD and signal scripts, payload swaps, targetability.
4. **Special features**, for example a cable, a different link model or a different airframe.
5. **Flight tuning:** dive speed, turn and descent limits for how the airframe actually handles.
6. **Testing in real games:** strikes, misses, shoot-downs, player takeover, multiplayer.

That's why new packs are only considered when they bring something genuinely new.
