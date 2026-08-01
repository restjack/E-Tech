-- factory-mk4/data.lua
-- Factory building Mk4: a fourth Factorissimo tier, added from E-Tech with no
-- fork. Only loaded when Factorissimo 3 is active (root data.lua checks), so
-- factory-3, factory-power-input-16, factory-wall-3 and factory-architecture-t3
-- all exist by the time this runs.
--
-- 120x120 interior behind factory-3's UNCHANGED 16x16 exterior - see
-- factory-mk4/layout.lua for the geometry and why 120 is the ceiling, and
-- docs/FACTORY-MK4-HANDOFF.md for the decision behind it.
--
-- Because the exterior is byte-for-byte a factory-3, the visual marker below
-- is not polish: without it the two tiers are indistinguishable on the map, on
-- the ground and in inventory. Factorissimo does the same thing for its own
-- space-factory-N variants (same footprint, same shadow, different body), so
-- this follows the mod's own precedent.
--
-- The icon has to be replaced in THREE places - entity, item, and the
-- item-with-tags a packed factory becomes when mined. Miss one and a Mk4 in a
-- player's inventory still reads as a Mk3.

local BASE = "factory-3"
local NAME = "factory-4"

-- Science packs are `item` in Factorio 2.1 and were `tool` before it; other
-- mods may still register either. data.raw.tool is nil when nothing defines
-- one, so it can never be indexed directly.
local function science_pack_exists(name)
  return (data.raw.tool and data.raw.tool[name]) ~= nil
      or data.raw.item[name] ~= nil
end

local base_entity = data.raw["storage-tank"][BASE]
if not base_entity then
  log("E-Tech: " .. BASE .. " not found - Factorissimo may have renamed its tiers. Mk4 skipped.")
  return
end

-- Visual marker --------------------------------------------------------------
-- FIRST ATTEMPT, REPLACED: a runtime `tint` on the sprite layer. It is a
-- multiply, so it can only darken, and in game the Mk4 still read as a brown
-- factory-3 - and the facade still had "03" painted on it, which no tint can
-- fix. The marker is the whole point of reusing the Mk3 exterior, so it had to
-- actually work.
--
-- Now real artwork, generated from Factorissimo's factory-3.png by
-- `tools/make-mk4-art.py` (outside the mod folder - the portal rejects zips
-- containing scripts). That script repaints the "3" on the facade into a "4"
-- and maps the warm brown siding to its own luminance tinted cold, so the
-- corrugation and grime survive but the building is unmistakably steel blue.
-- Re-run it if Factorissimo ever redraws factory-3.
--
-- The SHADOW is Factorissimo's, referenced unchanged - exactly what its own
-- space-factory variants do. A shadow does not need recolouring and copying it
-- would just bloat the zip.
local GFX = "__E-Tech__/graphics/factory-mk4/"
local MK4_ICON = GFX .. "icon-factory-4.png"
-- Every stock factory shares {0.8, 0.7, 0.55} on the map, so this makes a Mk4
-- unmistakable at map zoom too, where the artwork is not drawn at all.
local MK4_MAP_COLOR = {r = 0.30, g = 0.48, b = 0.85}

local function mk4_icons()
  return {{icon = MK4_ICON, icon_size = 64}}
end

-- Entity ---------------------------------------------------------------------

local entity = table.deepcopy(base_entity)
entity.name = NAME
entity.minable = {mining_time = 0.5, result = NAME .. "-instantiated", count = 1}
entity.max_health = 8000
entity.map_color = MK4_MAP_COLOR
entity.icon = nil
entity.icons = mk4_icons()

-- factory-3's picture is a plain two-layer static sprite: [1] shadow, [2]
-- body. Keep layer [1] as-is and point layer [2] at our repainted body. Every
-- other field (size, scale, shift) has to stay identical or the building will
-- not line up with its own shadow or its collision box. Indexed without a
-- guard on purpose: if a future Factorissimo restructures these layers this
-- should fail at load rather than silently ship a Mk4 that looks like a Mk3.
entity.pictures.picture.layers[2].filename = GFX .. "factory-4.png"

-- Items ----------------------------------------------------------------------

local item = table.deepcopy(data.raw.item[BASE])
item.name = NAME
item.place_result = NAME
item.order = "b-d"
item.icon = nil
item.icons = mk4_icons()

-- What a mined factory turns into: an item-with-tags carrying the interior's
-- id, so its contents survive being picked up.
local packed = table.deepcopy(data.raw["item-with-tags"][BASE .. "-instantiated"])
packed.name = NAME .. "-instantiated"
packed.localised_name = {"item-name.factory-packed", {"entity-name." .. NAME}}
packed.place_result = NAME
packed.order = "b-d"
packed.factoriopedia_alternative = NAME
packed.icon = nil
packed.icons = {
  {icon = MK4_ICON, icon_size = 64},
  {icon = "__factorissimo-2-notnotmelon__/graphics/icon/packing-tape.png", icon_size = 64},
}

-- Per-tier hidden chests -----------------------------------------------------
-- Factorissimo generates these in a hardcoded
-- `for _, factory_name in pairs {"factory-1", "factory-2", "factory-3"}` loop
-- in prototypes/roboport.lua, so a fourth tier has to bring its own pair. They
-- are the outside end of the roboport upgrade: the requester holds what the
-- interior construction network asks for, the ejector spits out what it
-- deconstructs. Both are invisible, sitting under the building itself.

local hidden_chests = {}
local steel_chest = data.raw.container["steel-chest"]
if steel_chest then
  local requester_chest = table.deepcopy(steel_chest)
  requester_chest.name = "factory-requester-chest-" .. NAME
  requester_chest.localised_name = {"entity-name.factory-requester-chest"}
  requester_chest.icons = mk4_icons()
  requester_chest.icon = nil
  requester_chest.collision_box = table.deepcopy(entity.collision_box)
  requester_chest.selection_box = nil
  requester_chest.inventory_type = "with_custom_stack_size"
  requester_chest.inventory_properties = {stack_size_multiplier = 50}
  requester_chest.inventory_size = 100
  requester_chest.picture = nil
  requester_chest.hidden = true
  requester_chest.factoriopedia_alternative = NAME
  requester_chest.quality_indicator_scale = 0
  requester_chest.flags = {"not-on-map", "hide-alt-info", "no-automated-item-removal", "no-automated-item-insertion", "not-in-kill-statistics", "not-rotatable"}
  hidden_chests[#hidden_chests + 1] = requester_chest

  local eject_chest = table.deepcopy(steel_chest)
  eject_chest.name = "factory-eject-chest-" .. NAME
  eject_chest.localised_name = {"entity-name.factory-eject-chest"}
  eject_chest.inventory_size = 1
  eject_chest.icons = mk4_icons()
  eject_chest.icon = nil
  eject_chest.collision_box = table.deepcopy(entity.collision_box)
  eject_chest.selection_box = nil
  eject_chest.picture = nil
  eject_chest.hidden = true
  eject_chest.factoriopedia_alternative = NAME
  eject_chest.quality_indicator_scale = 0
  eject_chest.flags = {"not-on-map", "hide-alt-info", "no-automated-item-removal", "no-automated-item-insertion", "not-in-kill-statistics", "not-rotatable"}
  hidden_chests[#hidden_chests + 1] = eject_chest

  for _, prototype in pairs(hidden_chests) do
    prototype.collision_mask = {layers = {}}
    prototype.fast_replaceable_group = nil
    prototype.next_upgrade = nil
    prototype.surface_conditions = nil
    prototype.max_health = 500
    prototype.minable = nil
    prototype.placeable_by = nil
    prototype.heating_energy = nil
  end
else
  -- Without these the roboport upgrade cannot build its outside ends, so a Mk4
  -- would work except for interior construction. Loud, because it is silent
  -- otherwise.
  log("E-Tech: steel-chest missing - Mk4 hidden requester/eject chests skipped, the Mk4 roboport upgrade will not work.")
end

-- Interior tiles ---------------------------------------------------------------
-- Without these the INSIDE of a Mk4 is identical to a Mk3 - same yellow walls,
-- same floor logo colour - which undoes half the point of giving it its own
-- exterior. The stock tiers are orange (1), blue (2) and yellow (3); the Mk4
-- goes teal, close to its steel-blue outside but clear of factory-2's blue.
--
-- Deepcopied rather than rebuilt: Factorissimo's tiles carry transition
-- spritesheets, sounds, collision masks and a frozen twin, and reproducing all
-- of that by hand would drift the moment they change any of it. Only the
-- graphics and the colour are swapped.

local TILE_COLOR = {r = 70, g = 190, b = 205}
-- The space tiles are amber to match the space building's amber paint, so
-- their map colour has to follow or the map disagrees with the floor.
local SPACE_TILE_COLOR = {r = 205, g = 150, b = 60}
local TILE_FROZEN_TINT = {0.75, 1, 1}

local function clone_tile(base_name, new_name, picture, map_color)
  local base = data.raw.tile[base_name]
  if not base then
    log("E-Tech: tile " .. base_name .. " not found - Mk4 keeps the Mk3 interior tiles.")
    return nil
  end

  local tile = table.deepcopy(base)
  tile.name = new_name
  tile.map_color = map_color

  -- variants.main is the list of {picture, count, size} entries the wall
  -- graphic comes from; the transition spritesheet is shared and stays.
  for _, variant in pairs((tile.variants or {}).main or {}) do
    variant.picture = picture
  end

  -- Freezing (Aquilo) gives every tile a frozen twin that is a recoloured
  -- concrete, not the wall graphic - so it needs its own copy and its own
  -- back-link, or a frozen Mk4 floor shows the Mk3's.
  if base.frozen_variant and data.raw.tile[base.frozen_variant] then
    local frozen = table.deepcopy(data.raw.tile[base.frozen_variant])
    frozen.name = new_name .. "-frozen"
    frozen.thawed_variant = new_name
    frozen.map_color = map_color
    frozen.tint = TILE_FROZEN_TINT
    -- Reuse Factorissimo's generic tile name rather than inventing a key per
    -- tier - they name every wall tile "tile-name.factory-wall".
    frozen.localised_name = base.localised_name or data.raw.tile[base.frozen_variant].localised_name
    tile.frozen_variant = frozen.name
    data:extend({frozen})
  end

  return tile
end

local tiles = {}
for _, spec in ipairs({
  {"factory-wall-3", "factory-wall-4", GFX .. "factory-wall-4.png", TILE_COLOR},
  {"factory-pattern-3", "factory-pattern-4", GFX .. "factory-wall-4.png", TILE_COLOR},
  -- The space tiles only exist when Factorissimo's space architecture setting
  -- is on; clone_tile returns nil and logs if they are absent. They use their
  -- own graphic, because the space skin is a dark panelled wall rather than
  -- the ground building's brick.
  {"space-factory-wall-3", "space-factory-wall-4", GFX .. "space-factory-wall-4.png", SPACE_TILE_COLOR},
  {"space-factory-pattern-3", "space-factory-pattern-4", GFX .. "space-factory-wall-4.png", SPACE_TILE_COLOR},
}) do
  local tile = clone_tile(spec[1], spec[2], spec[3], spec[4])
  if tile then tiles[#tiles + 1] = tile end
end
data:extend(tiles)

-- Hidden power relay pole ------------------------------------------------------
-- The interior power pole Factorissimo builds sits at the DOOR and has
-- supply_area_distance 63. The engine caps that field at 64 for every electric
-- pole prototype, so from the door no pole can ever reach the far side of a
-- 120-wide floor - the northern half would have no electricity.
--
-- Rather than dragging the visible pole (and the roboport with it) into the
-- middle of the floor, this invisible pole is built at the interior centre and
-- script-wired to Factorissimo's one. The player still sees the pole and the
-- roboport by the entrance where they belong; the electricity actually comes
-- from here. Placed by factory-mk4/control.lua.
--
-- Invisible on purpose, every way it can be: an empty sprite, no wires drawn
-- (the copper line to the door pole would otherwise cut across the floor), not
-- selectable, not on the map, no collision.
data:extend({
  {
    type = "electric-pole",
    name = "etech-factory-mk4-power-relay",
    icon = MK4_ICON,
    icon_size = 64,
    -- Its own name rather than borrowing the building's: it is unselectable so
    -- a player never sees it, but it does show up in logs and in debug views,
    -- where "Factory building Mk4" would be actively confusing.
    localised_name = {"entity-name.etech-factory-mk4-power-relay"},
    flags = {"not-on-map", "not-blueprintable", "not-deconstructable", "no-automated-item-removal", "no-automated-item-insertion"},
    hidden = true,
    hidden_in_factoriopedia = true,
    selectable_in_game = false,
    minable = nil,
    max_health = 500,
    collision_box = {{-0.4, -0.4}, {0.4, 0.4}},
    selection_box = {{0, 0}, {0, 0}},
    collision_mask = {layers = {}},
    -- 64 from the centre reaches +/-64, covering the floor's +/-60 with room
    -- to spare. This is the engine maximum.
    supply_area_distance = 64,
    maximum_wire_distance = 1,
    auto_connect_up_to_n_wires = 0,
    draw_copper_wires = false,
    draw_circuit_wires = false,
    pictures = {filename = "__core__/graphics/empty.png", width = 1, height = 1, direction_count = 1},
    connection_points = {{
      shadow = {copper = {0, 0}, red = {0, 0}, green = {0, 0}},
      wire = {copper = {0, 0}, red = {0, 0}, green = {0, 0}},
    }},
  },
})

-- Recipe ---------------------------------------------------------------------
-- Ingredients are resolved against what actually exists: E-Tech runs under
-- AAI Industry, Krastorio 2 and Space Age in various combinations and any of
-- them can retire an item.

local function first_present(...)
  for _, name in ipairs({...}) do
    if data.raw.item[name] then return name end
  end
  return nil
end

local ingredients = {{type = "item", name = BASE, amount = 1}}

local function add_ingredient(amount, ...)
  local name = first_present(...)
  if name then
    ingredients[#ingredients + 1] = {type = "item", name = name, amount = amount}
  end
end

add_ingredient(5000, "refined-concrete", "concrete")
add_ingredient(4000, "steel-plate")
add_ingredient(200, "substation")
add_ingredient(500, "processing-unit", "advanced-circuit")

-- Technology -----------------------------------------------------------------
-- Cost is derived from factory-architecture-t3's rather than written out, so
-- whichever overhaul rewrote that tech's science mix is respected here too -
-- the same trick factory-hub/data.lua uses against logistic-robotics.

local t3 = data.raw.technology["factory-architecture-t3"]
local unit
if t3 and t3.unit then
  unit = table.deepcopy(t3.unit)
  unit.count = (unit.count or 2000) * 2
  unit.time = 90

  -- Push it one science tier up. The ingredient list may be in either the
  -- {name, amount} array form or the {name=, amount=} table form depending on
  -- who last touched it; match whatever is already there.
  --
  -- data.raw.tool may not EXIST: Factorio 2.1 made science packs plain items,
  -- so `tool` is only present when some other mod still defines one. Indexing
  -- it unconditionally crashed the load for anyone running E-Tech with
  -- Factorissimo and nothing else that happens to define a tool - which is
  -- most people, and which no dev machine with a full modpack would ever see
  -- (found by tools/verify-matrix.ps1, fixed 0.21.1).
  if science_pack_exists("utility-science-pack") and unit.ingredients then
    local already = false
    for _, ingredient in pairs(unit.ingredients) do
      if (ingredient[1] or ingredient.name) == "utility-science-pack" then already = true end
    end
    if not already then
      local sample = unit.ingredients[1]
      if sample and sample.name then
        unit.ingredients[#unit.ingredients + 1] = {name = "utility-science-pack", amount = 1}
      else
        unit.ingredients[#unit.ingredients + 1] = {"utility-science-pack", 1}
      end
    end
  end
else
  unit = {
    count = 4000,
    time = 90,
    ingredients = {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
      {"chemical-science-pack", 1},
      {"production-science-pack", 1},
      {"utility-science-pack", 1},
    },
  }
end

local prerequisites = {}
if t3 then prerequisites[#prerequisites + 1] = "factory-architecture-t3" end
if data.raw.technology["utility-science-pack"] then
  prerequisites[#prerequisites + 1] = "utility-science-pack"
end

-- Factoriopedia quality table -------------------------------------------------
-- Factorissimo writes one of these per tier in prototypes/quality-tooltips.lua
-- via a local function, so it is reimplemented here. Without it a Mk4's
-- factoriopedia page is missing the interior/port/fluid rows every other tier
-- has. Locale keys are Factorissimo's and already exist.

local FACTORY_PUMPING_SPEED = 12000 -- per second, matching Factorissimo

-- Port counts are factory-3's, because the connection table is factory-3's.
local CONNECTIONS_BY_QUALITY = {[0] = 32, [1] = 34, [2] = 38, [3] = 42, [4] = 44}
local CONNECTIONS_MAX = 46

local function connections_at(quality_level)
  return CONNECTIONS_BY_QUALITY[quality_level] or CONNECTIONS_MAX
end

local function fluid_speed_at(quality_level)
  return tostring(FACTORY_PUMPING_SPEED * (1 + quality_level * 0.3)) .. "/s"
end

local function quality_row(stat, value_fn)
  local quality_values = {}
  for _, quality in pairs(data.raw.quality) do
    if not quality.hidden then
      quality_values[quality.name] = tostring(value_fn(quality.level))
    end
  end
  return {
    name = {"description." .. stat},
    quality_header = "quality-tooltip." .. stat,
    value = tostring(value_fn(0)),
    quality_values = quality_values,
  }
end

entity.custom_tooltip_fields = {
  quality_row("interior-space", function() return "120×120" end),
  quality_row("connections", connections_at),
  -- Not a Factorissimo stat. The Mk4's one real trade-off is that the ports
  -- did NOT grow with the floor - 32 of them serve four times the area - and
  -- that is much cheaper to learn from a tooltip than from a finished build.
  {
    -- "description." prefix, matching the quality_row entries around it - the
    -- key is defined under [description] in locale/en/factory-mk4.cfg, so the
    -- bare form here rendered as "Unknown key" (fixed 0.21.1).
    name = {"description.etech-mk4-tiles-per-connection"},
    value = tostring(math.floor(120 * 120 / 32)),
  },
  quality_row("fluid-transfer-speed", fluid_speed_at),
}

-- Registration ----------------------------------------------------------------

data:extend({
  entity,
  item,
  packed,
  {
    type = "recipe",
    name = NAME,
    enabled = false,
    energy_required = 120,
    ingredients = ingredients,
    results = {{type = "item", name = NAME, amount = 1}},
    main_product = NAME,
    localised_name = {"entity-name." .. NAME},
    categories = data.raw["recipe-category"]["metallurgy"] and {"metallurgy", "crafting"} or nil,
  },
  {
    type = "technology",
    name = "etech-factory-architecture-t4",
    icons = {{
      icon = GFX .. "tech-factory-architecture-4.png",
      icon_size = 256,
    }},
    prerequisites = prerequisites,
    effects = {{type = "unlock-recipe", recipe = NAME}},
    unit = unit,
    -- Factorissimo orders its architecture techs p-q-a-a / a-b / a-c, and its
    -- space architecture tech takes p-q-a-d. Slotting in at "a-c-m" puts
    -- Architecture 4 directly after Architecture 3 and before Space
    -- architecture, instead of stranding it elsewhere in the tree.
    order = "p-q-a-c-m",
  },
})

data:extend(hidden_chests)

-- Space-platform variant -------------------------------------------------------
-- Factorissimo builds space-factory-1/2/3 from a hardcoded per-tier list, so a
-- fourth tier gets none of it. This mirrors what that list produces: the same
-- building with the space skin, gated behind the same setting, unlocked by the
-- same technology.
--
-- The layout itself is registered in factory-mk4/control.lua, because layouts
-- live in Factorissimo's storage rather than in data.raw.

if settings.startup["Factorissimo2-space-architecture"]
  and settings.startup["Factorissimo2-space-architecture"].value
  and data.raw["storage-tank"]["space-factory-3"] then

  local SPACE = "space-" .. NAME
  local space_base = data.raw["storage-tank"]["space-factory-3"]

  local function space_icons()
    return {{icon = GFX .. "icon-factory-4.png", icon_size = 64}}
  end

  local space_entity = table.deepcopy(space_base)
  space_entity.name = SPACE
  space_entity.minable = {mining_time = 0.5, result = SPACE .. "-instantiated", count = 1}
  space_entity.max_health = 8000
  space_entity.map_color = MK4_MAP_COLOR
  space_entity.icon = nil
  space_entity.icons = space_icons()
  -- Layer [1] is the shared shadow, [2] the body - same structure as the
  -- ground tiers. The space bodies are drawn at half resolution with no
  -- `scale`, so only the filename may change here.
  space_entity.pictures.picture.layers[2].filename = GFX .. "space-factory-4.png"
  space_entity.custom_tooltip_fields = table.deepcopy(entity.custom_tooltip_fields)

  local space_item = table.deepcopy(data.raw.item["space-factory-3"])
  space_item.name = SPACE
  space_item.place_result = SPACE
  space_item.order = "a-d"
  space_item.icon = nil
  space_item.icons = space_icons()

  local space_packed = table.deepcopy(data.raw["item-with-tags"]["space-factory-3-instantiated"])
  space_packed.name = SPACE .. "-instantiated"
  space_packed.localised_name = {"item-name.factory-packed", {"entity-name." .. SPACE}}
  space_packed.place_result = SPACE
  space_packed.order = "a-d"
  space_packed.factoriopedia_alternative = SPACE
  space_packed.icon = nil
  space_packed.icons = {
    {icon = GFX .. "icon-factory-4.png", icon_size = 64},
    {icon = "__factorissimo-2-notnotmelon__/graphics/icon/packing-tape.png", icon_size = 64},
  }

  -- Ingredients follow whatever Factorissimo gave space-factory-3 under the
  -- current mod set (Space Exploration and Space Age get completely different
  -- lists), with the Mk3 swapped for a Mk4 and the quantities raised. Copying
  -- rather than writing our own keeps this working under either.
  local space_recipe = table.deepcopy(data.raw.recipe["space-factory-3"])
  space_recipe.name = SPACE
  space_recipe.energy_required = 120
  space_recipe.localised_name = {"entity-name." .. SPACE}
  space_recipe.main_product = SPACE
  space_recipe.results = {{type = "item", name = SPACE, amount = 1}}
  for _, ingredient in pairs(space_recipe.ingredients or {}) do
    if ingredient.name == BASE then
      ingredient.name = NAME
    else
      ingredient.amount = math.min(65535, math.ceil((ingredient.amount or 1) * 1.5))
    end
  end

  data:extend({space_entity, space_item, space_packed, space_recipe})

  -- Unlock it from Factorissimo's own space technology rather than adding a
  -- second one, so the space tier stays a single research like it is now.
  local space_tech = data.raw.technology["factory-space-architecture"]
  if space_tech then
    table.insert(space_tech.effects, {type = "unlock-recipe", recipe = SPACE})
    -- The Mk4 recipe needs a Mk4, so the ground tier has to come first.
    table.insert(space_tech.prerequisites, "etech-factory-architecture-t4")
  else
    log("E-Tech: factory-space-architecture technology missing - " .. SPACE .. " recipe has no unlock.")
  end

  -- Space Exploration decides what may exist in space from the collision mask,
  -- exactly as Factorissimo does for its own three at the end of factory.lua.
  if mods["space-exploration"] then
    local collision_mask_util = require("__core__/lualib/collision-mask-util")
    space_entity.collision_mask = collision_mask_util.get_mask(space_entity)
    space_entity.collision_mask.layers.ground_tile = true
    space_entity.collision_mask.layers.moving_tile = nil
  end
end

-- Tips and tricks entry, suggested once the tech is researched.
data:extend({
  {
    type = "tips-and-tricks-item",
    name = "etech-factory-mk4",
    tag = "[entity=" .. NAME .. "]",
    category = "etech",
    order = "c",
    indent = 1,
    trigger = {
      type = "research",
      technology = "etech-factory-architecture-t4",
    },
  },
})
