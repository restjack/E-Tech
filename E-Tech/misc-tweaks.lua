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

-- ---------------------------------------------------------------------------
-- FPS-friendly thrusters (port of FPS Friendly Thrusters, MIT — see
-- LICENSE-third-party.txt). Strips the animated exhaust plumes, the big
-- FPS cost on large platforms. Skipped when the original mod is enabled.
-- ---------------------------------------------------------------------------
if settings.startup["etech-fps-thrusters"].value then
  if mods["FPS_Friendly_Thrusters"] then
    elog("fps-thrusters setting on but the original FPS Friendly Thrusters mod is installed - skipped (disable one of the two)")
  elseif data.raw.thruster and data.raw.thruster.thruster then
    data.raw.thruster.thruster.plumes = nil
    elog("thruster plumes removed")
  end
end

-- ---------------------------------------------------------------------------
-- Pass-through fusion generators (port of pass-through-fusion-generator,
-- MIT — see LICENSE-third-party.txt). Replaces the fusion generator's input
-- fluid box connections with input-output ones on all four sides so
-- generators chain without separate plasma lines. Connection table verbatim
-- from the original. Skipped when the original mod is enabled.
-- ---------------------------------------------------------------------------
if settings.startup["etech-fusion-passthrough"].value then
  local generator = data.raw["fusion-generator"] and data.raw["fusion-generator"]["fusion-generator"]
  if mods["pass-through-fusion-generator"] then
    elog("fusion-passthrough setting on but the original pass-through-fusion-generator mod is installed - skipped (disable one of the two)")
  elseif generator then
    generator.input_fluid_box.pipe_connections = {
      { flow_direction="input-output", direction = defines.direction.south, position = {-1,  2}, connection_category = {"fusion-plasma"} },
      { flow_direction="input-output", direction = defines.direction.south, position = { 1,  2}, connection_category = {"fusion-plasma"} },
      { flow_direction="input-output", direction = defines.direction.north, position = { 0, -2}, connection_category = {"fusion-plasma"} },
      { flow_direction="input-output", direction = defines.direction.west,  position = {-1,  0}, connection_category = {"fusion-plasma"} },
      { flow_direction="input-output", direction = defines.direction.east,  position = { 1,  0}, connection_category = {"fusion-plasma"} },
      { flow_direction="input-output", direction = defines.direction.west,  position = {-1, -1}, connection_category = {"fusion-plasma"} },
      { flow_direction="input-output", direction = defines.direction.east,  position = { 1, -1}, connection_category = {"fusion-plasma"} },
    }
    elog("fusion generator pass-through connections applied")
  end
end
