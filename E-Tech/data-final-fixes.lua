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

  -- Order-independent (type,name,amount) key for an ingredient/result list.
  local function list_key(list)
    local parts = {}
    for _, e in pairs(list or {}) do
      parts[#parts + 1] = (e.type or "item") .. ":" .. e.name .. ":" .. tostring(e.amount)
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
      elog("restored vanilla recipe: " .. entry.name)
    else
      skipped = skipped + 1
      elog("SKIPPED " .. entry.name .. " (doesn't match AAI's version - another mod owns it now)")
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
      elog("restored hand-crafting: " .. name)
    end
  end

  -- K2 recipes that AAI's own Krastorio2-compat file rewrote: restore K2's
  -- originals. Guard = presence of an ingredient only AAI's version has.
  if mods["Krastorio2"] then
    for _, entry in ipairs(vr.k2_restores) do
      local recipe = data.raw.recipe[entry.name]
      if recipe and (entry.contains == nil or contains_name(recipe.ingredients, entry.contains)) then
        local k = entry.k2
        if k.ingredients then recipe.ingredients = table.deepcopy(k.ingredients) end
        if k.results then recipe.results = table.deepcopy(k.results) end
        if k.energy_required then recipe.energy_required = k.energy_required end
        if k.categories then
          recipe.categories = table.deepcopy(k.categories)
          recipe.category = nil
        end
        reverted = reverted + 1
        elog("restored K2 recipe: " .. entry.name)
      end
    end
  end

  -- Declutter: with K2's baseline restored, almost nothing uses AAI's motor
  -- ("Single-cylinder engine") - hide its recipe from the player crafting
  -- menu so it doesn't sit next to the real Engine unit. NOT fully hidden:
  -- assemblers can still craft it (burner-lab / fuel-processor recipes use
  -- it, and AAI's basic-logistics tech trigger is "craft 50 motors").
  -- K2-only: without K2 the first burner assembler needs a hand-made motor.
  if mods["Krastorio2"] and data.raw.recipe["motor"] then
    data.raw.recipe["motor"].hide_from_player_crafting = true
    elog("hid motor (single-cylinder engine) from player crafting menu")
  end

  -- AAI's "Electronic circuit (Wood)" alternate is redundant with K2:
  -- K2 alone puts wood in the main circuit recipe, and K2 Spaced Out ships
  -- its own kr-electronic-circuit-wood alternate.
  if mods["Krastorio2"] and data.raw.recipe["electronic-circuit-wood"] then
    data.raw.recipe["electronic-circuit-wood"].hidden = true
    elog("hid AAI's electronic-circuit-wood alternate recipe")
  end

  -- Cosmetic restore: AAI renames/reskins vanilla engine-unit as
  -- "Multi-cylinder engine" and electric-engine-unit as a big motor. Restore
  -- the vanilla icons (names are restored via this mod's locale file, which
  -- wins because E-Tech loads after AAI).
  if data.raw.item["engine-unit"] then
    data.raw.item["engine-unit"].icon = "__base__/graphics/icons/engine-unit.png"
    data.raw.item["engine-unit"].icon_size = 64
    elog("restored vanilla engine-unit icon")
  end
  if data.raw.item["electric-engine-unit"] then
    data.raw.item["electric-engine-unit"].icon = "__base__/graphics/icons/electric-engine-unit.png"
    data.raw.item["electric-engine-unit"].icon_size = 64
    elog("restored vanilla electric-engine-unit icon")
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
