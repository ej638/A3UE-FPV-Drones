# Arma3-AI-FPV-Drones

Arma 3 addon that turns supported UAVs into autonomous FPV kamikaze drones through Eden modules. Mission makers place a module, synchronize it to a UAV, configure target and attack settings, and the drone searches for and attacks matching enemy targets on its own.

The addon is designed around Arma 3's built-in module system. It does not add a separate scenario, UI workflow, or one-click mission action outside Eden.

## What players need to do after subscribing

Subscribing on the Steam Workshop only installs the addon. To actually use it in your own game, you still need to load the mod and set up a mission that uses its Eden module.

If you want to use the mod in your own mission:

1. Subscribe to the Workshop item.
2. Open the Arma 3 Launcher.
3. Enable `FPV AI Drones` in your mod preset.
4. Launch the game with the mod loaded.
5. Open Eden Editor and create or load a mission.
6. Place a UAV that Arma recognizes as a UAV.
7. In the Eden module browser, find one of these modules under the `Effects` category or by searching the name:
	- `FPV AI Drones`
	- `FPV AI Drones - Anti-Tank`
	- `FPV AI Drones - Anti-Personnel`
8. Synchronize the module to the UAV.
9. Adjust the module attributes if needed.
10. Preview, export, or host the mission.

If you are only joining a mission that someone else already configured with this addon, you normally just need the mod enabled before launching the game. For multiplayer, keep the server and clients on the same mod set.

## Quick start in Eden

1. Place a UAV.
2. Set the UAV's side correctly. East drones hunt West targets, and West drones hunt East targets. Other sides currently fall back to civilian targets.
3. Place one of the FPV AI Drones modules.
4. Synchronize the module to the UAV.
5. Leave the preset values as-is or tune the attributes.
6. Start the mission.

At runtime the drone climbs to its search height, looks for the nearest valid enemy within range, then transitions into a final attack run once both distance thresholds are met.

Important: the default `FPV AI Drones` and `FPV AI Drones - Anti-Tank` presets only search for vehicle targets. If you want the drone to attack an enemy soldier on foot, use `FPV AI Drones - Anti-Personnel` or set `Target Source` to `allUnits` and `Target Unit Types` to `Man`.

## Module variants

All three public modules are defined in the addon config and are the supported setup entry points:

| Module | Intended use | Target unit types | Target source | Initial search height | Detection range | Attack distance | Horizontal attack distance | Final attack height | Allow targets in vehicles | Default ammo |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `FPV AI Drones` | General-purpose vehicle attack | `LandVehicle,Car,Tank` | `vehicles` | 50 | 200 | 10 | 3 | 5 | Yes | `SatchelCharge_Remote_Ammo` |
| `FPV AI Drones - Anti-Tank` | Lower search height, vehicle-focused preset | `LandVehicle,Car,Tank` | `vehicles` | 30 | 200 | 10 | 3 | 5 | Yes | `SatchelCharge_Remote_Ammo` |
| `FPV AI Drones - Anti-Personnel` | Infantry-hunting preset | `Man` | `allUnits` | 50 | 200 | 30 | 8 | 8 | No | `DemoCharge_Remote_Ammo` |

The anti-tank and anti-personnel modules also ship with different movement and stuck-recovery defaults, but every preset remains editable through module attributes.

## Module attribute reference

- `Target Unit Types`: Comma-separated class filters checked with `isKindOf`. Examples: `LandVehicle,Car,Tank` or `Man`.
- `Target Source`: `vehicles` searches the global vehicle list. `allUnits` searches all units.
- `Initial Search Height`: Flight height used while the UAV is searching for a target.
- `Target Detection Range`: Maximum distance at which the drone can acquire a valid target.
- `Attack Distance`: Final 3D distance threshold for triggering the terminal attack.
- `Horizontal Attack Distance`: Final 2D distance threshold for triggering the terminal attack.
- `Final Attack Height`: Desired height during the last attack run.
- `Allow Object Parent`: If enabled, targets that are inside a vehicle can still count as valid targets.
- `Custom Ammo Types`: Comma-separated ammo class names that are attached to the drone and detonated at the end of the run. Example: `SatchelCharge_Remote_Ammo,DemoCharge_Remote_Ammo`.
- `Height Adjustment Delay`: Base delay between height corrections during the approach.
- `Stuck Check Interval`: Seconds between checks for stalled or circling behavior.
- `Stuck Detection Threshold`: Minimum relative distance change needed to count as progress.
- `Move Adjustment Delay`: Maximum delay between movement updates when the target is still far away.

## How the addon works

This is the current runtime flow implemented by the addon:

1. On mission start, the module reads its configured attributes.
2. The module looks at its synchronized objects and uses the first synchronized UAV to determine which UAV class it should manage.
3. If no UAV is synchronized, the addon prints `No UAV synchronized with module!` and stops.
4. Every 2 seconds, the module scans all UAVs of that class in the mission and starts the FPV logic for any instance that is not already initialized.
5. Each drone is initialized once, switched to `CARELESS`, set to full speed, given a search height, and marked as active.
6. The drone searches for the nearest valid enemy based on side, target source, class filters, occupancy rules, and detection range.
7. During the approach, the script repeatedly updates movement with `doMove`, predicts short-term target motion from velocity, and lowers the flight profile from the search height toward the final attack height.
8. If the UAV is directly controlled through a UAV terminal or Zeus remote control, the autonomous attack run stops.
9. If the drone stops making enough approach progress, the stuck handler offsets its position and the next scan cycle can try again.
10. Once both final distance checks are satisfied, the configured ammo classes are spawned, attached to the UAV, detached, detonated, and the UAV destroys itself in the strike.

## Behavior details and current limitations

- Settings currently apply per UAV class, not per individual synchronized vehicle. Syncing the module to one UAV of class `X` causes the script to manage every UAV of class `X` found in the mission.
- UAVs of the same class that appear later in the mission are also picked up by the recurring scan.
- Hostility is currently hardcoded around East vs West. A drone on another side will only consider civilian targets unless the script is changed.
- Autonomous attack behavior is suspended while the UAV is under direct player control or Zeus remote control.
- The addon is built on standard Arma 3 modules only. There is no required CBA dependency.
- Compatibility should be best with vanilla and modded UAVs that Arma exposes as UAVs, and with targets whose classes match the configured `Target Unit Types` filters.

## Troubleshooting

- Nothing happens: confirm the mod is enabled in the Launcher, the module is placed, and the module is synchronized to a UAV.
- The drone never finds a target: check the UAV side, `Target Source`, `Target Unit Types`, and `Target Detection Range`. An on-foot soldier will not be targeted by the default or anti-tank preset because those search `vehicles` and filter for vehicle classes.
- The drone is choosing the wrong thing: review `Allow Object Parent` and make sure the target's class actually matches the configured filters.
- The drone stops attacking while you test manual control: that is expected while the UAV is connected to a UAV terminal or remotely controlled by Zeus.
- You want different behavior for two drones of the same class: the current implementation groups by UAV class, so use different UAV classes or adjust the script.
