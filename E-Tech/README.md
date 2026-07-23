# E-Tech: Vanilla Recipes for AAI Industry + QoL Toggles

Likes [AAI Industry](https://mods.factorio.com/mod/aai-industry)'s new machines, dislikes its recipe rewrites? This mod restores **vanilla recipes** while keeping **everything AAI adds** — plus a handful of optional quality-of-life toggles.

Everything is a startup setting, and every recipe change is guarded so it never fights another overhaul mod (see "Plays nice" below).

## Recipe restore (the core feature)

- **Restores 45+ vanilla recipes** AAI changed back to their vanilla ingredients: transport belt, inserters, mining drills, furnaces, assembling machines, steam engine/turbine, engine units, concrete, oil processing, labs, science packs, electric poles, roboport, radar, turrets, gates, armor tiers, vehicles, and more.
- **Science packs are hand-craftable again** (AAI makes them assembler-only).
- **Keeps all AAI content untouched**: burner assembling machine, burner lab, burner turbine, industrial furnace, area mining drill, fuel processor, concrete/steel walls and gates, stone path, small iron pole, motors, glass, sand, stone tablets. Their recipes stay AAI's — they're new items, that's their design.
- **Tech tree untouched.** Research progression, unlock order, triggers — all remain AAI's. Recipes simply cost vanilla ingredients once unlocked.
- **Krastorio 2 aware.** With K2 (and K2 Spaced Out) installed, recipes restore to *K2's* values, not raw vanilla — i.e. the exact state a K2 game had before AAI was added. Names/icons AAI reskinned (engine unit ↔ "multi-cylinder engine") are restored too, and AAI's redundant duplicate recipes (e.g. its "single-cylinder engine" and "electronic circuit (wood)") are hidden from the crafting menu.

## Optional tweaks (each its own startup toggle)

| Setting | Default | What it does |
|---|---|---|
| Pick up & re-place the crashed ship | on | Crash-site spaceship parts become minable and get placement items |
| Allow all modules in beacons | on | Every beacon accepts every module type, productivity and quality included (modded beacons too). Beacon strength unchanged |
| Allow quality in asteroid crushing/reprocessing | on | Enables quality on all asteroid crush/reprocess recipes so quality modules in the crusher take effect |
| Quality adds module slots to all machines | on | Needs the Quality mod. Every machine with at least one module slot gains extra slots at higher quality — assemblers, furnaces, silos, beacons, drills, labs, modded ones included. Affected machines say so in their tooltip. Replaces the retired QualityEffectsFixed mod |
| Vanilla engine unit names & icons | on | Restores the vanilla names/icons AAI reskins ("Multi-cylinder engine" → Engine unit). Turn off if another mod should own their look |
| Nuclear fuel stack size | 1 (vanilla) | Set any stack size 1–1000 |
| Artillery shell stack size | 1 (vanilla) | Set any stack size 1–1000 |
| Agricultural science pack spoils | on (vanilla) | Turn off to stop agricultural science packs from spoiling |
| Restore nuclear fuel crafting (K2) | off | Brings back the vanilla nuclear fuel item/recipe that Krastorio 2 hides, unlocked by Kovarex enrichment as in vanilla. Off by default — hiding it is a deliberate K2 balance choice |
| Teleport-to-player shortcut | off (experimental) | Toolbar shortcut for multiplayer: one other player online = click teleports to them; several = a picker window opens |
| Teleporter pads | off | Buildable teleporter pads (chemical science tech) — walk onto one, pick a destination from a map GUI. Port of [Teleporters](https://mods.factorio.com/mod/Teleporters) by Klonan (LGPLv3 — see `LICENSE-third-party.txt`) extended with: energy cost drained from the destination pad (map settings, 0 = free), cross-surface teleporting with a surface filter + custom surface display names, a wireless-remote toolbar shortcut, a free return teleport with live camera preview, and your team's players in the list. Coming from the original mod? Run `/etech-migrate-teleporters` while both mods are installed — placed pads (names included), inventory items, and research carry over; then remove the original. QoL: right-click a pad in the list to star it (starred sort first), Shift+right-click renames, sort dropdown (recent / A–Z / nearest), distance shown per pad, up to 3 stacked return slots, unpowered-pad map alerts, teleport sound with volume setting, and a SHIFT+T hotkey for the remote |
| Resource map markers | off | Auto-tags resource patches on the map: one marker per patch with icon + total amount (oil shows well count and average yield). Updates as you chart and mine; delete a marker to mute that patch; `/etech-markers-rebuild` rescans. Written from scratch for E-Tech as a 2.1 replacement for the abandoned Resource Map Label Marker mod |
| Total productivity | off | Productivity modules allowed on recipes the game normally forbids — belts, inserters, rails, pipes, solar, walls, ammo, equipment — with four category group toggles. Port of [Total Productivity](https://mods.factorio.com/mod/Productivity) by AivanF (LGPLv3 — see `LICENSE-third-party.txt`); auto-skipped if the original is installed |
| Jetpack fuel HUD | off | Needs [Jetpack](https://mods.factorio.com/mod/jetpack). Movable in-flight window with fuel, count, burn bar, and remaining flight time. Port of [Puppy's Jetpack UI](https://mods.factorio.com/mod/puppy-jetpack-ui) (MIT) with the window-position reset bug fixed and no flib dependency; auto-skipped if the original is installed |
| Uranium bacteria on Gleba | off | Needs Space Age. Mirrors iron/copper bacteria: jelly → 1% uranium bacteria (Jellynut tech), bacteria + bioflux → ×4 in a biochamber (Bacteria cultivation tech), spoils into uranium ore. Port of the abandoned [Simple Gleba Uranium](https://mods.factorio.com/mod/simple-gleba-uranium) by cindersash (MIT — see `LICENSE-third-party.txt`); saves from that mod keep their items |
| Void chest & void pipe | off | Cheap void chest (destroys any item put in) and void pipe (destroys any fluid pumped in), unlocked by a small early tech. Port of [Easy Void](https://mods.factorio.com/mod/easyvoid) by zoryn (MIT); prototype names unchanged so placed voids from the original survive the switch; auto-skipped if the original is installed |
| Void: filtered void chest | off | Second (greenish) void chest that destroys only the items you pick — set an infinity filter to "exactly 0" per item to void; everything else sits. Same tech unlock. E-Tech addition on top of the Easy Void port |
| Edit map settings in-game | off | Toolbar shortcut opens an editor for map settings (pollution, evolution, expansion, peaceful/no-enemies, spoilage rate) and per-surface map gen settings; applying requires admin. Port of [Edit Map Settings](https://mods.factorio.com/mod/EditMapSettings) by Morsk (MIT) with the top-left mod-gui button replaced by the shortcut; auto-skipped if the original is installed |
| FPS-friendly thrusters | off | Removes the animated exhaust plumes from space platform thrusters — the big FPS drain on large platforms. Port of [FPS Friendly Thrusters](https://mods.factorio.com/mod/FPS_Friendly_Thrusters) by RockPaperKatana (MIT); auto-skipped if the original is installed |
| Pass-through fusion generators | off | Fusion generators get input-output plasma connections on all four sides so they chain without separate plasma lines. Port of [pass-through-fusion-generator](https://mods.factorio.com/mod/pass-through-fusion-generator) by daahl (MIT); auto-skipped if the original is installed |
| Colorful biochamber | off | Needs Space Age. Recolors the biochamber's pools, dome and windows per recipe so you can tell what it's making at a glance. Port of [Colorful Biochamber](https://mods.factorio.com/mod/colorful_biochamber) by meifray (public domain); auto-skipped if the original is installed |
| Copy modules with machine settings | off | Shift-click paste moves modules straight from your inventory (old modules handed back, bot request for what's missing); handles ghosts and remote view; furnaces/labs/beacons cross-pastable. Per-player runtime switch. Port of [Copy Paste Modules](https://mods.factorio.com/mod/CopyPasteModules) by kajacx (MIT); auto-skipped if the original is installed |
| Factory outlet, inlet & sensor | off | Needs [Factorissimo 3](https://mods.factorio.com/mod/factorissimo-2-notnotmelon). Bridges items between factory interiors and the outside logistic network: the outlet offers interior provider-chest stock to outside bots (with on-demand mode covering logistic requests AND construction ghosts), the inlet distributes into interior requesters (with auto-request), the sensor writes interior totals to the circuit network. GUI panels with per-factory breakdowns, search, filters, priority, circuit enable. Original E-Tech feature |

Always-on compat fix (legacy Cerys only): **Cerys below 4.24.5** redefined K2's nitric acid at 15°C (below the 25°C minimum K2 recipes expect, starving imersite crystal plants) and dropped the fluid's tooltip data. E-Tech restores K2's definition when it detects that overwrite. Cerys 4.24.5 fixed this upstream — with it installed the fix stays dormant and K2's recipe temperature bounds are left intact.

Stack-size and spoilage defaults match vanilla. A few vanilla-behavior restores are on by default (crashed-ship pickup, all modules in beacons, quality in asteroid crushing, quality module slots, engine-unit cosmetics) — turn those off for a strictly untouched game. Everything that adds content is off by default, so the mod is safe to share with friends who want different settings.

## What the recipe restore deliberately does NOT do

- No tech/progression edits. Pipes etc. still unlock via AAI's research.
- No removal of AAI items/machines — with one exception since 0.17.0: **with Krastorio 2 installed**, `motor` ("single-cylinder engine") is retired. Its icon is a vanilla engine-unit lookalike, so recipe pickers showed two near-identical "engines", and with K2's baseline restored nothing essential needs it. Every recipe that still used it gets iron gear wheels instead (burner lab, fuel processor, Mining Drones, …), AAI's craft-50-motors tech trigger counts gears, and the crash-debris motors become gears. Without K2 the motor stays craftable — the first burner assembler needs a hand-made one.
- `boiler` isn't touched (AAI's ingredients already equal vanilla).

## Plays nice with other overhaul mods

Every recipe restore is guarded by a fingerprint check: a recipe is only touched if it still matches AAI's version or contains an AAI-only item (motor, electric-motor, stone-tablet, glass, sand, …). If another mod — Krastorio 2, for example — has already rewritten a recipe into something else, E-Tech detects that and **leaves it alone**. Krastorio 2 and K2 Spaced Out are optional dependencies so E-Tech loads after them and sees the final state. Summary lines are always logged; turn on the "Verbose recipe-restore logging" startup setting for a per-recipe decision log, then search `factorio-current.log` for `[E-Tech]`.

## Known quirks (by design — tech is out of scope)

- AAI's *basic-logistics* tech trigger is "craft 50 motors" — still required to unlock belts, even though belts no longer use motors. (With Krastorio 2 the trigger counts iron gear wheels instead, since the motor is retired there.)
- A few recipes unlock before every vanilla ingredient is available (e.g. inserter needs electronic circuits, which unlock slightly later in AAI's tree). Nothing breaks; you just craft them a bit later.

## For developers / friends who want to tweak

- [vanilla-recipes.lua](vanilla-recipes.lua) — the recipe data: recipe name → vanilla/K2 values + AAI fingerprint. Add/remove entries freely.
- [data-final-fixes.lua](data-final-fixes.lua) — the engine that applies the restores.
- [beacons.lua](beacons.lua), [misc-tweaks.lua](misc-tweaks.lua), [crash-ship.lua](crash-ship.lua) — the optional tweaks.
- `build.ps1` — packages `E-Tech_<version>.zip` into your Factorio mods folder and archives a copy in `releases/`.

### Module map

Every feature is a self-contained module: a startup toggle in `settings.lua`, its data-stage file required from `data.lua`/`data-final-fixes.lua`, and (if it has runtime logic) an event_handler lib registered in `control.lua`. Absorbed ports auto-skip when their original mod is enabled.

| Module | Files | Toggle | Storage keys |
|---|---|---|---|
| Recipe restore | `data-final-fixes.lua`, `vanilla-recipes.lua` | always on | — |
| Misc tweaks + compat fixes | `misc-tweaks.lua` | per-tweak | — |
| Crashed ship / beacons | `crash-ship.lua`, `beacons.lua` | `etech-pickup-crashed-ship`, `etech-beacon-all-modules` | — |
| Teleport-to-player | `teleport-player.lua` | `etech-teleport-shortcut` | — |
| Teleporter pads | `teleporters/` | `etech-teleporters` | `storage.etech_teleporters` |
| Resource markers | `resource-markers.lua` | `etech-resource-markers` | `storage.etech_resource_markers` |
| Jetpack HUD | `jetpack-ui.lua` | `etech-jetpack-ui` | `storage.etech_jetpack_ui` |
| Total productivity | `productivity/data.lua` | `etech-total-productivity` | — |
| Gleba uranium | `gleba-uranium.lua` | `etech-gleba-uranium` | — |
| Void chest/pipe | `voidchest/` | `etech-void` (+`-filtered`) | `storage.pipes` |
| Map settings editor | `edit-map-settings/` | `etech-map-settings` | — (GUI only) |
| Copy modules | `copy-paste-modules.lua` | `etech-copy-paste-modules` | — |
| Colorful biochamber | `biochamber/` | `etech-colorful-biochamber` | — |
| Factory outlet/inlet/sensor | `factory-hub/` | `etech-factory-hub` | `storage.etech_factory_hub` |

One-shot save cleanups go in `migrations/` (run once per save), not `on_configuration_changed`. Lua is linted by luacheck in CI (`.luacheckrc`).

## License

None (public domain). Do whatever you want with it. Exceptions: the ported features listed below keep their original licenses — full texts and per-port modification notes in `LICENSE-third-party.txt`.

## Credits — mods absorbed into E-Tech

E-Tech carries forward these abandoned/orphaned mods as optional toggles. All credit for the original ideas and code goes to their authors:

- [Teleporters](https://mods.factorio.com/mod/Teleporters) by Klonan (LGPLv3) — teleporter pads
- [Total Productivity](https://mods.factorio.com/mod/Productivity) by AivanF (LGPLv3) — total productivity
- [Puppy's Jetpack UI](https://mods.factorio.com/mod/puppy-jetpack-ui) by Puppy (MIT) — jetpack fuel HUD
- [Simple Gleba Uranium](https://mods.factorio.com/mod/simple-gleba-uranium) by cindersash (MIT) — uranium bacteria on Gleba
- [Easy Void](https://mods.factorio.com/mod/easyvoid) by zoryn (MIT) — void chest & void pipe (in turn credits JDOGG, Optera, kendfrey, Rseding91 for the original void mods)
- [Edit Map Settings](https://mods.factorio.com/mod/EditMapSettings) by Morsk (MIT, a fork of Change Map Settings by Erik Wellmann) — in-game map settings editor
- [FPS Friendly Thrusters](https://mods.factorio.com/mod/FPS_Friendly_Thrusters) by RockPaperKatana (MIT) — plume-free thrusters
- [pass-through-fusion-generator](https://mods.factorio.com/mod/pass-through-fusion-generator) by daahl (MIT) — pass-through fusion generators
- [Colorful Biochamber](https://mods.factorio.com/mod/colorful_biochamber) by meifray (Unlicense) — per-recipe biochamber colors
- [Copy Paste Modules](https://mods.factorio.com/mod/CopyPasteModules) by kajacx (MIT) — copy modules with machine settings

Inspired-by (rewritten from scratch, not ports): [Resource Map Label Marker](https://mods.factorio.com/mod/resourceMarker) — resource map markers.
