-- productivity/data.lua
-- Allow productivity modules on (nearly) everything: belts, inserters,
-- rails, pipes, solar, walls, ammo, equipment, and so on. A recipe
-- qualifies when its single result is an item in one of the enabled
-- categories.
--
-- Adapted from "Total Productivity" 2.0.x by AivanF (LGPLv3 — see
-- LICENSE-third-party.txt; source: github.com/AivanF/factorio-AivanF-mods).
-- Changes from the original: the 28 per-category startup settings are
-- condensed into 4 group toggles (logistics / buildings / military / misc),
-- data.raw category lookups are nil-safe (a type table only exists when
-- some mod defines a prototype of that type), and the per-recipe pcall +
-- error wrapper is dropped in favor of the nil-safe lookups.
-- Only loaded when the etech-total-productivity setting is on AND the
-- original Productivity mod is absent (guard in data-final-fixes.lua).

local have_SA = mods["space-age"]

local logistics = settings.startup["etech-prod-logistics"].value
local buildings = settings.startup["etech-prod-buildings"].value
local military = settings.startup["etech-prod-military"].value
local misc = settings.startup["etech-prod-misc"].value

-- data.raw[type_name] is nil when no prototype of that type exists
local function in_raw(type_name, item_name)
  local group = data.raw[type_name]
  return group and group[item_name] ~= nil
end

local function item_has_field(item_name, field_name)
  local item = data.raw.item[item_name]
  return item and item[field_name] ~= nil
end

-- entity/tile/equipment types per group toggle
local logistics_types =
{
  "transport-belt", "underground-belt", "splitter", "loader", "loader-1x1",
  "inserter", "container", "logistic-container",
  "logistic-robot", "construction-robot",
  "rail-planner", "rail-ramp", "rail-support",
  "train-stop", "rail-signal", "rail-chain-signal",
  "locomotive", "artillery-wagon", "cargo-wagon", "fluid-wagon",
  "car", "spider-vehicle",
  "pipe", "pipe-to-ground", "pump", "offshore-pump", "storage-tank",
  "electric-pole", "lightning-attractor",
  "tile",
}

local buildings_types =
{
  "mining-drill", "assembling-machine", "furnace", "rocket-silo", "lab",
  "agricultural-tower", "roboport",
  "solar-panel", "accumulator",
  "reactor", "heat-pipe", "boiler", "generator", "burner-generator",
  "fusion-reactor", "fusion-generator",
  "radar", "wall", "gate",
  "cargo-landing-pad", "cargo-bay", "space-platform-starter-pack",
  "thruster", "asteroid-collector",
}

local military_types =
{
  "gun", "ammo", "land-mine", "capsule", "armor",
}

local misc_types =
{
  "module", "beacon", "repair-tool",
}

local function in_any(types, item_name)
  for _, type_name in pairs (types) do
    if in_raw(type_name, item_name) then return true end
  end
  return false
end

local function should_enable_prod(item_name)
  if type(item_name) ~= "string" then return false end
  if item_name:find("fish", 1, true) then return false end

  local placable = item_has_field(item_name, "place_result")
  local launchable = item_has_field(item_name, "rocket_launch_product") or item_has_field(item_name, "rocket_launch_products")

  if logistics and in_any(logistics_types, item_name) then return true end
  if logistics and item_name:find("combinator", 1, true) and placable then return true end

  if buildings and in_any(buildings_types, item_name) then return true end

  if military and in_any(military_types, item_name) then return true end
  if military and item_name:find("turret", 1, true) and placable then return true end
  if military and item_has_field(item_name, "place_as_equipment_result") then return true end

  if misc and in_any(misc_types, item_name) then return true end
  if misc and item_name:find("satellite", 1, true) and launchable then return true end
  if misc and item_name:find("-probe", 1, true) and launchable then return true end

  return false
end

local enabled = 0
for recipe_name, recipe in pairs (data.raw.recipe) do
  if not recipe.allow_productivity then
    local item_name = recipe.results and #recipe.results == 1 and recipe.results[1].name
    if item_name and should_enable_prod(item_name) then
      recipe.allow_productivity = true
      enabled = enabled + 1
    end
  end
end
log("[E-Tech] total productivity: allowed productivity modules on " .. enabled .. " recipes")
