# E-Tech — a Factorio mod (and a learning project)

This is the working repository for **[E-Tech](https://mods.factorio.com/mod/E-Tech)**, a Factorio 2.1 mod that restores vanilla recipes while keeping everything [AAI Industry](https://mods.factorio.com/mod/aai-industry) adds, plus a growing pile of optional quality-of-life toggles.

It is also, first and foremost, a **learning project** — an excuse to understand Lua, the Factorio modding API, and how mods fit together. The commit history and design notes are left in the open on purpose. If any of it helps you learn or build your own mod: **copy it, fork it, strip it for parts.** No permission needed (see License below).

## What the mod does

Short version: AAI Industry's machines are great, its recipe rewrites are a matter of taste. E-Tech puts the recipes back to vanilla (or Krastorio 2's values when K2 is installed) without touching AAI's content or tech tree, and bundles optional startup toggles — crashed-ship pickup, modules in beacons, stack sizes, Gleba uranium bacteria, a teleport-to-player shortcut, and more. Everything defaults to vanilla behavior.

Full feature list and design notes: **[E-Tech/README.md](E-Tech/README.md)**

## Repo layout

| Path | What it is |
|---|---|
| [`E-Tech/`](E-Tech/) | The mod itself — this folder is what gets zipped and shipped |
| [`E-Tech/build.ps1`](E-Tech/build.ps1) | Build script: packages `E-Tech_<version>.zip` into the Factorio mods folder |
| [`E-Tech/AAI-CHANGE-INVENTORY.md`](E-Tech/AAI-CHANGE-INVENTORY.md) | Full audit of everything AAI Industry changes, classified by revert difficulty |
| [`PORTAL-PAGE.md`](PORTAL-PAGE.md) | Source text for the mod portal page |

Release zips are not tracked here — they're built by `build.ps1` and published on the [mod portal](https://mods.factorio.com/mod/E-Tech).

## Useful reading if you're here to learn

- [`E-Tech/data-final-fixes.lua`](E-Tech/data-final-fixes.lua) — data-stage recipe patching with fingerprint guards so it never fights other overhaul mods
- [`E-Tech/control.lua`](E-Tech/control.lua) — control-stage (runtime) code: events, GUI, teleporting players
- [`E-Tech/changelog.txt`](E-Tech/changelog.txt) — full version history, including what each fix actually fixed

## License

**Public domain** ([LICENSE.txt](E-Tech/LICENSE.txt)) — copy, modify, redistribute, fork, sell, no attribution required, no warranty.

Exception: third-party content ported into the mod keeps its original license, documented in [LICENSE-third-party.txt](E-Tech/LICENSE-third-party.txt) (currently: Gleba uranium bacteria from *Simple Gleba Uranium* by cindersash, MIT; teleporter pads under `E-Tech/teleporters/` from *Teleporters* by Klonan, LGPLv3).
