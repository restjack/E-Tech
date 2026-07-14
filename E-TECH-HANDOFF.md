# E-Tech Mod — Session Handoff

Complete context for continuing work on the E-Tech Factorio mod. Written 2026-07-08; updated same day through v0.2.4.

## UPDATE — v0.5.3 (2026-07-11)

- Retitled for expanded scope: info.json title now "E-Tech: Vanilla Recipes for AAI Industry + QoL Toggles", description rewritten. Portal copy (title/summary/description markdown) lives in `PORTAL-PAGE.md` at repo root (NOT packaged) — Eli pastes into mod's portal Edit page (title/summary/description editable portal-side without new upload; new zip upload also carries new title in-game). 0.5.3 deployed.

## UPDATE — v0.5.1 + v0.5.2 (2026-07-11)

- 0.5.0 failed to load: product `probability` → `independent_probability`. 0.5.1 failed next: `result_is_always_fresh` moved to product. 0.5.2 = full fix, recipes verified field-by-field against vanilla 2.1 `iron-bacteria`/`iron-bacteria-cultivation` in the Steam install (also fixed: removed `organic-or-hand-crafting` category → `{"organic","crafting"}`, removed `show_amount_in_title`, added `auto_recycle = false` to cultivation). Full 2.0→2.1 porting checklist now in gotchas — USE IT before building any future port. 0.5.2 deployed, older zips removed (broken 0.5.0/0.5.1 remain in releases/).

## UPDATE — v0.5.0 (2026-07-11)

- **Gleba uranium bacteria** (startup toggle `etech-gleba-uranium`, default OFF, needs Space Age): port of dead portal mod `simple-gleba-uranium` 1.0.2 by cindersash (MIT — attribution shipped in `LICENSE-third-party.txt`, README license section updated). New file `gleba-uranium.lua` (required from data-final-fixes section 5, gated by setting + `mods["space-age"]`). Item `sgu_uranium-bacteria` (spoils→uranium-ore, 1 min) + 2 recipes: jelly 3 → 1% bacteria (unlock: jellynut tech), bacteria+bioflux → ×4 biochamber (unlock: bacteria-cultivation tech). **Kept original `sgu_` prototype names** = saves from old mod keep items. Guard: skips if original mod's prototypes present. Icons copied to `E-Tech/graphics/icons/` (3 pngs), paths rewritten `__simple-gleba-uranium__`→`__E-Tech__`. Original's `category` singular converted to `categories` array (2.1 gotcha). `? space-age` added to deps. Eli's stated direction: absorbing old dead mods as toggles — expect more.

## UPDATE — v0.4.0 (2026-07-11)

- **Nuclear fuel restore** (startup toggle `etech-restore-nuclear-fuel`, default OFF): K2 hides vanilla `nuclear-fuel` item+recipe. Toggle unhides both; recipe re-attached to `kovarex-enrichment-process` tech unlock (vanilla gate) when that tech exists/visible/enabled, else `enabled = true` from start. Lives in `misc-tweaks.lua`. Inspired by portal mod `k2-nuclear-fuel` 1.0.0 (8-line mod, just unhides + enabled=true — ours adds the tech gate).
- **Teleport-to-player shortcut** (startup toggle `etech-teleport-shortcut`, default OFF, experimental): NEW files `data.lua` (shortcut prototype `etech-teleport-to-player`, icon = base spidertron-remote, only created when setting on) + `control.lua` (on_lua_shortcut: 0 others = message, 1 = teleport, 2+ = screen-GUI picker with per-player buttons; on_gui_click + on_gui_closed handle picker). Teleports via `target.physical_surface/physical_position` (remote-view aware), `find_non_colliding_position("character", ...)`, cross-surface OK in 2.0, pcall-wrapped. First control-stage code in the mod.
- 0.3.1 zip was file-locked (game running) — Eli must delete `E-Tech_0.3.1.zip` from mods folder after exiting Factorio. 0.4.0 built + deployed + archived.

## UPDATE — v0.2.1→0.2.4 (read this first, supersedes parts below)

- **0.2.1**: New `M.k2_restores` table + pass in data-final-fixes: AAI's own K2-compat file (`phase-3/compatibility/krastorio2.lua`) rewrites K2's recipes; E-Tech restores K2's originals. First entry: chemical-science-pack (Chemical tech card — AAI injected engine-unit + changed glass; K2 original = blank card 5 + kr-glass 15 + adv-circuit 5 + acid 50 → 5).
- **0.2.2**: Cosmetic restore — engine-unit/electric-engine-unit get vanilla icons (data stage) + vanilla names via `locale/en/en.cfg` (E-Tech loads after AAI so its locale wins; AAI had renamed them "Multi-cylinder engine"/big motor). build.ps1 now packages subfolders recursively (locale/ was being dropped) and auto-archives every build to `E-Tech/releases/`.
- **0.2.3 — KEY DESIGN SHIFT**: Eli's real baseline = **K2-on-vanilla, not raw vanilla** (his "before AAI" save = K2 modpack). K2 itself modifies ~10 recipes we were flattening to vanilla. Now: **K2's opinion wins where K2 has one, raw vanilla elsewhere, AAI loses everywhere.** k2_restores extended (entries without `contains` apply unconditionally, idempotent): engine-unit (IRON plate not steel — K2 converts steel→iron, AAI converted back), gun-turret (kr-iron-beam+automation-core), asm-1 (kr-iron-beam), steam-turbine (+steam-engine 2), electronic-circuit (+wood, ×2 out), solar-panel (+kr-silicon), heavy-armor (no copper, +light-armor), roboport (kr-steel-beam), laser-turret (+kr-quartz), lab (copper-cable not belts). Source of K2 values: `Krastorio2_2.1.2/prototypes/updates/base/recipes.lua` (mostly relative edits — replace/insert on vanilla).
- **0.2.4**: motor ("Single-cylinder engine") recipe `hide_from_player_crafting = true`, K2-gated. Not fully hidden: burner-lab + fuel-processor consume motors, AAI's basic-logistics trigger = craft 50 motors; without K2 the first burner assembler needs a hand-made motor (would deadlock).
- Water-Friendly-Walls saga resolved: Waterfill_v17 places plain `water` tile (WFW deep list → no walls, by design). A waterfill→water-shallow patch was built as 0.2.2-draft and **reverted at Eli's request** (world already generated, pointless). Don't re-add.
- Every build now archived in `Factorio/E-Tech/releases/` — old versions revisitable.

## What E-Tech is

A Factorio 2.1 mod with one purpose: **restore vanilla recipes while keeping everything AAI Industry adds**. Born from "AAI locked iron pipes behind research and I don't like its recipe rewrites, but I like its machines."

- **Source of truth:** `Factorio\E-Tech\` in this repo (this folder's sibling).
- **Deployed to:** `C:\Users\Eli Tellez\AppData\Roaming\Factorio\mods\E-Tech_<version>.zip`
- **Current version:** 0.2.0, Factorio 2.1, loads clean, verified in-game log.
- **Never edit other mods** (AAI, K2, etc.) — E-Tech loads after them and overrides via `data.raw`.
- **Never enable/disable mods in mod-list.json** — Eli does that in-game. Just build the zip into the mods folder.

## Design history (how we got here — 3 pivots)

1. **v0.1.0 (shipped, superseded):** per-recipe startup toggles (15 reverts + fluid un-gate + crashed ship). Worked, but settings list was clutter.
2. **Considered:** bundle toggles per AAI "tier" (motor tier, glass tier...) — see `E-Tech\AAI-CHANGE-INVENTORY.md`, the full audit of everything AAI changes, classified A–E by revert difficulty. Kept as reference; superseded as design.
3. **Considered:** parallel vanilla recipes coexisting with AAI's (additive, no overwrites). Rejected: menu clutter, can't remove redundant tiers, intermediate-picking issues.
4. **v0.2.0 (current):** no toggles. Unconditionally restore ~45 vanilla recipes, keep all AAI content, **tech tree untouched** (Eli's explicit call — pipes stay behind AAI's Basic fluid handling research; recipe *ingredients* go vanilla). Science packs hand-craftable again (category restore counts as recipe, not tech). Crashed-ship pickup kept as the only startup setting.

## Decisions locked by Eli (do not relitigate)

- Strictly **no tech/progression changes**. Even though the original complaint was gated pipes, Eli chose research-stays over un-gating when forced to pick.
- Science packs **hand-craftable** (vanilla behavior restored).
- AAI's new machines/items all stay, with their AAI recipes: burner assembler/lab/turbine, industrial furnace, area mining drill, fuel processor (recipe: iron 10 + brick 10 + motor 1 — needs `motor` alive, which it is), wall/gate tiers, stone path, motors, glass, sand, stone-tablet.
- Respect other overhaul mods (Krastorio 2 especially): never stomp their recipe changes.
- Publish on mod portal, mostly private/friends use. No-strings license (public domain / Unlicense).

## Architecture (3 files matter)

- **`vanilla-recipes.lua`** — one big table. Each entry: recipe `name`, `vanilla` fields to restore (ingredients / results / energy_required / categories / clear_categories), `aai` fingerprint (exact ingredient multiset, or `contains = "item"`, or results multiset). Adding a revert = adding an entry. Nothing else to touch.
- **`data-final-fixes.lua`** — ~100-line engine. Runs last (deps force load after AAI and K2). For each entry: apply vanilla values ONLY if the recipe still "looks AAI-authored" — exact fingerprint match OR contains an AAI-only marker item (motor, electric-motor, stone-tablet, small-iron-electric-pole, burner-assembling-machine, burner-lab, glass/sand via AAI's `aai_glass_name`/`aai_sand_name` data-stage globals). Mismatch = another mod owns the recipe now = skip + log. All decisions log with `[E-Tech]` prefix to factorio-current.log.
- **`crash-ship.lua`** — makes all `crash-site-spaceship*` entities minable + creates placement items (`etech-` prefixed). Gated by the mod's only setting `etech-pickup-crashed-ship` (default on). Verified: 12 parts processed.

Support files: `settings.lua` (one toggle), `info.json`, `changelog.txt` (strict Factorio format per https://lua-api.factorio.com/latest/auxiliary/changelog-format.html — separator EXACTLY 99 dashes, `Version: x.y.z`, category = 2 spaces + recognized name + colon [use `Info` not `Notes`], entry = 4 spaces + `- `, continuation = exactly 6 spaces, no tabs/trailing whitespace; validated fully compliant 2026-07-11), `README.md`, `LICENSE.txt` (public domain), `thumbnail.png` (144×144, generated from art in Eli's Downloads), `build.ps1`.

## Build / deploy workflow

```powershell
powershell -File "C:\Users\Eli Tellez\Documents\GitHub\Projects\Factorio\E-Tech\build.ps1"
```
- Reads name+version from info.json, zips `E-Tech_<version>/` with **forward-slash entry paths** (PowerShell `Compress-Archive` writes backslashes — that's why build.ps1 uses .NET ZipArchive directly; don't "simplify" it back).
- Writes straight to the Factorio mods folder. Excludes build.ps1 + AAI-CHANGE-INVENTORY.md.
- **Zips are file-locked while Factorio runs.** Build fails with IOException → tell Eli to exit the game, then rebuild.
- Version bumps: edit info.json `version`, rebuild (zip name follows), delete the older zip from mods folder.

## Verified state (2026-07-08 log)

`[E-Tech] vanilla restore done: 37 reverted, 11 skipped, 1 absent`
- 11 skips = K2 owns those recipes now (guard working as intended): burner/normal/long-handed inserter, asm-3, repair-pack, logistic + utility science, big-pole, substation, locomotive, flying-robot-frame.
- 1 absent = satellite (doesn't exist in Space Age). Correct.
- Crash ship: 12 wreck parts made minable+placeable.
- Zero E-Tech errors in log.

## Gotchas learned the hard way

- **Porting 2.0 mods to 2.1 — CHECKLIST (cost us 0.5.0 AND 0.5.1 load errors, one at a time):**
  - Recipe `category` (singular) → `categories` array.
  - Combined categories REMOVED (`organic-or-hand-crafting`, `electronics`, `basic-crafting`, `chemistry-or-cryogenics`, ...) — use multiple plain categories instead (`{"organic","crafting"}`).
  - Product `probability` → `independent_probability`.
  - Recipe `result_is_always_fresh` / `reset_freshness_on_craft` → moved onto the PRODUCT (`always_fresh` / `reset_freshness_on_craft`); vanilla 2.1 cultivation recipes use product `reset_freshness_on_craft = true`.
  - Recipe `show_amount_in_title` + `always_show_products` REMOVED.
  - **Method that actually works:** don't fix errors one by one — diff ported prototypes field-by-field against the closest vanilla 2.1 equivalent in `C:\Program Files (x86)\Steam\steamapps\common\Factorio\data\<base|space-age>\prototypes\` and grep `data\changelog.txt` (the 2.1.0 "Modding"/"Scripting" sections list every rename/removal).
- **Factorio 2.1 recipes: `category` (singular) is ILLEGAL** — merged into `categories` array. Writing `recipe.category = "x"` hard-errors at load ("category and additional_categories got merged into categories"). Engine nils out `category` everywhere it touches; only sets `categories`.
- `info.json` `factorio_version` must be `"2.1"` (game is 2.1.x; `"2.0"` gets the mod rejected at load).
- AAI renames its `motor` item to "single-cylinder engine" and reskins vanilla `engine-unit` as "multi-cylinder engine". They're AAI's invented tier; E-Tech strips them from vanilla recipes but keeps the items (AAI's own machines consume them).
- `boiler` is deliberately NOT in the revert table: AAI's ingredients already equal vanilla (only the tech gate differs — out of scope).
- `offshore-pump` deliberately skipped: vanilla 2.x ingredient values unverified. Open item if anyone cares.
- Data-stage Lua globals are shared across mods — that's how we read AAI's `aai_glass_name`/`aai_sand_name`.

## Mod portal publishing (in progress when session ended)

Eli was on the "Create new mod" portal page. State:
- Zip with thumbnail: built (rebuilt AFTER he queued the older 10.32 kB zip — **he must re-select the new ~55 kB zip from the mods folder**).
- Portal description markdown: written, provided in chat — regenerate from README if lost.
- Recommendations given: Category = **Tweaks** (not Content), Tag = **Manufacturing** only, License dropdown = **The Unlicense** (matches LICENSE.txt; MIT requires attribution, wrong fit).
- Name `E-Tech` becomes permanent at first submit.
- Updates post-publish: bump info.json version → build.ps1 → upload on mod's Edit page. Players auto-notified in-game.
- Optional: upload the full-res art (Downloads, "ChatGPT Image Jul 8 ... 03_50_38 PM.png", 1254×1254) to the portal gallery.

## Open items / possible next steps

1. **Skip audit** (offered, not requested): add a debug line dumping each skipped recipe's actual current ingredients to confirm they're K2's values, not a wrong fingerprint on our side.
2. **offshore-pump**: verify vanilla 2.x ingredients in-game, then add to table.
3. Confirm portal submission went through; help with gallery/description if needed.
4. In-game verification of specific recipes (belt = iron+gear, engine-unit = steel+gear+pipe, red science hand-craft) — log says done, eyeball not yet confirmed by Eli.

## Related context (separate issues, same sessions)

- **Water-Friendly-Walls "not working"**: diagnosed 2026-07-08. (a) Game wasn't loading mods at all — `companion-drones-2-updated` is 2.0-only on Factorio 2.1, must be disabled; (b) WFW only affects SHALLOW water tiles (water-shallow, water-mud, Gleba wetlands, oil-ocean-shallow) — regular/deep water is deliberately untouched by that mod, landfill still required. Its land-mine setting (default off) writes a likely-invalid collision layer `item` on 2.1 — advise leaving it off.
- AAI Industry 0.7.1 unpacked & analyzed in scratchpad (gone after session). Redownload zip from mods folder if needed; full change inventory survives in `E-Tech\AAI-CHANGE-INVENTORY.md`.
