-- misc-tweaks.lua
-- Small optional Space Age / base tweaks, each gated by its own startup
-- setting. Data stage; no dependency on AAI or K2.

local function elog(msg) log("[E-Tech] " .. msg) end
local debug_log = settings.startup["etech-debug-log"].value
local function dlog(msg) if debug_log then elog(msg) end end

-- ---------------------------------------------------------------------------
-- Quality modules in asteroid crushing / reprocessing
-- The crusher already allows the quality effect (module_slots = 2,
-- allowed_effects includes "quality"); the recipes set allow_quality = false.
-- Flip that on every asteroid crushing/reprocessing recipe (modded ones too).
-- ---------------------------------------------------------------------------
if settings.startup["etech-quality-asteroid"].value then
  -- The name match alone could hit an unrelated modded recipe that merely
  -- has "asteroid" in its name - when the recipe declares crafting
  -- categories, require one of them to be crusher-related.
  local function crusher_category(recipe)
    if not recipe.categories then return true end
    for _, c in pairs(recipe.categories) do
      if c:find("crush") then return true end
    end
    return false
  end
  local n = 0
  for name, recipe in pairs(data.raw.recipe) do
    if name:find("asteroid")
       and (name:find("crushing") or name:find("reprocessing") or name:find("asteroid%-processing"))
       and recipe.allow_quality == false
       and crusher_category(recipe) then
      recipe.allow_quality = true
      n = n + 1
      dlog("allow_quality enabled on recipe: " .. name)
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
-- Krastorio 2 + Cerys nitric acid compat fix (legacy Cerys only).
-- Cerys below 4.24.5 loads after K2 (optional dependency on K2SO) and
-- redefines the kr-nitric-acid fluid with default_temperature = 15 and none
-- of K2's other fields — so all Cerys-produced acid comes out at 15°C, below
-- the 25°C minimum K2's recipes expect, and the tooltip loses K2's info.
-- Cerys 4.24.5 fixed this upstream (it no longer defines the fluid when K2 is
-- installed), so this only runs when the 15°C overwrite is actually present.
-- Existing saves self-heal: the engine clamps stored fluid temperatures to the
-- prototype range on load, so no recipe temperature bounds need touching.
-- ---------------------------------------------------------------------------
if mods["Krastorio2"] and mods["Cerys-Moon-of-Fulgora"] then
  local fluid = data.raw.fluid["kr-nitric-acid"]
  if fluid and fluid.default_temperature == 15 then
    fluid.default_temperature = 25
    fluid.gas_temperature = 25
    fluid.max_temperature = 100
    fluid.icon = "__Krastorio2Assets__/icons/fluids/nitric-acid.png"
    fluid.base_color = { r = 0.752, g = 0.215, b = 0.337, a = 1.0 }
    fluid.flow_color = { r = 0.752, g = 0.215, b = 0.337, a = 0.8 }
    fluid.auto_barrel = true
    elog("kr-nitric-acid: restored K2's definition over pre-4.24.5 Cerys's 15C overwrite")
  end
end

-- ---------------------------------------------------------------------------
-- Copy-paste modules: make furnaces, labs and beacons cross-pastable so
-- module sets copy between them (data-stage half of the Copy Paste Modules
-- port; runtime half in copy-paste-modules.lua). Skipped when the original
-- mod is enabled.
-- ---------------------------------------------------------------------------
if settings.startup["etech-copy-paste-modules"].value then
  if mods["CopyPasteModules"] then
    elog("copy-paste-modules setting on but the original Copy Paste Modules mod is installed - skipped (disable one of the two)")
  else
    for _, type_name in pairs({ "furnace", "lab", "beacon" }) do
      local raw_entities = data.raw[type_name]
      if raw_entities then
        local entity_names = {}
        for _, entity in pairs(raw_entities) do
          table.insert(entity_names, entity.name)
        end
        for _, entity in pairs(raw_entities) do
          entity.additional_pastable_entities = entity_names
        end
      end
    end
    elog("copy-paste-modules: furnaces/labs/beacons made cross-pastable")
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

-- ---------------------------------------------------------------------------
-- Quality adds module slots to every machine that has any (needs Quality).
-- Blanket replacement for the retired QualityEffectsFixed mod (clean
-- reimplementation, no code reused): sets the engine flag
-- quality_affects_module_slots on all six prototype types that can hold
-- modules. Machines with 0 base slots are untouched (the flag would do
-- nothing there anyway). Honors the qef_ignore opt-out field other mods
-- may have set for QualityEffectsFixed.
-- ---------------------------------------------------------------------------
if settings.startup["etech-quality-module-slots"].value then
  if mods["quality"] then
    -- Appended to tooltips of affected machines so players can see the rule
    -- in-game without digging through mod settings. Localised key (bare, at
    -- the top of locale/en/en.cfg).
    local note = {"etech-quality-slots-note"}
    local function add_note(proto, primary, fallback)
      if proto.localised_description then
        proto.localised_description = {"", proto.localised_description, "\n", note}
      else
        proto.localised_description = {"?",
          {"", {primary .. "." .. proto.name}, "\n", note},
          {"", {fallback .. "." .. proto.name}, "\n", note},
          note}
      end
    end
    local n = 0
    for _, t in ipairs({"assembling-machine", "furnace", "rocket-silo",
                        "beacon", "mining-drill", "lab"}) do
      for _, proto in pairs(data.raw[t] or {}) do
        if (proto.module_slots or 0) > 0 and not proto.qef_ignore then
          proto.quality_affects_module_slots = true
          add_note(proto, "entity-description", "item-description")
          local item = data.raw.item[proto.name]
          if item then add_note(item, "item-description", "entity-description") end
          n = n + 1
        end
      end
    end
    if mods["QualityEffectsFixed"] then
      elog("QualityEffectsFixed is still installed - it can be removed, this setting covers everything it did")
    end
    elog("quality module slots enabled on " .. n .. " machine prototypes")
  else
    elog("quality module slots setting on but Quality mod not active - skipped")
  end
end
