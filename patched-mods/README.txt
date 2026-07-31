PATCHED MODS - read me first
============================

These are mods from the Factorio mod portal with small local fixes so they
run on the current Factorio version (or don't crash). You need these exact
files to join the multiplayer server - the versions on the mod portal will
NOT match.

HOW TO INSTALL
--------------
1. Copy this whole folder to your PC (or download it from the shared link).
2. Double-click  install-mods.bat
   It copies every mod zip into your Factorio mods folder
   (C:\Users\<you>\AppData\Roaming\Factorio\mods - the Steam default)
   and overwrites older copies.
3. Start Factorio. Done.

Doing it by hand works too: copy all the .zip files into that mods folder.

WHEN THERE'S AN UPDATE
----------------------
Same thing again: grab the folder, run install-mods.bat. It safely
overwrites the old versions.

If Factorio's own mod updater offers an update for one of these mods,
take it - that means the original author fixed it properly and the
patched copy retires itself.

NOTABLE LOCAL PATCHES
---------------------
- factorissimo-roboport-buff: REMOVED from the pack entirely (2026-07-29) -
  absorbed into E-Tech 0.19.7 ("Factory interior roboport buff", ON by
  default). E-Tech now does everything the mod did (logistics radius 64,
  7 robot + 7 material slots) plus the real fix: robots could never charge
  inside factory buildings at all. Factorissimo runs that roboport on a
  "void" energy source, which stores no energy - and charging a robot is
  paid out of a roboport's stored energy, so it never charged anything.
  E-Tech gives it a proper electric source, which does mean bot charging
  inside factories now draws from your grid (about 1-2 MW per busy
  factory). All settings are under Startup -> E-Tech.
  DELETE factorissimo-roboport-buff_1.1.0.zip from your mods folder - it
  won't break anything if you leave it, but E-Tech replaces it and its two
  settings will just sit there doing nothing. Safe for saves.
- Kux-SmartLinkedChests_3.3.7: E-Tech build (2026-07-21). Chest GUI shows
  a Pool row + live item Flow display, opens faster, research tooltips
  show real numbers, /slc rescan can't delete items anymore. Optional
  per-save setting "[E-Tech] Experimental patches" fixes global chests
  inside factories built underground (Subsurface/Maraxis). Details in the
  mod's own changelog (changes marked [E-Tech]).
- QualityEffectsFixed: REMOVED from this set (2026-07-21) - absorbed into
  E-Tech 0.18.0+ ("Quality adds module slots to all machines", on by
  default). Delete the old zip from your mods folder.
- PlanetsLibTiers: REMOVED from the pack entirely (2026-07-26) - nothing
  in the pack ever used it (inert planet-tier data, no gameplay effect).
  Delete any PlanetsLibTiers zip from your mods folder. Safe for saves.

Questions -> ask Eli.
