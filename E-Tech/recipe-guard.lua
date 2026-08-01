-- recipe-guard.lua
-- Late safety net for every recipe and technology E-Tech adds.
--
-- WHY THIS EXISTS. E-Tech's own content is defined in the data stage, where it
-- can only see what base and the mods loaded before it provide. Overhauls
-- rewrite the world afterwards: Krastorio 2, Space Age, Space Exploration,
-- pY and friends all retire items and technologies in data-updates or
-- data-final-fixes. A recipe naming an item that no longer exists is not a
-- warning - it is a HARD LOAD ERROR, and the player sees E-Tech's name on a
-- crash caused by a mod combination E-Tech never claimed to know about.
--
-- factory-mk4 already solved this for itself (factory-mk4/data-final-fixes.lua).
-- Until 0.21.1 the factory hub, the teleporter pads and the void chest did not,
-- and simply hardcoded processing-unit / advanced-circuit / battery /
-- constant-combinator / stone-furnace and hardcoded tech prerequisites. This
-- file generalises the Mk4 approach to all of them.
--
-- WHAT IT DOES, in data-final-fixes, after every other mod has had its say:
--   * ingredients   - a missing item is SUBSTITUTED down a documented fallback
--                     chain (processing unit -> advanced circuit -> electronic
--                     circuit). Substituting beats dropping: dropping silently
--                     makes the recipe cheaper, and a player reading the recipe
--                     has no way to tell that happened. Only when the whole
--                     chain is gone is the ingredient dropped, loudly.
--   * results       - never touched. A result item that vanished means the
--                     feature itself is gone, which is not this file's problem.
--   * tech unit     - science packs that no longer exist are dropped from the
--                     research cost; a tech with no ingredients left falls back
--                     to a plain count-based unit rather than failing to load.
--   * prerequisites - dropped if the technology is gone.
--   * unlock effects- dropped if the recipe is gone.
--
-- Everything it changes is logged unconditionally. A silent degradation here
-- would be worse than the crash it replaces.

local M = {}

local function elog(msg) log("[E-Tech] recipe-guard: " .. msg) end

-- Every prototype type that is an "item" for recipe purposes. data.raw.item
-- alone is not enough - science packs are `tool`, ammo is `ammo`, modules are
-- `module`, and a recipe may legitimately consume any of them.
local ITEM_TYPES = {
  "item", "ammo", "armor", "blueprint", "blueprint-book", "capsule",
  "copy-paste-tool", "deconstruction-item", "gun", "item-with-entity-data",
  "item-with-inventory", "item-with-label", "item-with-tags", "module",
  "rail-planner", "repair-tool", "selection-tool",
  "space-platform-starter-pack", "spidertron-remote", "tool", "upgrade-item",
}

local item_set
local function items()
  if item_set then return item_set end
  item_set = {}
  for _, type_name in ipairs(ITEM_TYPES) do
    for name in pairs(data.raw[type_name] or {}) do
      item_set[name] = true
    end
  end
  return item_set
end

local function item_exists(name)
  return items()[name] == true
end

local function ingredient_exists(ingredient)
  local name = ingredient.name or ingredient[1]
  if not name then return true end -- malformed; leave it for the engine to report
  if ingredient.type == "fluid" then
    return data.raw.fluid[name] ~= nil
  end
  return item_exists(name) or data.raw.fluid[name] ~= nil
end

-- Ordered degradation chains. Each entry lists what to try, in order, when the
-- key item is missing. Kept deliberately short and boring: the goal is a recipe
-- that still loads and still costs roughly the right amount of effort, not a
-- clever guess at what the overhaul intended.
local FALLBACKS = {
  ["processing-unit"]        = {"advanced-circuit", "electronic-circuit"},
  ["advanced-circuit"]       = {"electronic-circuit"},
  ["battery"]                = {"advanced-circuit", "electronic-circuit"},
  ["steel-plate"]            = {"iron-plate"},
  ["stone-furnace"]          = {"stone-brick", "stone", "iron-plate"},
  ["iron-chest"]             = {"steel-chest", "wooden-chest"},
  ["passive-provider-chest"] = {"storage-chest", "steel-chest", "iron-chest"},
  ["requester-chest"]        = {"storage-chest", "steel-chest", "iron-chest"},
  ["storage-tank"]           = {"pipe", "iron-plate"},
  ["constant-combinator"]    = {"electronic-circuit"},
  ["pipe"]                   = {"iron-plate"},
  ["electronic-circuit"]     = {"copper-cable", "iron-plate"},
}

local function substitute_for(name)
  for _, candidate in ipairs(FALLBACKS[name] or {}) do
    if item_exists(candidate) then return candidate end
  end
  return nil
end

-- Rewrite one recipe's ingredient list in place. Returns nothing; logs every
-- substitution and every drop.
function M.scrub_recipe(recipe_name)
  local recipe = data.raw.recipe[recipe_name]
  if not (recipe and recipe.ingredients) then return end

  local kept = {}
  for _, ingredient in ipairs(recipe.ingredients) do
    if ingredient_exists(ingredient) then
      kept[#kept + 1] = ingredient
    else
      local name = ingredient.name or ingredient[1]
      local replacement = substitute_for(name)
      if replacement then
        if ingredient.name then
          ingredient.name = replacement
        else
          ingredient[1] = replacement
        end
        kept[#kept + 1] = ingredient
        elog(recipe_name .. ": ingredient " .. tostring(name)
          .. " no longer exists - substituted " .. replacement)
      else
        elog(recipe_name .. ": ingredient " .. tostring(name)
          .. " no longer exists and has no available substitute - DROPPED"
          .. " (this recipe is now cheaper than intended)")
      end
    end
  end
  recipe.ingredients = kept

  if #kept == 0 then
    elog(recipe_name .. ": every ingredient is gone - the recipe is now free."
      .. " Something is very wrong with this mod combination.")
  end
end

-- Drop missing prerequisites, missing unlock targets, and missing science
-- packs from a technology.
function M.scrub_technology(tech_name)
  local tech = data.raw.technology[tech_name]
  if not tech then return end

  if tech.prerequisites then
    local kept = {}
    for _, name in ipairs(tech.prerequisites) do
      if data.raw.technology[name] then
        kept[#kept + 1] = name
      else
        elog(tech_name .. ": prerequisite " .. name .. " no longer exists - dropped")
      end
    end
    tech.prerequisites = kept
  end

  if tech.effects then
    local kept = {}
    for _, effect in ipairs(tech.effects) do
      if effect.type == "unlock-recipe" and not data.raw.recipe[effect.recipe] then
        elog(tech_name .. ": unlock target " .. tostring(effect.recipe)
          .. " no longer exists - effect dropped")
      else
        kept[#kept + 1] = effect
      end
    end
    tech.effects = kept
  end

  local unit = tech.unit
  if unit and unit.ingredients then
    local kept = {}
    for _, ingredient in ipairs(unit.ingredients) do
      local name = ingredient.name or ingredient[1]
      if name and item_exists(name) then
        kept[#kept + 1] = ingredient
      else
        elog(tech_name .. ": science pack " .. tostring(name)
          .. " no longer exists - dropped from the research cost")
      end
    end
    if #kept == 0 then
      -- A unit with an empty ingredient list will not load. Anything that gets
      -- here has had its entire science mix retired, so fall back to whatever
      -- the game's first available science pack is.
      local fallback = item_exists("automation-science-pack") and "automation-science-pack"
      if fallback then
        kept[1] = {fallback, 1}
        elog(tech_name .. ": research cost had no packs left - reset to 1 x " .. fallback)
      else
        tech.unit = nil
        tech.research_trigger = tech.research_trigger or {type = "craft-item", item = "iron-plate"}
        elog(tech_name .. ": no science packs exist at all - converted to a craft trigger")
        return
      end
    end
    unit.ingredients = kept
  end
end

-- Everything E-Tech adds that names a foreign item or technology. Recipes and
-- technologies that do not exist (their feature is switched off) are skipped
-- silently by the two functions above, so this list can be unconditional.
-- lint-locale: ignore (prototype names, not localised strings)
local RECIPES = {
  -- factory hub (factory-hub/data.lua)
  "etech-factory-provider-hub",
  "etech-factory-inlet",
  "etech-factory-sensor",
  "etech-factory-fluid-outlet",
  "etech-factory-fluid-inlet",
  -- teleporter pads (teleporters/data.lua)
  "etech-teleporter",
  -- void chest / pipe (voidchest/data.lua)
  "void-pipe",
  "void-chest",
  "void-chest-filtered",
  -- factory Mk4 (factory-mk4/data.lua). Its own data-final-fixes already
  -- drops retired ingredients; running them through here too is harmless and
  -- gives them the substitution chains as well.
  "factory-4",
  "space-factory-4",
}

-- lint-locale: ignore (prototype names, not localised strings)
local TECHNOLOGIES = {
  "etech-factory-provider-hub",
  "etech-teleporter",
  "void",
  "etech-factory-architecture-t4",
}

function M.run()
  for _, name in ipairs(RECIPES) do M.scrub_recipe(name) end
  for _, name in ipairs(TECHNOLOGIES) do M.scrub_technology(name) end
end

return M
