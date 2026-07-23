-- factory-hub/data.lua
-- Factory outlet (+ inlet + sensor): logistics across the Factorissimo
-- surface boundary. Written for E-Tech (public domain). Only loaded when
-- Factorissimo 3 is active (root data.lua checks), so factory-1 and the
-- factory-connection-type-chest tech exist.
--
--   Factory outlet  - passive provider kept stocked with items pulled out of
--                     the provider chests inside factories on its surface.
--   Factory inlet   - requester chest whose contents get distributed INTO
--                     the requester/buffer chests inside those factories.
--   Factory sensor  - constant combinator broadcasting the totals sitting in
--                     the factories' provider chests as circuit signals.
--
-- 2.1 GOTCHA (cost us a yellow chest in 0.12.x): logistic containers keep
-- their sprite in robot_door.animation.layers, NOT in a top-level animation
-- field. Tints are applied without existence guards on purpose - if a future
-- game version moves the sprites again this file should ERROR at load, not
-- silently ship untinted chests.

local hubTint = { r = 1, g = 0.6, b = 0.15, a = 1 }

local function tinted_icons(icon)
    return {{ icon = icon, icon_size = 64, tint = hubTint }}
end

local function build_chest(base_name, name, icon)
    local chest = table.deepcopy(data.raw["logistic-container"][base_name])
    chest.name = name
    chest.minable.result = name
    chest.order = "b[storage]-c[" .. name .. "]"
    chest.icon = nil
    chest.icons = tinted_icons(icon)
    chest.robot_door.animation.layers[1].tint = hubTint

    local item = table.deepcopy(data.raw.item[base_name])
    item.name = name
    item.place_result = name
    item.order = "b[storage]-c[" .. name .. "]"
    item.icon = nil
    item.icons = tinted_icons(icon)
    return chest, item
end

-- Factory outlet -------------------------------------------------------------

local outlet, outlet_item = build_chest("storage-chest",
    "etech-factory-provider-hub", "__base__/graphics/icons/storage-chest.png")
outlet.logistic_mode = "passive-provider"
-- storage-chest's storage-filter slot; inherited it gives filter_slot_count
-- == 1 without storage mode and Filter Helper crashes calling get_filter.
outlet.max_logistic_slots = nil
outlet.inventory_size = 200 -- fixed since 0.17.0 (was the etech-hub-slots setting)
outlet.enable_inventory_bar = false -- per-item caps make the red-X limiter pointless
outlet.trash_inventory_size = nil

-- Factory inlet ---------------------------------------------------------------

local inlet, inlet_item = build_chest("requester-chest",
    "etech-factory-inlet", "__base__/graphics/icons/requester-chest.png")
inlet.inventory_size = 200 -- fixed since 0.17.0 (was the etech-hub-slots setting)
inlet.enable_inventory_bar = false

-- Factory fluid outlet / inlet ------------------------------------------------
-- Storage-tank copies bridging FLUIDS across the factory wall (0.19.0):
-- the fluid outlet fills itself from storage tanks inside the factories,
-- the fluid inlet drains itself into them. One fluid per device at a time.

local function build_tank(name)
    local tank = table.deepcopy(data.raw["storage-tank"]["storage-tank"])
    tank.name = name
    tank.minable.result = name
    tank.icon = nil
    tank.icons = tinted_icons("__base__/graphics/icons/storage-tank.png")
    tank.pictures.picture.sheets[1].tint = hubTint

    local item = table.deepcopy(data.raw.item["storage-tank"])
    item.name = name
    item.place_result = name
    item.order = item.order .. "-" .. name
    item.icon = nil
    item.icons = tinted_icons("__base__/graphics/icons/storage-tank.png")
    return tank, item
end

local fluid_outlet, fluid_outlet_item = build_tank("etech-factory-fluid-outlet")
local fluid_inlet, fluid_inlet_item = build_tank("etech-factory-fluid-inlet")

-- Factory sensor --------------------------------------------------------------

local sensor = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
sensor.name = "etech-factory-sensor"
sensor.minable.result = "etech-factory-sensor"
sensor.icon = nil
sensor.icons = tinted_icons("__base__/graphics/icons/constant-combinator.png")
for _, direction in pairs({"north", "east", "south", "west"}) do
    sensor.sprites[direction].layers[1].tint = hubTint
end

local sensor_item = table.deepcopy(data.raw.item["constant-combinator"])
sensor_item.name = "etech-factory-sensor"
sensor_item.place_result = "etech-factory-sensor"
sensor_item.order = sensor_item.order .. "-etech"
sensor_item.icon = nil
sensor_item.icons = tinted_icons("__base__/graphics/icons/constant-combinator.png")

-- Recipes + technology --------------------------------------------------------
-- (the hidden "etech-hub-energy" buffer entity from the removed
-- energy-per-item setting is gone; the engine deletes any leftovers in old
-- saves when the prototype disappears)

-- Research cost mirrors logistic-robotics so the unlock lands at the same
-- science tier no matter which overhaul (K2 etc.) rewrote that tech.
local robotics = data.raw.technology["logistic-robotics"]
local unit = robotics and table.deepcopy(robotics.unit) or {
    time = 30,
    count = 250,
    ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
    },
}

local prerequisites = {"logistic-robotics"}
if data.raw.technology["factory-connection-type-chest"] then
    table.insert(prerequisites, "factory-connection-type-chest")
end

data:extend({
    outlet, outlet_item,
    inlet, inlet_item,
    sensor, sensor_item,
    fluid_outlet, fluid_outlet_item,
    fluid_inlet, fluid_inlet_item,
    {
        type = "recipe",
        name = "etech-factory-fluid-outlet",
        enabled = false,
        energy_required = 10,
        ingredients = {
            {type = "item", name = "factory-1", amount = 1},
            {type = "item", name = "storage-tank", amount = 1},
            {type = "item", name = "advanced-circuit", amount = 20},
            {type = "item", name = "processing-unit", amount = 10},
            {type = "item", name = "steel-plate", amount = 25},
        },
        results = {{type = "item", name = "etech-factory-fluid-outlet", amount = 1}},
    },
    {
        type = "recipe",
        name = "etech-factory-fluid-inlet",
        enabled = false,
        energy_required = 10,
        ingredients = {
            {type = "item", name = "factory-1", amount = 1},
            {type = "item", name = "storage-tank", amount = 1},
            {type = "item", name = "advanced-circuit", amount = 20},
            {type = "item", name = "processing-unit", amount = 10},
            {type = "item", name = "steel-plate", amount = 25},
        },
        results = {{type = "item", name = "etech-factory-fluid-inlet", amount = 1}},
    },
    {
        type = "recipe",
        name = "etech-factory-provider-hub",
        enabled = false,
        energy_required = 10,
        ingredients = {
            {type = "item", name = "factory-1", amount = 1},
            {type = "item", name = "passive-provider-chest", amount = 1},
            {type = "item", name = "advanced-circuit", amount = 20},
            {type = "item", name = "processing-unit", amount = 10},
            {type = "item", name = "steel-plate", amount = 25},
        },
        results = {{type = "item", name = "etech-factory-provider-hub", amount = 1}},
    },
    {
        type = "recipe",
        name = "etech-factory-inlet",
        enabled = false,
        energy_required = 10,
        ingredients = {
            {type = "item", name = "factory-1", amount = 1},
            {type = "item", name = "requester-chest", amount = 1},
            {type = "item", name = "advanced-circuit", amount = 20},
            {type = "item", name = "processing-unit", amount = 10},
            {type = "item", name = "steel-plate", amount = 25},
        },
        results = {{type = "item", name = "etech-factory-inlet", amount = 1}},
    },
    {
        type = "recipe",
        name = "etech-factory-sensor",
        enabled = false,
        energy_required = 5,
        ingredients = {
            {type = "item", name = "constant-combinator", amount = 1},
            {type = "item", name = "advanced-circuit", amount = 5},
            {type = "item", name = "steel-plate", amount = 5},
        },
        results = {{type = "item", name = "etech-factory-sensor", amount = 1}},
    },
    {
        type = "technology",
        name = "etech-factory-provider-hub",
        icons = tinted_icons("__base__/graphics/icons/storage-chest.png"),
        prerequisites = prerequisites,
        effects = {
            { type = "unlock-recipe", recipe = "etech-factory-provider-hub" },
            { type = "unlock-recipe", recipe = "etech-factory-inlet" },
            { type = "unlock-recipe", recipe = "etech-factory-sensor" },
            { type = "unlock-recipe", recipe = "etech-factory-fluid-outlet" },
            { type = "unlock-recipe", recipe = "etech-factory-fluid-inlet" },
        },
        unit = unit,
        order = "c-k-d-e",
    },
    -- Tips and tricks entry, suggested once the tech is researched
    {
        type = "tips-and-tricks-item",
        name = "etech-factory-outlet",
        tag = "[entity=etech-factory-provider-hub]",
        category = "etech",
        order = "b",
        indent = 1,
        trigger = {
            type = "research",
            technology = "etech-factory-provider-hub",
        },
    },
})
