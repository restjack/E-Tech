-- voidchest/data.lua
-- Void chest (eats items) + void pipe (eats fluids) prototypes, ported from
-- the abandoned Easy Void mod (see LICENSE-third-party.txt). Prototype names
-- (void-chest, void-pipe, tech "void") are kept IDENTICAL to Easy Void so
-- entities already placed in a save survive the switch to E-Tech.
-- Gated by the etech-void startup setting; skipped when the original mod is
-- still enabled (data.lua checks) so the two never define the same names.
--
-- Credits to JDOGG, Optera, kendfrey, Rseding91 for their original void mods.

-- Colour comes from one hex string since 0.21.1 (was three 0-1 sliders).
-- Accepts "BF00FF", "#BF00FF" or "bf00ff"; anything else falls back to the
-- default and says so in the log rather than shipping a black chest.
local DEFAULT_VOID_TINT = "BF00FF"

local function parse_hex_tint(text)
    local hex = tostring(text or ""):gsub("^#", ""):gsub("%s", "")
    if #hex ~= 6 or hex:find("[^0-9A-Fa-f]") then return nil end
    return {
        r = tonumber(hex:sub(1, 2), 16) / 255,
        g = tonumber(hex:sub(3, 4), 16) / 255,
        b = tonumber(hex:sub(5, 6), 16) / 255,
        a = 1,
    }
end

local configured = settings.startup["etech-void-tint"].value
local voidTint = parse_hex_tint(configured)
if not voidTint then
    log("[E-Tech] void tint " .. tostring(configured)
        .. " is not a 6-digit hex colour - using " .. DEFAULT_VOID_TINT)
    voidTint = parse_hex_tint(DEFAULT_VOID_TINT)
end

local function tintPictures(pictures, tint)
    for _, picture in pairs(pictures) do
        picture.tint = tint;
    end
end

-- entities ------------------------------------------------------------------

local void_pipe = table.deepcopy(data.raw["pipe"]["pipe"])
void_pipe.type = "infinity-pipe"
void_pipe.name = "void-pipe"
void_pipe.minable.result = "void-pipe"
void_pipe.gui_mode = "none"
-- 2.0 replaced the 1.1-era height/base_area pair with a single `volume`. The
-- old fields were silently ignored, so the pipe had been running on vanilla's
-- buffer since the port (fixed 0.21.1). 1 x 2500 was the original intent.
void_pipe.fluid_box.volume = 2500
void_pipe.pictures = table.deepcopy(data.raw["pipe"]["pipe"].pictures)
tintPictures(void_pipe.pictures, voidTint)

local void_chest = table.deepcopy(data.raw["container"]["iron-chest"])
void_chest.type = "infinity-container"
void_chest.name = "void-chest"
void_chest.minable.result = "void-chest"
void_chest.order = "a[items]-c[void-chest]"
void_chest.erase_contents_when_mined = true
void_chest.logistic_mode = nil
void_chest.gui_mode = "none"
void_chest.inventory_size = settings.startup["etech-void-slots"].value
void_chest.circuit_wire_max_distance = 0
void_chest.enable_inventory_bar = false
void_chest.picture.layers[1].tint = voidTint

-- items ---------------------------------------------------------------------

local void_pipe_item = table.deepcopy(data.raw.item["pipe"])
void_pipe_item.name = "void-pipe"
void_pipe_item.place_result = "void-pipe"
void_pipe_item.order = void_pipe_item.order .. "a"
void_pipe_item.icon = nil
void_pipe_item.icons = {
    { icon = "__base__/graphics/icons/pipe.png", icon_size = 64 },
    { icon = "__base__/graphics/icons/pipe.png", icon_size = 64, tint = voidTint },
}

local void_chest_item = table.deepcopy(data.raw.item["iron-chest"])
void_chest_item.name = "void-chest"
void_chest_item.place_result = "void-chest"
void_chest_item.order = "a[items]-c[void-chest]"
void_chest_item.icon = nil
void_chest_item.icons = {
    { icon = "__base__/graphics/icons/iron-chest.png", icon_size = 64 },
    { icon = "__base__/graphics/icons/iron-chest.png", icon_size = 64, tint = voidTint },
}

-- Filtered void chest (optional): opens like an infinity chest so the
-- player picks WHICH items get destroyed (set a filter to "exactly 0" for
-- each item to void); everything else just sits. E-Tech addition on top of
-- the Easy Void port.
local filtered = {}
if settings.startup["etech-void-filtered"].value then
    local filteredTint = {
        r = voidTint.r,
        g = math.min(1, voidTint.g + 0.5),
        b = voidTint.b,
        a = 1
    }
    local void_chest_filtered = table.deepcopy(void_chest)
    void_chest_filtered.name = "void-chest-filtered"
    void_chest_filtered.minable.result = "void-chest-filtered"
    void_chest_filtered.order = "a[items]-c[void-chest-b]"
    void_chest_filtered.gui_mode = "all"
    -- The plain void chest erases on mine because everything in it is doomed
    -- anyway. The filtered one is the opposite: its whole point is that items
    -- you did NOT pick just sit there safely - so mining it must hand them
    -- back, not delete them (fixed 0.21.1; inherited from the deepcopy above).
    void_chest_filtered.erase_contents_when_mined = false
    void_chest_filtered.picture.layers[1].tint = filteredTint

    local void_chest_filtered_item = table.deepcopy(void_chest_item)
    void_chest_filtered_item.name = "void-chest-filtered"
    void_chest_filtered_item.place_result = "void-chest-filtered"
    void_chest_filtered_item.order = "a[items]-c[void-chest-b]"
    void_chest_filtered_item.icons[2].tint = filteredTint

    filtered = {
        void_chest_filtered,
        void_chest_filtered_item,
        {
            type = "recipe",
            name = "void-chest-filtered",
            enabled = false,
            ingredients =
            {
                {type = "item", name = "iron-chest", amount = 1},
                {type = "item", name = "stone-furnace", amount = 1},
                {type = "item", name = "electronic-circuit", amount = 1}
            },
            results = {{type="item", name="void-chest-filtered", amount=1}},
        },
    }
end

-- recipes + technology ------------------------------------------------------

data:extend({
    void_pipe,
    void_chest,
    void_pipe_item,
    void_chest_item,
    {
        type = "recipe",
        name = "void-pipe",
        enabled = false,
        ingredients =
        {
            {type = "item", name = "pipe", amount = 1},
            {type = "item", name = "stone-furnace", amount = 1}
        },
        results = {{type="item", name="void-pipe", amount=1}},
    },
    {
        type = "recipe",
        name = "void-chest",
        enabled = false,
        ingredients =
        {
            {type = "item", name = "iron-chest", amount = 1},
            {type = "item", name = "stone-furnace", amount = 1}
        },
        results = {{type="item", name="void-chest", amount=1}},
    },
    {
        type = "technology",
        name = "void",
        icon = "__E-Tech__/voidchest/void-technology.png",
        icon_size = 128,
        prerequisites = {
            "fluid-handling",
        },
        effects =
        {
            { type = "unlock-recipe", recipe = "void-pipe" },
            { type = "unlock-recipe", recipe = "void-chest" },
        },
        unit =
        {
            time = 30,
            count = 10,
            ingredients =
            {
                {"automation-science-pack", 1},
            },
        },
        order = "c-a",
    },
})

if #filtered > 0 then
    data:extend(filtered)
    table.insert(data.raw.technology["void"].effects,
        { type = "unlock-recipe", recipe = "void-chest-filtered" })
end
