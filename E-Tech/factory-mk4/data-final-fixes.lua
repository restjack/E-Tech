-- factory-mk4/data-final-fixes.lua
-- Re-derives the Mk4's research cost from the Mk3's, and drops any recipe
-- ingredient that no longer exists, AFTER every other mod has had its say.
--
-- WHY THIS RUNS LATE. factory-mk4/data.lua builds the Mk4 in the data stage,
-- where it can only see Factorissimo's own numbers. Overhauls rewrite the
-- factory technologies later: Factorissimo's compat/pyanodon.lua rewrites
-- factory-architecture-t2's unit in data-updates, Krastorio 2 and Space Age
-- reshape the science mix, and any of them can retire an item the Mk4 recipe
-- asks for. Deriving here means the Mk4 inherits whatever those mods settled
-- on rather than a snapshot taken before they ran.
--
-- Nothing here is Py- or K2-specific on purpose - a hardcoded compat file for
-- each overhaul would go stale; reading the tier below never does.

local TECH = "etech-factory-architecture-t4"
local BASE_TECH = "factory-architecture-t3"

local tech = data.raw.technology[TECH]
if not tech then return end

-- Research cost: the tier below, doubled.
local base_tech = data.raw.technology[BASE_TECH]
if base_tech and base_tech.unit then
  local unit = table.deepcopy(base_tech.unit)
  unit.count = (unit.count or 2000) * 2
  unit.time = 90

  -- Push it one science tier up where that pack exists. The ingredient list is
  -- either the {name, amount} array form or the {name=, amount=} table form
  -- depending on who last touched it, so match whatever is already there.
  if data.raw.tool["utility-science-pack"] and unit.ingredients then
    local present = false
    for _, ingredient in pairs(unit.ingredients) do
      if (ingredient[1] or ingredient.name) == "utility-science-pack" then present = true end
    end
    if not present then
      local sample = unit.ingredients[1]
      if sample and sample.name then
        unit.ingredients[#unit.ingredients + 1] = {name = "utility-science-pack", amount = 1}
      else
        unit.ingredients[#unit.ingredients + 1] = {"utility-science-pack", 1}
      end
    end
  end

  tech.unit = unit
end

-- Prerequisites may name technologies an overhaul removed.
local prerequisites = {}
for _, name in ipairs(tech.prerequisites or {}) do
  if data.raw.technology[name] then
    prerequisites[#prerequisites + 1] = name
  else
    log("E-Tech: Mk4 prerequisite " .. name .. " no longer exists - dropped.")
  end
end
tech.prerequisites = prerequisites

-- Recipe ingredients: drop anything retired, so the Mk4 stays craftable rather
-- than becoming a load error under an overhaul that removed, say, refined
-- concrete or processing units.
for _, recipe_name in ipairs({"factory-4", "space-factory-4"}) do
  local recipe = data.raw.recipe[recipe_name]
  if recipe and recipe.ingredients then
    local kept = {}
    for _, ingredient in ipairs(recipe.ingredients) do
      local name = ingredient.name or ingredient[1]
      if data.raw.item[name] or data.raw.fluid[name] then
        kept[#kept + 1] = ingredient
      else
        log("E-Tech: " .. recipe_name .. " ingredient " .. tostring(name) .. " no longer exists - dropped.")
      end
    end
    recipe.ingredients = kept
  end
end
