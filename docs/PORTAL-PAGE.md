# Mod portal copy — paste into https://mods.factorio.com/mod/E-Tech/edit
# (Portal markdown has no tables. Style: many small headers, short paragraphs,
#  bold lead-ins, bullets kept to 1-2 lines. Avoid walls of text.)
#
# IMAGES: upload each on the mod's edit page first, then swap the IMG-n
# placeholders below for the URLs it gives you. Syntax: ![alt](url)
# Save the PNGs into docs/images/ with these names, push, then the raw URL is
#   https://raw.githubusercontent.com/restjack/E-Tech/main/docs/images/<name>
#
#   IMG-1  mk4-hero.png          Mk3 + Mk4 side by side, 03 vs 04   [hero]
#   IMG-2  mk4-interior.png      Mk4 interior, teal walls + 04 logo
#   IMG-3  factory-roboport.png  Interior roboport, 30 robot + 30 material slots
#   IMG-4  teleporter-remote.png Named/starred pads across surfaces
#   IMG-5  resource-markers.png  Auto-tagged ore patches on the map
#   IMG-6  mk4-exterior.png      Mk4 exterior close-up
#   IMG-7  factory-outlet.png    Factory outlet panel, interior stock + settings
#
# Still worth capturing: colorful biochamber, the startup settings tab.

## Title

E-Tech: Vanilla Recipes for AAI Industry + QoL Toggles

## Summary

Restores vanilla recipes while keeping everything AAI Industry adds (Krastorio 2 aware). Plus a box of optional features, nearly all on by default: a fourth Factorissimo factory tier, the fix that lets robots charge inside factory buildings at all, a factory outlet/inlet/sensor that bridges factory interiors with your logistic network, teleporter pads, resource map markers, void chests, and a dozen more.

## Description — copy everything BELOW this line

**Source:** https://github.com/restjack/E-Tech
**License:** public domain, except where a revived mod's own license applies.

![A Factory building Mk3 and a Mk4 side by side: same footprint, one brown marked 03, one steel blue marked 04](https://raw.githubusercontent.com/restjack/E-Tech/main/docs/images/mk4-hero.png)

Likes [AAI Industry](https://mods.factorio.com/mod/aai-industry)'s new machines, dislikes its recipe rewrites?

E-Tech restores **vanilla recipes** while keeping **everything AAI adds** — and has grown into a box of quality-of-life features, several of them revivals of good mods that stopped being updated.

## Defaults changed in 0.21.0

Nearly everything is now **on by default**. A toggle you never found is a feature you never got, and turning one off is a single switch.

**This changes nothing for existing saves or servers.** Factorio only applies a default the first time it sees a setting, so an existing game keeps exactly what it had.

Leaving it all on is safe by construction:

- Every revived mod disables itself if you still have the original.
- Anything needing Space Age, Factorissimo or Jetpack does nothing without it.
- No new recipe changes. Four features stay off, listed near the bottom.

## Recipe restore

The core feature. Always on, no setting.

- **45+ vanilla recipes restored** — belts, inserters, drills, furnaces, assemblers, steam power, engine units, concrete, oil processing, labs, science packs, poles, roboport, radar, turrets, armor, vehicles, and more.
- **Science packs are hand-craftable again.** AAI makes them assembler-only.
- **All AAI content stays** — burner machines, industrial furnace, area mining drill, fuel processor, wall/gate tiers, motors, glass, sand. Their own recipes are untouched.
- **Tech tree untouched.** Progression stays AAI's; only ingredients go vanilla.

### Krastorio 2 aware

With K2 (or K2 Spaced Out), recipes restore to *K2's* values, not raw vanilla — the exact state a K2 game had before AAI was added.

AAI's redundant duplicates (single-cylinder engine, wooden electronic circuit) are hidden from the crafting menu.

### It never fights another overhaul

Every restore is fingerprint-guarded: a recipe is only touched if it still matches AAI's version, or contains an AAI-only item. If another mod already rewrote it, E-Tech leaves it alone.

Every decision is logged — search factorio-current.log for [E-Tech].

## Factorissimo 3 add-ons

Three features, all on by default. Each needs [Factorissimo 3](https://mods.factorio.com/mod/factorissimo-2-notnotmelon) and does nothing without it.

### Robots can finally charge inside factories

![The interior roboport with 30 robot slots and 30 material slots](https://raw.githubusercontent.com/restjack/E-Tech/main/docs/images/factory-roboport.png)

Factorissimo runs the interior roboport on a *void* energy source. Robot charging is paid out of a roboport's stored energy — and a void source stores none.

So that roboport can never charge a robot. Not slowly; never. Adding pads or power changes nothing, because charging never starts.

Upstream never hit this: their own hidden construction robots are defined with no energy drain.

E-Tech gives it a real electric source, plus:

- Whole-floor logistics coverage, instead of the stock radius of 2.
- Slots for logistic robots and repair packs.
- A proper charging pad count and rate.
- Every value is a startup setting.

Charging then costs grid power like any roboport — roughly 1-2 MW per busy factory. Krastorio 2's logistic-mode and construction-mode roboport variants are patched too; without that, switching a factory roboport's mode would silently revert the fix.

### Factory building Mk4

![Mk4 exterior close-up, steel blue with 04 painted on the front](https://raw.githubusercontent.com/restjack/E-Tech/main/docs/images/mk4-exterior.png)

A fourth tier: **120x120 of interior behind an exterior that is still 16x16**, with the Mk3's 32 connection ports in the same positions.

So a Mk4 drops straight into a slot you already built for a Mk3.

- Painted steel blue with "04" on the front, teal interior walls, its own map colour.
- Quality unlocks the same extra ports at the same levels — 46 at legendary.
- Works on space platforms too, as Space factory Mk4.

Two things worth knowing before you build one:

- **The ports did not grow with the floor.** 450 floor tiles per connection, against a Mk3's 112. Plan more internal bussing per port.
- **120x120 is the ceiling.** It is the largest interior Factorissimo can generate, so this is the last tier at this exterior size.

![Inside a Mk4: a 120x120 floor with teal walls and the tier logo](https://raw.githubusercontent.com/restjack/E-Tech/main/docs/images/mk4-interior.png)

Turning the setting off later removes the buildings. The interiors are not deleted, but the building is the only way in — so switch it off before you build your first one, or leave it on.

### Factory logistics: outlet, inlet & sensor

![The factory outlet panel: everything held inside the factories, with per-item totals and pull settings](https://raw.githubusercontent.com/restjack/E-Tech/main/docs/images/factory-outlet.png)

Robots can't fly in or out of factory buildings. These bridge the wall by teleporting items across.

- **Factory outlet** — offers everything made inside your factories to the outside logistic network.
- **Factory inlet** — the reverse: fill it and it distributes into the requester and buffer chests inside.
- **Factory sensor** — interior stock as circuit signals.
- **Fluid outlet and inlet** — the same bridge for fluids, one fluid per device.

In its default on-demand mode the outlet sits empty and fetches only what the network actually wants: requester and buffer chests, player and spidertron requests, **and construction ghosts** — module requests included, so blueprints build straight from factory stock. Buffer mode instead keeps a set number of stacks on hand.

The outlet panel shows everything inside your factories:

- Search, per-factory breakdowns, and factory naming.
- Click-to-locate map pins, shift-click to grab a stack.
- Per-outlet item filters, stack caps, priorities, circuit enable.
- Optional storage-chest draining. Reaches nested factories.

Built for big bases: ghost demand is tracked event-driven, not by rescanning the map.

## Teleporter pads

![The teleporter remote: starred and named pads across Nauvis, Gleba, Vulcanus and space platforms](https://raw.githubusercontent.com/restjack/E-Tech/main/docs/images/teleporter-remote.png)

Buildable teleporters, unlocked with chemical science. Walk onto a pad and pick a destination from a map GUI.

Revival of [Teleporters](https://mods.factorio.com/mod/Teleporters) by Klonan, updated for 2.1 and extended:

- Pads hold a 200 MJ buffer, and teleporting drains the **destination** pad. Map setting; 0 = free, like the original.
- Cross-surface teleporting, with a surface filter and custom surface display names.
- Wireless-remote toolbar shortcut, plus a free return jump with live camera preview.
- Your team's online players at the top of the list.
- Star pads, rename them, sort by recent / A-Z / nearest, per-pad distances.
- Unpowered-pad map alerts, teleport sound with volume setting, SHIFT+T hotkey.

### Coming from the original mod?

Run `/etech-migrate-teleporters` with both installed. Placed pads keep their names, items and research carry over. Then remove the original.

## Resource map markers

![Ore patches auto-tagged on the map with icons and totals](https://raw.githubusercontent.com/restjack/E-Tech/main/docs/images/resource-markers.png)

Auto-tags every resource patch: one marker per patch, with the resource icon and total amount. Oil shows well count and average yield.

Markers update as you chart and mine, and respect any you delete. `/etech-markers-rebuild` rescans everything.

Written from scratch and 2.1-native.

## Edit map settings in-game

A toolbar shortcut opens an editor for pollution, evolution, expansion, peaceful/no-enemies, spoilage rate, and per-surface map gen settings.

Applying requires admin.

## Void chest & void pipe

A cheap void chest destroys any item put in it; a void pipe destroys any fluid pumped in. Unlocked by a small early tech.

A second toggle adds a **filtered void chest** that destroys only the items you pick — everything else just sits.

Placed voids from the original mod survive the switch.

## Quality of life

- **Copy modules with machine settings** — shift-click paste moves modules straight from your inventory, old ones handed back, with a bot request for anything missing. Handles ghosts and remote view; furnaces, labs and beacons become cross-pastable. Has a per-player switch.
- **Quality adds module slots to all machines** — needs the Quality mod. Every machine with at least one module slot gains extra slots at higher quality, modded machines included. Machines with no slots are untouched, and affected ones say so in their tooltip.
- **All modules in beacons** — every beacon accepts every module type, productivity and quality included. Beacon strength unchanged.
- **Pick up & re-place the crashed ship** — crash-site parts become minable, with placement items.
- **Vanilla engine unit names & icons** — undoes AAI's "Multi-cylinder engine" reskin. Turn off if another mod should own their look.
- **Jetpack fuel HUD** — needs [Jetpack](https://mods.factorio.com/mod/jetpack). Movable in-flight window: current fuel, inventory count, burn bar, estimated flight time remaining.

## Space Age extras

Each does nothing without Space Age.

- **Uranium bacteria on Gleba** — jelly gives a 1% chance of uranium bacteria, multiply it with bioflux in a biochamber, and it spoils into uranium ore. Saves from the original mod keep their items.
- **Colorful biochamber** — recolours the pools, dome and windows per recipe, so you can tell what a biochamber is making at a glance.
- **FPS-friendly thrusters** — removes the animated exhaust plumes from platform thrusters, the big FPS drain on large platforms.
- **Pass-through fusion generators** — plasma connections on all four sides, so generators chain without separate plasma lines.
- **Quality in asteroid crushing/reprocessing** — makes quality modules actually take effect in the crusher.
- **Agricultural science pack spoils** — on = vanilla. Turn off to stop it spoiling.

## Off by default

Four things, each for a reason.

- **Total productivity** — productivity modules on recipes the game normally forbids: belts, inserters, rails, pipes, solar, walls, ammo, equipment and more, with four category group toggles. Off because it is a real balance change, not a convenience. Revival of [Total Productivity](https://mods.factorio.com/mod/Productivity) by AivanF.
- **Restore nuclear fuel crafting** — un-hides the nuclear fuel Krastorio 2 removes, unlocked by Kovarex enrichment like vanilla. Off because K2 hides it deliberately, and overriding another mod's balance call shouldn't be a default.
- **Teleport-to-player shortcut** — experimental. Multiplayer toolbar shortcut: one other player online = click teleports to them, several = a picker window. No pads, no energy cost.
- **Verbose recipe-restore logging** — one log line per recipe touched or skipped. A diagnostic, and it is noisy.

Also tunable: **nuclear fuel and artillery shell stack sizes**. 1 = vanilla, anything up to 1000.

## Compatibility

**Legacy Cerys fix, always on.** Cerys below 4.24.5 redefined Krastorio 2's nitric acid at 15 C — below the 25 C minimum K2 recipes expect — starving imersite crystal plants.

E-Tech restores K2's definition when it detects that overwrite. With Cerys 4.24.5+ the fix stays dormant and K2's temperature bounds are left intact.

## Credits — revived and ported mods

All credit for the original ideas and code goes to their authors. Full license texts and per-port modification notes ship in the mod as LICENSE-third-party.txt.

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
- [factorissimo-roboport-buff](https://mods.factorio.com/mod/factorissimo-roboport-buff) by RandomBruh (Unlicense)
- QualityEffectsFixed (CC BY-NC-SA) — reimplemented from scratch as a blanket rule, no code reused.

**Inspired by, rewritten from scratch:** [Resource Map Label Marker](https://mods.factorio.com/mod/resourceMarker) — resource map markers.

Everything else is public domain. Source: https://github.com/restjack/E-Tech
