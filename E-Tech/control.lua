-- control.lua
-- Registers the runtime modules via the base game's event_handler library,
-- which lets several modules listen to the same events (plain
-- script.on_event would overwrite handlers between modules).
--
--   teleport-player.lua   - teleport-to-player toolbar shortcut
--   teleporters/control.lua - teleporter pads (only when the setting is on;
--                             prototypes don't exist otherwise)
--   resource-markers.lua  - automatic map markers on resource patches

local handler = require("event_handler")

handler.add_lib(require("teleport-player"))

if settings.startup["etech-teleporters"].value then
  handler.add_lib(require("teleporters/control"))
end

if settings.startup["etech-resource-markers"].value then
  handler.add_lib(require("resource-markers"))
end
