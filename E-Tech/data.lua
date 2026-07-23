-- data.lua
-- Prototypes E-Tech adds from scratch: the optional teleport-to-player
-- toolbar shortcut, the teleporter pads (teleporters/data.lua), and the
-- absorbed-mod ports (void chest/pipe, map settings editor, colorful
-- biochamber). Field edits on existing prototypes live in data-final-fixes
-- and misc-tweaks. Each port is skipped when its original mod is still
-- enabled so the two never define the same prototype names.
--
-- Convention: "is mod X present" checks use `mods[...]` in the data stage
-- and `script.active_mods[...]` in the control stage - same information,
-- different API per stage. Keep any new guard in BOTH stages when a feature
-- spans them.

-- Teleport sound, heard by the teleporting player themselves (the world
-- flash's sound plays at the destination before arrival, inaudible
-- cross-surface). Defined unconditionally: both the pad GUI and the
-- teleport-to-player shortcut use it, and each can be enabled alone.
data:extend({
  {
    type = "sound",
    name = "etech-teleporter-sound",
    filename = "__E-Tech__/teleporters/graphics/teleporter-explosion.ogg",
    volume = 0.6,
  },
})

-- Tips and tricks: an E-Tech category with an always-unlocked overview
-- entry (the category header). Feature entries are added next to their
-- prototypes (e.g. factory-hub/data.lua) so they only exist when the
-- feature does. Text lives in locale [tips-and-tricks-item-description].
data:extend({
  {
    type = "tips-and-tricks-item-category",
    name = "etech",
    order = "z-[etech]",
  },
  {
    type = "tips-and-tricks-item",
    name = "etech-overview",
    category = "etech",
    order = "a",
    is_title = true,
    starting_status = "unlocked",
  },
})

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

if settings.startup["etech-factory-hub"].value
  and mods["factorissimo-2-notnotmelon"] then
  require("factory-hub/data")
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
      localised_name = {"etech-tp2p-shortcut-name"},
      localised_description = {"etech-tp2p-shortcut-description"},
    },
  })
end
