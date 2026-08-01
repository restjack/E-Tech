-- factory-mk4/control.lua
-- Registers the Mk4 layout with Factorissimo. Only added when the setting is
-- on AND Factorissimo 3 is active (root control.lua checks).
--
-- HOW THIS WORKS. Factorissimo keeps its layouts in ITS OWN `storage`, not in
-- data.raw, and exposes remote.call("factorissimo", "add_layout", table).
-- add_layout does `storage.layout_generators = storage.layout_generators or {}`
-- and then writes a single named entry, so it is safe to call at any point and
-- safe to call repeatedly.
--
-- WHY on_init AND on_configuration_changed. Factorissimo's own reload_layouts()
-- runs on both (its lib/events.lua maps its on_init pseudo-event to
-- script.on_init AND script.on_configuration_changed). That function rewrites
-- only ITS OWN names into the same table, so a foreign entry is not wiped -
-- but the reverse matters: our entry has to be re-added whenever the mod set
-- changes, because it only exists if we put it there.
--
-- Not on_load: writing to `storage` during on_load desyncs multiplayer, and it
-- is not needed - the registration lives in the save.
--
-- IF REGISTRATION EVER FAILS, every placed Mk4 has no layout and the buildings
-- break. So this shouts rather than degrading quietly: it verifies with
-- has_layout afterwards and reports to the log AND to chat.

local layout = require("factory-mk4/layout")

local RELAY = "etech-factory-mk4-power-relay"

-- Hidden power relay ---------------------------------------------------------
-- Called by Factorissimo itself: the layout's `upgrades` list names
-- ("etech-factory-mk4", "build_power_relay"), and build_factory_upgrades()
-- does remote.call(mod, fn, factory) for any entry that is not its own. That
-- happens when a factory is built, for every existing factory on on_init and
-- on_configuration_changed, and on every research finish - so this repairs
-- itself and needs no event handlers. It must therefore be idempotent.
--
-- What it does: builds an invisible pole at the interior centre and wires it
-- to the pole Factorissimo put at the door. The door pole has
-- supply_area_distance 63 and the engine caps that at 64, so from the door
-- nothing can reach the far side of a 120-wide floor. This keeps the visible
-- pole and roboport at the entrance while the electricity actually comes from
-- the middle.
local function build_power_relay(factory)
  if not (factory and factory.inside_surface and factory.inside_surface.valid) then return end
  if not (factory.force and factory.force.valid) then return end

  local surface = factory.inside_surface
  local position = {factory.inside_x, factory.inside_y}

  -- No bookkeeping in E-Tech's storage and nothing written into
  -- Factorissimo's factory table: just ask the surface. Cheap, because this
  -- only runs on the events above, and it cannot go stale.
  local relay = surface.find_entities_filtered {name = RELAY, position = position}[1]
  if not relay then
    relay = surface.create_entity {
      name = RELAY,
      position = position,
      force = factory.force,
    }
    if not relay then
      local message = "[E-Tech] Factory Mk4: could not create the interior power relay at "
        .. surface.name .. " " .. factory.inside_x .. "," .. factory.inside_y
        .. " - the far half of that factory will have no power."
      log(message)
      if game then game.print(message) end
      return
    end
    relay.destructible = false
    relay.operable = false
    relay.rotatable = false
  end

  -- Wire it to the door pole. Factorissimo's own interior pole is created
  -- lazily, so this can legitimately find nothing on an early call - the next
  -- pass picks it up.
  --
  -- `_inside_power_pole` is a PRIVATE field of Factorissimo's factory table
  -- (leading underscore and all), and there is no public accessor for it. If a
  -- future Factorissimo renames it this silently returns forever and the far
  -- half of every Mk4 loses power with nothing in the log to explain it - so
  -- say it once (0.21.1). Once per session is enough: this runs on every
  -- research finish.
  local pole = factory._inside_power_pole
  if not (pole and pole.valid) then
    if factory.built and not storage.etech_mk4_warned_no_pole then
      storage.etech_mk4_warned_no_pole = true
      log("[E-Tech] Factory Mk4: Factorissimo's interior power pole"
        .. " (factory._inside_power_pole) was not available for factory "
        .. tostring(factory.id) .. ". If Mk4 floors are losing power in their"
        .. " northern half, Factorissimo may have renamed that field.")
    end
    return
  end

  local a = relay.get_wire_connector(defines.wire_connector_id.pole_copper, true)
  local b = pole.get_wire_connector(defines.wire_connector_id.pole_copper, true)
  if not (a and b) then return end

  -- Called unconditionally rather than after an "already connected?" test:
  -- connecting an existing connection is a no-op, and this runs on research
  -- finishes where a needless check would cost more than the call.
  --
  -- wire_origin.script is what lets this ignore wire reach - the same call
  -- Factorissimo uses to bridge a factory's interior to the outside surface,
  -- which is a different surface entirely.
  a.connect_to(b, false, defines.wire_origin.script)
end

remote.add_interface("etech-factory-mk4", {build_power_relay = build_power_relay})

local mk4 = {}

local function register()
  local factorissimo = remote.interfaces["factorissimo"]

  if not (factorissimo and factorissimo["add_layout"]) then
    local message = "[E-Tech] Factory Mk4: Factorissimo's add_layout remote interface is missing."
      .. " The Mk4 layout could NOT be registered - do not place any Mk4 factory buildings."
    log(message)
    if game then game.print(message) end
    return
  end

  remote.call("factorissimo", "add_layout", layout)

  -- Space-platform twin. Factorissimo builds its own with make_space_layout():
  -- deepcopy, swap every tile for its space counterpart, set surface_override.
  -- That function is local to its control stage, so this repeats it. Only
  -- registered when the space prototypes actually exist - the tiles and the
  -- entity are behind Factorissimo's space architecture startup setting.
  if prototypes.entity["space-factory-4"] and prototypes.tile["space-factory-wall-4"] then
    local space_tiles = {
      ["factory-wall-4"] = "space-factory-wall-4",
      ["factory-pattern-4"] = "space-factory-pattern-4",
      ["factory-floor"] = "space-factory-floor",
      ["factory-entrance"] = "space-factory-entrance",
    }
    local space = table.deepcopy(layout)
    space.name = "space-factory-4"
    for _, rect in pairs(space.rectangles) do
      rect.tile = space_tiles[rect.tile] or rect.tile
    end
    for _, mosaic in pairs(space.mosaics) do
      mosaic.tile = space_tiles[mosaic.tile] or mosaic.tile
    end
    space.connection_tile = space_tiles[space.connection_tile] or space.connection_tile
    space.surface_override = "space-factory-floor"
    remote.call("factorissimo", "add_layout", space)
  end

  -- Confirm it actually landed. add_layout has no return value, and a silent
  -- failure here is the difference between a working tier and broken buildings.
  if factorissimo["has_layout"] and not remote.call("factorissimo", "has_layout", layout.name) then
    local message = "[E-Tech] Factory Mk4: registered the " .. layout.name
      .. " layout but Factorissimo does not report it. Do not place any Mk4 factory buildings."
    log(message)
    if game then game.print(message) end
    return
  end

  log("[E-Tech] Factory Mk4: registered layout " .. layout.name
    .. " (" .. layout.inside_size .. "x" .. layout.inside_size .. " interior).")

  -- Factorissimo blacklists its own tiers from Picker Dollies (compat/
  -- picker-dollies.lua) because dragging a factory building would strand its
  -- interior. Same applies here, and that list is per-name.
  if remote.interfaces["PickerDollies"] then
    remote.call("PickerDollies", "add_blacklist_name", layout.name, true)
  end
end

mk4.on_init = register
mk4.on_configuration_changed = register

return mk4
