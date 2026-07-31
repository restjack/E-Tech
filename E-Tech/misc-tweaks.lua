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

-- ---------------------------------------------------------------------------
-- Factorissimo interior roboport: whole-floor logistics + real charging
-- Absorbs factorissimo-roboport-buff by RandomBruh (Unlicense/public domain),
-- and adds the charging fix that mod never had.
--
-- Factorissimo builds "factory-construction-roboport" as a deepcopy of the
-- vanilla roboport shrunk to 2x2, so it inherits vanilla's 4 charging pads -
-- and its vector_downscale() halves the pad offsets to ~0.75 tiles. Stock it
-- also gets logistics_radius 2, robot_slots_count 0, material_slots_count 1,
-- i.e. it covers almost nothing and holds no bots. Once the radius covers the
-- whole floor, those 4 pads become the bottleneck: hundreds of logistic bots
-- queue to charge instead of working. They also charge at half the rate of a
-- real roboport in this pack: Factorissimo copies vanilla in data.lua, when
-- charging_energy is the base game's 500 kW, and Krastorio 2 only raises the
-- vanilla roboport to 1000 kW later in data-updates (updates/base/entities.lua)
-- - too late for a copy that was already taken.
--
-- Runs in data-final-fixes (required from there), so we land after every other
-- mod's data-updates - which is where the standalone buff mod wrote and lost.
--
-- Only the VISIBLE roboport is touched. Factorissimo also builds
-- "factory-hidden-construction-roboport", a reservoir that tops the factory
-- network up to 200 free hidden construction robots. Those robots are defined
-- with energy_per_move/energy_per_tick = nil, so they never charge at all; its
-- single centre pad, logistics_radius 2 and material_slots_count 0 are
-- deliberate. Buffing it is a no-op at best, so we leave it alone.
-- ---------------------------------------------------------------------------
-- The interior roboport is built at the factory's DOOR (layout.inside_energy,
-- y = +half+2), not at its centre. On every stock tier that is harmless: a
-- factory-3 roboport sits at y = +32 and radius 64 reaches y = -32, past the
-- far wall at -31. A Mk4 is 120 wide - its roboport sits at y = +62 and radius
-- 64 dies at y = -2, leaving the entire northern half of the floor with no
-- logistics and no construction coverage. 128 reaches y = -66, clear of the
-- wall at -61.
--
-- Safe for the small tiers too. Factory interiors are 512 tiles apart, so the
-- farthest this can reach from a cell centre is 190 - nowhere near the 449 at
-- which the next factory's floor begins - and this prototype only ever exists
-- inside a factory.
local MK4_ROBOPORT_REACH = 128
local function apply_mk4_roboport_reach(rb)
  if not settings.startup["etech-factory-mk4"].value then return end
  if not rb then return end
  if (rb.logistics_radius or 0) < MK4_ROBOPORT_REACH then
    rb.logistics_radius = MK4_ROBOPORT_REACH
  end
  if (rb.construction_radius or 0) < MK4_ROBOPORT_REACH then
    rb.construction_radius = MK4_ROBOPORT_REACH
  end
  -- The engine REFUSES to load a roboport whose logistics_connection_distance
  -- is below its logistics_radius. Factorissimo ships 64/64, so raising only
  -- the radius is a hard prototype error, not a warning.
  if (rb.logistics_connection_distance or 0) < rb.logistics_radius then
    rb.logistics_connection_distance = rb.logistics_radius
  end
  dlog("factory Mk4 on: interior roboport reach raised to " .. MK4_ROBOPORT_REACH
    .. " so it covers a 120x120 floor from the door")
end

if settings.startup["etech-factory-roboport"].value then
  if mods["factorissimo-2-notnotmelon"] then
    local rb = data.raw.roboport and data.raw.roboport["factory-construction-roboport"]
    if rb then
      local pads = settings.startup["etech-factory-roboport-pads"].value
      local kw = settings.startup["etech-factory-roboport-kw"].value
      local ring = settings.startup["etech-factory-roboport-pad-radius"].value
      local stock_pads = rb.charging_station_count
        or (rb.charging_offsets and #rb.charging_offsets) or 0

      dlog("interior roboport before: logistics_radius=" .. tostring(rb.logistics_radius)
        .. " robot_slots=" .. tostring(rb.robot_slots_count)
        .. " material_slots=" .. tostring(rb.material_slots_count)
        .. " pads=" .. tostring(stock_pads)
        .. " charging_energy=" .. tostring(rb.charging_energy))

      -- Factorissimo gives the copied roboport a construction-CHEST icon. That
      -- is invisible while the roboport is just a hidden entity on a factory
      -- floor, but metered mode puts it in the electric network list, where a
      -- chest drawing tens of MW reads as nonsense. Point it back at whatever
      -- the current roboport item uses (so a K2/mod reskin is respected).
      local roboport_item = data.raw.item["roboport"]
      if roboport_item and roboport_item.icon then
        rb.icon = roboport_item.icon
        rb.icon_size = roboport_item.icon_size
        rb.icons = nil
      end

      rb.logistics_radius = settings.startup["etech-factory-roboport-logistics-radius"].value
      rb.robot_slots_count = settings.startup["etech-factory-roboport-robot-slots"].value
      rb.material_slots_count = settings.startup["etech-factory-roboport-material-slots"].value

      -- Factorissimo ships logistics_connection_distance = 64, and the engine
      -- refuses to load a roboport whose connection distance is below its
      -- logistics radius. The radius setting goes up to 512, so anything above
      -- 64 was a hard load error until now.
      if (rb.logistics_connection_distance or 0) < rb.logistics_radius then
        rb.logistics_connection_distance = rb.logistics_radius
      end

      -- After the radius setting is applied, never before - and before the K2
      -- mode-variant loop below, which derives the twins' radii from these.
      apply_mk4_roboport_reach(rb)

      -- THE ACTUAL CHARGING FIX. Factorissimo swaps this roboport's
      -- energy_source for {type = "void"} but builds it as a table.deepcopy of
      -- the vanilla roboport, so it keeps vanilla's recharge_minimum = 40MJ.
      -- Vanilla can satisfy that from its 100MJ electric buffer; a void source
      -- has no buffer to accumulate into, so the threshold is never met and the
      -- roboport never starts charging a robot at all. Symptom: bots pile up on
      -- the roboport with no recharging animation, and no number of pads or kW
      -- changes anything. Factorissimo hit this on its hand-built hidden
      -- roboport and set BOTH energy_usage and recharge_minimum to "1W" there;
      -- we match that pair. Both are needed: the engine rejects any prototype
      -- with recharge_minimum < energy_usage ("the roboport will toggle on and
      -- off every tick"), so dropping recharge_minimum alone fails to load.
      -- energy_usage is free to lower because a void source draws from no grid.
      --
      -- ...except that lowering the threshold turned out NOT to be enough. A
      -- void source stores no energy, and robot charging is paid out of the
      -- roboport's stored energy - so a void-powered roboport cannot charge a
      -- robot at all, at any pad count or per-pad power. Verified in game:
      -- bots parked on it drain to empty. Every roboport in the pack that does
      -- charge (vanilla, K2's, mk2/mk3, umr) has an electric source; the only
      -- void ones are Factorissimo's two, and its hidden roboport serves robots
      -- defined with zero energy drain, so upstream would never notice.
      --
      -- Metered mode (etech-factory-roboport-electric, ON by default) swaps the
      -- void source for a real electric one. That is what actually makes
      -- charging work, and it means charging costs grid power - there is no
      -- free-charging configuration. Factorissimo 3 wires a factory's interior
      -- pole straight to an outside pole with copper (script/electricity.lua),
      -- and nested factories chain into their parent, so "the grid" here is the
      -- same network as the rest of your base at any nesting depth - there is
      -- no per-factory power budget to blow. usage_priority "secondary-input"
      -- is what vanilla roboports use: charging is served after primary
      -- consumers, so an under-supplied grid throttles bot charging instead of
      -- browning out machines. recharge_minimum stays well under vanilla's 40MJ
      -- so the roboport resumes charging promptly after a dip rather than
      -- refilling 40MJ first.
      local metered = settings.startup["etech-factory-roboport-electric"].value
      local source_type = rb.energy_source and rb.energy_source.type
      local void_source = source_type == "void"

      if metered then
        local input_mw = settings.startup["etech-factory-roboport-input-mw"].value
        -- Buffer: ~2 s of inflow, with a floor well above a single robot's
        -- energy capacity (6 MJ for a quality logistic bot here). Too small a
        -- buffer next to a deliberately low recharge_minimum makes the roboport
        -- oscillate across the threshold instead of degrading smoothly.
        local buffer_mj = math.max(50, input_mw * 2)
        if not void_source then
          elog("interior roboport energy_source was '" .. tostring(source_type)
            .. "' (not Factorissimo's void source - another mod changed it);"
            .. " replacing it anyway because metered mode is on")
        end
        rb.energy_source = {
          type = "electric",
          usage_priority = "secondary-input",
          input_flow_limit = input_mw .. "MW",
          buffer_capacity = buffer_mj .. "MJ",
        }
        rb.energy_usage = "50kW"
        rb.recharge_minimum = "1MJ"
        elog("interior roboport METERED: electric source, " .. input_mw
          .. " MW input flow limit, " .. buffer_mj .. " MJ buffer. Charging now"
          .. " costs real power, and sustained throughput is capped by the flow"
          .. " limit rather than by pads x kW. A factory with no power pole in"
          .. " range of it has no supply at all, so its bots will never charge.")
      elseif void_source then
        elog("interior roboport left on Factorissimo's VOID energy source"
          .. " (etech-factory-roboport-electric is off). A void source stores no"
          .. " energy, and robot charging is paid from stored energy, so robots"
          .. " will NOT charge inside factories no matter how many pads or how"
          .. " much per-pad power is configured. Turn the setting on to fix it.")
        elog("interior roboport energy_usage " .. tostring(rb.energy_usage)
          .. " / recharge_minimum " .. tostring(rb.recharge_minimum)
          .. " -> 1W / 1W (void energy source has no buffer to reach the old"
          .. " threshold, so charging never started)")
        rb.energy_usage = "1W"
        rb.recharge_minimum = "1W"
      end

      -- charging_station_count > 0 makes the engine ignore charging_offsets and
      -- space the pads evenly on a circle of charging_distance tiles. We leave
      -- charging_station_count_affected_by_quality as Factorissimo set it
      -- (true), so higher-quality factories still earn extra pads on top.
      if pads > 0 then
        rb.charging_offsets = nil
        rb.charging_station_count = pads
        rb.charging_distance = ring
      end

      if kw > 0 then
        -- Robot charging is paid out of the roboport's OWN energy source.
        -- Factorissimo gives this one {type = "void"}, so the power is free.
        -- If another mod swaps that for an electric source, the real charge
        -- rate is capped by the buffer refill and raising per-pad power
        -- achieves nothing - so say so instead of failing quietly.
        if not metered and not void_source then
          elog("interior roboport energy_source is '" .. tostring(source_type)
            .. "', not 'void' - charging at " .. kw
            .. " kW per pad may be capped by its energy buffer, and its"
            .. " recharge_minimum was left alone")
        end
        rb.charging_energy = kw .. "kW"
      end

      elog("factorissimo interior roboport: logistics radius " .. rb.logistics_radius
        .. ", " .. rb.robot_slots_count .. " robot / " .. rb.material_slots_count
        .. " material slots, "
        .. (pads > 0 and (stock_pads .. " -> " .. pads .. " charging pads")
                      or "stock charging pads")
        .. ", "
        .. (kw > 0 and (kw .. " kW per pad") or "stock charging power"))

      -- Krastorio 2's roboport mode switch (logistic-only / construction-only)
      -- is implemented by deep-copying EVERY prototype in data.raw.roboport
      -- into "<name>-logistic-mode" and "<name>-construction-mode"
      -- (Krastorio2/prototypes/updates/generate-roboport-variations.lua). That
      -- runs in data-updates - before this file - so the factory roboport's
      -- twins are copies of Factorissimo's STOCK prototype: void energy source,
      -- 4 pads at 500 kW, logistics_radius 3, 0 robot slots. Flipping a factory
      -- roboport to either mode would swap in that stale copy and silently undo
      -- everything above, energy source included, so its robots would stop
      -- charging again with no visible cause.
      --
      -- Re-apply the mode-independent fields, then recompute K2's derived radii
      -- from our new values using their own formulas (ceil(r * 1.275) for
      -- logistic, ceil(c * 1.25) for construction). This is deliberately
      -- coupled to K2's implementation: if they change the formulas, the twins
      -- end up with slightly different radii, not broken ones.
      for _, mode in ipairs({"logistic", "construction"}) do
        local twin = data.raw.roboport["factory-construction-roboport-" .. mode .. "-mode"]
        if twin then
          twin.energy_source = table.deepcopy(rb.energy_source)
          twin.energy_usage = rb.energy_usage
          twin.recharge_minimum = rb.recharge_minimum
          twin.charging_energy = rb.charging_energy
          twin.charging_station_count = rb.charging_station_count
          twin.charging_distance = rb.charging_distance
          twin.charging_offsets = rb.charging_offsets and table.deepcopy(rb.charging_offsets) or nil
          twin.robot_slots_count = rb.robot_slots_count
          twin.material_slots_count = rb.material_slots_count
          twin.icon = rb.icon
          twin.icon_size = rb.icon_size
          twin.icons = nil

          if mode == "logistic" then
            twin.logistics_radius = math.ceil(rb.logistics_radius * 1.275)
            twin.logistics_connection_distance = twin.logistics_radius
            twin.construction_radius = 0
          else
            twin.construction_radius = math.ceil((rb.construction_radius or 0) * 1.25)
            twin.logistics_connection_distance =
              math.ceil(math.min(rb.logistics_radius * 1.5, twin.construction_radius))
            twin.logistics_radius = 0
          end

          dlog("patched K2 mode variant factory-construction-roboport-" .. mode
            .. "-mode: logistics_radius=" .. tostring(twin.logistics_radius)
            .. " construction_radius=" .. tostring(twin.construction_radius))
        end
      end

      if mods["factorissimo-roboport-buff"] then
        elog("factorissimo-roboport-buff is still installed - it can be removed, this setting covers everything it did")
      end
    else
      elog("factorissimo interior roboport not found (prototype factory-construction-roboport) - skipped, Factorissimo may have renamed it")
    end
  else
    elog("factorissimo roboport setting on but Factorissimo 3 not active - skipped")
  end
elseif settings.startup["etech-factory-mk4"].value and mods["factorissimo-2-notnotmelon"] then
  -- Mk4 without the roboport buff: the reach fix is still required, otherwise
  -- half of every Mk4 floor is outside the interior roboport. Nothing else
  -- from the buff block is applied here.
  apply_mk4_roboport_reach(data.raw.roboport and data.raw.roboport["factory-construction-roboport"])
end
