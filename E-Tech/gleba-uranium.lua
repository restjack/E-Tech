-- gleba-uranium.lua
-- Uranium bacteria on Gleba, ported from the abandoned "Simple Gleba Uranium"
-- 1.0.2 by cindersash (MIT - see LICENSE-third-party.txt). Mirrors Space Age's
-- iron/copper bacteria pattern: jelly has a 1% chance to yield uranium
-- bacteria (jellynut tech), bacteria + bioflux multiplies it in a biochamber
-- (bacteria cultivation tech), and the bacteria spoils into uranium ore.
--
-- Prototype names keep the original sgu_ prefix so saves that used the old
-- mod keep their items when switching to E-Tech. If the original mod is
-- somehow still installed, it owns the prototypes and we do nothing.
-- Caller (data-final-fixes) guarantees space-age is active.

local function elog(msg) log("[E-Tech] " .. msg) end

if data.raw.item["sgu_uranium-bacteria"] then
  elog("gleba uranium skipped: simple-gleba-uranium prototypes already present")
  return
end

local space_age_item_sounds = require("__space-age__.prototypes.item_sounds")

local GLEBA_ONLY = {
  {property = "pressure", min = 2000, max = 2000},
}
local TINT = {
  primary = {r = 60, g = 171, b = 56},
  secondary = {r = 195, g = 245, b = 193},
}

data:extend({
  {
    type = "item",
    name = "sgu_uranium-bacteria",
    icon = "__E-Tech__/graphics/icons/uranium-bacteria.png",
    pictures =
    {
      { size = 64, filename = "__E-Tech__/graphics/icons/uranium-bacteria.png", scale = 0.5, mipmap_count = 4 },
      { size = 64, filename = "__E-Tech__/graphics/icons/uranium-bacteria-2.png", scale = 0.5, mipmap_count = 4 },
    },
    subgroup = "agriculture-processes",
    order = "b[agriculture]-d[copper-bacteria]",
    inventory_move_sound = space_age_item_sounds.agriculture_inventory_move,
    pick_sound = space_age_item_sounds.agriculture_inventory_pickup,
    drop_sound = space_age_item_sounds.agriculture_inventory_move,
    stack_size = 50,
    default_import_location = "gleba",
    weight = 1 * kg,
    spoil_ticks = 1 * minute,
    spoil_result = "uranium-ore",
  },
  {
    type = "recipe",
    name = "sgu_uranium-bacteria",
    icon = "__E-Tech__/graphics/icons/uranium-bacteria.png",
    categories = {"organic", "crafting"},
    surface_conditions = GLEBA_ONLY,
    subgroup = "agriculture-processes",
    order = "e[bacteria]-a[bacteria]-b[uranium]",
    enabled = false,
    allow_productivity = true,
    energy_required = 1,
    ingredients =
    {
      {type = "item", name = "jelly", amount = 3},
    },
    results =
    {
      {type = "item", name = "sgu_uranium-bacteria", amount = 1, independent_probability = 0.01},
      {type = "item", name = "spoilage", amount = 1},
    },
    main_product = "sgu_uranium-bacteria",
    crafting_machine_tint = TINT,
  },
  {
    type = "recipe",
    name = "sgu_uranium-bacteria-cultivation",
    icon = "__E-Tech__/graphics/icons/uranium-bacteria-cultivation.png",
    categories = {"organic"},
    auto_recycle = false,
    surface_conditions = GLEBA_ONLY,
    subgroup = "agriculture-processes",
    order = "e[bacteria]-b[cultivation]-b[uranium]",
    enabled = false,
    allow_productivity = true,
    energy_required = 4,
    ingredients =
    {
      {type = "item", name = "sgu_uranium-bacteria", amount = 1},
      {type = "item", name = "bioflux", amount = 1},
    },
    results =
    {
      {type = "item", name = "sgu_uranium-bacteria", amount = 4, reset_freshness_on_craft = true},
    },
    crafting_machine_tint = TINT,
  },
})

-- Tech unlocks, same gates as the original mod: the seeding recipe on
-- jellynut, the multiplication recipe on bacteria cultivation.
local function add_unlock(tech_name, recipe_name)
  local tech = data.raw.technology[tech_name]
  if not tech then
    elog("gleba uranium: tech " .. tech_name .. " missing, " .. recipe_name .. " has no unlock")
    return
  end
  tech.effects = tech.effects or {}
  tech.effects[#tech.effects + 1] = {type = "unlock-recipe", recipe = recipe_name}
end
add_unlock("jellynut", "sgu_uranium-bacteria")
add_unlock("bacteria-cultivation", "sgu_uranium-bacteria-cultivation")

elog("gleba uranium bacteria added (port of simple-gleba-uranium)")
