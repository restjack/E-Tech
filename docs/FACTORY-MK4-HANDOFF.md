# Handoff — adding a Factorissimo tier-4 factory ("Mk4")

**Written:** 2026-07-30. Researched against **Factorissimo 3.12.2** (`factorissimo-2-notnotmelon`), Factorio 2.1.
Everything below was read out of the mod's own source; nothing here is guessed.

**STATUS: BUILT 2026-07-30, shipped in E-Tech 0.20.0.** This doc is now a
record, not a plan. The tier exists, `dump-data` is clean and every prototype
was confirmed present in the dump. What is *not* yet done is an in-game test:
the layout registration and the interior itself are control-stage and cannot be
verified headlessly. See §8 for what to check on first launch.

Three claims in the original version of this doc were wrong and have been
corrected in place — the interior ceiling (§3), the registration risk (§3), and
a missed roboport problem (§8).

---

## 1. The decision — SETTLED 2026-07-30

**Option B, plus a visual marker.** Eli's call: *"keep the exterior footprint the
same as the one before it, but some visual marks outside that it's larger."*

| | value | notes |
|---|---|---|
| interior | **120×120** | 4× factory-3's area; his original "double the last one" |
| exterior | **16×16** | identical to factory-3 (`collision_box` ±7.8) |
| base ports | **32** | factory-3's connection table copied verbatim |
| quality ports | **14** | inherited with the copy |
| ratio | 7.5 | deliberately off-pattern; see below |
| power input | `factory-power-input-16` | reused, no new prototype |

This trades the 3.75 interior/exterior ratio for a same-footprint drop-in. That's
the point: the Mk4 must be placeable in a slot already built for a factory-3.
Consequences, accepted knowingly:

- **Port density falls.** 32 base ports feed 4× the floor. Interiors will want
  more internal bussing per port than a factory-3 does.
- **A future Mk5 has no room on this pattern.** Whoever wants one goes back to
  the 20×20 exterior track (the old option A: 76×76 interior, 40 ports,
  `factory-power-input-20` — kept in §2 in case it's ever revived).

Rejected: pattern-consistent 76×76 / 20×20 / 40 ports / 1.6× area.

### The visual marker

Without one this is indistinguishable from a factory-3 on the map, in inventory,
and on the ground — the one real cost of B, so this part is not optional.

Factorissimo's **own precedent**: `space-factory-1/2/3` reuse each tier's shadow
layer verbatim and swap only the main png (`prototypes/factory.lua:277–290`).
Same-footprint visual variants are already how this mod works.

factory-3's exterior is a plain static two-layer sprite — no masks, no runtime
tint, no animation:

```lua
pictures = {picture = {layers = {
    {filename = F.."/graphics/factory/factory-3-shadow.png", width = 704*2, height = 608*2,
     scale = 0.5, shift = {2, -0.09375}, draw_as_shadow = true},
    {filename = F.."/graphics/factory/factory-3.png",        width = 704*2, height = 608*2,
     scale = 0.5, shift = {2, -0.09375}},
}}}
```

Four ways to mark it, cheapest first. Do 1+2 immediately; 3 or 4 when there's
appetite.

1. **`map_color`** — one line. All six existing factories share
   `{r = 0.8, g = 0.7, b = 0.55}`, so any change makes the Mk4 unmistakable on
   the map. Free.
2. **`tint` on the main layer** (shadow layer untinted). Sprite `tint` multiplies,
   so it can only darken or shift hue — a deeper/cooler body reads as
   "heavier tier" and needs zero art. Tint the icon layer to match so inventory
   agrees with the ground.
3. **Runtime marker via `rendering.draw_sprite` / `draw_text`** on build — a "IV"
   or a badge floating on the building. Control-stage, zero art, but it's one
   render object per building that must be recreated on load and cleaned up on
   destroy. Only worth it if 1+2 read too subtly.
4. **A real recolored `factory-4.png`** (1408×1216, drawn at `scale = 0.5`) plus
   a matching 64px icon. Reuse `factory-3-shadow.png` unchanged, exactly as the
   space variants do. The clean answer; the only one needing art.

Icon note: the item, the `-instantiated` item-with-tags, and the entity all point
at the same icon path — change all three or the packed factory in a player's
inventory still looks like a Mk3.

## 2. How the existing tiers scale

| layout | interior | exterior | ratio | area | connections |
|---|---|---|---|---|---|
| `factory-1` | 30×30 | 8×8 | 3.75 | 900 | 26 (16 base + 10 quality-gated) |
| `factory-2` | 46×46 | 12×12 | 3.83 | 2,116 | 34 (24 + 10) |
| `factory-3` | 60×60 | 16×16 | 3.75 | 3,600 | 46 (32 + 14) |

Invariants that actually hold:

- **Exterior grows exactly +4 per tier** → tier 4 = 20
- **interior/exterior ratio is 3.75–3.83** → tier 4 interior ≈ 75–77 (use an even
  number; rectangles are symmetric `±n`, so **76** is the natural pick)
- **Base connections +8 per tier** (16 → 24 → 32), which equals one per 2 perimeter
  tiles → tier 4 = **40**
- Interior deltas are +16 then +14 (decreasing), which would argue 72–74 instead.
  The ratio is the more stable signal.

Source: `script/layout.lua`.

**This section is now reference only** — it describes the rejected
pattern-consistent track (76×76 / 20×20 / 40 ports). Kept because it's the
recipe for any later tier that goes back on-pattern. The Mk4 being built ignores
all three invariants by design; see §1.

## 3. The layout system

### Schema

`layout_generators["factory-3"]` top-level fields, in order:

```
name, tier, inside_size, outside_size,
inside_door_x, inside_door_y, outside_door_x, outside_door_y,
outside_energy_receiver_type, outside_requester_chest, outside_ejector_chest,
inside_energy_x, inside_energy_y,
overlay_x, overlay_y,
rectangles, mosaics, connection_tile, connections, overlays,
cerys_radiative_towers
```

`rectangles` are `{x1, x2, y1, y2, tile}` fills. `mosaics` are the same plus an
ASCII-art `pattern` array of strings for decorative floor tiles. Connections are
built by two helpers:

```lua
w1 = make_connection("w1", -8.5, -5.5, -30.5, -24.5, west),
w9 = make_quality_connection("w9", -8.5, -1.5, -30.5, -1.5, west, 2),
```

Args are `(id, outside_x, outside_y, inside_x, inside_y, direction_out[, quality])`.
`remote_api.create_layout(name, quality)` filters connections with
`(connection.quality or 0) <= quality.level`, so quality tiers unlock extra ports.
Copying factory-3's connection table inherits that behaviour.

**The actual work, given §1:** copy factory-3's whole connection table, leave
every `outside_x`/`outside_y` untouched, and move only the interior endpoints out
to the 120×120 wall — i.e. every `±30.5` becomes `±60.5`, with the along-wall
coordinates respaced across the longer run. Quality gating comes along free.

`remote_api.add_layout` writes straight into `storage.layout_generators`, and
`has_layout(name)` is what gates the rest of the mod, so a properly registered
layout behaves like a native tier — no fork needed.

### Interior size ceiling — 120 is the maximum. CORRECTED.

The original version of this doc said interiors up to ~240×240 fit and that
size was not a blocker. **That was wrong**, and it was luck that the chosen
size is exactly the largest that works.

The 512-tile cell spacing is real — `find_surrounding_factory`
(`script/remote-api.lua`) divides by `16 * 32` and caps at 8 columns, so each
interior owns a 512×512 cell, 64 per surface. But cell *spacing* is not what
limits interior *size*. Two things do, both in `script/factory-buildings.lua`:

```lua
-- create_factory_position(): only these chunks are marked generated
for xx = -2, 2 do
    for yy = -2, 2 do
        surface.set_chunk_generated_status({cx + xx, cy + yy}, ...)
```

```lua
-- add_hidden_tile_rect(): same box
local xmin = factory.inside_x - 64
```

±2 chunks = **±64 tiles**, and the hidden-tile rect matches. A 120×120 interior
puts its walls at ±61 and runs its door corridor to y = 63 — one tile inside
the limit. **122 would not fit.** Anything larger needs Factorissimo itself
patched, not just a new layout.

`cleanup_factory_interior` agrees: it works over `(inside_size + 8) / 2`, which
at 120 is exactly 64.

### Registration — there is a public API, and the risk was overstated. CORRECTED.

```lua
remote.call("factorissimo", "add_layout", layout_table)
```

The original version warned that Factorissimo's `reload_layouts()` "rewrites its
entries" and could wipe a custom layout. Reading it properly:

```lua
_G.reload_layouts = function()
    storage.layout_generators = storage.layout_generators or {}
    for name, layout in pairs(layout_generators) do
        storage.layout_generators[name] = layout
    end
```

It never clears the table — it writes its own names into whatever is there. A
foreign entry survives. `add_layout` is equally defensive
(`storage.layout_generators or {}`), so call order against Factorissimo's
`on_init` does not matter.

What *does* matter, and is the real requirement: **the entry only exists
because we put it there**, so it has to be re-added on `on_init` *and*
`on_configuration_changed`. Factorissimo's `lib/events.lua` maps its own
`on_init` pseudo-event to both:

```lua
elseif event == factorissimo.events.on_init() then
    script.on_init(f)
    script.on_configuration_changed(f)
```

Not `on_load` — writing `storage` there desyncs multiplayer, and it is
unnecessary since the registration lives in the save.

`factory-mk4/control.lua` registers on both and then verifies with
`has_layout`, reporting to `log` and `game.print` on failure, because an
unregistered layout means every placed Mk4 has no interior.

Factorissimo's own debug hook, useful while iterating:

```
/c __factorissimo-2-notnotmelon__ reload_layouts()
```

## 4. Prototypes a new tier needs

`BUILDING_TYPE = "storage-tank"` (`script/remote-api.lua:3`) — factory buildings
are storage-tank prototypes.

1. **Entity** `factory-4` — deepcopy `data.raw["storage-tank"]["factory-3"]`,
   rename, keep `collision_box`/`selection_box` at ±7.8. Apply the §1 visual
   marker here (`map_color`, layer `tint`). Bump `max_health` past 5000 to match
   the tier.
2. **Item + `item-with-tags`** — `factory-4` and `factory-4-instantiated`, both
   with the marked icon, `order = "b-d"`, and `+ recipe` (natural progression is
   factory-3 + ingredients).
3. **Technology** unlock.
4. **`factory-requester-chest-factory-4` and `factory-eject-chest-factory-4`** —
   Factorissimo generates these in a hardcoded loop
   `for _, factory_name in pairs {"factory-1", "factory-2", "factory-3"}`
   in `prototypes/roboport.lua`. A fourth tier needs its own pair.
5. **Power input interface** — **none needed.** `factory-power-input-16` is
   reused as-is, since the exterior is unchanged. (For the record, a 20×20
   exterior would have needed `factory-power-input-20` via
   `create_energy_interfaces(size, icon)` in `prototypes/component.lua` — an
   all-zeros `electric-energy-interface` used purely to read `electric_network_id`.)
6. Tiles reuse `factory-wall-3` / `factory-floor` unchanged.

### Other hardcoded tier lists to check

- `prototypes/factory.lua` — entity/item/recipe per tier
- `prototypes/quality-tooltips.lua` — `add_quality_factoriopedia_info` per tier
- `compat/picker-dollies.lua` — blacklist names
- `compat/pyanodon.lua` — recipe overrides
- `script/layout.lua` `make_space_layout()` — builds `space-factory-1/2/3`; a Mk4
  usable on space platforms needs the same treatment

## 5. Power, for reference

Factorissimo 3 does **not** meter factory power. `script/electricity.lua`
`connect_power()` wires the interior `factory-power-pole` (supply_area_distance 63)
directly to an exterior pole with copper wire, and nested factories connect to
their *parent's* interior pole — so a factory at any nesting depth is on the same
electric network as the base. There is no per-factory power budget, no transfer
limit, no loss. A Mk4 inherits this for free.

## 6. Where the work goes

Build target is **E-Tech**, not a fork:
`C:\Users\Eli Tellez\Nextcloud\Projects\Factorio (E-Tech)\E-Tech\`

- Data-stage prototypes → new file, required from `data.lua` behind a startup toggle
  (follow the `factory-hub/` pattern — it already guards on
  `mods["factorissimo-2-notnotmelon"]`)
- Layout registration → control stage, `handler.add_lib` in `control.lua`
- Settings → `settings.lua` + `locale/en/settings.cfg` (every setting needs both a
  name and a description; they are cross-checked)

Build and verify:

```bash
powershell -File "E-Tech\build.ps1"
```

```bash
powershell -File "tools\verify.ps1"
```

`build.ps1` writes straight into `%APPDATA%\Factorio\mods` — **Factorio must be
closed or the zip is locked.** `verify.ps1` does Lua syntax (luaparser),
changelog lint, and `factorio --dump-data` against the live mod set. The dump
catches prototype errors headlessly and has already caught two real ones in this
project; use it before every launch.

Inspect resulting prototypes at
`%APPDATA%\Factorio\script-output\data-raw-dump.json`.

**Gotcha:** changing a setting's `default_value` has no effect once that setting
exists in `mod-settings.dat`. Defaults only apply to fresh installs and to the
server if it has never loaded the mod. Confirmed again during this build: the
setting was shipped at `default_value = false` *after* a dump had already
written `true` into `mod-settings.dat`, and the Mk4 kept building locally.

---

## 8. What was actually built (0.20.0)

| file | role |
|---|---|
| `E-Tech/factory-mk4/layout.lua` | the layout table — geometry, 46 ports, floor logo |
| `E-Tech/factory-mk4/data.lua` | entity, item, packed item, recipe, tech, hidden chests, factoriopedia rows |
| `E-Tech/factory-mk4/control.lua` | `add_layout` registration + verification + Picker Dollies blacklist |

Wired into `data.lua`, `control.lua`, `settings.lua`
(`etech-factory-mk4`, startup, **default off**), `locale/en/settings.cfg`,
new `locale/en/factory-mk4.cfg`, `misc-tweaks.lua`, `info.json`, `changelog.txt`.

### The roboport problem the original doc missed

Factorissimo builds the interior roboport at the factory's **door**
(`layout.inside_energy`, y = +`half`+2), not at its centre, with
`construction_radius = 64`:

| tier | roboport y | reach | far wall | covered? |
|---|---|---|---|---|
| factory-3 | +32 | −32 | −31 | yes |
| factory-4 | +62 | −2 | −61 | **no — northern half dead** |

E-Tech now raises both `logistics_radius` and `construction_radius` to **128**
whenever the Mk4 setting is on (`misc-tweaks.lua`,
`apply_mk4_roboport_reach`). It applies whether or not the interior-roboport
buff is on, and runs before the Krastorio 2 mode-variant loop so the twins
derive from the new values.

Safe for the small tiers: interiors sit 512 tiles apart, so the farthest this
reaches from a cell centre is 190, and the next floor starts at 449.

**`dump-data` caught the follow-on error immediately:**

```
Error while loading entity prototype "factory-construction-roboport" (roboport):
logistics_connection_distance (64) cannot be less than logistics_radius (128)
```

Fixed by raising `logistics_connection_distance` to match. That also fixes a
**pre-existing latent bug**: `etech-factory-roboport-logistics-radius` accepts
up to 512, and any value above 64 would have been a hard load failure before
this. Third real error the dump has caught in this project.

### Verified headlessly

`VERIFY OK` — Lua syntax, changelog lint, `dump-data` clean. Confirmed present
in `data-raw-dump.json`: `factory-4` (collision box ±7.8 = unchanged 16×16,
max_health 8000, tinted body layer, own map colour), `factory-4` item,
`factory-4-instantiated`, the recipe (factory-3 + 5000 refined concrete +
4000 steel + 200 substations + 500 processing units), tech
`etech-factory-architecture-t4` (4000×90s, inherited science mix +
utility, prereqs `factory-architecture-t3` + `utility-science-pack`),
`factory-requester-chest-factory-4`, `factory-eject-chest-factory-4`, the
factoriopedia rows (32 ports normal → 46 legendary), and the roboport at
128/128/128.

The derive-cost-from-t3 trick paid off: in this modpack t3 had already been
rewritten to space + utility + metallurgic science, and t4 inherited it rather
than hardcoding a vanilla mix that doesn't exist here.

### In-game test 2026-07-30 — two real failures, both fixed in 0.20.1

**1. Half the floor had no electricity.** Machines in the northern half sat at
"No power" with nothing to trace — the pole that feeds a factory interior is
hidden and has no wire.

`get_or_create_inside_power_pole` (`script/electricity.lua:56`) places
`factory-power-pole` at `layout.inside_energy`, which every stock tier puts
*beside the door* (`y = half+2`). That pole has `supply_area_distance = 63`:

| tier | pole y | reaches | far wall | powered? |
|---|---|---|---|---|
| factory-3 | +32 | −31 | −31 | yes, exactly |
| factory-4 | +62 | −1 | −61 | **no — 59 tiles dead** |

**The engine caps `supply_area_distance` at 64 for every electric pole
prototype**, so unlike the roboport this cannot be fixed by raising a number —
and a custom pole prototype does not help either. From the door, *no* pole can
reach the far side of a 120-wide floor.

Screenshot evidence: the factory power monitor read **Supply area 126×126**
(= 2×63) on a 120-wide floor.

Two ways out. The first attempt moved `inside_energy` to `(-4, 0)` — the middle
of the floor. It works (63 covers ±63) and fixes the roboport for free, but
`inside_energy` positions *both* the pole and the roboport
(`script/roboport/roboport.lua:287` reads it as `(-x, y)`), so it parks both in
the middle of the player's build area.

**Shipped instead: the visible pair stays at the door, and a hidden relay pole
does the work.** `inside_energy` is back at `(-4, 62)`. An invisible,
uncollidable, unselectable `etech-factory-mk4-power-relay` (empty sprite, no
wires drawn, `supply_area_distance = 64`) is built at the interior centre and
script-wired to Factorissimo's door pole, putting the whole floor on one
network. The roboport needs nothing — the 128 reach bump already covers a
120-wide floor from the door.

### The extension point that made it clean: `layout.upgrades`

No event handlers, no polling, no migration. `build_factory_upgrades`
(`script/factory-buildings.lua:156`) walks `factory.layout.upgrades` and, for
any entry whose first element is **not** `"factorissimo"`, calls
`remote.call(mod, function, factory)` with the live factory table — giving
direct access to `inside_surface`, `inside_x/y`, `force` and
`_inside_power_pole`.

It runs in three places, which is what makes it self-healing:

| caller | when |
|---|---|
| `create_factory_exterior` (:469) | a factory is built |
| `activate_factories` (:173) | `on_init` **and** `on_configuration_changed`, for every existing factory |
| research handler (:184) | every research finish |

So the handler must be **idempotent** — it checks the surface for an existing
relay rather than keeping bookkeeping — and existing Mk4s repair themselves on
the next config change instead of needing a migration.

⚠ Setting `upgrades` **replaces** `DEFAULT_FACTORY_UPGRADES`, so all four
Factorissimo defaults (lights, greenhouse, display, roboport) have to be listed
again or the tier silently loses them.

`connect_to(other, false, defines.wire_origin.script)` ignores wire reach —
that is the same call Factorissimo uses to bridge an interior to a *different
surface*, so `maximum_wire_distance = 1` on both poles is irrelevant.

**2. The visual marker didn't work.** The prototype `tint` is a multiply — it
can only darken — so in game the Mk4 still read as a brown Mk3, and no tint can
do anything about the **"03" painted on the facade**. Reusing the Mk3 exterior
is the whole reason the marker exists, so a weak marker is a failed feature.

Replaced with real artwork: `tools/make-mk4-art.py` reads Factorissimo's
`factory-3.png`, repaints the "3" into a "4", and maps every non-paint pixel to
its own luminance tinted cold — corrugation and grime survive, the siding
becomes steel blue. Icon and technology icon get the same treatment. The
**shadow is Factorissimo's, referenced unchanged**, exactly as its own
`space-factory` variants do.

Four things that cost time, worth knowing before touching that script:

- The first erase pass sampled a single fixed column to fill over the old "3".
  That column sat inside the **"0"**, so it filled the area with yellow paint
  and produced a solid blob. It now inpaints per row from the nearest
  non-paint pixel in a clean strip to the right.
- The "4" was first drawn from hand-built polygons and looked crude in game.
  The facade font is a **heavy rounded grotesque** — measured off the "0":
  136 wide, 151 tall, uniform **~42px stroke**, far heavier than the 34 guessed.
  It is now a real **Arial Black** glyph scaled to the "0"'s height, blended by
  the glyph's own antialiasing.
- The loading crates are drawn **on top of** the digits and are the same yellow
  at every brightness, so they cannot be masked per pixel. The "4" carries its
  crossbar lower than the "3" carried its middle, so the bar vanished behind
  the crate and the digit read as a wedge. **The crate under the digit is
  deleted** and the bay inpainted; the crates left of the door and under the
  "0" stay.
- A flat paint fill next to the weathered "0" looks pasted on. The digit is
  multiplied by the underlying wall's luminance ratio, so the wall's streaks
  and stains show through it the way they do on the original digits.

Re-run the script if Factorissimo ever redraws factory-3. It needs Pillow and
`C:/Windows/Fonts/ariblk.ttf`.

### Still untested — needs an actual launch

Everything above is data stage. These are control stage and cannot be checked
by `dump-data`:

Confirmed working in the 2026-07-30 test: registration, the 120×120 interior
with closed walls and the "F4" floor logo, the factoriopedia rows (120×120,
32 ports, 12000/s), the tech at 4000×90s, the packed item, and the roboport
reach fix (256×256 supply/construction, up from 128×128).

Left to check after 0.20.1:

1. **Power in the north half.** Place a machine near the top wall of a
   *freshly built* Mk4 and confirm it runs.
2. **All 46 ports.** Confirm each exterior port lines up with its interior
   endpoint; the interior coordinates were respaced by hand.
3. **Roboport coverage.** Stand in the far (north) corner and confirm a ghost
   gets built.
4. **Recursion.** A Mk4 should accept a Mk3 inside it (tier 4 > tier 3).

### Deliberately not done

- **Space platforms.** `make_space_layout()` builds `space-factory-1/2/3` from
  a hardcoded list; a Mk4 there would need its own tile-mapped twin.
- **Deregistration.** Factorissimo exposes `add_layout` but no remove. Turning
  the setting off leaves the layout in the save with no prototype behind it —
  so treat enabling it as a one-way choice per save, which the setting
  description says.

## 7. Context from the session this came out of

The interior roboport work is **finished and shipped in E-Tech 0.19.7** — separate
feature, but it's why the Factorissimo source was read in the first place.

Headline finding, in case it matters for Mk4: Factorissimo's
`factory-construction-roboport` runs on a `{type = "void"}` energy source, and
because robot charging is paid from a roboport's *stored* energy, that roboport
**cannot charge robots at all**. E-Tech now gives it a real electric source.
Measured cost ~1–2 MW per busy factory, ~29 MW across 16. Full writeup:
`docs/FACTORISSIMO-ROBOPORT-BUG-REPORT.md` (drafted for upstream) and the
`factorissimo-roboport-buff` row in `docs/LOCAL-PATCHED-MODS.md`.

Related trap worth knowing if Mk4 touches roboports: **Krastorio 2 deep-copies
every `data.raw.roboport` entry in data-updates** to build its logistic-only /
construction-only mode variants
(`Krastorio2/prototypes/updates/generate-roboport-variations.lua`). Anything you
change in `data-final-fixes` will not be in those twins unless you patch them
too. E-Tech already does this for the factory roboport.


---

## 9. Polish pass (0.20.2)

Twelve items, all shipped. One was investigated and deliberately **not**
shipped — see the end.

### Matching the stock tiers

| | was | now |
|---|---|---|
| tech name | "Factory architecture 4" | **"Architecture 4"** — Factorissimo names its own "Architecture 2/3" |
| tech order | `c-k-a-d` | **`p-q-a-c-m`** — theirs are `p-q-a-a/b/c` and space architecture takes `p-q-a-d`, so this slots between |
| entity description | our prose only | Factorissimo's own control lines first (`__CONTROL__factory-rotate__`, `…-open-outside-surface-to-remote-view__`, `__CONTROL__cut__`), then ours |
| tech icon | still read **"03"** | repainted to "04" in place |
| item icon | — | no digit is legible at 64px; recolour only. Nothing to fix. |

The tech icon is an isometric render with the digits on a **tilted** face,
straddling the yellow band and the grey wall. Both problems are solved by
working along the **face axis** (`FACE_SLOPE = 0.39`, measured from the 0/3
baselines) instead of screen rows — a horizontal fill smears band colour up
over wall. The replacement "4" is squashed to `X_SQUASH = 0.41` and rotated
21°, derived by un-rotating the "3"'s 30×49 on-screen box to ~14×47.

### Interior identity

`factory-wall-4` / `factory-pattern-4`, **teal** — the stock tiers are orange,
blue, yellow, and teal stays clear of factory-2's blue. Deepcopied from
Factorissimo's tiles rather than rebuilt, because those carry transition
spritesheets, sounds, collision masks and a **frozen twin** (Aquilo) that needs
its own copy and back-link, or a frozen Mk4 floor shows the Mk3's.

### Space platforms

`space-factory-4` — entity, item, packed item, recipe, layout, and its own
tiles. Unlocked from Factorissimo's existing `factory-space-architecture`
rather than a second research, with `etech-factory-architecture-t4` added as a
prerequisite since the recipe eats a Mk4.

Ingredients are **copied from `space-factory-3`'s and scaled**, not written
out: Factorissimo gives that recipe completely different ingredients under
Space Exploration vs Space Age, and copying works under either.

The space skin is blue paint on grey at **half** the ground resolution, so the
art generator takes every measured box halved and a different paint detector
(`b - r > 30` instead of `b < r * 0.68`). All three stock space tiers already
share one blue-grey look, so recolouring the *wall* would not separate a Mk4 —
the **paint** goes amber instead, tiles included.

### Smaller items

- **Cerys radiative towers 4 → 9.** Four suits a 60-wide floor; over four times
  the area it left the middle and edges cold.
- **"Floor tiles per connection" factoriopedia row** — 450 vs a Mk3's 112. The
  ports did not grow with the floor, and a tooltip is a cheaper place to learn
  that than a finished build.
- **Relay pole has its own locale key** instead of borrowing the building's.

### Overhaul compatibility — generalised instead of per-mod

`factory-mk4/data-final-fixes.lua` re-derives the Mk4's research cost from the
Mk3's and drops retired recipe ingredients, **after** everyone else has run.
Factorissimo's own `compat/pyanodon.lua` rewrites the factory technologies in
`data-updates` — later than our data stage — so a snapshot taken at data time
was already stale. Reading the tier below at final-fixes never goes stale,
which is why there is no per-overhaul compat file here.

### NOT shipped: `next_upgrade` Mk3 → Mk4

Investigated and rejected. **Factorissimo has no upgrade or fast-replace
handling for factory buildings at all** — no `on_marked_for_upgrade`, no
`fast_replaceable_group`, nothing. An upgrade planner would therefore:

1. have a bot mine the Mk3 → the player gets a `factory-3-instantiated` item
   with the interior intact, and
2. build an **empty** Mk4 in its place.

Nothing is destroyed, but the machines are now inside a packed item in someone's
inventory rather than in the new building — which is not what "upgrade" means
to anyone using the planner. One line to enable (`next_upgrade` on `factory-3`)
if that trade is ever wanted.
