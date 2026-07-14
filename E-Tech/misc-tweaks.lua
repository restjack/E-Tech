-- misc-tweaks.lua
-- Small optional Space Age / base tweaks, each gated by its own startup
-- setting. Data stage; no dependency on AAI or K2.

local function elog(msg) log("[E-Tech] " .. msg) end

-- ---------------------------------------------------------------------------
-- Quality modules in asteroid crushing / reprocessing
-- The crusher already allows the quality effect (module_slots = 2,
-- allowed_effects includes "quality"); the recipes set allow_quality = false.
-- Flip that on every asteroid crushing/reprocessing recipe (modded ones too).
-- ---------------------------------------------------------------------------
if settings.startup["etech-quality-asteroid"].value then
  local n = 0
  for name, recipe in pairs(data.raw.recipe) do
    if name:find("asteroid")
       and (name:find("crushing") or name:find("reprocessing") or name:find("asteroid%-processing"))
       and recipe.allow_quality == false then
      recipe.allow_quality = true
      n = n + 1
      elog("allow_quality enabled on recipe: " .. name)
    end
  end
  elog("asteroid recipes quality-enabled: " .. n)
end

-- ---------------------------------------------------------------------------
-- Nuclear fuel stack size
-- ---------------------------------------------------------------------------
do
  local size = settings.startup["etech-nuclear-fuel-stack"].value
  local item = data.raw.item["nuclear-fuel"]
  if item and size and size > 0 and item.stack_size ~= size then
    item.stack_size = size
    elog("nuclear-fuel stack_size = " .. size)
  end
end

-- ---------------------------------------------------------------------------
-- Artillery shell stack size (type "ammo")
-- ---------------------------------------------------------------------------
do
  local size = settings.startup["etech-artillery-shell-stack"].value
  local item = data.raw.ammo["artillery-shell"]
  if item and size and size > 0 and item.stack_size ~= size then
    item.stack_size = size
    elog("artillery-shell stack_size = " .. size)
  end
end

-- ---------------------------------------------------------------------------
-- Restore nuclear fuel crafting (Krastorio 2 hides the item and recipe).
-- Same idea as the tiny "k2-nuclear-fuel" mod, but instead of enabling the
-- recipe from game start we re-attach it to Kovarex enrichment (its vanilla
-- unlock) when that tech is usable; enabled-from-start is only the fallback.
-- ---------------------------------------------------------------------------
if settings.startup["etech-restore-nuclear-fuel"].value then
  local item = data.raw.item["nuclear-fuel"]
  local recipe = data.raw.recipe["nuclear-fuel"]
  if item then item.hidden = false end
  if recipe then
    recipe.hidden = false
    recipe.hide_from_player_crafting = nil
    local tech = data.raw.technology["kovarex-enrichment-process"]
    if tech and not tech.hidden and tech.enabled ~= false then
      local found = false
      for _, eff in pairs(tech.effects or {}) do
        if eff.type == "unlock-recipe" and eff.recipe == "nuclear-fuel" then
          found = true
          break
        end
      end
      if not found then
        tech.effects = tech.effects or {}
        tech.effects[#tech.effects + 1] = {type = "unlock-recipe", recipe = "nuclear-fuel"}
      end
      recipe.enabled = false -- gated behind the tech, vanilla behavior
      elog("nuclear-fuel restored (unlocked by Kovarex enrichment)")
    else
      recipe.enabled = true -- no usable Kovarex tech; craftable from start
      elog("nuclear-fuel restored (enabled from start, Kovarex tech unavailable)")
    end
  end
end

-- ---------------------------------------------------------------------------
-- Agricultural science pack spoilage
-- Setting = "does it spoil". When off, strip the spoil fields.
-- ---------------------------------------------------------------------------
if not settings.startup["etech-ag-science-spoils"].value then
  local item = data.raw.tool["agricultural-science-pack"]
             or data.raw.item["agricultural-science-pack"]
  if item and (item.spoil_ticks or item.spoil_result) then
    item.spoil_ticks = nil
    item.spoil_result = nil
    item.spoil_to_trigger_result = nil
    elog("disabled spoilage on agricultural-science-pack")
  end
end
