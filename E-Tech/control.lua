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

if settings.startup["etech-jetpack-ui"].value
  and script.active_mods["jetpack"]
  and not script.active_mods["puppy-jetpack-ui"] then
  handler.add_lib(require("jetpack-ui"))
end

-- One-time cleanup for saves that ran the short-lived Factorissimo map
-- icons experiment (removed 2026-07-14): drop its tags and storage.
handler.add_lib({
  on_configuration_changed = function()
    local leftover = storage.etech_factorissimo_icons
    if not leftover then return end
    for _, data in pairs (leftover.buildings or {}) do
      local tag = data.tag
      if tag and tag.valid then tag.destroy() end
    end
    storage.etech_factorissimo_icons = nil
  end,
})
