# Changelog

All notable changes to [A3UE] AI FPV Drones. Versions match the Steam Workshop item.

## 1.0.10

- **Fixed: the drone swarm never came on a dedicated server.** When the commander was not also the host (a dedicated server, with or without a headless client), the swarm call took the support point and the money and showed the call area, but no drones launched, and every later call was refused until the mission restarted. Player-hosted games were not affected.

## 1.0.9

- **Your own FPV drone swarm.** The rebel commander can call in a swarm of friendly FPV drones from AU's Supports menu, next to the bomb runs and supply drops.
  - It costs 1 support point and 500 money. No airport is needed.
  - Click the centre of a 300 m circle on the map and launch. Seven drones (3–8, a setting) launch behind the commander and fly in overhead.
  - Each drone takes its own enemy in the circle: static guns and machine gunners first, then infantry. When there are vehicles or boats, anti-tank drones come along and go for armour first.
  - Enemies under cover are taken once nothing in the open is left. Men on the stairs of a patrol tower are the last resort, after 10 s with nothing else to hit.
  - No drone dives at a target with a civilian or one of your own within 15 m.
  - After a minute with nothing left to hit, the swarm leaves. One swarm at a time; AU's support cooldown holds until the swarm is on station.
  - The server flies the swarm. Players can't take its drones over with a UAV terminal.
- **New settings** in a new **Friendly supports** section (Addon Options → [A3UE] AI FPV Drones): **FPV drone swarm (commander)**, on by default, and **FPV swarm size**, 3–8, default 7.
- **Workshop page.** The item is now called "[A3UE] AI FPV Drones - Sites and Supports". Its Required Items are Antistasi Ultimate, CBA and FPV Drone Crocus; Ukraine FPV Drone and KVN are optional. In multiplayer, everyone still needs the same drone packs as the host.

## 1.0.8

- **Low approach for fiber-optic drones.** About one KVN attack in three now comes in low instead of from above.
  - The drone glides down early, skims the ground at 1–4 m with the pilot's weave, and sprints the last 60 m.
  - It flies the lowest safe line over whatever is in its way: up over a tree, a wall, a parked vehicle or a hill, then back down. It passes under power lines.
  - Once it has started a low approach, it never gives it up.
  - Only KVN drones fly low, against soldiers on foot or parked vehicles at least 300 m away when the attack begins. Radio drones (Ukraine FPV, Crocus) would lose their link that low, so they attack as before.
  - When drones take turns on you, the next one may wait about 500 m out and come in low after the first strike.
- **New setting: Low approach chance** (Addon Options → [A3UE] AI FPV Drones → Drone attacks): 0–100%, default 33%. 0% turns low approaches off.
- **Antistasi Ultimate 12.4.2** is now on the tested list, so the server log no longer shows a version notice for it.
- **Contact fuse.** During its attack, a drone now detonates when it touches anything: the ground, a tree, a wall, a soldier or a vehicle. Exactly one warhead fires, even when the drone pack has its own impact charge.

## 1.0.7

- **Settings** in Options → Addon Options → [A3UE] AI FPV Drones (CBA). They are server settings: the host's or server's values apply to everyone.
  - **Site drone frequency:** Off, Less, Normal, More or Always.
  - **Drones per site:** Fewer, Normal or More.
  - **Lost drone replacement:** never, or one drone every 15, 30 or 60 minutes, ready for the next time the site spawns.
  - **Enemy FPV strikes:** on or off.
  - **Earliest war level for FPV strikes:** 1–10, default 3.
  - **Rivals FPV drone:** on or off.
  - **Debug logging:** on or off.
- **Attack waves.** Major attack waves offer an FPV strike only when one is allowed. Below the minimum war level, they no longer swap the refused FPV for an extra attack helicopter.
- **Debug logging only logs.** It no longer makes every site spawn drones; use the "Always" frequency for that.

## 1.0.6

- **Quieter server logs.**
  - Headless clients no longer send a site message that the server could only refuse; the server's own check handles those sites.
  - AU's late "site ready" events for sites the server already handled are ignored quietly. The `siteIntent refused` line now appears only for real problems.
  - Location events for towns, roadblocks and the HQ are no longer logged unless debug logging is on.
- **License notice.** The mod now ships `THIRD-PARTY-NOTICES.txt` with the MIT notices for the Antistasi Ultimate code it adapts.
- **Docs.** A new README, architecture pages, and a known-limitations section.

## 1.0.5

- **Headless clients.** Site drones now deploy when AU runs sites on a headless client: the server confirms each site from AU's own records about 5 seconds after it activates. Before this, a server with a headless client deployed no site drones at all.

## 1.0.4

- **Drones take turns.** One drone attacks each target at a time; the rest circle in overwatch 140–170 m out, and the next one comes in 2.5–3.5 s after each attack ends. Players within 25 m of each other share one attack.
- **Smooth dives on busy servers.** Attacking drones are stepped every frame within a fixed time budget, instead of waiting for the script scheduler. This fixes drones hovering mid-dive on dedicated servers.
- **Lighter drones.** Lower update rates for drones that aren't attacking, one shared target scan per site, and cached radio relays.

## 1.0.3

- **Antistasi Ultimate 12.4.1 support.** Works with AU's new CBA-based events. The mod no longer switches features off on AU versions it hasn't been tested on.

## 1.0.2

- **Load-tolerant dives.** A late dive step is limited to 0.25 s of movement, so a stalled server shows a short slow-down instead of a jump.

## 1.0.1

- Mod logo and version information.

## 1.0.0 (beta)

The first beta. Its features include:

- **Site defence:** enemy airports, military bases, seaports, outposts, factories and resources launch FPV drones, with a limited stock per session.
- **Attack runs:**
  - approach styles (direct, high dive, flank);
  - a committed high-speed dive with pilot-like aim corrections and reaction lag;
  - deliberate near misses;
  - one "flip back" after a close miss;
  - flying over trees.
- **Enemy supports:**
  - FPV strikes for Occupants and Invaders;
  - FPV options in counterattacks, attack waves, HQ attacks and punishments;
  - a Rivals FPV drone event.
- **Drone packs:** support for the Ukraine FPV, KVN fiber-optic and Crocus packs, including KVN cables and radio jamming.
- **Control:** player and Zeus takeover pause the autopilot.
- **Correctness:** one warhead and one settlement per drone, with correct kill credit and AU resource accounting.
