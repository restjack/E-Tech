-- control.lua
-- Registers the runtime modules via the base game's event_handler library,
-- which lets several modules listen to the same events (plain
-- script.on_event would overwrite handlers between modules).
--
--   teleport-player.lua   - teleport-to-player toolbar shortcut
--   teleporters/control.lua - teleporter pads (only when the setting is on;
--                             prototypes don't exist otherwise)
--   resource-markers.lua  - automatic map markers on resource patches
--   voidchest/control.lua - void chest/pipe port (Easy Void)
--   edit-map-settings/control.lua - map settings editor port (Edit Map Settings)

local handler = require("event_handler")

handler.add_lib(require("teleport-player"))

if settings.startup["etech-teleporters"].value then
  handler.add_lib(require("teleporters/control"))
end

if settings.startup["etech-void"].value
  and not script.active_mods["easyvoid"] then
  handler.add_lib(require("voidchest/control"))
end

if settings.startup["etech-map-settings"].value
  and not script.active_mods["EditMapSettings"] then
  handler.add_lib(require("edit-map-settings/control"))
end

if settings.startup["etech-copy-paste-modules"].value
  and not script.active_mods["CopyPasteModules"] then
  handler.add_lib(require("copy-paste-modules"))
end

if settings.startup["etech-resource-markers"].value then
  handler.add_lib(require("resource-markers"))
end

if settings.startup["etech-jetpack-ui"].value
  and script.active_mods["jetpack"]
  and not script.active_mods["puppy-jetpack-ui"] then
  handler.add_lib(require("jetpack-ui"))
end

-- One-time save cleanups live in migrations/ (run once per save by the
-- engine, unlike on_configuration_changed which fires on every mod-set
-- change).
