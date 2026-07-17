-- factory-hub/data.lua
-- Factory provider hub: a passive-provider chest that E-Tech's control stage
-- keeps stocked with items pulled out of the provider chests INSIDE
-- Factorissimo factory buildings on the same surface. Written for E-Tech
-- (public domain). Only loaded when Factorissimo 3 is active (root data.lua
-- checks), so the factory-connection-type-chest tech prerequisite exists.
--
-- Sprite/icon build from the YELLOW storage chest, fully tinted orange —
-- multiplicative tint over the red passive provider gave a muddy brown
-- (0.11.0), and a half-tinted icon that still looked red in hand.

local hubTint = { r = 1, g = 0.6, b = 0.15, a = 1 }

local hubIcons = {
    { icon = "__base__/graphics/icons/storage-chest.png", icon_size = 64, tint = hubTint },
}

local hub = table.deepcopy(data.raw["logistic-container"]["storage-chest"])
hub.name = "etech-factory-provider-hub"
hub.minable.result = "etech-factory-provider-hub"
hub.logistic_mode = "passive-provider"
-- storage-chest carries max_logistic_slots = 1 (its storage filter slot);
-- inherited, it gives the hub filter_slot_count == 1 while not being storage
-- mode, and Filter Helper crashes calling get_filter on it. Drop it.
hub.max_logistic_slots = nil
hub.inventory_size = settings.startup["etech-hub-slots"].value
hub.enable_inventory_bar = false -- per-item caps make the red-X limiter pointless
hub.order = "b[storage]-c[etech-factory-provider-hub]"
hub.icon = nil
hub.icons = hubIcons
if hub.animation and hub.animation.layers then
    hub.animation.layers[1].tint = hubTint
end

local hub_item = table.deepcopy(data.raw.item["storage-chest"])
hub_item.name = "etech-factory-provider-hub"
hub_item.place_result = "etech-factory-provider-hub"
hub_item.order = "b[storage]-c[etech-factory-provider-hub]"
hub_item.icon = nil
hub_item.icons = hubIcons

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
    hub,
    hub_item,
    {
        type = "recipe",
        name = "etech-factory-provider-hub",
        enabled = false,
        energy_required = 5,
        ingredients = {
            {type = "item", name = "passive-provider-chest", amount = 1},
            {type = "item", name = "advanced-circuit", amount = 5},
            {type = "item", name = "steel-plate", amount = 10},
        },
        results = {{type = "item", name = "etech-factory-provider-hub", amount = 1}},
    },
    {
        type = "technology",
        name = "etech-factory-provider-hub",
        icons = {
            { icon = "__base__/graphics/icons/storage-chest.png", icon_size = 64, tint = hubTint },
        },
        prerequisites = prerequisites,
        effects = {
            { type = "unlock-recipe", recipe = "etech-factory-provider-hub" },
        },
        unit = unit,
        order = "c-k-d-e",
    },
})
