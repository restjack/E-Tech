-- teleporters/shared.lua
-- Prototype names shared between the data stage and control stage.
-- Everything is etech-prefixed so E-Tech can coexist with the original
-- Teleporters mod (whose entity is plain "teleporter").

local shared = {}

shared.entities =
{
  teleporter = "etech-teleporter",
  teleporter_sticker = "etech-teleporter-sticker",
}

shared.explosions =
{
  flash = "etech-teleporter-explosion",
  flash_no_sound = "etech-teleporter-explosion-no-sound",
}

shared.hotkeys =
{
  focus_search = "etech-teleporter-focus-search",
}

return shared
