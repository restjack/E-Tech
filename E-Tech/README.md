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
| Nuclear fuel stack size | 1 (vanilla) | Set any stack size 1–1000 |
| Artillery shell stack size | 1 (vanilla) | Set any stack size 1–1000 |
| Agricultural science pack spoils | on (vanilla) | Turn off to stop agricultural science packs from spoiling |
| Restore nuclear fuel crafting (K2) | off | Brings back the vanilla nuclear fuel item/recipe that Krastorio 2 hides, unlocked by Kovarex enrichment as in vanilla. Off by default — hiding it is a deliberate K2 balance choice |
| Teleport-to-player shortcut | off (experimental) | Toolbar shortcut for multiplayer: one other player online = click teleports to them; several = a picker window opens |
| Teleporter pads | off | Buildable teleporter pads (chemical science tech) — walk onto one, pick a destination from a map GUI. Port of [Teleporters](https://mods.factorio.com/mod/Teleporters) by Klonan (LGPLv3 — see `LICENSE-third-party.txt`) extended with: energy cost drained from the destination pad (map settings, 0 = free), cross-surface teleporting with a surface filter + custom surface display names, a wireless-remote toolbar shortcut, a free return teleport with live camera preview, and your team's players in the list. Coming from the original mod? Run `/etech-migrate-teleporters` while both mods are installed — placed pads (names included), inventory items, and research carry over; then remove the original |
| Resource map markers | off | Auto-tags resource patches on the map: one marker per patch with icon + total amount (oil shows well count and average yield). Updates as you chart and mine; delete a marker to mute that patch; `/etech-markers-rebuild` rescans. Written from scratch for E-Tech as a 2.1 replacement for the abandoned Resource Map Label Marker mod |
| Total productivity | off | Productivity modules allowed on recipes the game normally forbids — belts, inserters, rails, pipes, solar, walls, ammo, equipment — with four category group toggles. Port of [Total Productivity](https://mods.factorio.com/mod/Productivity) by AivanF (LGPLv3 — see `LICENSE-third-party.txt`); auto-skipped if the original is installed |
| Jetpack fuel HUD | off | Needs [Jetpack](https://mods.factorio.com/mod/jetpack). Movable in-flight window with fuel, count, burn bar, and remaining flight time. Port of [Puppy's Jetpack UI](https://mods.factorio.com/mod/puppy-jetpack-ui) (MIT) with the window-position reset bug fixed and no flib dependency; auto-skipped if the original is installed |
| Uranium bacteria on Gleba | off | Needs Space Age. Mirrors iron/copper bacteria: jelly → 1% uranium bacteria (Jellynut tech), bacteria + bioflux → ×4 in a biochamber (Bacteria cultivation tech), spoils into uranium ore. Port of the abandoned [Simple Gleba Uranium](https://mods.factorio.com/mod/simple-gleba-uranium) by cindersash (MIT — see `LICENSE-third-party.txt`); saves from that mod keep their items |
| Void chest & void pipe | off | Cheap void chest (destroys any item put in) and void pipe (destroys any fluid pumped in), unlocked by a small early tech. Port of [Easy Void](https://mods.factorio.com/mod/easyvoid) by zoryn (MIT); prototype names unchanged so placed voids from the original survive the switch; auto-skipped if the original is installed |
| Edit map settings in-game | off | Toolbar shortcut opens an editor for map settings (pollution, evolution, expansion, peaceful/no-enemies, spoilage rate) and per-surface map gen settings; applying requires admin. Port of [Edit Map Settings](https://mods.factorio.com/mod/EditMapSettings) by Morsk (MIT) with the top-left mod-gui button replaced by the shortcut; auto-skipped if the original is installed |
| FPS-friendly thrusters | off | Removes the animated exhaust plumes from space platform thrusters — the big FPS drain on large platforms. Port of [FPS Friendly Thrusters](https://mods.factorio.com/mod/FPS_Friendly_Thrusters) by RockPaperKatana (MIT); auto-skipped if the original is installed |
| Pass-through fusion generators | off | Fusion generators get input-output plasma connections on all four sides so they chain without separate plasma lines. Port of [pass-through-fusion-generator](https://mods.factorio.com/mod/pass-through-fusion-generator) by daahl (MIT); auto-skipped if the original is installed |
| Colorful biochamber | off | Needs Space Age. Recolors the biochamber's pools, dome and windows per recipe so you can tell what it's making at a glance. Port of [Colorful Biochamber](https://mods.factorio.com/mod/colorful_biochamber) by meifray (public domain); auto-skipped if the original is installed |

Stack-size and spoilage defaults match vanilla, so installing the mod changes nothing until you move a slider or flip a switch — safe to share with friends who want different settings.

## What the recipe restore deliberately does NOT do

- No tech/progression edits. Pipes etc. still unlock via AAI's research.
- No removal of AAI items/machines. `motor` ("single-cylinder engine") and friends stay craftable — AAI's own machines use them (e.g. fuel processor = iron 10 + brick 10 + motor 1).
- `boiler` isn't touched (AAI's ingredients already equal vanilla).
- `offshore-pump` ingredients left as AAI's (vanilla 2.x values unverified; both versions are cheap).

## Plays nice with other overhaul mods

Every recipe restore is guarded by a fingerprint check: a recipe is only touched if it still matches AAI's version or contains an AAI-only item (motor, electric-motor, stone-tablet, glass, sand, …). If another mod — Krastorio 2, for example — has already rewritten a recipe into something else, E-Tech detects that and **leaves it alone**. Krastorio 2 and K2 Spaced Out are optional dependencies so E-Tech loads after them and sees the final state. All decisions are logged; search `factorio-current.log` for `[E-Tech]`.

## Known quirks (by design — tech is out of scope)

- AAI's *basic-logistics* tech trigger is "craft 50 motors" — still required to unlock belts, even though belts no longer use motors.
- A few recipes unlock before every vanilla ingredient is available (e.g. inserter needs electronic circuits, which unlock slightly later in AAI's tree). Nothing breaks; you just craft them a bit later.

## For developers / friends who want to tweak

- [vanilla-recipes.lua](vanilla-recipes.lua) — the recipe data: recipe name → vanilla/K2 values + AAI fingerprint. Add/remove entries freely.
- [data-final-fixes.lua](data-final-fixes.lua) — the engine that applies the restores.
- [beacons.lua](beacons.lua), [misc-tweaks.lua](misc-tweaks.lua), [crash-ship.lua](crash-ship.lua) — the optional tweaks.
- `build.ps1` — packages `E-Tech_<version>.zip` into your Factorio mods folder and archives a copy in `releases/`.

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

Inspired-by (rewritten from scratch, not ports): [Resource Map Label Marker](https://mods.factorio.com/mod/resourceMarker) — resource map markers.
