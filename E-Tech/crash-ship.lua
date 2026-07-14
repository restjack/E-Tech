-- crash-ship.lua
-- Best-effort: make the crashed-ship parts minable and give each a placement
-- item, so they can be picked up and put back down.
--
-- The freeplay crash site is built from a family of entity prototypes whose
-- names start with "crash-site-spaceship". We scan ALL entity types for that
-- prefix so we don't depend on their exact prototype type (base vs Space Age
-- may differ), and guard everything with existence checks.
--
-- NOTE: this is intentionally conservative. If a given part refuses to be
-- placed in-game, check factorio-current.log for the "[E-Tech]" lines this
-- prints, and tell me which prototype names showed up.

local PREFIX = "crash-site-spaceship"
local FALLBACK_ICON = "__base__/graphics/icons/steel-chest.png"
local FALLBACK_ICON_SIZE = 64

local new_items = {}
local touched = 0

for _, prototypes in pairs(data.raw) do
  if type(prototypes) == "table" then
    for name, proto in pairs(prototypes) do
      -- Only real entity prototypes have a collision/selection box; that also
      -- keeps us from matching an item or recipe of the same name.
      if type(name) == "string"
         and name:sub(1, #PREFIX) == PREFIX
         and proto.selection_box ~= nil then

        local item_name = "etech-" .. name

        -- Make the entity minable, returning the placement item.
        proto.minable = {
          mining_time = 1,
          result = item_name,
          count = 1,
        }
        -- Help pipette / blueprints resolve the item.
        proto.placeable_by = {item = item_name, count = 1}

        -- Ensure it can be placed by the player. Drop flags that would block it.
        proto.flags = proto.flags or {}
        local keep = {}
        for _, flag in pairs(proto.flags) do
          if flag ~= "not-deconstructable"
             and flag ~= "not-blueprintable"
             and flag ~= "not-selectable-in-game" then
            keep[#keep + 1] = flag
          end
        end
        keep[#keep + 1] = "player-creation"
        proto.flags = keep

        -- Reuse the entity's own icon if it has one, else fall back.
        local icon = proto.icon
        local icons = proto.icons
        if not icon and not icons then
          icon = FALLBACK_ICON
        end

        new_items[#new_items + 1] = {
          type = "item",
          name = item_name,
          localised_name = {"", "Crashed ship part (", name, ")"},
          icon = icon,
          icons = icons,
          icon_size = proto.icon_size or FALLBACK_ICON_SIZE,
          subgroup = "other",
          order = "z[crash-ship]-" .. name,
          stack_size = 10,
          place_result = name,
        }
        touched = touched + 1
        log("[E-Tech] crashed-ship part made minable+placeable: '" .. name .. "'")
      end
    end
  end
end

if #new_items > 0 then
  data:extend(new_items)
end
log("[E-Tech] crashed-ship parts processed: " .. touched)
