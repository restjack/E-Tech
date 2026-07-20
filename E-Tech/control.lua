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

if settings.startup["etech-factory-hub"].value
  and script.active_mods["factorissimo-2-notnotmelon"] then
  handler.add_lib(require("factory-hub/control"))
end

if settings.startup["etech-resource-markers"].value then
  handler.add_lib(require("resource-markers"))
end

-- AAI seeds new freeplay games with 24 motors in the ship debris; with K2
-- the motor is retired (see data-final-fixes), so hand out iron gears
-- instead. on_init only fires on new games, and E-Tech's runs after AAI's
-- (load order), so AAI has already set its debris list by then.
if script.active_mods["aai-industry"] and script.active_mods["Krastorio2"] then
  handler.add_lib({
    on_init = function()
      local freeplay = remote.interfaces["freeplay"]
      if not (freeplay and freeplay["get_debris_items"]) then return end
      local debris = remote.call("freeplay", "get_debris_items") or {}
      if debris["motor"] then
        debris["iron-gear-wheel"] = (debris["iron-gear-wheel"] or 0) + debris["motor"]
        debris["motor"] = nil
        remote.call("freeplay", "set_debris_items", debris)
      end
    end,
  })
end

if settings.startup["etech-jetpack-ui"].value
  and script.active_mods["jetpack"]
  and not script.active_mods["puppy-jetpack-ui"] then
  handler.add_lib(require("jetpack-ui"))
end

-- One-time save cleanups live in migrations/ (run once per save by the
-- engine, unlike on_configuration_changed which fires on every mod-set
-- change).
