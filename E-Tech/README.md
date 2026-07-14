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
| Uranium bacteria on Gleba | off | Needs Space Age. Mirrors iron/copper bacteria: jelly → 1% uranium bacteria (Jellynut tech), bacteria + bioflux → ×4 in a biochamber (Bacteria cultivation tech), spoils into uranium ore. Port of the abandoned [Simple Gleba Uranium](https://mods.factorio.com/mod/simple-gleba-uranium) by cindersash (MIT — see `LICENSE-third-party.txt`); saves from that mod keep their items |

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

None (public domain). Do whatever you want with it. Exception: the Gleba uranium feature (code + icons) is ported from Simple Gleba Uranium by cindersash under the MIT license — see `LICENSE-third-party.txt`.
