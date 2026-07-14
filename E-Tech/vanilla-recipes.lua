-- vanilla-recipes.lua
-- The single source of truth: every vanilla recipe AAI Industry changes,
-- with the vanilla (Factorio 2.x base / Space Age) values to restore.
--
-- Each entry:
--   name    : recipe name
--   vanilla : fields to restore. Supported: ingredients, results,
--             energy_required, categories (Factorio 2.1 array form),
--             clear_categories (reset to default {"crafting"} = hand-craftable).
--   aai     : fingerprint of AAI's version, used as a guard so we only
--             revert recipes that still look AAI-authored. If another mod
--             (e.g. Krastorio 2) has already rewritten the recipe into
--             something else, the fingerprint won't match and we leave it
--             alone. Forms:
--               aai.ingredients  -> exact (type,name,amount) multiset match
--               aai.results      -> exact results multiset match
--               aai.contains     -> recipe currently contains this ingredient
--             A recipe also matches if it contains any global AAI marker
--             item (motor, electric-motor, stone-tablet, glass, sand, ...) -
--             those items only ever appear in a recipe because of AAI.
--
-- Deliberately NOT listed:
--   boiler          - AAI's ingredients are identical to vanilla (only the
--                     tech gate differs, and we don't touch tech).
--   offshore-pump   - vanilla 2.x values unverified; AAI's version is cheap
--                     and reasonable. Revisit if it bothers anyone.
--   All AAI-added recipes (motor, glass, burner machines, walls, gates,
--   industrial-furnace, area-mining-drill, fuel-processor, sand, ...) -
--   new content stays exactly as AAI made it.

local M = {}

M.entries = {
  -- ============================ logistics ============================
  {
    name = "transport-belt",
    vanilla = { ingredients = {
      {type="item", name="iron-plate", amount=1},
      {type="item", name="iron-gear-wheel", amount=1},
    }},
    aai = { ingredients = {
      {type="item", name="iron-plate", amount=1},
      {type="item", name="motor", amount=1},
    }},
  },
  {
    name = "splitter",
    vanilla = { ingredients = {
      {type="item", name="electronic-circuit", amount=5},
      {type="item", name="iron-plate", amount=5},
      {type="item", name="transport-belt", amount=4},
    }},
    aai = { ingredients = {
      {type="item", name="iron-plate", amount=8},
      {type="item", name="transport-belt", amount=4},
      {type="item", name="motor", amount=4},
    }},
  },
  {
    name = "burner-inserter",
    vanilla = { ingredients = {
      {type="item", name="iron-plate", amount=1},
      {type="item", name="iron-gear-wheel", amount=1},
    }},
    aai = { ingredients = {
      {type="item", name="iron-stick", amount=2},
      {type="item", name="motor", amount=1},
    }},
  },
  {
    name = "inserter",
    vanilla = { ingredients = {
      {type="item", name="iron-plate", amount=1},
      {type="item", name="iron-gear-wheel", amount=1},
      {type="item", name="electronic-circuit", amount=1},
    }},
    aai = { ingredients = {
      {type="item", name="burner-inserter", amount=1},
      {type="item", name="electric-motor", amount=1},
    }},
  },
  {
    name = "long-handed-inserter",
    vanilla = { ingredients = {
      {type="item", name="iron-plate", amount=1},
      {type="item", name="iron-gear-wheel", amount=1},
      {type="item", name="inserter", amount=1},
    }},
    aai = { ingredients = {
      {type="item", name="inserter", amount=1},
      {type="item", name="iron-plate", amount=2},
      {type="item", name="iron-stick", amount=2},
    }},
  },

  -- ============================ mining / smelting ============================
  {
    name = "burner-mining-drill",
    vanilla = { ingredients = {
      {type="item", name="iron-gear-wheel", amount=3},
      {type="item", name="stone-furnace", amount=1},
      {type="item", name="iron-plate", amount=3},
    }},
    aai = { ingredients = {
      {type="item", name="stone-brick", amount=4},
      {type="item", name="iron-plate", amount=4},
      {type="item", name="motor", amount=1},
    }},
  },
  {
    name = "electric-mining-drill",
    vanilla = { ingredients = {
      {type="item", name="electronic-circuit", amount=3},
      {type="item", name="iron-gear-wheel", amount=5},
      {type="item", name="iron-plate", amount=10},
    }},
    aai = { ingredients = {
      {type="item", name="iron-gear-wheel", amount=4},
      {type="item", name="electric-motor", amount=4},
      {type="item", name="burner-mining-drill", amount=1},
    }},
  },
  {
    name = "steel-furnace",
    vanilla = { ingredients = {
      {type="item", name="steel-plate", amount=6},
      {type="item", name="stone-brick", amount=10},
    }},
    aai = { ingredients = {
      {type="item", name="stone-brick", amount=6},
      {type="item", name="steel-plate", amount=6},
      {type="item", name="stone-furnace", amount=1},
    }},
  },
  {
    name = "electric-furnace",
    vanilla = { ingredients = {
      {type="item", name="steel-plate", amount=10},
      {type="item", name="advanced-circuit", amount=5},
      {type="item", name="stone-brick", amount=10},
    }},
    aai = { ingredients = {
      {type="item", name="steel-plate", amount=5},
      {type="item", name="advanced-circuit", amount=5},
      {type="item", name="concrete", amount=5},
      {type="item", name="steel-furnace", amount=1},
    }},
  },

  -- ============================ assemblers ============================
  {
    name = "assembling-machine-1",
    vanilla = { ingredients = {
      {type="item", name="electronic-circuit", amount=3},
      {type="item", name="iron-gear-wheel", amount=5},
      {type="item", name="iron-plate", amount=9},
    }},
    aai = { ingredients = {
      {type="item", name="iron-gear-wheel", amount=4},
      {type="item", name="electric-motor", amount=1},
      {type="item", name="burner-assembling-machine", amount=1},
    }},
  },
  {
    name = "assembling-machine-2",
    vanilla = { ingredients = {
      {type="item", name="steel-plate", amount=2},
      {type="item", name="iron-gear-wheel", amount=5},
      {type="item", name="electronic-circuit", amount=3},
      {type="item", name="assembling-machine-1", amount=1},
    }},
    aai = { ingredients = {
      {type="item", name="steel-plate", amount=2},
      {type="item", name="electronic-circuit", amount=2},
      {type="item", name="electric-motor", amount=2},
      {type="item", name="assembling-machine-1", amount=1},
    }},
  },
  {
    name = "assembling-machine-3",
    vanilla = { ingredients = {
      {type="item", name="assembling-machine-2", amount=2},
      {type="item", name="speed-module", amount=4},
    }},
    aai = { ingredients = {
      {type="item", name="concrete", amount=8},
      {type="item", name="steel-plate", amount=8},
      {type="item", name="advanced-circuit", amount=8},
      {type="item", name="electric-engine-unit", amount=4},
      {type="item", name="assembling-machine-2", amount=1},
    }},
  },

  -- ============================ power ============================
  {
    name = "steam-engine",
    vanilla = { ingredients = {
      {type="item", name="iron-plate", amount=10},
      {type="item", name="iron-gear-wheel", amount=8},
      {type="item", name="pipe", amount=5},
    }},
    aai = { ingredients = {
      {type="item", name="iron-plate", amount=10},
      {type="item", name="iron-gear-wheel", amount=5},
      {type="item", name="electric-motor", amount=3},
    }},
  },
  {
    name = "steam-turbine",
    vanilla = { ingredients = {
      {type="item", name="iron-gear-wheel", amount=50},
      {type="item", name="copper-plate", amount=50},
      {type="item", name="pipe", amount=20},
    }},
    aai = { ingredients = {
      {type="item", name="copper-plate", amount=30},
      {type="item", name="iron-gear-wheel", amount=30},
      {type="item", name="pipe", amount=20},
      {type="item", name="electric-motor", amount=10},
    }},
  },
  {
    name = "solar-panel",
    vanilla = { ingredients = {
      {type="item", name="steel-plate", amount=5},
      {type="item", name="electronic-circuit", amount=15},
      {type="item", name="copper-plate", amount=5},
    }},
    -- AAI appends glass; the global glass/sand marker check catches this.
  },

  -- ============================ intermediates ============================
  {
    name = "electronic-circuit",
    vanilla = { ingredients = {
      {type="item", name="iron-plate", amount=1},
      {type="item", name="copper-cable", amount=3},
    }},
    aai = { ingredients = {
      {type="item", name="stone-tablet", amount=1},
      {type="item", name="copper-cable", amount=3},
    }},
  },
  {
    name = "engine-unit",
    vanilla = {
      ingredients = {
        {type="item", name="steel-plate", amount=1},
        {type="item", name="iron-gear-wheel", amount=1},
        {type="item", name="pipe", amount=2},
      },
      categories = {"advanced-crafting"}, -- vanilla: not hand-craftable
    },
    aai = { ingredients = {
      {type="item", name="steel-plate", amount=2},
      {type="item", name="iron-gear-wheel", amount=2},
      {type="item", name="motor", amount=2},
    }},
  },
  {
    name = "electric-engine-unit",
    vanilla = { ingredients = {
      {type="item", name="engine-unit", amount=1},
      {type="fluid", name="lubricant", amount=15},
      {type="item", name="electronic-circuit", amount=2},
    }},
    aai = { ingredients = {
      {type="fluid", name="lubricant", amount=40},
      {type="item", name="steel-plate", amount=2},
      {type="item", name="electronic-circuit", amount=4},
      {type="item", name="electric-motor", amount=2},
    }},
  },
  {
    name = "concrete",
    vanilla = { ingredients = {
      {type="item", name="stone-brick", amount=5},
      {type="item", name="iron-ore", amount=1},
      {type="fluid", name="water", amount=100},
    }},
    -- AAI version contains sand -> global marker catches it.
  },
  {
    name = "repair-pack",
    vanilla = { ingredients = {
      {type="item", name="electronic-circuit", amount=2},
      {type="item", name="iron-gear-wheel", amount=2},
    }},
    aai = { ingredients = {
      {type="item", name="iron-plate", amount=3},
      {type="item", name="copper-plate", amount=3},
      {type="item", name="stone", amount=3},
    }},
  },

  -- ============================ fluid / oil buildings ============================
  {
    name = "chemical-plant",
    vanilla = { ingredients = {
      {type="item", name="steel-plate", amount=5},
      {type="item", name="iron-gear-wheel", amount=5},
      {type="item", name="electronic-circuit", amount=5},
      {type="item", name="pipe", amount=5},
    }},
  },
  {
    name = "oil-refinery",
    vanilla = { ingredients = {
      {type="item", name="steel-plate", amount=15},
      {type="item", name="iron-gear-wheel", amount=10},
      {type="item", name="stone-brick", amount=10},
      {type="item", name="electronic-circuit", amount=10},
      {type="item", name="pipe", amount=10},
    }},
  },
  {
    name = "pump",
    vanilla = { ingredients = {
      {type="item", name="engine-unit", amount=1},
      {type="item", name="steel-plate", amount=1},
      {type="item", name="pipe", amount=1},
    }},
    aai = { ingredients = {
      {type="item", name="electric-motor", amount=2},
      {type="item", name="pipe", amount=2},
      {type="item", name="steel-plate", amount=1},
    }},
  },
  {
    name = "pumpjack",
    vanilla = { ingredients = {
      {type="item", name="steel-plate", amount=5},
      {type="item", name="iron-gear-wheel", amount=10},
      {type="item", name="electronic-circuit", amount=5},
      {type="item", name="pipe", amount=10},
    }},
    aai = { ingredients = {
      {type="item", name="steel-plate", amount=15},
      {type="item", name="iron-gear-wheel", amount=10},
      {type="item", name="electric-motor", amount=10},
      {type="item", name="pipe", amount=10},
    }},
  },
  {
    name = "basic-oil-processing",
    vanilla = {
      ingredients = {
        {type="fluid", name="crude-oil", amount=100, fluidbox_index=2},
      },
      results = {
        {type="fluid", name="petroleum-gas", amount=45, fluidbox_index=3},
      },
    },
    aai = { ingredients = {
      {type="fluid", name="water", amount=50},
      {type="fluid", name="crude-oil", amount=100},
    }},
  },
  {
    name = "advanced-oil-processing",
    vanilla = {
      results = {
        {type="fluid", name="heavy-oil", amount=25},
        {type="fluid", name="light-oil", amount=45},
        {type="fluid", name="petroleum-gas", amount=55},
      },
    },
    aai = { results = { -- ingredients identical in both; results are the fingerprint
      {type="fluid", name="heavy-oil", amount=20},
      {type="fluid", name="light-oil", amount=70},
      {type="fluid", name="petroleum-gas", amount=30},
    }},
  },

  -- ============================ science / research ============================
  {
    name = "lab",
    vanilla = { ingredients = {
      {type="item", name="iron-gear-wheel", amount=10},
      {type="item", name="electronic-circuit", amount=10},
      {type="item", name="transport-belt", amount=4},
    }},
  },
  {
    name = "logistic-science-pack",
    vanilla = {
      ingredients = {
        {type="item", name="transport-belt", amount=1},
        {type="item", name="inserter", amount=1},
      },
      results = {{type="item", name="logistic-science-pack", amount=1}},
      energy_required = 6,
      clear_categories = true, -- hand-craftable again
    },
    aai = { ingredients = {
      {type="item", name="transport-belt", amount=2},
      {type="item", name="inserter", amount=1},
    }},
  },
  {
    name = "utility-science-pack",
    vanilla = {
      ingredients = {
        {type="item", name="low-density-structure", amount=3},
        {type="item", name="processing-unit", amount=2},
        {type="item", name="flying-robot-frame", amount=1},
      },
      results = {{type="item", name="utility-science-pack", amount=3}},
      energy_required = 21,
      clear_categories = true,
    },
    aai = { ingredients = {
      {type="item", name="low-density-structure", amount=3},
      {type="item", name="processing-unit", amount=3},
      {type="item", name="flying-robot-frame", amount=1},
    }},
  },

  -- ============================ electric network ============================
  {
    name = "medium-electric-pole",
    vanilla = { ingredients = {
      {type="item", name="iron-stick", amount=4},
      {type="item", name="steel-plate", amount=2},
      {type="item", name="copper-plate", amount=2},
    }},
    aai = { ingredients = {
      {type="item", name="iron-stick", amount=4},
      {type="item", name="steel-plate", amount=2},
      {type="item", name="copper-cable", amount=4},
      {type="item", name="small-iron-electric-pole", amount=1},
    }},
  },
  {
    name = "big-electric-pole",
    vanilla = { ingredients = {
      {type="item", name="iron-stick", amount=8},
      {type="item", name="steel-plate", amount=5},
      {type="item", name="copper-plate", amount=5},
    }},
    aai = { ingredients = {
      {type="item", name="iron-stick", amount=8},
      {type="item", name="steel-plate", amount=5},
      {type="item", name="copper-cable", amount=10},
      {type="item", name="concrete", amount=1},
    }},
  },
  {
    name = "substation",
    vanilla = { ingredients = {
      {type="item", name="steel-plate", amount=10},
      {type="item", name="advanced-circuit", amount=5},
      {type="item", name="copper-plate", amount=5},
    }},
    aai = { ingredients = {
      {type="item", name="copper-cable", amount=20},
      {type="item", name="steel-plate", amount=10},
      {type="item", name="concrete", amount=5},
      {type="item", name="advanced-circuit", amount=5},
    }},
  },
  {
    name = "small-lamp",
    vanilla = { ingredients = {
      {type="item", name="copper-cable", amount=3},
      {type="item", name="iron-plate", amount=1},
      {type="item", name="electronic-circuit", amount=1},
    }},
  },
  {
    name = "roboport",
    vanilla = { ingredients = {
      {type="item", name="steel-plate", amount=45},
      {type="item", name="iron-gear-wheel", amount=45},
      {type="item", name="advanced-circuit", amount=45},
    }},
    aai = { ingredients = {
      {type="item", name="steel-plate", amount=50},
      {type="item", name="electric-motor", amount=50},
      {type="item", name="advanced-circuit", amount=50},
      {type="item", name="concrete", amount=50},
    }},
  },
  {
    name = "radar",
    vanilla = { ingredients = {
      {type="item", name="iron-plate", amount=10},
      {type="item", name="iron-gear-wheel", amount=5},
      {type="item", name="electronic-circuit", amount=5},
    }},
    aai = { ingredients = {
      {type="item", name="iron-plate", amount=20},
      {type="item", name="electronic-circuit", amount=8},
      {type="item", name="stone-brick", amount=4},
      {type="item", name="electric-motor", amount=4},
    }},
  },

  -- ============================ military ============================
  {
    name = "gun-turret",
    vanilla = { ingredients = {
      {type="item", name="iron-plate", amount=20},
      {type="item", name="copper-plate", amount=10},
      {type="item", name="iron-gear-wheel", amount=10},
    }},
    aai = { ingredients = {
      {type="item", name="iron-plate", amount=20},
      {type="item", name="iron-gear-wheel", amount=10},
      {type="item", name="motor", amount=5},
    }},
  },
  {
    name = "laser-turret",
    vanilla = { ingredients = {
      {type="item", name="steel-plate", amount=20},
      {type="item", name="electronic-circuit", amount=20},
      {type="item", name="battery", amount=12},
    }},
  },
  {
    name = "gate",
    vanilla = { ingredients = {
      {type="item", name="stone-wall", amount=1},
      {type="item", name="steel-plate", amount=2},
      {type="item", name="electronic-circuit", amount=2},
    }},
  },
  {
    name = "heavy-armor",
    vanilla = { ingredients = {
      {type="item", name="copper-plate", amount=100},
      {type="item", name="steel-plate", amount=50},
    }},
    aai = { contains = "light-armor" },
  },
  {
    name = "modular-armor",
    vanilla = { ingredients = {
      {type="item", name="advanced-circuit", amount=30},
      {type="item", name="steel-plate", amount=50},
    }},
    aai = { contains = "heavy-armor" },
  },
  {
    name = "power-armor",
    vanilla = { ingredients = {
      {type="item", name="processing-unit", amount=40},
      {type="item", name="electric-engine-unit", amount=20},
      {type="item", name="steel-plate", amount=40},
    }},
    aai = { contains = "modular-armor" },
  },
  {
    name = "power-armor-mk2",
    vanilla = { ingredients = {
      {type="item", name="efficiency-module-2", amount=25},
      {type="item", name="speed-module-2", amount=25},
      {type="item", name="processing-unit", amount=60},
      {type="item", name="electric-engine-unit", amount=40},
      {type="item", name="low-density-structure", amount=30},
    }},
    aai = { contains = "power-armor" },
  },
  {
    name = "personal-laser-defense-equipment",
    vanilla = { ingredients = {
      {type="item", name="processing-unit", amount=20},
      {type="item", name="low-density-structure", amount=5},
      {type="item", name="laser-turret", amount=5},
    }},
  },

  -- ============================ vehicles / misc ============================
  {
    name = "car",
    vanilla = { ingredients = {
      {type="item", name="iron-plate", amount=20},
      {type="item", name="iron-gear-wheel", amount=8},
      {type="item", name="engine-unit", amount=8},
    }},
    aai = { ingredients = {
      {type="item", name="iron-gear-wheel", amount=10},
      {type="item", name="steel-plate", amount=5},
      {type="item", name="engine-unit", amount=5},
    }},
  },
  {
    name = "locomotive",
    vanilla = { ingredients = {
      {type="item", name="engine-unit", amount=20},
      {type="item", name="electronic-circuit", amount=10},
      {type="item", name="steel-plate", amount=30},
    }},
    aai = { ingredients = {
      {type="item", name="steel-plate", amount=30},
      {type="item", name="engine-unit", amount=15},
      {type="item", name="iron-gear-wheel", amount=10},
      {type="item", name="electronic-circuit", amount=10},
    }},
  },
  {
    name = "flying-robot-frame",
    vanilla = { ingredients = {
      {type="item", name="electric-engine-unit", amount=1},
      {type="item", name="battery", amount=2},
      {type="item", name="steel-plate", amount=1},
      {type="item", name="electronic-circuit", amount=3},
    }},
    aai = { ingredients = {
      {type="item", name="electric-engine-unit", amount=4},
      {type="item", name="battery", amount=4},
      {type="item", name="electronic-circuit", amount=4},
      {type="item", name="steel-plate", amount=4},
    }},
  },
  {
    name = "centrifuge",
    vanilla = { ingredients = {
      {type="item", name="concrete", amount=100},
      {type="item", name="steel-plate", amount=50},
      {type="item", name="advanced-circuit", amount=100},
      {type="item", name="iron-gear-wheel", amount=100},
    }},
    -- AAI adds electric-motor 25 -> marker catches it.
  },
  {
    name = "satellite",
    vanilla = { ingredients = {
      {type="item", name="low-density-structure", amount=100},
      {type="item", name="solar-panel", amount=100},
      {type="item", name="accumulator", amount=100},
      {type="item", name="radar", amount=5},
      {type="item", name="processing-unit", amount=100},
      {type="item", name="rocket-fuel", amount=50},
    }},
    -- AAI adds glass 100 -> marker. (Recipe absent in Space Age; guarded.)
  },
}

-- Science packs AAI made assembler-only (removed hand-crafting) WITHOUT
-- touching their ingredients. logistic + utility are handled above because
-- AAI also changed their ingredients/time/output.
M.science_uncategory = {
  "automation-science-pack",
  "military-science-pack",
  "chemical-science-pack",
  "production-science-pack",
}

-- ============================================================================
-- Krastorio 2 restores
-- AAI's own K2-compat file (phase-3/compatibility/krastorio2.lua) rewrites
-- some of K2's recipes. Same principle as the vanilla restores: K2's design
-- is intentional, AAI's rewrite gets undone. Values below are K2's originals
-- (Krastorio2 2.1.2, prototypes/updates/base/recipes.lua).
-- `contains` = ingredient that only AAI's version has (the guard).
-- Only applied when Krastorio2 is active.
-- ============================================================================
-- Entries WITHOUT `contains` are applied unconditionally (idempotent - we are
-- the last mod to run). Values = K2's changes applied on top of vanilla,
-- i.e. the state of a K2 (no-AAI) game - the baseline this modpack had
-- before AAI was added.
M.k2_restores = {
  {
    -- AAI rewrites the Chemical tech card to glass 5 + engine-unit
    -- ("multi-cylinder engine") + adv-circuit 5 + blank card 5 + acid 50.
    -- K2's original has no engine and 15 kr-glass.
    name = "chemical-science-pack",
    contains = "engine-unit",
    k2 = {
      ingredients = {
        {type="item", name="kr-blank-tech-card", amount=5},
        {type="item", name="kr-glass", amount=15},
        {type="item", name="advanced-circuit", amount=5},
        {type="fluid", name="sulfuric-acid", amount=50},
      },
      results = {{type="item", name="chemical-science-pack", amount=5}},
      energy_required = 20,
      categories = {"crafting-with-fluid"},
    },
  },
  {
    -- K2 converts engine-unit steel -> iron (AAI converts it back; vanilla
    -- uses steel). K2 baseline = iron.
    name = "engine-unit",
    k2 = { ingredients = {
      {type="item", name="iron-plate", amount=1},
      {type="item", name="iron-gear-wheel", amount=1},
      {type="item", name="pipe", amount=2},
    }},
  },
  {
    name = "gun-turret", -- K2: iron->kr-iron-beam 5, copper->kr-automation-core 3, gear 4
    k2 = {
      ingredients = {
        {type="item", name="kr-iron-beam", amount=5},
        {type="item", name="kr-automation-core", amount=3},
        {type="item", name="iron-gear-wheel", amount=4},
      },
      energy_required = 10,
    },
  },
  {
    name = "assembling-machine-1", -- K2: iron-plate -> kr-iron-beam 4
    k2 = {
      ingredients = {
        {type="item", name="kr-iron-beam", amount=4},
        {type="item", name="iron-gear-wheel", amount=5},
        {type="item", name="electronic-circuit", amount=3},
      },
      energy_required = 1,
    },
  },
  {
    name = "steam-turbine", -- K2: gear 14, pipe 10, + steam-engine 2
    k2 = {
      ingredients = {
        {type="item", name="iron-gear-wheel", amount=14},
        {type="item", name="copper-plate", amount=50},
        {type="item", name="pipe", amount=10},
        {type="item", name="steam-engine", amount=2},
      },
      energy_required = 10,
    },
  },
  {
    -- K2 alone: + wood 1, iron 1, cable 4, output x2.
    -- K2 Spaced Out then REMOVES the wood and bumps iron to 2 (it ships its
    -- own separate kr-electronic-circuit-wood alternate instead).
    name = "electronic-circuit",
    k2 = mods["Krastorio2-spaced-out"] and {
      ingredients = {
        {type="item", name="iron-plate", amount=2},
        {type="item", name="copper-cable", amount=4},
      },
      results = {{type="item", name="electronic-circuit", amount=2}},
      energy_required = 2,
    } or {
      ingredients = {
        {type="item", name="iron-plate", amount=1},
        {type="item", name="copper-cable", amount=4},
        {type="item", name="wood", amount=1},
      },
      results = {{type="item", name="electronic-circuit", amount=2}},
      energy_required = 2,
    },
  },
  {
    name = "solar-panel", -- K2: vanilla + kr-silicon 5
    k2 = { ingredients = {
      {type="item", name="steel-plate", amount=5},
      {type="item", name="electronic-circuit", amount=15},
      {type="item", name="copper-plate", amount=5},
      {type="item", name="kr-silicon", amount=5},
    }},
  },
  {
    name = "heavy-armor", -- K2: copper removed, + light-armor 1
    k2 = { ingredients = {
      {type="item", name="steel-plate", amount=50},
      {type="item", name="light-armor", amount=1},
    }},
  },
  {
    name = "roboport", -- K2: steel -> kr-steel-beam 20
    k2 = { ingredients = {
      {type="item", name="kr-steel-beam", amount=20},
      {type="item", name="iron-gear-wheel", amount=45},
      {type="item", name="advanced-circuit", amount=45},
    }},
  },
  {
    name = "laser-turret", -- K2: steel 15, + kr-quartz 5
    k2 = {
      ingredients = {
        {type="item", name="steel-plate", amount=15},
        {type="item", name="electronic-circuit", amount=20},
        {type="item", name="battery", amount=12},
        {type="item", name="kr-quartz", amount=5},
      },
      energy_required = 30,
    },
  },
  {
    name = "lab", -- K2: transport-belt -> copper-cable 10
    k2 = { ingredients = {
      {type="item", name="iron-gear-wheel", amount=10},
      {type="item", name="electronic-circuit", amount=10},
      {type="item", name="copper-cable", amount=10},
    }},
  },
}

return M
