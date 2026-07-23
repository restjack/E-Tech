-- jetpack-ui.lua
-- Small fuel HUD while flying a jetpack: current fuel item + inventory
-- count, a burn progressbar, and an estimated remaining-flight time based
-- on measured consumption. Talks to the jetpack mod via its remote
-- interface; only loaded when the etech-jetpack-ui setting is on, the
-- jetpack mod is present, and the original puppy-jetpack-ui is absent
-- (guards in control.lua).
--
-- Adapted from "Puppy's Jetpack UI" 0.2.x by Puppy (MIT — see
-- LICENSE-third-party.txt). Changes from the original: flib dependency
-- removed (plain gui construction), etech- element names, and the window
-- position bug fixed — the original discarded the saved position when it
-- looked off-screen against player.display_resolution, which reports a
-- stale default during the first ticks after joining a server, resetting
-- the window every session. We always restore the saved position and
-- instead clamp it into view on the display-resolution/scale events, when
-- the values are real.

local WINDOW = "etech-jetpack-ui"

local script_data =
{
  -- [player_index] = {location, gui = {frame, icon, count, bar, time},
  --                   remaining_energy, synced_tick, estimated_consumption,
  --                   item_name}
  players = {},
}

local fuel_value_cache

local get_state = function(player_index)
  local state = script_data.players[player_index]
  if not state then
    state = {}
    script_data.players[player_index] = state
  end
  return state
end

local close_window = function(player, state)
  local frame = player.gui.screen[WINDOW]
  if frame then frame.destroy() end
  state.gui = nil
  -- fresh consumption estimate per flight — a tick delta measured across
  -- the gap between flights makes consumption look tiny and the remaining
  -- time absurdly long
  state.remaining_energy = nil
  state.synced_tick = nil
  state.estimated_consumption = nil
end

local render_time = function(seconds)
  seconds = math.floor(seconds)
  if seconds < 60 then
    return {"time-symbol-seconds-short", seconds}
  end
  local minutes = math.floor(seconds / 60)
  if minutes < 60 then
    return {"", {"time-symbol-minutes-short", minutes}, " ", {"time-symbol-seconds-short", seconds % 60}}
  end
  local hours = math.floor(seconds / 3600)
  return {"", {"time-symbol-hours-short", hours}, " ", {"time-symbol-minutes-short", minutes % 60}, " ", {"time-symbol-seconds-short", seconds % 60}}
end

local ensure_window = function(player, state)
  local existing = player.gui.screen[WINDOW]
  if existing and state.gui and state.gui.frame and state.gui.frame.valid then return end
  if existing then existing.destroy() end

  local frame = player.gui.screen.add{type = "frame", name = WINDOW, direction = "horizontal"}
  -- match the width of the weapon/quickbar panel so the HUD lines up with
  -- the gun slots it usually sits above
  frame.style.width = 180
  local handle = frame.add{type = "empty-widget", style = "draggable_space"}
  handle.style.width = 8
  handle.style.height = 45
  handle.drag_target = frame

  local column = frame.add{type = "flow", direction = "vertical"}
  local row = column.add{type = "flow", direction = "horizontal"}
  row.style.vertical_align = "center"
  local icon = row.add{type = "sprite", resize_to_sprite = false}
  icon.style.width = 16
  icon.style.height = 16
  local count = row.add{type = "label"}
  local bar = row.add{type = "progressbar"}
  bar.style.color = {r = 1, g = 0.667, b = 0.2}
  bar.style.horizontally_stretchable = true
  local time = column.add{type = "label"}

  state.gui = {frame = frame, icon = icon, count = count, bar = bar, time = time}

  -- Always restore the saved position. If it drifted off-screen (resolution
  -- change), the display-resolution/scale handlers clamp it — deliberately
  -- NOT checked here, where display_resolution can still be a stale default.
  if state.location then
    frame.location = state.location
  else
    frame.location = {0, player.display_resolution.height - math.floor(135 * player.display_scale)}
  end
end

local get_fuel_values = function()
  if fuel_value_cache then return fuel_value_cache end
  fuel_value_cache = {}
  local ok, fuels = pcall(remote.call, "jetpack", "get_fuels", {})
  if ok and fuels then
    for _, fuel in pairs (fuels) do
      local proto = prototypes.item[fuel.fuel_name]
      if proto then
        fuel_value_cache[fuel.fuel_name] = proto.fuel_value
      end
    end
  end
  return fuel_value_cache
end

local update_window = function(player, state)
  local gui = state.gui
  if not (gui and gui.frame and gui.frame.valid) then return end

  local proto = prototypes.item[state.item_name]
  if not proto then return end

  local total = state.remaining_energy
  for fuel_name, fuel_value in pairs (get_fuel_values()) do
    total = total + player.get_item_count(fuel_name) * fuel_value
  end

  gui.icon.sprite = "item/" .. state.item_name
  gui.count.caption = tostring(player.get_item_count(state.item_name))
  gui.bar.value = state.remaining_energy / proto.fuel_value
  if state.estimated_consumption and state.estimated_consumption > 0 then
    gui.time.caption = {"etech-jui-remaining", render_time(total / state.estimated_consumption)}
  end
end

local sync = function()
  local ok, fuels = pcall(remote.call, "jetpack", "get_current_fuels")
  if not (ok and fuels) then return end

  -- Nobody airborne (the overwhelmingly common pass): close any leftover
  -- windows and skip the per-player is_jetpacking remote calls entirely.
  if not next(fuels) then
    for player_index, state in pairs (script_data.players) do
      if state.gui then
        local player = game.get_player(player_index)
        if player and player.valid then close_window(player, state) end
      end
    end
    return
  end

  for _, player in pairs (game.connected_players) do
    local state = get_state(player.index)
    local character = player.character
    local fuel = character and character.valid and fuels[character.unit_number]
    local jetpacking = false
    if fuel then
      local ok2, result = pcall(remote.call, "jetpack", "is_jetpacking", {character = character})
      jetpacking = ok2 and result
    end

    if not (fuel and jetpacking) then
      close_window(player, state)
    else
      local dt = state.synced_tick and (game.tick - state.synced_tick)
      if state.remaining_energy and dt and dt > 0 and dt <= 60 then
        local burned = state.remaining_energy - fuel.energy
        if burned >= 0 then -- negative = fuel item switched, skip that sample
          state.estimated_consumption = burned * (60 / dt)
        end
      end
      state.synced_tick = game.tick
      state.remaining_energy = fuel.energy
      state.item_name = fuel.name

      if state.estimated_consumption and state.estimated_consumption > 0 then
        ensure_window(player, state)
        update_window(player, state)
        -- Hide the HUD while the player is in map/remote view — a screen-gui
        -- window otherwise draws on top of the map.
        local in_world = player.render_mode == defines.render_mode.game
        local frame = state.gui and state.gui.frame
        if frame and frame.valid and frame.visible ~= in_world then
          frame.visible = in_world
        end
      end
    end
  end
end

local on_gui_location_changed = function(event)
  local element = event.element
  if not (element and element.valid and element.name == WINDOW) then return end
  local state = get_state(event.player_index)
  state.location = element.location
end

-- Clamp the saved position into the CURRENT view. These events fire when
-- the resolution/scale values are real, unlike the first ticks after join.
local clamp_location = function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local state = script_data.players[player.index]
  if not (state and state.location) then return end
  local resolution = player.display_resolution
  local x = math.max(0, math.min(state.location.x, resolution.width - 40))
  local y = math.max(0, math.min(state.location.y, resolution.height - 40))
  state.location = {x = x, y = y}
  local gui = state.gui
  if gui and gui.frame and gui.frame.valid then
    gui.frame.location = state.location
  end
end

local on_player_removed = function(event)
  script_data.players[event.player_index] = nil
end

local jetpack_ui = {}

jetpack_ui.events =
{
  [defines.events.on_gui_location_changed] = on_gui_location_changed,
  [defines.events.on_player_display_resolution_changed] = clamp_location,
  [defines.events.on_player_display_scale_changed] = clamp_location,
  [defines.events.on_player_removed] = on_player_removed,
}

jetpack_ui.on_nth_tick =
{
  [5] = sync,
}

jetpack_ui.on_init = function()
  storage.etech_jetpack_ui = storage.etech_jetpack_ui or script_data
end

jetpack_ui.on_load = function()
  script_data = storage.etech_jetpack_ui or script_data
end

jetpack_ui.on_configuration_changed = function()
  if not storage.etech_jetpack_ui then
    storage.etech_jetpack_ui = script_data
  else
    script_data = storage.etech_jetpack_ui
  end
end

return jetpack_ui
