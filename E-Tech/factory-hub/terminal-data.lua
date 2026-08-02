-- factory-hub/terminal-data.lua
-- Prototypes for the factory terminal: an armor module (the "factory link")
-- plus the toolbar shortcut that opens the surface-wide device list. Written
-- for E-Tech (public domain). Required from factory-hub/data.lua, so it only
-- exists when Factorissimo and the factory-hub feature are both on.
--
-- WHY AN ARMOR MODULE and not just a technology: a tech is force-wide and
-- free forever once researched. The module costs grid space, and - being a
-- real battery-equipment - it holds a real energy buffer that charges from
-- your armor's generators. Runtime drains it (terminal.lua), so a terminal
-- open on a flat suit stops working. That is the whole design: remote reach
-- into every factory on the surface, paid for in power.
--
-- ART IS PLACEHOLDER: sprite and icons are the base game's battery equipment,
-- tinted with the same orange the outlet/inlet/sensor use. Swap in real art
-- later; nothing else has to change.

local hubTint = { r = 1, g = 0.6, b = 0.15, a = 1 }
local ICON = "__base__/graphics/icons/battery-equipment.png"
-- Held in a local, not written inline: a one-element table holding a bare
-- etech-prefixed string is indistinguishable from a LocalisedString to
-- tools/lint-locale.py, which then reports a missing locale key.
local HUB_TECH = "etech-factory-provider-hub"

local function tinted_icons(icon)
    return {{ icon = icon, icon_size = 64, tint = hubTint }}
end

local equipment = table.deepcopy(data.raw["battery-equipment"]["battery-equipment"])
equipment.name = "etech-factory-link"
equipment.sprite.tint = hubTint
-- 2 MJ: enough for a long session at the drain rates in terminal.lua, small
-- enough that it is not a meaningful battery upgrade in its own right (the
-- vanilla battery it is copied from holds 20 MJ).
equipment.energy_source.buffer_capacity = "2MJ"
equipment.take_result = "etech-factory-link"

local item = table.deepcopy(data.raw["item"]["battery-equipment"])
item.name = "etech-factory-link"
item.icon = nil
item.icons = tinted_icons(ICON)
item.place_as_equipment_result = "etech-factory-link"
item.order = "e[factory-link]"

data:extend({
    equipment,
    item,
    {
        type = "recipe",
        name = "etech-factory-link",
        enabled = false,
        energy_required = 10,
        ingredients = {
            {type = "item", name = "battery-equipment", amount = 1},
            {type = "item", name = "processing-unit", amount = 20},
            {type = "item", name = "advanced-circuit", amount = 20},
            {type = "item", name = "steel-plate", amount = 10},
        },
        results = {{type = "item", name = "etech-factory-link", amount = 1}},
    },
    {
        type = "technology",
        name = "etech-factory-terminal",
        icons = tinted_icons(ICON),
        prerequisites = {HUB_TECH},
        effects = {
            { type = "unlock-recipe", recipe = "etech-factory-link" },
        },
        -- Same cost as the tech it follows; that one already mirrors
        -- logistic-robotics so overhaul mods keep it at their own tier.
        unit = table.deepcopy(data.raw.technology[HUB_TECH].unit),
        order = "c-k-d-f",
    },
    -- The shortcut prototype exists whenever the feature does; the runtime
    -- refuses to open the terminal without the tech AND a charged link, so an
    -- unresearched player just gets told why.
    {
        type = "shortcut",
        name = "etech-factory-terminal",
        order = "z[etech]-b[factory-terminal]",
        action = "lua",
        icons = tinted_icons(ICON),
        small_icons = tinted_icons(ICON),
        localised_name = {"gui-etech-terminal.shortcut-name"},
        localised_description = {"gui-etech-terminal.shortcut-description"},
    },
})
