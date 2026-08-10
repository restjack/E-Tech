# E-Tech Polish Backlog — 2026-07-21

60 improvement candidates from a 3-agent code sweep (teleporters/GUIs, factory-hub/void/markers, data-stage/settings/locale), 6 areas × 10. File:line refs verified at sweep time (E-Tech 0.18.1). Excludes ideas already killed (Factorissimo map icons, waterfill patch, tech-tree changes — see kill history in E-TECH-HANDOFF.md / Build-Log).

## STATUS: ALL 60 ADDRESSED IN 0.19.0 (2026-07-21, branch polish-0.19)

Verified: luaparser syntax on every changed file, dump-data clean (0 errors, 49 recipes reverted), 120-tick benchmark of live save "2026 July 22 2p" clean (avg 7.1 ms). NOT yet: in-game GUI eyeballing, server deploy, portal upload.

Deviations from the list as written (everything else implemented as described):
- 1.4 remote rename: per-pad Shift+Right-click already works in remote mode (documented in the favorite tooltip); the title-bar rename button stays pad-GUI-only (it renames the source pad, which remote mode doesn't have).
- 1.8 cost preview: tooltips already carry cost + stored MJ and unaffordable pads disable; a confirm dialog was judged friction, not safety. Return/player buttons already say "Free".
- 1.10/2.8 "incremental GUI refresh" + network_wants caching: not restructured — search-state persistence removed the sting of the teleporter rebuild, and one-outlet-per-surface means the requester walk has nothing to share. Sensor dirty-check, rate-sample prune, chart throttle, alert early-out all shipped.
- 2.2 inlet priority: skipped (inlets don't compete); filters + deficit panel shipped.
- 3.2 void pipe circuit enable: skipped (infinity pipes have no circuit connector; a hidden-combinator companion wasn't worth it) — throughput readout on hover shipped instead.
- 3.7 markers playerless merge: verified NOT a bug (the destroy pass covers all buckets before the player-force filter applies); background rescan shipped.
- 4.1 "7 dead entries": false alarm — all seven AAI versions contain marker items (verified vs AAI-CHANGE-INVENTORY.md), so contains_marker restores them. Comment added at the looks_aai definition.
- 4.3 K2 third-mod guard: idempotent skip shipped; the ownership WARNING was built, fired false positives on the normal vanilla→K2 path in dump-data, and was removed same session. Real guard needs per-entry AAI fingerprints in k2_restores — future work if it ever matters.
- 5.8 locale headerless files: deliberate — bare etech-prefixed keys are valid and collision-safe; renaming sections would break every reference for zero gain.
- 6.5 hub insert/request-walk dedupe: reviewed, kept separate — stack-based vs spec-based insertion have different spoil semantics, and the two request walks differ in deficit handling. They already share return_passes.

Original list below for reference.

## 1. Teleporters

1. Search text survives GUI rebuild — refresh tears down + recreates whole frame, typed search resets on any built/mined/rename event (`teleporters/control.lua:677`, box at `:391`).
2. Hiding search box should clear its filter — pads stay hidden by lingering term (`:1019`, filter `:1016`).
3. Search should match surface aliases + surface names, not just pad names (`:1011`).
4. Rename from the remote GUI — rename button hidden when opened remotely; shift+right-click is undiscoverable (`:386`).
5. Pad names into blueprint tags — pasted pads currently get generic "Teleporter N" (`:1038`).
6. Vehicle/spidertron handling — `player.teleport` strands the vehicle (`:910`; same in `teleport-player.lua:37`).
7. Favorites leak — never pruned on pad removal (`:878` set, `:1048` never clears); also keyed by `player.name` not index (`:149`).
8. Remote jump: cost preview/confirm before draining destination energy (`:891`); energy/free info missing from return + player button tooltips (`:494` vs `:656`).
9. Teleport robustness: `return_button` not pcall-wrapped (`:945` vs `:969`); `teleport-player.lua:33` hardcodes `"character"` collision proto (jetpack/modded characters mismatch — `:965` already solves this, port it).
10. Perf: incremental GUI refresh instead of full rebuild per event; `force.chart` per pad per rebuild (`:602`); pad-alert rescan re-issues alerts every 601 ticks (`:1278`).

## 2. Factory Hub (outlet / inlet / sensor)

1. Blueprint/clone/upgrade keep outlet settings — `on_entity_cloned` → `register_device` resets filters/mode/storage (`factory-hub/control.lua:1103`, `:98`); no upgrade-planner transfer.
2. Inlet parity with outlet — per-item filters, priority, per-factory deficit list, stock view (`:1289`, `:922`).
3. Empty/paused feedback — grid "Nothing found" doesn't distinguish no-chests vs circuit-paused vs search-filtered; rate shows "0/min" with no reason (`:1229`, `:1195`).
4. Fluid bridging — item-only today; interior tanks invisible outside (whole file; Factorissimo pipes fluids, players will expect it).
5. Filter slots: 10 hard slots, no overflow (`:1144`); named constant + scroll or grow.
6. "N more" counts instead of bare "..." — tooltip factory cap 8 (`:1246`), factory rows cap 20 (`:1185`).
7. Factorissimo API safety — remote calls unguarded (`:83`, `:215`); check function presence, pcall the per-pass calls; their internals re-verified only on majors.
8. Perf: `network_wants` walks every requester point per outlet pass uncached (`:748`); sensor rewrites full section every pass, no dirty check (`:970`); `moved_samples` full-copy prune each pass (`:364`); `gunit` unbounded on huge pastes (`:592`).
9. Localize player-facing prints — locate/take prints, "Factory N" fallback, GPS lines (`:1055`, `:1095`, `:95`, `:1415`); factory-hub.cfg has no message section yet.
10. Placement feedback — alert/flying-text when outlet placed with no factories on surface, or auto-request can't satisfy.

## 3. Small features (void, markers, jetpack UI, teleport-player, CPM, EMS)

1. Void pipe: clone/upgrade events not subscribed — cloned pipes never registered, never drain (`voidchest/control.lua:31`).
2. Void pipe: circuit enable + throughput readout; fixed 120-tick drain only (`:12`).
3. Void chest: filtered-mode ("exactly 0" infinity filter) hint in GUI, not just item description (`voidchest/data.lua:90`).
4. Markers: patches under min-size silently hidden — aggregate indicator or per-player reveal (`resource-markers.lua:112`).
5. Markers: `add_chart_tag` nil (uncharted centroid) leaves patch tagless with no retry (`:141`).
6. Markers: `full_rescan` synchronous over all charted chunks — multi-second stall on megamap; chunk it (`:263`); also fired by force merge (`:445`).
7. Markers: merge into playerless force orphans tags — `full_rescan` skips zero-player forces (`:278`, `:437`).
8. Jetpack UI: `remote.call` sync every 5 ticks + per-player `is_jetpacking` (`jetpack-ui.lua:138`, `:220`) — throttle or event-drive.
9. teleport-player: fold into teleporters (shared teleport helper) or at minimum localize everything + titlebar/close button (whole file — 100% hardcoded English).
10. CPM: `assert` on module inventory crashes mid-paste — graceful abort (`copy-paste-modules.lua:338`); EMS: `game.forces["enemy"]` unguarded on Apply (`edit-map-settings/control.lua:148`).

## 4. Recipe engine / data stage

1. Fingerprint-less entries never revert — chemical-plant, oil-refinery, lab, small-lamp, gate, laser-turret, personal-laser-defense have `vanilla` only; `looks_aai` nil+no-marker → always SKIP (`vanilla-recipes.lua:298-565`, `data-final-fixes.lua:58`). Audit each: dead entry or real miss.
2. offshore-pump: verify vanilla 2.x values, add entry — or delete the note (`vanilla-recipes.lua:25`; open since 0.2.x).
3. K2 restores apply unconditionally — third overhaul touching same recipe gets stomped; add fingerprint guard like the vanilla pass (`data-final-fixes.lua:127`).
4. Per-recipe `log()` lines unconditional — debug-gate them (`:94`); noisy on big packs.
5. Biochamber: 24 unguarded `data.raw.recipe[...].crafting_machine_tint` writes — any recipe absent → load crash (`biochamber/data.lua:89-224`).
6. `beacons.lua:15` iterates `data.raw["beacon"]` without nil guard (only file that doesn't).
7. Quality-asteroid substring match (`name:find("asteroid")`) fragile vs modded names — explicit list or category check (`misc-tweaks.lua:13`).
8. Engine-unit icon/name cosmetic restore is unconditional — give it a toggle (`data-final-fixes.lua:210`).
9. Productivity port only enables prod on single-result recipes — document in setting desc or extend (`productivity/data.lua:105`).
10. Consistency: `mods[]` vs `script.active_mods[]` guard convention unify across stages; fingerprint `list_key` ignores fluid temperature (`data-final-fixes.lua:35`).

## 5. Settings & docs UX

1. FALSE CLAIM: tips page + README say "all off by default" — crash-ship, beacon-all-modules, quality-asteroid, quality-module-slots default ON (`locale/en/en.cfg:16`, `README.md:42`, `settings.lua:11,20,29,430`). Fix wording or defaults.
2. Move ALL setting strings to `[mod-setting-name]`/`[mod-setting-description]` locale sections — zero exist today, every setting is inline `localised_name` English (`settings.lua` throughout).
3. Reconcile `order` strings vs file order — markers `"tk"` inside teleporter t-block (`settings.lua:238`), gleba `"i"` defined last, jetpack `"n"` before productivity `"m"`.
4. Reclassify per-player prefs: teleporter sound volume (`:204`), preview size (`:192`), hide-platforms (`:135`) are `runtime-global` — should be `runtime-per-user` like `etech-cpm-enabled`.
5. "Teleport-to-player shortcut" vs "Teleporter: wireless remote" name confusion (`:74`, `:143`) — cross-reference descriptions or merge features.
6. Consistent name prefixes — top-level toggles (crash-ship, beacons, quality) have no group prefix; menu reads as flat wall.
7. README optional-tweaks table missing quality-module-slots (0.18) + factory outlet/inlet/sensor rows (`README.md:17-38`) — drifts from info.json description.
8. Locale file hygiene: `jetpack-ui.cfg` + `markers.cfg` headerless top-level keys; others use sections — normalize.
9. Localize remaining inline strings: teleport shortcut name (`data.lua:76`), remote hotkey (`teleporters/data.lua:182`), crash-ship item names (`crash-ship.lua:64`), quality tooltip (`misc-tweaks.lua:204`).
10. PORTAL-PAGE.md refresh pass — portal copy drift vs 0.18 feature set (portal uploads chronically lag; last known portal = 0.17.x-era description).

## 6. Cross-cutting code quality / infra

1. Shared teleport helper — `teleport-player.lua:30` vs `teleporters/control.lua:951` near-duplicates (find-position, pcall, flash, sound).
2. Dedupe `confirm_rename_button`/`confirm_rename_textfield` copy-paste pairs (`teleporters/control.lua:821`/`:839`, + surface-rename pair).
3. Named-constants sweep — recent-cap 9, preview 128, +64/+32/+8 offsets, alert 601, jetpack 5-tick, tooltip-cap 8, grid columns 8, filter slots 10 etc.
4. `"name|quality"` join/split helper — convention repeated ~10 places in factory-hub (`factory-hub/control.lua:447` etc.).
5. Dedupe hub insert paths + request-walk paths — `insert_stack_into_chests`/`insert_spec_into_chests` (`:407`), `network_wants`/`chest_requests` (`:744`/`:872`).
6. Remove dead debug scaffolding — `debug_print=false` + shadowing `print` never enabled (`teleporters/control.lua:66`).
7. `adopt_existing` legacy-field cleanup list growing (`factory-hub/control.lua:1596`) — date entries, prune policy (e.g. drop after 2 minor versions).
8. Style normalization of verbatim ports — biochamber (tabs, magic RGB, C-style comments), CPM (informal comments) — repo is PUBLIC on GitHub.
9. Drop deprecated `event.created_entity` fallback chain (`teleporters/control.lua:1034`) — 2.x events are stable now.
10. Repo infra: scripted headless verify (dump-data + N-tick benchmark) as a repo script next to build.ps1; changelog-format lint (99-dash rule bites repeatedly).
