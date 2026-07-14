-- data.lua
-- Only prototype E-Tech adds from scratch: the optional teleport-to-player
-- toolbar shortcut (runtime logic in control.lua). Everything else the mod
-- does is field edits on existing prototypes and lives in data-final-fixes.

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
