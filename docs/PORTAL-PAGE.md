# Mod portal copy — paste into https://mods.factorio.com/mod/E-Tech/edit
# (Portal markdown has no tables; description below uses lists only.)

## Title

E-Tech: Vanilla Recipes for AAI Industry + QoL Toggles

## Summary

Restores vanilla recipes while keeping everything AAI Industry adds (Krastorio 2 aware). Plus optional startup toggles: a factory outlet/inlet/sensor set that bridges Factorissimo factory interiors with your logistic network (on-demand mode even supplies construction ghosts), teleporter pads, resource map markers, all modules in beacons, void chests, total productivity, and a dozen more — everything defaults to vanilla behavior.

## Description — copy everything BELOW this line

Likes [AAI Industry](https://mods.factorio.com/mod/aai-industry)'s new machines, dislikes its recipe rewrites? E-Tech restores **vanilla recipes** while keeping **everything AAI adds** — and has grown a set of optional quality-of-life toggles, including revived features from abandoned mods.

Every recipe change is guarded so it never fights another overhaul mod, and every extra is a startup setting that defaults to "change nothing".

## Recipe restore (the core feature)

- **Restores 45+ vanilla recipes** AAI changed: belts, inserters, drills, furnaces, assemblers, steam power, engine units, concrete, oil processing, labs, science packs, poles, roboport, radar, turrets, armor, vehicles, and more.
- **Science packs are hand-craftable again** (AAI makes them assembler-only).
- **All AAI content stays**: burner machines, industrial furnace, area mining drill, fuel processor, wall/gate tiers, motors, glass, sand — their recipes untouched.
- **Tech tree untouched.** Research progression stays AAI's; only recipe ingredients go vanilla.
- **Krastorio 2 aware.** With K2 (or K2 Spaced Out), recipes restore to *K2's* values, not raw vanilla — the exact state a K2 game had before AAI was added. AAI's redundant duplicates (single-cylinder engine, electronic circuit (wood)) are hidden from the crafting menu.

## Optional toggles (all startup settings)

Defaults marked; everything defaults to vanilla behavior.

- **Pick up & re-place the crashed ship** (on) — crash-site parts become minable with placement items.
- **All modules in beacons** (on) — every beacon accepts every module type, productivity and quality included.
- **Quality in asteroid crushing/reprocessing** (on) — quality modules work in the crusher.
- **Nuclear fuel / artillery shell stack sizes** (1 = vanilla) — any stack size 1–1000.
- **Agricultural science pack spoils** (on = vanilla) — turn off to stop it spoiling.
- **Restore nuclear fuel crafting** (off) — un-hides the nuclear fuel Krastorio 2 removes, unlocked by Kovarex enrichment like vanilla.
- **Uranium bacteria on Gleba** (off, needs Space Age) — jelly gives a 1% chance of uranium bacteria, multiply it with bioflux in a biochamber, and it spoils into uranium ore. Revival of the abandoned [Simple Gleba Uranium](https://mods.factorio.com/mod/simple-gleba-uranium) by cindersash (MIT); saves from that mod keep their items.
- **Teleport-to-player shortcut** (off, experimental) — multiplayer toolbar shortcut: one other player online = click teleports to them, several = a picker window.
- **Total productivity** (off) — productivity modules on recipes the game normally forbids: belts, inserters, rails, pipes, solar, walls, ammo, equipment, and more, with four category group toggles. Revival of [Total Productivity](https://mods.factorio.com/mod/Productivity) by AivanF (LGPLv3), auto-skipped if the original is installed.
- **Jetpack fuel HUD** (off, needs [Jetpack](https://mods.factorio.com/mod/jetpack)) — movable in-flight window with current fuel, inventory count, burn bar, and estimated remaining flight time. Revival of [Puppy's Jetpack UI](https://mods.factorio.com/mod/puppy-jetpack-ui) (MIT) with the window-position reset bug fixed; auto-skipped if the original is installed.
- **Resource map markers** (off) — auto-tags every resource patch on the map: one marker per patch with the resource icon and total amount (oil shows well count + average yield). Updates as you chart and mine, respects markers you delete, `/etech-markers-rebuild` rescans. Written from scratch, 2.1-native — replaces the abandoned Resource Map Label Marker mod (whose 2.1 fork crashes on any mod change).
- **Teleporter pads** (off) — buildable teleporters (chemical science tech): walk onto a pad, pick a destination from a map GUI. Revival of [Teleporters](https://mods.factorio.com/mod/Teleporters) by Klonan (LGPLv3), updated for 2.1 and extended: pads have a 200 MJ buffer and teleporting drains the DESTINATION pad (map settings; 0 = free like the original), cross-surface teleporting with a surface filter and custom surface display names, a wireless-remote toolbar shortcut (default 2x cost), a free return teleport with live camera preview after remote jumps, and your team's online players at the top of the list. QoL: right-click a pad to star it, Shift+right-click renames, sort dropdown (recent / A-Z / nearest), per-pad distances, unpowered-pad map alerts, teleport sound with volume setting, SHIFT+T remote hotkey. Upgrading from the original mod? Run `/etech-migrate-teleporters` while both mods are installed — placed pads keep their names, items and research carry over — then remove the original.
- **Factory logistics: outlet, inlet & sensor** (off, needs [Factorissimo 3](https://mods.factorio.com/mod/factorissimo-2-notnotmelon)) — robots can't fly in or out of factory buildings, so these bridge the wall by teleporting items across. The **factory outlet** offers everything made inside your factories to the outside logistic network: in its default on-demand mode it sits empty and fetches items only when the network actually wants them — requester and buffer chests, player and spidertron requests, **and construction ghosts** (including module requests), so blueprints build straight from factory stock; buffer mode instead keeps a set number of stacks of everything on hand. The **factory inlet** is the reverse direction: fill it (or let its auto-request option set its own bot requests) and it distributes into the requester/buffer chests inside. The **factory sensor** outputs interior provider stock as circuit signals. The outlet panel shows everything inside your factories with search, per-factory breakdowns and naming, click-to-locate map pins, and shift-click to grab a stack; per-outlet item filters, stack caps, priorities, circuit enable, and optional storage-chest draining. Reaches nested factories (toggleable), optional range limit and per-item energy cost (map settings). Built for big bases: ghost demand is tracked event-driven, not by rescanning the map. Unlocked alongside logistic robotics; mining an outlet/inlet returns its items to the factories.
- **Void chest & void pipe** (off) — cheap void chest (destroys any item put in) and void pipe (destroys any fluid pumped in), unlocked by a small early tech. Revival of [Easy Void](https://mods.factorio.com/mod/easyvoid) by zoryn (MIT); placed voids from the original survive the switch; auto-skipped if the original is installed. A second toggle adds a **filtered void chest** that destroys only the items you pick.
- **Edit map settings in-game** (off) — toolbar shortcut opens an editor for map settings (pollution, evolution, expansion, peaceful/no-enemies, spoilage rate) and per-surface map gen settings; applying requires admin. Revival of [Edit Map Settings](https://mods.factorio.com/mod/EditMapSettings) by Morsk (MIT); auto-skipped if the original is installed.
- **FPS-friendly thrusters** (off) — removes the animated exhaust plumes from space platform thrusters, the big FPS drain on large platforms. Port of [FPS Friendly Thrusters](https://mods.factorio.com/mod/FPS_Friendly_Thrusters) by RockPaperKatana (MIT); auto-skipped if the original is installed.
- **Pass-through fusion generators** (off) — fusion generators get plasma connections on all four sides so they chain without separate plasma lines. Port of [pass-through-fusion-generator](https://mods.factorio.com/mod/pass-through-fusion-generator) by daahl (MIT); auto-skipped if the original is installed.
- **Colorful biochamber** (off, needs Space Age) — recolors the biochamber's pools, dome and windows per recipe so you can tell what it's making at a glance. Port of [Colorful Biochamber](https://mods.factorio.com/mod/colorful_biochamber) by meifray; auto-skipped if the original is installed.
- **Copy modules with machine settings** (off) — shift-click paste moves modules straight from your inventory (old modules handed back, bot request for what's missing); handles ghosts and remote view; furnaces/labs/beacons cross-pastable. Per-player runtime switch. Port of [Copy Paste Modules](https://mods.factorio.com/mod/CopyPasteModules) by kajacx (MIT); auto-skipped if the original is installed.

## Plays nice with other overhaul mods

Every restore is fingerprint-guarded: a recipe is only touched if it still matches AAI's version or contains an AAI-only item. If another mod already rewrote it, E-Tech leaves it alone. All decisions are logged — search factorio-current.log for [E-Tech].

## Compatibility note

Always-on compat fix (legacy Cerys only): Cerys below 4.24.5 redefined Krastorio 2's nitric acid at 15C, starving imersite crystal plants. E-Tech restores K2's definition when it detects that overwrite; with Cerys 4.24.5+ the fix stays dormant.

## Credits — revived/ported mods

All credit for the original ideas and code goes to their authors; full license texts and per-port modification notes ship in the mod as LICENSE-third-party.txt:

- [Teleporters](https://mods.factorio.com/mod/Teleporters) by Klonan (LGPLv3)
- [Total Productivity](https://mods.factorio.com/mod/Productivity) by AivanF (LGPLv3)
- [Puppy's Jetpack UI](https://mods.factorio.com/mod/puppy-jetpack-ui) by Puppy (MIT)
- [Simple Gleba Uranium](https://mods.factorio.com/mod/simple-gleba-uranium) by cindersash (MIT)
- [Easy Void](https://mods.factorio.com/mod/easyvoid) by zoryn (MIT)
- [Edit Map Settings](https://mods.factorio.com/mod/EditMapSettings) by Morsk (MIT)
- [FPS Friendly Thrusters](https://mods.factorio.com/mod/FPS_Friendly_Thrusters) by RockPaperKatana (MIT)
- [pass-through-fusion-generator](https://mods.factorio.com/mod/pass-through-fusion-generator) by daahl (MIT)
- [Colorful Biochamber](https://mods.factorio.com/mod/colorful_biochamber) by meifray (Unlicense)
- [Copy Paste Modules](https://mods.factorio.com/mod/CopyPasteModules) by kajacx (MIT)

Inspired-by (rewritten from scratch, not ports): [Resource Map Label Marker](https://mods.factorio.com/mod/resourceMarker) — resource map markers.

Everything else: public domain. Source: https://github.com/restjack/E-Tech

---

# FAQ page — copy everything BELOW this line into the portal FAQ tab

## Is it safe to add to an existing save?

Yes. Recipe changes apply on load and the game recalculates recipe availability automatically. Nothing is removed from your world.

## Is it safe to remove?

Mostly. The recipe restores simply revert to AAI's versions. Exception: if you used the **Uranium bacteria on Gleba** toggle, any uranium bacteria items in your world disappear when the feature (or mod) is removed — let them spoil into uranium ore first if you care.

## Does this change the tech tree?

No. Research progression, unlock order and AAI's trigger techs are untouched. Only recipe *ingredients* go back to vanilla (or Krastorio 2's values). That also means AAI's "craft 50 motors" trigger still gates belts — by design, tech is out of scope.

## Does it work with Krastorio 2 / K2 Spaced Out?

Yes, that's a first-class setup. With K2 installed, recipes restore to *K2's* values instead of raw vanilla — the exact state a K2 game had before adding AAI. Recipes K2 owns are detected and left alone.

## A recipe I expected to be restored wasn't. Why?

Every restore is fingerprint-guarded: if the recipe no longer matches AAI's version (because another mod rewrote it), E-Tech skips it rather than fight that mod. Check your log — every decision is logged. Search factorio-current.log for [E-Tech]; skipped recipes are listed by name.

## Where do I unlock the restored nuclear fuel (K2 toggle)?

Kovarex enrichment process, same as vanilla. K2 keeps that technology (repriced), it just removes the fuel — the toggle puts the unlock back. Already researched Kovarex? The recipe appears immediately.

## How does the Gleba uranium loop work?

Requires Space Age and the toggle (default off). On Gleba: 3 jelly gives a 1% chance of uranium bacteria (unlocked by Jellynut research). Then 1 bacteria + 1 bioflux in a biochamber multiplies it to 4 (unlocked by Bacteria cultivation). The bacteria spoils into uranium ore in about a minute — same rhythm as iron/copper bacteria.

## I used the old Simple Gleba Uranium mod. Can I switch?

Yes. E-Tech keeps the original prototype names, so bacteria items and assembler recipes in your save carry over. Disable the old mod, enable the toggle in E-Tech, load, done. Don't run both at once.

## The teleport shortcut doesn't show up.

Three things to check: (1) the startup setting **Teleport-to-player shortcut** is on, (2) restart/reload after changing it (startup setting), (3) shortcuts can be hidden — click the three-dots menu at the right end of the shortcut bar and enable "Teleport to player".

## Does teleport work across planets/surfaces?

Yes. It follows the target's physical position, so it works while they're on another planet or wandering in remote view. With one other player online it teleports instantly; with more it opens a picker.

## The factory outlet sits empty and pulls nothing. Is it broken?

Probably not — that's on-demand mode (the default) working as intended: the outlet only fetches items when its logistic network has unmet demand (requester/buffer chests, player or spidertron requests, construction ghosts). No demand = empty outlet. If you want it to keep stock on hand regardless, open it and uncheck **On-demand mode** (buffer mode). `/etech-hub-debug` prints exactly what every outlet sees and why it is or isn't pulling.

## Bots aren't building my blueprint from factory stock.

Checklist: (1) the outlet is inside the same logistic network as the ghosts (roboport coverage — ghosts outside any construction area generate no demand), (2) the items actually exist in provider chests inside a factory the outlet reaches, (3) construction bots are available in that network. `/etech-hub-debug` shows the ghost demand the outlet currently sees.

## Multiplayer?

Works. All toggles are startup settings, so the host's settings apply to everyone automatically.

## Can you revive another abandoned mod as a toggle?

Open a discussion thread with a link. Small data-stage mods (recipes/items/tweaks) are good candidates; licensing has to permit it.
