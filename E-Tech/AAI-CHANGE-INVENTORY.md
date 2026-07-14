# AAI Industry 0.7.1 — Change Inventory & E-Tech Revert Design

Source of truth for what AAI Industry changes vs vanilla Factorio, and the plan for which changes E-Tech should expose as revert toggles. No code decisions are locked in here — this is the map we design against.

## How to read this

Every AAI change is tagged by **kind**, because kind determines how hard it is to revert:

| Tag | Kind | Revert difficulty |
|-----|------|-------------------|
| **A** | Cost / ingredient swap on an existing vanilla recipe | **Easy** — mutate one recipe's ingredients |
| **B** | New intermediate-item tier inserted into many recipes | **Hard — cascades.** Must heal every recipe that consumes the item, restore vanilla ingredients, and fix the item's tech unlock |
| **C** | Tech-tree relocation / new gating | **Medium** — re-enable recipe + strip added unlock, or restore prerequisites |
| **D** | Craftability / recipe-category change | **Medium** — flip category back |
| **E** | Brand-new building or mechanic (additive) | **N/A** — nothing vanilla to revert; leave alone (or hide, separately) |

**Revert difficulty is the whole point.** A per-recipe toggle cleanly handles **A**. **B** changes must be shipped as *bundles* (one toggle = many coordinated edits), because the AAI-invented item is threaded through ~20 recipes.

---

## The engine/motor progression (your focal point)

This is the clearest example of a **type-B** change and why it needs a bundle, not a checkbox.

AAI invents a two-item motor tier and slots it *underneath* vanilla's engine chain:

```
AAI:      motor (single-cylinder engine)          <- NEW, hand-craft: iron-plate + gear
            └─> engine-unit (reskinned "multi-cylinder engine")   <- made from 2x motor
          electric-motor                          <- NEW: iron-plate + gear + copper-cable
            └─> electric-engine-unit ("big electric motor")       <- made from 2x electric-motor

Vanilla:  engine-unit          <- steel-plate + gear + pipe (assembler only)
          electric-engine-unit <- engine-unit + lubricant + circuit
```

- `engine-unit` is reskinned to a **"multi-cylinder engine"** icon (`engine` tech icon → `multi-cylinder-engine.png`) and made **hand-craftable** from `2x motor`. That's the "multi engine as a middle ground" you flagged — it exists only because the single-cylinder `motor` exists below it.
- `motor` is injected into ~20 recipes (belt, inserters, drills, turrets, burner buildings, gun-turret, gate…).
- `electric-motor` is injected into ~20 more (steam-engine, asm-1/2, lab, chem-plant, refinery, pumps, roboport, radar…).

**To truly revert the motor tier** you must, in one coordinated pass: restore vanilla ingredients on every consuming recipe (swap `motor`→`iron-gear-wheel`/`engine-unit` as appropriate), restore `engine-unit` to `steel-plate+gear+pipe`, and remove the `burner-mechanics` tech unlocks for `motor`. Doing it recipe-by-recipe risks a half-reverted chain. → **Bundle toggle: "Remove single-cylinder engine (motor) tier."**

---

## Inventory by system

### 1. Motor / engine tier — TYPE B (bundle candidate)

| AAI change | AAI recipe | Vanilla target |
|---|---|---|
| `motor` new item | iron-plate 1 + gear 1 (hand-craft) | *(delete from chain)* |
| `electric-motor` new item | iron-plate 1 + gear 1 + copper-cable 6 | *(delete from chain)* |
| `engine-unit` reskin + recipe | steel-plate 2 + gear 2 + **motor 2**, hand-craft | steel-plate 1 + gear 1 + pipe 2, assembler |
| `electric-engine-unit` | lubricant 40 + steel-plate 2 + circuit 4 + **electric-motor 2** | engine-unit 1 + lubricant 15 + circuit 2 |
| ~40 recipes consuming motor/electric-motor | see §2 | swap back to gear / engine-unit |

**Proposed:** two bundle toggles — *Remove single-cylinder (motor) tier* and *Remove electric-motor tier* — each rewriting all its consumers. Granular per-recipe toggles (§2) stay available for people who want to keep the tier but revert only specific costs.

### 2. Cost / ingredient swaps — TYPE A (granular toggles)

Existing E-Tech toggles cover the first block. Verified vanilla values (cross-checked against the *affordable-industry* fork) for the rest:

| Recipe | AAI | Vanilla | In E-Tech? |
|---|---|---|---|
| transport-belt | iron-plate 1 + motor 1 | iron-plate 1 + gear 1 → 2 | ✅ |
| burner-inserter | iron-stick 2 + motor 1 | iron-plate 1 + gear 1 | ✅ |
| inserter | burner-inserter 1 + electric-motor 1 | iron-plate 1 + gear 1 + circuit 1 | ✅ |
| long-handed-inserter | inserter 1 + iron-plate 2 + iron-stick 2 | iron-plate 1 + gear 1 + inserter 1 | ✅ |
| burner-mining-drill | stone-brick 4 + iron-plate 4 + motor 1 | iron-plate 3 + gear 3 + stone-furnace 1 | ✅ |
| electric-mining-drill | gear 4 + electric-motor 4 + burner-drill 1 | iron-plate 10 + gear 5 + circuit 3 | ✅ |
| steel-furnace | stone-brick 6 + steel-plate 6 + stone-furnace 1 | steel-plate 6 + stone-brick 10 | ✅ |
| assembling-machine-1 | gear 4 + electric-motor 1 + burner-asm 1 | iron-plate 9 + gear 5 + circuit 3 | ✅ |
| steam-engine | iron-plate 10 + gear 5 + electric-motor 3 | iron-plate 10 + gear 8 + pipe 5 | ✅ |
| lab | circuit 5 + electric-motor 5 + glass 5 + burner-lab 1 | circuit 10 + gear 10 + belt 4 | ✅ |
| engine-unit | steel-plate 2 + gear 2 + motor 2 | steel-plate 1 + gear 1 + pipe 2 | ✅ |
| car | gear 10 + steel-plate 5 + engine-unit 5 | iron-plate 20 + gear 8 + engine-unit 8 | ✅ |
| radar | iron-plate 20 + circuit 8 + stone-brick 4 + electric-motor 4 | iron-plate 10 + gear 5 + circuit 5 | ✅ |
| gun-turret | iron-plate 20 + gear 10 + motor 5 | iron-plate 20 + copper-plate 10 + gear 10 | ✅ |
| small-lamp | iron-plate 1 + copper-cable 4 + glass 1 | iron-plate 1 + copper-cable 3 + circuit 1 | ✅ |
| assembling-machine-2 | steel-plate 2 + circuit 2 + electric-motor 2 + asm-1 1 | steel-plate 2 + gear 5 + circuit 3 + asm-1 1 | ➕ add |
| assembling-machine-3 | concrete 8 + steel-plate 8 + adv-circuit 8 + elec-engine 4 + asm-2 1 | asm-2 2 + speed-module 4 | ➕ add |
| electric-furnace | steel-plate 5 + adv-circuit 5 + concrete 5 + steel-furnace 1 | steel-plate 10 + adv-circuit 5 + stone-brick 10 | ➕ add |
| chemical-plant | steel-plate 5 + electric-motor 5 + glass 5 + pipe 5 + stone-brick 5 | steel-plate 5 + gear 5 + circuit 5 + pipe 5 | ➕ add |
| oil-refinery | steel-plate 15 + electric-motor 15 + glass 15 + pipe 15 + stone-brick 15 | steel-plate 15 + gear 10 + stone-brick 10 + circuit 10 + pipe 10 | ➕ add |
| beacon | adv-circuit 20 + concrete 10 + steel-plate 10 + electric-motor 10 | circuit 20 + adv-circuit 20 + steel-plate 10 + copper-cable 10 | ➕ add |
| pumpjack | steel-plate 15 + gear 10 + electric-motor 10 + pipe 10 | steel-plate 5 + gear 10 + circuit 5 + pipe 10 | ➕ add |
| pump | electric-motor 2 + pipe 2 + steel-plate 1 | electric-motor→ engine-unit 1 + steel-plate 1 + pipe 1 | ➕ add |
| offshore-pump | electric-motor 2 + pipe 4 | *(vanilla 2.0 differs; verify)* | ⚠ verify |
| laser-turret | steel-plate 20 + circuit 20 + glass 20 + battery 12 + electric-motor 5 | steel-plate 20 + circuit 20 + battery 12 | ➕ add |
| gate | stone-wall 1 + steel-plate 2 + circuit 2 + motor 2 | stone-wall 1 + steel-plate 2 + circuit 2 | ➕ add |
| medium-electric-pole | iron-stick 4 + steel-plate 2 + copper-cable 4 + small-iron-pole 1 | iron-stick 4 + steel-plate 2 + copper-plate 2 | ➕ add |
| big-electric-pole | iron-stick 8 + steel-plate 5 + copper-cable 10 + concrete 1 | iron-stick 8 + steel-plate 5 + copper-plate 5 | ➕ add |
| substation | copper-cable 20 + steel-plate 10 + concrete 5 + adv-circuit 5 | steel-plate 10 + adv-circuit 5 + copper-plate 5 | ➕ add |
| roboport | steel-plate 50 + electric-motor 50 + adv-circuit 50 + concrete 50 | steel-plate 45 + gear 45 + adv-circuit 45 | ➕ add |
| steam-turbine | +electric-motor 10 (added) | *(remove added electric-motor)* | ➕ add |
| centrifuge | +electric-motor 25 (added) | *(remove added electric-motor)* | ➕ add |
| flying-robot-frame | elec-engine 4 + battery 4 + circuit 4 + steel-plate 4 | elec-engine 1 + battery 2 + steel-plate 1 + circuit 3 | ➕ add |
| locomotive | steel-plate 30 + engine-unit 15 + gear 10 + circuit 10 | steel-plate 30 + engine-unit 20 + circuit 10 | ➕ add |
| repair-pack | iron-plate 3 + copper-plate 3 + stone 3 | gear 2 + circuit 2 | ➕ add |
| heavy/modular/power armor + mk2 | +prior-tier item added | remove the added prior-tier ingredient | ➕ add (armor bundle) |
| solar-panel / satellite / p-laser-defense | +glass added | remove added glass | ➕ tied to glass bundle |

### 3. Glass / sand tier — TYPE B (bundle candidate)

`sand` (from stone) → `glass` (smelt sand). Glass injected into: chem-plant, oil-refinery, lab, laser-turret, small-lamp, solar-panel, satellite, personal-laser-defense. Sand also enters `concrete`. Gated behind new `sand-processing` → `glass-processing` techs.
**Proposed:** *Remove glass/sand tier* bundle (restore vanilla ingredients on all glass consumers; concrete handled in §5).

### 4. Stone-tablet electronics — TYPE B/C (bundle candidate)

`electronic-circuit` recipe: iron-plate → **stone-tablet** (stone-brick → 4 tablets). Gated: `electronics` tech now unlocks stone-tablet + circuit. Also `automation-science-pack` trigger changed to craft-in-burner-lab.
**Proposed:** *Restore vanilla electronic circuit* toggle (circuit back to iron-plate, drop stone-tablet dependency).

### 5. Concrete — TYPE A/B

AAI: stone-brick 5 + **sand 10** + iron-stick 2 + water 100 → 10 (crafting-with-fluid). Vanilla: stone-brick 5 + iron-ore 1 + water 100 → 10.
**Proposed:** single toggle (rolls up with glass/sand bundle or standalone).

### 6. Science packs not hand-craftable — TYPE D (bundle candidate)

All 7 science packs get `"crafting"` removed from categories (→ assembler-only). Plus ingredient/count tweaks on logistic (belt 2, ×2 out) and utility (proc-unit 3, ×5 out).
**Proposed:** *Restore hand-craftable science packs* toggle (re-add `"crafting"` category). Ingredient-count reverts optional sub-toggle.

### 7. Tech-gate relocations — TYPE C

The big one. Vanilla craft-from-start / early recipes AAI pushed behind research:

| Recipe(s) | Moved to AAI tech | Vanilla |
|---|---|---|
| pipe, pipe-to-ground, offshore-pump | basic-fluid-handling | craft from start |
| boiler, steam-engine | steam-power | craft from start |
| transport-belt | basic-logistics | craft from start |
| motor, iron-stick, burner-inserter, burner-drill/asm/lab | burner-mechanics | (new items) |
| electric-motor, inserter, copper-cable, small-poles | electricity | early |
| electronic-circuit, stone-tablet | electronics | early |
| lab | electric-lab | early |

Plus ~120 prerequisite edits weaving the new `burner-mechanics → basic-logistics → electricity → …` spine through the vanilla tree. **Full tech-tree revert is not realistic** (it would fight AAI's entire structure). E-Tech already ships the highest-value slice: *Un-gate fluid basics* (pipe/offshore-pump/boiler/steam-engine). Realistic additions: *Un-gate transport belt*, *Un-gate electronics (stone-tablet off)*. Everything deeper = leave.

### 8. Brand-new buildings/mechanics — TYPE E (leave alone)

Nothing vanilla to revert. Not E-Tech's job unless you later want a *hide/disable* mode:
burner-assembling-machine, burner-lab, burner-turbine, industrial-furnace, area-mining-drill (setting-gated), fuel-processor + processed-fuel (setting-gated), small-iron-electric-pole, concrete/steel wall + gate tiers, stone-path tile, toolbelt tiers. Offshore-pump→electric is TYPE D but core to AAI; leave.

### 9. AAI's own settings (reference)

AAI already exposes: `aai-fast-motor-crafting`, `aai-wide-drill`, `aai-fuel-processor`, `aai-stone-path`, turbine/fuel efficiency, flashlight/nightvision/LUT, `start-with-basic-logistics`, `quick-start-science`. E-Tech should **not** duplicate these — they're AAI-native. E-Tech only covers what AAI does *not* let you turn off.

---

## Proposed toggle taxonomy

Two layers, grouped by section in Mod Settings.

### Bundles (TYPE B/D — coordinated multi-recipe reverts)
- ☐ **Remove single-cylinder engine (motor) tier** — motor→gear/engine-unit everywhere; engine-unit→vanilla; drop burner-mechanics motor unlock
- ☐ **Remove electric-motor tier** — electric-motor→gear/engine-unit everywhere; electric-engine-unit→vanilla
- ☐ **Remove glass/sand tier** — glass/sand→vanilla ingredients on all consumers
- ☐ **Restore vanilla electronic circuit** — drop stone-tablet
- ☐ **Restore hand-craftable science packs**
- ☐ **Restore vanilla concrete** (iron-ore, no sand/iron-stick)

### Granular cost reverts (TYPE A — one recipe each)
- The 15 shipped + ~25 to add from §2 (only meaningful when its tier bundle is *off*).

### Un-gate (TYPE C)
- ☐ Un-gate fluid basics *(shipped)*
- ☐ Un-gate transport belt
- ☐ Un-gate electronics / stone-tablet

### Non-AAI (separate section, already built)
- ☐ Freeplay: pick up & re-place crashed ship

### Interaction rule to design for
A granular cost toggle and its parent bundle can conflict (both rewrite the same recipe). Rule: **if a bundle is ON, it wins and its granular children are ignored/greyed**; granular toggles only apply when the bundle is OFF. Implement as: apply bundles first, then apply granular reverts only for recipes not already claimed by an active bundle.

---

## Open questions before building
1. Motor-tier bundle: when removed, should `engine-unit` become **hand-craftable** (affordable-fork style) or strictly **assembler-only** (true vanilla)? Affects early-game feel.
2. Do you want the ~25 extra granular toggles, or only the bundles + the current 15?
3. Should there be a **"full vanilla recipes"** master preset that flips every bundle on at once?
4. offshore-pump vanilla 2.0 ingredients need confirming in-game before I hardcode.
