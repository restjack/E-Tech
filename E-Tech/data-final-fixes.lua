-- data-final-fixes.lua
-- Runs in the last data stage, after AAI Industry (and after Krastorio 2,
-- which we list as an optional dependency so we see the final recipe state).
-- We never edit other mods' files; we only reassign fields on data.raw.
--
-- Behaviour: unconditionally restore vanilla values on every recipe AAI
-- changed, but ONLY if the recipe still looks AAI-authored (fingerprint
-- guard). If another mod rewrote a recipe into something that is neither
-- vanilla nor AAI's version, we leave it alone and log it.

local vr = require("vanilla-recipes")

local function elog(msg) log("[E-Tech] " .. msg) end

-- Per-recipe decision lines are debug-only (etech-debug-log startup toggle) -
-- on a big modpack they were ~50 log lines every load. Summaries and
-- warnings still use elog unconditionally.
local debug_log = settings.startup["etech-debug-log"].value
local function dlog(msg) if debug_log then elog(msg) end end

-- ---------------------------------------------------------------------------
-- 1. Vanilla recipe restore (only when AAI Industry is active)
-- ---------------------------------------------------------------------------
if mods["aai-industry"] then

  -- Items that only ever appear in a recipe because of AAI. Presence of one
  -- of these in a recipe's ingredients marks it AAI-authored.
  local MARKERS = {
    ["motor"] = true,
    ["electric-motor"] = true,
    ["stone-tablet"] = true,
    ["small-iron-electric-pole"] = true,
    ["burner-assembling-machine"] = true,
    ["burner-lab"] = true,
  }
  -- AAI publishes the resolved glass/sand item names as data-stage globals.
  if aai_glass_name then MARKERS[aai_glass_name] = true else MARKERS["glass"] = true end
  if aai_sand_name  then MARKERS[aai_sand_name]  = true else MARKERS["sand"]  = true end

  -- Order-independent (type,name,amount[,temperature]) key for an
  -- ingredient/result list. Fluid temperature bounds are part of the key so
  -- two recipes that differ only in fluid temperature (e.g. a mod tightening
  -- an acid's range) don't false-match.
  local function list_key(list)
    local parts = {}
    for _, e in pairs(list or {}) do
      local key = (e.type or "item") .. ":" .. e.name .. ":" .. tostring(e.amount)
      if e.temperature then key = key .. ":t" .. tostring(e.temperature) end
      if e.minimum_temperature then key = key .. ":tmin" .. tostring(e.minimum_temperature) end
      if e.maximum_temperature then key = key .. ":tmax" .. tostring(e.maximum_temperature) end
      parts[#parts + 1] = key
    end
    table.sort(parts)
    return table.concat(parts, "|")
  end

  local function contains_name(list, name)
    for _, e in pairs(list or {}) do
      if e.name == name then return true end
    end
    return false
  end

  local function contains_marker(list)
    for _, e in pairs(list or {}) do
      if MARKERS[e.name] then return true end
    end
    return false
  end

  -- NOTE: entries in vanilla-recipes.lua without an `aai` fingerprint are
  -- still covered - every AAI version of those recipes (chemical-plant,
  -- oil-refinery, lab, small-lamp, gate, laser-turret, personal-laser-
  -- defense...) contains a marker item (glass/electric-motor/motor), so
  -- contains_marker matches them. Verified against AAI-CHANGE-INVENTORY.md.
  local function looks_aai(recipe, entry)
    if contains_marker(recipe.ingredients) then return true end
    local aai = entry.aai
    if not aai then return false end
    if aai.contains then
      return contains_name(recipe.ingredients, aai.contains)
    end
    if aai.ingredients and list_key(recipe.ingredients) ~= list_key(aai.ingredients) then
      return false
    end
    if aai.results and list_key(recipe.results) ~= list_key(aai.results) then
      return false
    end
    return (aai.ingredients or aai.results) and true or false
  end

  local reverted, skipped, absent = 0, 0, 0
  for _, entry in ipairs(vr.entries) do
    local recipe = data.raw.recipe[entry.name]
    if not recipe then
      absent = absent + 1
    elseif looks_aai(recipe, entry) then
      local v = entry.vanilla
      if v.ingredients then recipe.ingredients = table.deepcopy(v.ingredients) end
      if v.results then recipe.results = table.deepcopy(v.results) end
      if v.energy_required then recipe.energy_required = v.energy_required end
      -- Factorio 2.1: recipes use a `categories` array only (`category` is
      -- illegal). nil = default {"crafting"} = hand-craftable.
      if v.clear_categories then
        recipe.categories = nil
        recipe.category = nil
      elseif v.categories then
        recipe.categories = table.deepcopy(v.categories)
        recipe.category = nil
      end
      reverted = reverted + 1
      dlog("restored vanilla recipe: " .. entry.name)
    else
      skipped = skipped + 1
      dlog("SKIPPED " .. entry.name .. " (doesn't match AAI's version - another mod owns it now)")
    end
  end

  -- Science packs AAI made assembler-only (category change only). Restore
  -- hand-crafting by removing AAI's `categories` field. Guarded: only if the
  -- field carries AAI's signature values.
  local function has_value(list, value)
    for _, x in pairs(list or {}) do
      if x == value then return true end
    end
    return false
  end
  for _, name in ipairs(vr.science_uncategory) do
    local recipe = data.raw.recipe[name]
    if recipe and recipe.categories
       and (has_value(recipe.categories, "advanced-crafting")
            or has_value(recipe.categories, "burner-crafting")) then
      recipe.categories = nil
      recipe.category = nil -- default "crafting" = hand-craftable
      reverted = reverted + 1
      dlog("restored hand-crafting: " .. name)
    end
  end

  -- K2 recipes that AAI's own Krastorio2-compat file rewrote: restore K2's
  -- originals. Guard = presence of an ingredient only AAI's version has.
  if mods["Krastorio2"] then
    for _, entry in ipairs(vr.k2_restores) do
      local recipe = data.raw.recipe[entry.name]
      if recipe and (entry.contains == nil or contains_name(recipe.ingredients, entry.contains)) then
        local k = entry.k2
        -- Idempotency guard (0.19.0): if the recipe already matches the K2
        -- target, nothing to do (and no misleading "restored" log). A
        -- non-matching recipe is the NORMAL case here (it holds AAI's or
        -- the vanilla pass's version), so no third-mod warning is possible
        -- without per-entry AAI fingerprints - entries with `contains` are
        -- guarded, the rest apply as before.
        local already = (not k.ingredients or list_key(recipe.ingredients) == list_key(k.ingredients))
                    and (not k.results or list_key(recipe.results) == list_key(k.results))
        if already then
          dlog("K2 recipe already correct: " .. entry.name)
        else
          if k.ingredients then recipe.ingredients = table.deepcopy(k.ingredients) end
          if k.results then recipe.results = table.deepcopy(k.results) end
          if k.energy_required then recipe.energy_required = k.energy_required end
          if k.categories then
            recipe.categories = table.deepcopy(k.categories)
            recipe.category = nil
          end
          reverted = reverted + 1
          dlog("restored K2 recipe: " .. entry.name)
        end
      end
    end
  end

  -- Retire AAI's motor ("Single-cylinder engine") under K2. Its icon is a
  -- vanilla-engine-unit lookalike, so players see two near-identical
  -- "engines" (assembler recipe pickers ignored 0.16's
  -- hide_from_player_crafting). With K2's baseline restored nothing
  -- essential needs it: AAI's own K2 compat already swapped it out of the
  -- burner assembler, leaving only burner-lab, the optional fuel-processor
  -- and third-party recipes (Mining Drones). Iron gears are a fair 1:1
  -- stand-in at that tech level, so: swap motor -> gears in every recipe
  -- that still uses it, repoint any craft-motor research trigger (AAI's
  -- basic-logistics), then hide the item and recipe. Without K2 the motor
  -- stays - the first burner assembler needs a hand-made one.
  if mods["Krastorio2"] and data.raw.item["motor"] and data.raw.recipe["motor"] then
    -- Only swap CONSTRUCTION recipes (motor is one ingredient among
    -- several, and not a result). Recipes ABOUT the motor itself -
    -- recycling, crushing, incineration, quality augmenting - keep it, so
    -- leftover motors in existing saves can still be disposed of, and no
    -- bogus "crush iron gears" recipes appear.
    local function swap_motor_for_gears(recipe)
      local ings = recipe.ingredients
      if not ings then return false end
      for _, res in pairs(recipe.results or {}) do
        if res.name == "motor" then return false end
      end
      local motor_index, other, gear
      for i, ing in pairs(ings) do
        if ing.name == "motor" then motor_index = i else other = true end
        if ing.name == "iron-gear-wheel" then gear = ing end
      end
      if not (motor_index and other) then return false end
      if gear then
        gear.amount = gear.amount + ings[motor_index].amount
        table.remove(ings, motor_index)
      else
        ings[motor_index] = {type = "item", name = "iron-gear-wheel",
                             amount = ings[motor_index].amount}
      end
      return true
    end
    for name, recipe in pairs(data.raw.recipe) do
      if swap_motor_for_gears(recipe) then
        dlog("motor retired: swapped motor -> iron-gear-wheel in recipe " .. name)
      end
    end
    for name, tech in pairs(data.raw.technology) do
      local trigger = tech.research_trigger
      if trigger and trigger.type == "craft-item" and trigger.item == "motor" then
        trigger.item = "iron-gear-wheel"
        dlog("motor retired: research trigger of " .. name .. " now counts iron gear wheels")
      end
    end
    data.raw.recipe["motor"].hidden = true
    data.raw.recipe["motor"].hide_from_player_crafting = nil
    data.raw.item["motor"].hidden = true
    elog("motor retired: item and recipe hidden")
  end

  -- AAI's "Electronic circuit (Wood)" alternate is redundant with K2:
  -- K2 alone puts wood in the main circuit recipe, and K2 Spaced Out ships
  -- its own kr-electronic-circuit-wood alternate.
  if mods["Krastorio2"] and data.raw.recipe["electronic-circuit-wood"] then
    data.raw.recipe["electronic-circuit-wood"].hidden = true
    elog("hid AAI's electronic-circuit-wood alternate recipe")
  end

  -- Cosmetic restore (toggleable since 0.19.0): AAI renames/reskins vanilla
  -- engine-unit as "Multi-cylinder engine" and electric-engine-unit as a big
  -- motor. Names are restored by pointing localised_name at this mod's own
  -- [etech-name] locale keys (a plain locale override can't be gated by a
  -- setting), icons by reassigning the vanilla files.
  if settings.startup["etech-restore-engine-cosmetics"].value then
    for _, name in ipairs({"engine-unit", "electric-engine-unit"}) do
      local item = data.raw.item[name]
      if item then
        item.icon = "__base__/graphics/icons/" .. name .. ".png"
        item.icon_size = 64
        item.localised_name = {"etech-name." .. name}
        dlog("restored vanilla " .. name .. " icon and name")
      end
      local recipe = data.raw.recipe[name]
      if recipe then
        recipe.localised_name = {"etech-name." .. name}
      end
    end
  end

  elog(string.format("vanilla restore done: %d reverted, %d skipped, %d absent", reverted, skipped, absent))
else
  elog("aai-industry not active - no recipe changes made")
end

-- ---------------------------------------------------------------------------
-- 2. Crashed-ship pickup (optional, base freeplay tweak)
-- ---------------------------------------------------------------------------
if settings.startup["etech-pickup-crashed-ship"].value then
  require("crash-ship")
end

-- ---------------------------------------------------------------------------
-- 3. Allow all modules (incl. productivity + quality) in every beacon
-- ---------------------------------------------------------------------------
if settings.startup["etech-beacon-all-modules"].value then
  require("beacons")
end

-- ---------------------------------------------------------------------------
-- 4. Misc optional tweaks (asteroid quality, stack sizes, spoilage)
-- ---------------------------------------------------------------------------
require("misc-tweaks")

-- ---------------------------------------------------------------------------
-- 5. Uranium bacteria on Gleba (port of simple-gleba-uranium, needs Space Age)
-- ---------------------------------------------------------------------------
if settings.startup["etech-gleba-uranium"].value then
  if mods["space-age"] then
    require("gleba-uranium")
  else
    elog("gleba uranium setting on but Space Age not active - skipped")
  end
end

-- ---------------------------------------------------------------------------
-- 6. Total productivity (port of Total Productivity by AivanF, LGPLv3)
-- ---------------------------------------------------------------------------
if settings.startup["etech-total-productivity"].value then
  if mods["Productivity"] then
    elog("total productivity setting on but the original Productivity mod is installed - skipped (disable one of the two)")
  else
    require("productivity/data")
  end
end
