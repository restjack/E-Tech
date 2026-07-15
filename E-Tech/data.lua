-- data.lua
-- Prototypes E-Tech adds from scratch: the optional teleport-to-player
-- toolbar shortcut, the teleporter pads (teleporters/data.lua), and the
-- absorbed-mod ports (void chest/pipe, map settings editor, colorful
-- biochamber). Field edits on existing prototypes live in data-final-fixes
-- and misc-tweaks. Each port is skipped when its original mod is still
-- enabled so the two never define the same prototype names.

if settings.startup["etech-teleporters"].value then
  require("teleporters/data")
end

if settings.startup["etech-void"].value and not mods["easyvoid"] then
  require("voidchest/data")
end

if settings.startup["etech-map-settings"].value and not mods["EditMapSettings"] then
  require("edit-map-settings/data")
end

if settings.startup["etech-colorful-biochamber"].value
  and mods["space-age"]
  and not mods["colorful_biochamber"] then
  require("biochamber/data")
end

if settings.startup["etech-teleport-shortcut"].value then
  data:extend({
    {
      type = "shortcut",
      name = "etech-teleport-to-player",
      order = "z[etech]-a[teleport]",
      action = "lua",
      icon = "__base__/graphics/icons/spidertron-remote.png",
      icon_size = 64,
      small_icon = "__base__/graphics/icons/spidertron-remote.png",
      small_icon_size = 64,
      localised_name = {"", "Teleport to player"},
      localised_description = {"", "Teleport to another player. One other player online: teleports straight to them. Several: opens a picker."},
    },
  })
end
