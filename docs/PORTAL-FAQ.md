# Mod portal FAQ — paste into https://mods.factorio.com/mod/E-Tech/faq/edit
# (Same markdown rules as the description: no tables. ## groups, ### questions.)

## Updating and saves

### Is it safe to add to an existing save?

Yes. Recipe changes apply on load and the game recalculates recipe availability automatically. Nothing is removed from your world.

### I updated to 0.21.0 and expected everything to switch on. It didn't.

Correct, and that is deliberate. 0.21.0 changed most features to default **on**, but a default only applies the first time Factorio sees a setting. Your `mod-settings.dat` already has a value for every one of them, so an existing game or server keeps exactly what it had.

If you want the new feature set in an existing game, turn the settings on yourself — Settings > Mod settings > Startup.

### Is it safe to remove?

Mostly. The recipe restores simply revert to AAI's versions.

Two exceptions, both about content features that place things in your world:

- **Uranium bacteria on Gleba** — any uranium bacteria items disappear with the feature. Let them spoil into uranium ore first if you care.
- **Factory building Mk4** — see the Mk4 question below. Read that one before switching it off.

### Everything is on by default now. Is that safe?

Yes, by construction rather than by hope. Every revived mod disables itself if you still have the original installed, and every feature that needs Space Age, Factorissimo or Jetpack does nothing at all without it. No feature added in 0.21.0 touches a vanilla recipe.

Four things stay off on purpose: total productivity, restoring Krastorio 2's hidden nuclear fuel, the experimental teleport-to-player shortcut, and verbose logging.

## Compatibility

### Does this change the tech tree?

No. Research progression, unlock order and AAI's trigger techs are untouched. Only recipe *ingredients* go back to vanilla (or Krastorio 2's values).

That also means AAI's "craft 50 motors" trigger still gates belts — by design, tech is out of scope.

### Does it work with Krastorio 2 / K2 Spaced Out?

Yes, that's a first-class setup. With K2 installed, recipes restore to *K2's* values instead of raw vanilla — the exact state a K2 game had before adding AAI. Recipes K2 owns are detected and left alone.

### A recipe I expected to be restored wasn't. Why?

Every restore is fingerprint-guarded: if the recipe no longer matches AAI's version, because another mod rewrote it, E-Tech skips it rather than fight that mod.

Check your log — every decision is recorded. Search `factorio-current.log` for `[E-Tech]`; skipped recipes are listed by name.

### Multiplayer and dedicated servers?

Works, but know which machine decides. All toggles are **startup** settings, so the **server's** values win for everyone who joins — your local settings are ignored on someone else's server.

So if a feature is off on the server, it is off for you, no matter what your own settings say. Changing a server's mod settings means editing them on the server and restarting it.

## Factorissimo features

### Robots still aren't charging inside my factories.

Check **Factory roboport: charge bots from your power grid** (`etech-factory-roboport-electric`). It is on by default and it is the setting that makes charging work at all — with it off you get Factorissimo's stock void energy source, which stores no energy and therefore can never charge a robot.

On a server, that setting has to be on **on the server**. Also check the factory has a power pole in range outside: a factory with no supply has nothing to charge from, and it fails silently.

### What happens if I turn the Mk4 setting off after building some?

The Mk4 **buildings** are removed, because their prototype no longer exists once the setting is off.

The interiors are **not** deleted — nothing in Factorissimo cleans them up — but the building was the only way in, so everything inside becomes unreachable without console commands. Turning the setting back on does not rebuild the buildings.

Stranded, not destroyed. Decide before you build your first Mk4.

### My Mk4's interior walls are yellow, not teal.

That factory was built before the teal tiles were added. A factory's floor is written **once**, when its interior is first created, so existing interiors keep whatever they were built with.

Build a new Mk4 and it will be teal. There is nothing wrong with the old one.

### Half of my Mk4 has no power. Machines say "No power" with no wire to trace.

A Mk4 built before 0.20.1. Factorissimo puts the interior power pole beside the door, and an electric pole's supply area is capped at 64 tiles by the engine — not far enough to cross a 120-wide floor, so the far half got nothing.

0.20.1 fixes it with a hidden relay pole at the centre of the floor. That is created for **new** factories, so remove and re-place any Mk4 built earlier.

### The factory outlet sits empty and pulls nothing. Is it broken?

Probably not — that is on-demand mode (the default) working as intended. The outlet only fetches items when its logistic network has unmet demand: requester and buffer chests, player or spidertron requests, construction ghosts. No demand means an empty outlet.

Want it to keep stock on hand regardless? Open it and uncheck **On-demand mode** for buffer mode. `/etech-hub-debug` prints exactly what every outlet sees and why it is or isn't pulling.

### Bots aren't building my blueprint from factory stock.

Checklist:

1. The outlet is in the same logistic network as the ghosts — ghosts outside any construction area generate no demand.
2. The items actually exist in provider chests inside a factory the outlet reaches.
3. Construction bots are available in that network.

`/etech-hub-debug` shows the ghost demand the outlet currently sees.

### Why does my Mk4 have the same number of ports as a Mk3?

Because it has the same exterior. The Mk4 exists to drop into a slot already built for a Mk3, which means the same 16x16 footprint and the same 32 ports in the same positions — but four times the floor behind them.

That works out at 450 floor tiles per connection against a Mk3's 112, so plan more internal bussing per port. It is a deliberate trade, not an oversight.

## Other features

### Where do I unlock the restored nuclear fuel (K2 toggle)?

Kovarex enrichment process, same as vanilla. K2 keeps that technology (repriced), it just removes the fuel — the toggle puts the unlock back. Already researched Kovarex? The recipe appears immediately.

### How does the Gleba uranium loop work?

Requires Space Age. On Gleba: 3 jelly gives a 1% chance of uranium bacteria (unlocked by Jellynut research). Then 1 bacteria + 1 bioflux in a biochamber multiplies it to 4 (unlocked by Bacteria cultivation).

The bacteria spoils into uranium ore in about a minute — same rhythm as iron and copper bacteria.

### I used the old Simple Gleba Uranium mod. Can I switch?

Yes. E-Tech keeps the original prototype names, so bacteria items and assembler recipes in your save carry over. Disable the old mod, load, done. Don't run both at once.

### The teleport-to-player shortcut doesn't show up.

Three things to check:

1. The startup setting **Teleport-to-player shortcut** is on — this one is **off** by default.
2. You restarted after changing it. It is a startup setting.
3. Shortcuts can be hidden — click the three-dots menu at the right end of the shortcut bar and enable "Teleport to player".

### Does teleport work across planets and surfaces?

Yes. It follows the target's physical position, so it works while they are on another planet or wandering in remote view. With one other player online it teleports instantly; with more it opens a picker.

## Contributing

### Can you revive another abandoned mod as a toggle?

Open a discussion thread with a link. Small data-stage mods — recipes, items, tweaks — are good candidates. Licensing has to permit it.
