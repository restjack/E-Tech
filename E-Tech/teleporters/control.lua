-- teleporters/control.lua
-- Runtime logic for teleporter pads: network bookkeeping, the destination
-- GUI (minimap buttons per pad), renaming (GUI + map tag), and the teleport
-- itself. Registered from the mod root control.lua via event_handler, only
-- when the etech-teleporters startup setting is on.
--
-- Adapted from "Teleporters" 2.0.x by Klonan (LGPLv3 — see
-- LICENSE-third-party.txt). Changes from the original: etech-prefixed
-- prototype/locale names, storage key etech_teleporters, rocket-launch
-- easter egg removed. Logic is otherwise Klonan's.

local util = require("teleporters/script_util")
local names = require("teleporters/shared")
local common = require("teleport-common")
local teleporter_name = names.entities.teleporter
local teleporter_sticker = names.entities.teleporter_sticker

local script_data =
{
  networks = {},
  rename_frames = {},
  button_actions = {},
  teleporter_map = {},
  teleporter_frames = {},
  player_linked_teleporter = {},
  to_be_removed = {},
  tag_map = {},
  search_boxes = {},
  recent = {},
  -- Display-only names for surfaces (keyed by surface index). The real
  -- surface is never renamed — other mods may reference it by name.
  surface_aliases = {},
  -- Per-player surface filter in the destination GUI (surface index, or nil
  -- for "all surfaces").
  surface_filter = {},
  surface_rename_frames = {},
  -- Players whose destination GUI was opened via the wireless-remote
  -- shortcut (no source pad, character not frozen).
  remote_open = {},
  -- Per-player return history after remote teleports: an ARRAY of
  -- {surface_index, position, tick}, newest first, capped at 3.
  returns = {},
  -- Per-player favorite pads ([player.name][unit_number] = true) — starred
  -- via right-click in the destination GUI, listed before everything else.
  favorites = {},
  -- Per-player sort mode for the destination list (1 = recent, 2 = A-Z,
  -- 3 = distance). Favorites always sort first regardless.
  sort_mode = {},
  -- Last dragged position of the destination window per player, so it
  -- reopens where the player left it instead of re-centering after every
  -- teleport (position only lived as long as the frame did before).
  frame_locations = {},
  -- Per-player search filter text, so the typed search survives the full
  -- GUI rebuild that every pad built/mined/rename event triggers.
  search_text = {},
}

local RETURN_SLOTS = 3

-- The teleport sound the player themselves hears. The world flash's own
-- sound plays at the destination BEFORE the player arrives, so it's
-- inaudible cross-surface — this one follows the player.
local play_teleport_sound = common.play_sound

-- Show only pad buttons whose searchable text (pad name + surface name +
-- alias, carried in the button's tags) contains `search`. The "no
-- teleporters" label has no tags and an empty name, so it only survives an
-- empty search — acceptable.
local apply_search_filter = function(parent, search)
  if not (parent and parent.valid) then return end
  search = search:lower()
  for _, child in pairs (parent.children) do
    local hay = (child.tags and child.tags.etech_search) or child.name
    child.visible = tostring(hay):lower():find(search, 1, true) ~= nil
  end
end

-- Pad preview size comes from the etech-teleporter-preview-size per-player
-- setting (read per GUI build in make_teleporter_gui).

local create_flash = function(surface, position)
  surface.create_entity{name = names.explosions.flash, position = position}
  for k = 1, 3 do
    surface.create_entity{name = names.explosions.flash_no_sound, position = position}
  end
end

local clear_gui = function(frame)
  if not (frame and frame.valid) then return end
  util.deregister_gui(frame, script_data.button_actions)
  frame.clear()
end

local close_gui = function(frame)
  if not (frame and frame.valid) then return end
  util.deregister_gui(frame, script_data.button_actions)
  frame.destroy()
end

local get_rename_frame = function(player)
  local frame = script_data.rename_frames[player.index]
  if frame and frame.valid then return frame end
  script_data.rename_frames[player.index] = nil
end

local get_teleporter_frame = function(player)
  local frame = script_data.teleporter_frames[player.index]
  if frame and frame.valid then return frame end
  script_data.teleporter_frames[player.index] = nil
end

local get_surface_rename_frame = function(player)
  local frame = script_data.surface_rename_frames[player.index]
  if frame and frame.valid then return frame end
  script_data.surface_rename_frames[player.index] = nil
end

local make_rename_frame = function(player, caption)

  local teleporter_frame = get_teleporter_frame(player)
  if teleporter_frame then
    teleporter_frame.ignored_by_interaction = true
  end

  player.opened = nil

  local force = player.force
  local teleporters = script_data.networks[force.name]
  local param = teleporters and teleporters[caption]
  if not param then return end
  local text = param.flying_text
  local gui = player.gui.screen
  local frame = gui.add{type = "frame", caption = {"etech-tp-rename-teleporter", caption}, direction = "horizontal"}
  frame.auto_center = true
  player.opened = frame
  script_data.rename_frames[player.index] = frame

  local textfield = frame.add{type = "textfield", text = caption, icon_selector = true}
  textfield.style.horizontally_stretchable = true
  textfield.focus()
  textfield.select_all()
  util.register_gui(script_data.button_actions, textfield, {type = "confirm_rename_textfield", textfield = textfield, flying_text = text, tag = param.tag})

  local confirm = frame.add{type = "sprite-button", sprite = "utility/enter", style = "tool_button", tooltip = {"gui-train-rename.perform-change"}}
  util.register_gui(script_data.button_actions, confirm, {type = "confirm_rename_button", textfield = textfield, flying_text = text, tag = param.tag})

end

local get_force_color = function(force)
  local player = force.connected_players[1]
  if player and player.valid then
    return player.chat_color
  end
  return {r = 1, b = 1, g = 1}
end

-- Favorites/recents are keyed by player.index since 0.19.0 (player.name
-- broke on player rename; on_configuration_changed migrates old keys).
local get_favorites = function(player)
  local favorites = script_data.favorites[player.index]
  if not favorites then
    favorites = {}
    script_data.favorites[player.index] = favorites
  end
  return favorites
end

local add_recent = function(player, teleporter)
  local recent = script_data.recent[player.index]
  if not recent then
    recent = {}
    script_data.recent[player.index] = recent
  end
  recent[teleporter.unit_number] = game.tick
  if table_size(recent) >= 9 then
    local min = math.huge
    local index
    for k, tick in pairs (recent) do
      if tick < min then
        min = tick
        index = k
      end
    end
    if index then recent[index] = nil end
  end
end

-- Remember where the player left the window before destroying it.
local save_frame_location = function(player)
  local frame = get_teleporter_frame(player)
  if frame then
    script_data.frame_locations[player.index] = frame.location
  end
end

local unlink_teleporter = function(player)
  if player.character then player.character.disabled_by_script = false end
  save_frame_location(player)
  close_gui(get_teleporter_frame(player))
  local source = script_data.player_linked_teleporter[player.index]
  if source and source.valid then
    source.disabled_by_script = false
    add_recent(player, source)
  end
  script_data.player_linked_teleporter[player.index] = nil
  script_data.remote_open[player.index] = nil
end

-- Visuals only (flying text + chart tag) — safe to call from resync, which
-- recreates them right after.
local clear_teleporter_visuals = function(teleporter_data)
  local flying_text = teleporter_data.flying_text
  if flying_text and flying_text.valid then
    flying_text.destroy()
  end
  local map_tag = teleporter_data.tag
  if map_tag and map_tag.valid then
    script_data.tag_map[map_tag.tag_number] = nil
    map_tag.destroy()
  end
end

-- Full teardown: visuals + the energy companion. Only for pads that are
-- actually gone.
local clear_teleporter_data = function(teleporter_data)
  clear_teleporter_visuals(teleporter_data)
  local eei = teleporter_data.energy_interface
  if eei and eei.valid then
    eei.destroy()
  end
  teleporter_data.energy_interface = nil
end

-- Find-or-create the pad's invisible electric buffer. Searching before
-- creating keeps clones/migrations/toggle-flips from stacking duplicates.
local get_energy_interface = function(teleporter_data, entity)
  local eei = teleporter_data.energy_interface
  if eei and eei.valid then return eei end
  if not (entity and entity.valid) then return end
  local surface = entity.surface
  local found = surface.find_entities_filtered{name = names.entities.energy_interface, position = entity.position, limit = 1}
  eei = found[1] or surface.create_entity
  {
    name = names.entities.energy_interface,
    position = entity.position,
    force = entity.force,
  }
  if eei then
    eei.destructible = false
    teleporter_data.energy_interface = eei
  end
  return eei
end

-- Cost in joules to teleport from `source` (pad or nil) to the destination
-- pad. Flat per-use cost plus an optional per-distance term (same surface
-- only — cross-surface distance is meaningless).
-- Cost in joules to teleport to `destination`. `source` is the pad the
-- player is standing on, or nil for a wireless-remote jump — then the
-- player's own surface/position anchor the distance and cross-surface
-- terms, and the remote multiplier applies.
local get_teleport_cost = function(source, destination, player)
  local per_use = settings.global["etech-teleporter-energy-mj"].value
  local per_100 = settings.global["etech-teleporter-energy-distance-mj"].value
  local cost = per_use
  local from_surface, from_position
  if source and source.valid then
    from_surface = source.surface
    from_position = source.position
  elseif player and player.valid then
    from_surface = player.surface
    from_position = player.position
    cost = cost * settings.global["etech-teleporter-remote-multiplier"].value
  end
  if from_surface then
    if from_surface ~= destination.surface then
      cost = cost * settings.global["etech-teleporter-cross-surface-multiplier"].value
    elseif per_100 > 0 then
      cost = cost + per_100 * (util.distance(from_position, destination.position) / 100)
    end
  end
  return cost * 1000000
end

-- Display name for a surface: player-set alias first, then the platform's
-- ship name ("Icarus", not "platform-1"), then the planet prototype's
-- localised name ("Nauvis", not "nauvis"), then the engine's localised
-- name, then the raw name.
local get_surface_label = function(surface)
  local alias = script_data.surface_aliases[surface.index]
  if alias and alias ~= "" then return alias end
  local platform = surface.platform
  if platform then return platform.name end
  local planet = surface.planet
  if planet then return planet.prototype.localised_name end
  return surface.localised_name or surface.name
end

-- The player's still-usable return slots (setting on, surface exists, grace
-- period not expired), newest first. Prunes dead entries as a side effect.
local get_valid_returns = function(player)
  local rets = script_data.returns[player.index]
  if not rets then return {} end
  if not settings.global["etech-teleporter-return-enabled"].value then return {} end
  local grace = settings.global["etech-teleporter-return-grace-min"].value
  local valid = {}
  for _, ret in ipairs(rets) do
    local surface = game.surfaces[ret.surface_index]
    if surface and surface.valid
       and not (grace > 0 and game.tick > ret.tick + grace * 60 * 60) then
      valid[#valid + 1] = ret
    end
  end
  script_data.returns[player.index] = (#valid > 0) and valid or nil
  return valid
end

local push_return = function(player, surface_index, position)
  local rets = script_data.returns[player.index]
  if not rets then
    rets = {}
    script_data.returns[player.index] = rets
  end
  table.insert(rets, 1, {surface_index = surface_index, position = position, tick = game.tick})
  while #rets > RETURN_SLOTS do
    table.remove(rets)
  end
end

local make_teleporter_gui = function(player, source)

  local location
  local teleporter_frame = get_teleporter_frame(player)
  if teleporter_frame then
    location = teleporter_frame.location
    script_data.frame_locations[player.index] = location
    script_data.teleporter_frames[player.index] = nil
    close_gui(teleporter_frame)
    player.opened = nil
  end

  -- source = the pad the player is standing on, or nil when opened via the
  -- wireless-remote shortcut.
  if source then
    if not (source.valid and not script_data.to_be_removed[source.unit_number]) then
      unlink_teleporter(player)
      return
    end
  elseif not script_data.remote_open[player.index] then
    unlink_teleporter(player)
    return
  end

  local force = source and source.force or player.force
  local network = script_data.networks[force.name] or {}
  -- The surface jumps are measured from (pad surface, or the player's own
  -- for remote use).
  local here_surface = source and source.surface or player.surface

  local preview_size = settings.get_player_settings(player)["etech-teleporter-preview-size"].value

  -- No live frame (e.g. reopening after a teleport closed it): fall back to
  -- the last saved position, unless it's off-screen (resolution changed).
  if not location then
    local saved = script_data.frame_locations[player.index]
    if saved then
      local res = player.display_resolution
      if saved.x >= 0 and saved.y >= 0 and saved.x < res.width - 50 and saved.y < res.height - 50 then
        location = saved
      else
        script_data.frame_locations[player.index] = nil
      end
    end
  end

  local gui = player.gui.screen
  local frame = gui.add{type = "frame", direction = "vertical", ignored_by_interaction = false}
  if location then
    frame.location = location
  else
    frame.auto_center = true
  end

  player.opened = frame
  script_data.teleporter_frames[player.index] = frame
  frame.ignored_by_interaction = false
  local title_flow = frame.add{type = "flow", direction = "horizontal"}
  title_flow.style.vertical_align = "center"
  local title = title_flow.add{type = "label", style = "frame_title"}
  title.drag_target = frame
  if not source then
    title.caption = {"etech-tp-remote-title"}
  end
  local rename_button = title_flow.add{type = "sprite-button", sprite = "utility/rename_icon", style = "mini_button_aligned_to_text_vertically_when_centered", visible = source ~= nil and source.force == player.force}
  local pusher = title_flow.add{type = "empty-widget", direction = "horizontal", style = "draggable_space_header"}
  pusher.style.horizontally_stretchable = true
  pusher.style.vertically_stretchable = true
  pusher.drag_target = frame
  -- The search text persists in storage: the GUI is fully rebuilt on every
  -- pad built/mined/rename event, and the typed filter used to vanish.
  local saved_search = script_data.search_text[player.index] or ""
  local search_box = title_flow.add{type = "textfield", visible = saved_search ~= "", text = saved_search}
  local search_button = title_flow.add{type = "sprite-button", style = "frame_action_button", sprite = "utility/search", tooltip = {"gui.search-with-focus", {"etech-tp-search"}}}
  script_data.search_boxes[player.index] = search_box
  local recent = script_data.recent[player.index] or {}
  local favorites = get_favorites(player)

  local sorted = {}
  local i = 1
  for name, teleporter in pairs (network) do
    if teleporter.teleporter.valid then
      sorted[i] = {name = name, teleporter = teleporter, unit_number = teleporter.teleporter.unit_number}
      i = i + 1
    else
      clear_teleporter_data(teleporter)
    end
  end

  local cross_surface = settings.global["etech-teleporter-cross-surface"].value
  local hide_platforms = settings.get_player_settings(player)["etech-teleporter-hide-platforms"].value

  -- Surfaces that actually have pads, for the filter dropdown.
  local surface_indices = {}
  local seen_surfaces = {}
  for _, entry in pairs (sorted) do
    local surface_index = entry.teleporter.teleporter.surface.index
    if not seen_surfaces[surface_index] then
      seen_surfaces[surface_index] = true
      surface_indices[#surface_indices + 1] = surface_index
    end
  end
  table.sort(surface_indices)

  local filter_index = script_data.surface_filter[player.index]
  if filter_index and not (seen_surfaces[filter_index] and cross_surface) then
    filter_index = nil
    script_data.surface_filter[player.index] = nil
  end

  local filter_flow = frame.add{type = "flow", direction = "horizontal"}
  filter_flow.style.vertical_align = "center"

  -- Sort mode dropdown (favorites always pin first).
  local sort_mode = script_data.sort_mode[player.index] or 1
  local sort_dropdown = filter_flow.add{type = "drop-down",
    items = {{"etech-tp-sort-recent"}, {"etech-tp-sort-name"}, {"etech-tp-sort-distance"}},
    selected_index = sort_mode,
    tooltip = {"etech-tp-sort-tooltip"}}
  util.register_gui(script_data.button_actions, sort_dropdown, {type = "sort_mode"})

  if cross_surface and #surface_indices > 1 then
    local items = {{"etech-tp-all-surfaces"}}
    local index_map = {false}
    local selected = 1
    for _, surface_index in ipairs(surface_indices) do
      local surf = game.surfaces[surface_index]
      if surf and surf.valid then
        items[#items + 1] = get_surface_label(surf)
        index_map[#index_map + 1] = surface_index
        if filter_index == surface_index then selected = #items end
      end
    end
    local dropdown = filter_flow.add{type = "drop-down", items = items, selected_index = selected}
    dropdown.style.horizontally_stretchable = true
    util.register_gui(script_data.button_actions, dropdown, {type = "surface_filter", index_map = index_map})
    local rename_surface_button = filter_flow.add{type = "sprite-button", sprite = "utility/rename_icon", style = "tool_button", tooltip = {"etech-tp-rename-surface-tooltip"}}
    util.register_gui(script_data.button_actions, rename_surface_button, {type = "rename_surface_button"})
  end

  -- Return slot + same-force players, in one row above the pad list.
  local special_size = math.min(128, preview_size)
  local special_flow
  local get_special_flow = function()
    if special_flow and special_flow.valid then return special_flow end
    local special_frame = frame.add{type = "frame", style = "inside_deep_frame"}
    special_flow = special_frame.add{type = "flow", direction = "horizontal"}
    special_flow.style.horizontal_spacing = 2
    return special_flow
  end

  local add_preview_button = function(parent, view_spec, caption, tooltip, action)
    local button = parent.add{type = "button"}
    button.style.height = special_size + 32 + 8
    button.style.width = special_size + 8
    button.style.left_padding = 0
    button.style.right_padding = 0
    button.tooltip = tooltip
    local inner_flow = button.add{type = "flow", direction = "vertical", ignored_by_interaction = true}
    inner_flow.style.vertically_stretchable = true
    inner_flow.style.horizontally_stretchable = true
    inner_flow.style.horizontal_align = "center"
    local view = inner_flow.add(view_spec)
    view.ignored_by_interaction = true
    view.style.height = special_size
    view.style.width = special_size
    local label = inner_flow.add{type = "label", caption = caption}
    label.style.font = "default-dialog-button"
    label.style.font_color = {}
    label.style.maximal_width = special_size
    util.register_gui(script_data.button_actions, button, action)
  end

  local rets = get_valid_returns(player)
  for i, ret in ipairs(rets) do
    local caption = (#rets > 1) and {"", {"etech-tp-return"}, " " .. i} or {"etech-tp-return"}
    -- Pass the entry itself, not its index — the list can shift between GUI
    -- build and click (slots expiring / other slots consumed).
    add_preview_button(get_special_flow(),
      {type = "camera", position = ret.position, surface_index = ret.surface_index, zoom = 0.2},
      caption,
      {"etech-tp-return-tooltip", get_surface_label(game.surfaces[ret.surface_index])},
      {type = "return_button", ret = ret})
  end

  if settings.global["etech-teleporter-players-section"].value then
    for _, other in pairs (player.force.connected_players) do
      if other.index ~= player.index then
        local other_surface = other.physical_surface or other.surface
        local other_position = other.physical_position or other.position
        add_preview_button(get_special_flow(),
          {type = "minimap", surface_index = other_surface.index, zoom = 1, force = force.name, position = other_position},
          other.name,
          {"etech-tp-player-tooltip", other.name, get_surface_label(other_surface)},
          {type = "player_button", target_index = other.index})
      end
    end
  end

  local inner = frame.add{type = "frame", style = "inside_deep_frame"}
  local scroll = inner.add{type = "scroll-pane", direction = "vertical"}
  scroll.style.maximal_height = (player.display_resolution.height / player.display_scale) * 0.8
  -- At least one column — a large preview size on a small window would
  -- otherwise round to zero and error on the table add.
  local column_count = math.max(1, math.floor(((player.display_resolution.width / player.display_scale) * 0.6) / preview_size))
  local holding_table = scroll.add{type = "table", column_count = column_count}
  util.register_gui(script_data.button_actions, search_box, {type = "search_text_changed", parent = holding_table})
  util.register_gui(script_data.button_actions, search_button, {type = "search_button", box = search_box, parent = holding_table})
  holding_table.style.horizontal_spacing = 2
  holding_table.style.vertical_spacing = 2
  local any = false

  -- Anchor for distances: the pad the player stands on, or the player.
  local anchor_position = source and source.position or player.position
  local distance_to = function(entry)
    local entity = entry.teleporter.teleporter
    if entity.surface ~= here_surface then return nil end
    return util.distance(anchor_position, entity.position)
  end

  -- Favorites always first (alphabetical); the rest per the sort dropdown:
  -- 1 = recently used then A-Z, 2 = A-Z, 3 = distance (same surface by
  -- range, other surfaces after, A-Z).
  table.sort(sorted, function(a, b)
    local fav_a = favorites[a.unit_number] and true or false
    local fav_b = favorites[b.unit_number] and true or false
    if fav_a ~= fav_b then
      return fav_a
    end
    if fav_a then
      return a.name:lower() < b.name:lower()
    end

    if sort_mode == 3 then
      local dist_a = distance_to(a)
      local dist_b = distance_to(b)
      if dist_a and dist_b then return dist_a < dist_b end
      if dist_a then return true end
      if dist_b then return false end
      return a.name:lower() < b.name:lower()
    end

    if sort_mode == 1 then
      if recent[a.unit_number] and recent[b.unit_number] then
        return recent[a.unit_number] > recent[b.unit_number]
      end
      if recent[a.unit_number] then
        return true
      end
      if recent[b.unit_number] then
        return false
      end
    end

    return a.name:lower() < b.name:lower()
  end)

  local sorted_network = {}
  for k, sorted_script_data in pairs (sorted) do
    sorted_network[sorted_script_data.name] = sorted_script_data.teleporter
  end

  local chart = player.force.chart
  for name, teleporter in pairs(sorted_network) do
    local teleporter_entity = teleporter.teleporter
    if not (teleporter_entity.valid) then
      clear_teleporter_data(teleporter)
    elseif teleporter_entity == source then
      title.caption = name
      util.register_gui(script_data.button_actions, rename_button, {type = "rename_button", caption = name})
    else
      local pad_surface = teleporter_entity.surface
      local show
      if not cross_surface then
        show = pad_surface == here_surface
      elseif filter_index then
        show = pad_surface.index == filter_index
      else
        show = not (hide_platforms and pad_surface.platform)
      end
      if show then
      local position = teleporter_entity.position
      -- Charting the preview area per pad per rebuild was measurable with
      -- many pads - once a minute per pad is plenty for minimap previews.
      if (teleporter.charted_tick or 0) + 3600 <= game.tick then
        local area = {{position.x - preview_size / 2, position.y - preview_size / 2}, {position.x + preview_size / 2, position.y + preview_size / 2}}
        chart(pad_surface, area)
        teleporter.charted_tick = game.tick
      end
      local cost = get_teleport_cost(source, teleporter_entity, player)
      -- Searchable text: pad name + raw surface name + string surface label
      -- (alias / platform name). Localised planet names can't be searched -
      -- the raw name ("nauvis") covers that case.
      local searchable = name .. " " .. pad_surface.name
      local surface_label_value = get_surface_label(pad_surface)
      if type(surface_label_value) == "string" and surface_label_value ~= pad_surface.name then
        searchable = searchable .. " " .. surface_label_value
      end
      local button = holding_table.add{type = "button", name = "_"..name, tags = {etech_search = searchable}}
      -- Buttons clip their children to the button's own size, so the height
      -- must account for every label row: name + distance/surface line,
      -- plus the button's own vertical padding (zeroed below, headroom kept).
      -- The energy cost lives in the tooltip, not a label.
      button.style.height = preview_size + 64
      button.style.width = preview_size + 8
      button.style.top_padding = 2
      button.style.bottom_padding = 2
      button.style.left_padding = 0
      button.style.right_padding = 0
      local inner_flow = button.add{type = "flow", direction = "vertical", ignored_by_interaction = true}
      inner_flow.style.vertically_stretchable = true
      inner_flow.style.horizontally_stretchable = true
      inner_flow.style.horizontal_align = "center"
      local map = inner_flow.add
      {
        type = "minimap",
        surface_index = teleporter_entity.surface.index,
        zoom = 1,
        force = teleporter_entity.force.name,
        position = position,
      }
      map.ignored_by_interaction = true
      map.style.height = preview_size
      map.style.width = preview_size
      map.style.horizontally_stretchable = true
      map.style.vertically_stretchable = true
      local caption = name
      if recent[teleporter_entity.unit_number] then
        caption = "[img=quantity-time] "..name
      end
      if favorites[teleporter_entity.unit_number] then
        caption = "★ "..caption
      end
      button.tooltip = {"etech-tp-favorite-tooltip"}
      local label = inner_flow.add{type = "label", caption = caption}
      label.style.horizontally_stretchable = true
      label.style.font = "default-dialog-button"
      label.style.font_color = {}
      label.style.horizontally_stretchable = true
      label.style.maximal_width = preview_size
      if pad_surface ~= here_surface then
        local surface_label = inner_flow.add{type = "label", caption = get_surface_label(pad_surface)}
        surface_label.style.font_color = {r = 0.7, g = 0.7, b = 0.7}
        surface_label.style.maximal_width = preview_size
      else
        local dist = util.distance(anchor_position, position)
        local distance_label = inner_flow.add{type = "label", caption = {"etech-tp-distance", string.format("%.0f", dist)}}
        distance_label.style.font_color = {r = 0.7, g = 0.7, b = 0.7}
        distance_label.style.maximal_width = preview_size
      end
      if cost > 0 then
        local eei = get_energy_interface(teleporter, teleporter_entity)
        local stored = (eei and eei.valid and eei.energy) or 0
        local energy_line = {"etech-tp-energy-label", string.format("%.0f", cost / 1000000), string.format("%.0f", stored / 1000000)}
        if stored < cost then
          button.enabled = false
          button.tooltip = {"", {"etech-tp-not-enough-energy"}, "\n", energy_line}
        else
          button.tooltip = {"", {"etech-tp-favorite-tooltip"}, "\n", energy_line}
        end
      end
      util.register_gui(script_data.button_actions, button, {type = "teleport_button", param = teleporter})
      any = true
      end
    end
  end
  if not any then
    holding_table.add{type = "label", caption = {"etech-tp-no-teleporters"}}
  end
  if saved_search ~= "" then
    apply_search_filter(holding_table, saved_search)
  end
end

local refresh_teleporter_frames = function()
  local players = game.players
  for player_index, source in pairs (script_data.player_linked_teleporter) do
    local player = players[player_index]
    local frame = get_teleporter_frame(player)
    if frame then
      make_teleporter_gui(player, source)
    end
  end
  for player_index in pairs (script_data.remote_open) do
    local player = players[player_index]
    if player and player.valid and get_teleporter_frame(player) then
      make_teleporter_gui(player, nil)
    end
  end
end

local check_player_linked_teleporter = function(player)
  if script_data.remote_open[player.index] then
    make_teleporter_gui(player, nil)
    return
  end
  local source = script_data.player_linked_teleporter[player.index]
  if source and source.valid then
    make_teleporter_gui(player, source)
  else
    unlink_teleporter(player)
  end
end

local resync_teleporter = function(name, teleporter_data)
  local teleporter = teleporter_data.teleporter
  if not (teleporter and teleporter.valid) then
    return
  end
  local force = teleporter.force
  local surface = teleporter.surface
  local color = get_force_color(force)

  clear_teleporter_visuals(teleporter_data)

  local flying_text = rendering.draw_text
  {
    text = name,
    surface = surface,
    alignment = "center",
    target = {entity = teleporter, offset = {0, -2}},
    forces = {force},
    only_in_alt_mode = true,
    use_rich_text = true,
    color = color
  }
  teleporter_data.flying_text = flying_text

  script_data.adding_tag = true
  local map_tag = force.add_chart_tag(surface,
  {
    icon = {type = "item", name = teleporter_name},
    position = teleporter.position,
    text = name
  })
  script_data.adding_tag = false

  if map_tag then
    teleporter_data.tag = map_tag
    script_data.tag_map[map_tag.tag_number] = teleporter_data
  end

end

local is_name_available = function(force, name)
  local network = script_data.networks[force.name]
  return not network[name]
end

local rename_teleporter = function(force, old_name, new_name)
  if old_name == new_name then
    refresh_teleporter_frames()
    return
  end
  local network = script_data.networks[force.name]
  local teleporter_data = network[old_name]
  network[new_name] = teleporter_data
  network[old_name] = nil
  resync_teleporter(new_name, teleporter_data)
  refresh_teleporter_frames()
end

-- Alias editor for the surface picked in the filter dropdown (or the
-- player's current surface when "All surfaces" is selected). Sets a
-- display-only alias in storage — the real surface is never renamed.
local make_surface_rename_frame = function(player)
  local surface_index = script_data.surface_filter[player.index] or player.surface.index
  local surface = game.surfaces[surface_index]
  if not (surface and surface.valid) then return end

  local teleporter_frame = get_teleporter_frame(player)
  if teleporter_frame then
    teleporter_frame.ignored_by_interaction = true
  end
  player.opened = nil

  local frame = player.gui.screen.add{type = "frame", caption = {"etech-tp-rename-surface", get_surface_label(surface)}, direction = "horizontal"}
  frame.auto_center = true
  player.opened = frame
  script_data.surface_rename_frames[player.index] = frame

  local textfield = frame.add{type = "textfield", text = script_data.surface_aliases[surface_index] or ""}
  textfield.style.horizontally_stretchable = true
  textfield.focus()
  textfield.select_all()
  util.register_gui(script_data.button_actions, textfield, {type = "confirm_surface_rename_textfield", textfield = textfield, surface_index = surface_index})

  local confirm = frame.add{type = "sprite-button", sprite = "utility/enter", style = "tool_button", tooltip = {"gui-train-rename.perform-change"}}
  util.register_gui(script_data.button_actions, confirm, {type = "confirm_surface_rename_button", textfield = textfield, surface_index = surface_index})
end

local apply_surface_rename = function(event, param)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local alias
  if param.textfield and param.textfield.valid then
    alias = param.textfield.text
  end
  if alias == "" then alias = nil end
  script_data.surface_aliases[param.surface_index] = alias
  close_gui(get_surface_rename_frame(player))
  check_player_linked_teleporter(player)
end

-- Shared by the rename confirm button and the textfield confirm (they were
-- copy-pasted bodies before 0.19.0).
local apply_pad_rename = function(event, param)
  local flying_text = param.flying_text
  if not (flying_text and flying_text.valid) then return end
  local player = game.players[event.player_index]
  if not (player and player.valid) then return end
  local old_name = flying_text.text
  local new_name = param.textfield.text

  -- Same rule as the chart-tag path: no empty names, no duplicates.
  if new_name == "" or (new_name ~= old_name and not is_name_available(player.force, new_name)) then
    player.print({"etech-tp-name-already-taken"})
    return
  end

  close_gui(get_rename_frame(player))
  rename_teleporter(player.force, old_name, new_name)
end

local gui_actions =
{
  rename_button = function(event, param)
    make_rename_frame(game.get_player(event.player_index), param.caption)
  end,
  cancel_rename = function(event, param)
    local player = game.get_player(event.player_index)
    close_gui(get_rename_frame(player))
    check_player_linked_teleporter(player)
  end,
  confirm_rename_button = function(event, param)
    if event.name ~= defines.events.on_gui_click then return end
    apply_pad_rename(event, param)
  end,
  confirm_rename_textfield = function(event, param)
    if event.name ~= defines.events.on_gui_confirmed then return end
    apply_pad_rename(event, param)
  end,
  teleport_button = function(event, param)
    local teleport_param = param.param
    if not teleport_param then return end
    local destination = teleport_param.teleporter
    if not (destination and destination.valid) then return end
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end

    -- Right-click stars/unstars the pad; shift+right-click renames it.
    if event.name == defines.events.on_gui_click and event.button == defines.mouse_button_type.right then
      if event.shift then
        local network = script_data.networks[player.force.name] or {}
        for name, teleporter_data in pairs(network) do
          if teleporter_data == teleport_param then
            make_rename_frame(player, name)
            return
          end
        end
        return
      end
      local favorites = get_favorites(player)
      local unit_number = destination.unit_number
      favorites[unit_number] = not favorites[unit_number] or nil
      check_player_linked_teleporter(player)
      return
    end

    local source = script_data.player_linked_teleporter[player.index]
    local remote = not source and script_data.remote_open[player.index]
    if not settings.global["etech-teleporter-cross-surface"].value then
      if destination.surface ~= player.surface then
        player.print({"etech-tp-cross-surface-disabled"})
        return
      end
    end
    local cost = get_teleport_cost(source, destination, player)
    local eei
    if cost > 0 then
      eei = get_energy_interface(teleport_param, destination)
      local stored = (eei and eei.valid and eei.energy) or 0
      if stored < cost then
        player.print({"etech-tp-not-enough-energy"})
        return
      end
    end

    local from_surface = player.surface
    local from_position = player.position

    destination.timeout = destination.prototype.timeout
    local destination_surface = destination.surface
    local destination_position = destination.position
    -- On foot the player lands exactly on the pad; driving a car/spidertron
    -- teleports the vehicle to a clear spot next to it. Rolling stock
    -- refuses. Energy is only drained once the jump actually happened.
    local ok, result = common.teleport_player(player, destination_surface, destination_position, {exact = true})
    if not ok then
      player.print(result == "train" and {"etech-tp-in-train"} or {"etech-tp-player-teleport-failed"})
      return
    end
    if cost > 0 and eei and eei.valid then
      eei.energy = eei.energy - cost
    end
    create_flash(destination_surface, destination_position)
    create_flash(from_surface, from_position)
    play_teleport_sound(player)
    unlink_teleporter(player)
    add_recent(player, destination)

    if remote and settings.global["etech-teleporter-return-enabled"].value then
      push_return(player, from_surface.index, from_position)
    end
  end,

  return_button = function(event, param)
    if event.name ~= defines.events.on_gui_click then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local rets = get_valid_returns(player)
    -- Find the entry by identity — indices may have shifted since the GUI
    -- was built.
    local index
    for i, ret in ipairs(rets) do
      if ret == param.ret then
        index = i
        break
      end
    end
    local ret = index and rets[index]
    if not ret then
      player.print({"etech-tp-return-expired"})
      check_player_linked_teleporter(player)
      return
    end
    local surface = game.surfaces[ret.surface_index]
    local from_surface = player.surface
    local from_position = player.position
    local ok, result = common.teleport_player(player, surface, ret.position)
    if not ok then
      player.print(result == "train" and {"etech-tp-in-train"} or {"etech-tp-player-teleport-failed"})
      return
    end
    create_flash(from_surface, from_position)
    create_flash(surface, result)
    play_teleport_sound(player)
    table.remove(rets, index)
    script_data.returns[player.index] = (#rets > 0) and rets or nil
    unlink_teleporter(player)
  end,
  player_button = function(event, param)
    if event.name ~= defines.events.on_gui_click then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local target = game.get_player(param.target_index)
    if not (target and target.valid and target.connected) then
      player.print({"etech-tp-player-offline"})
      check_player_linked_teleporter(player)
      return
    end
    local surface = target.physical_surface or target.surface
    local position = target.physical_position or target.position
    local from_surface = player.surface
    local from_position = player.position
    local ok, result = common.teleport_player(player, surface, position)
    if not ok then
      player.print(result == "train" and {"etech-tp-in-train"} or {"etech-tp-player-teleport-failed"})
      return
    end
    create_flash(from_surface, from_position)
    create_flash(surface, result)
    play_teleport_sound(player)
    unlink_teleporter(player)
  end,

  surface_filter = function(event, param)
    if event.name ~= defines.events.on_gui_selection_state_changed then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local chosen = param.index_map[event.element.selected_index]
    script_data.surface_filter[player.index] = chosen or nil
    check_player_linked_teleporter(player)
  end,
  sort_mode = function(event, param)
    if event.name ~= defines.events.on_gui_selection_state_changed then return end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    script_data.sort_mode[player.index] = event.element.selected_index
    check_player_linked_teleporter(player)
  end,
  rename_surface_button = function(event, param)
    make_surface_rename_frame(game.get_player(event.player_index))
  end,
  confirm_surface_rename_button = function(event, param)
    if event.name ~= defines.events.on_gui_click then return end
    apply_surface_rename(event, param)
  end,
  confirm_surface_rename_textfield = function(event, param)
    if event.name ~= defines.events.on_gui_confirmed then return end
    apply_surface_rename(event, param)
  end,

  search_text_changed = function(event, param)
    local box = event.element
    script_data.search_text[event.player_index] = (box.text ~= "") and box.text or nil
    apply_search_filter(param.parent, box.text)
  end,
  search_button = function(event, param)
    local box = param.box
    box.visible = not box.visible
    if box.visible then
      box.focus()
    else
      -- Hiding the box clears the filter — pads filtered out by a lingering
      -- term used to stay invisible with no visible cause.
      box.text = ""
      script_data.search_text[event.player_index] = nil
      apply_search_filter(param.parent, "")
    end
  end
}

local get_network = function(force)
  local name = force.name
  local network = script_data.networks[name]
  if network then return network end
  script_data.networks[name] = {}
  return script_data.networks[name]
end

local on_built_entity = function(event)
  local entity = event.entity or event.destination
  if not (entity and entity.valid) then return end
  if entity.name ~= teleporter_name then return end
  local force = entity.force
  local network = get_network(force)
  local name = "Teleporter ".. entity.unit_number
  -- Blueprint-pasted pads carry their original name as a blueprint tag
  -- (written in on_player_setup_blueprint); reuse it, suffixing on collision.
  local wanted = event.tags and event.tags.etech_tp_name
  if type(wanted) == "string" and wanted ~= "" then
    local target, n = wanted, 2
    while network[target] do
      target = wanted .. " (" .. n .. ")"
      n = n + 1
    end
    name = target
  end
  local teleporter_data = {teleporter = entity}
  network[name] = teleporter_data
  script_data.teleporter_map[entity.unit_number] = teleporter_data
  get_energy_interface(teleporter_data, entity)
  resync_teleporter(name, teleporter_data)
  refresh_teleporter_frames()
end

local on_teleporter_removed = function(entity)
  if not (entity and entity.valid) then return end
  if entity.name ~= teleporter_name then return end
  local force = entity.force
  local teleporter_data = script_data.teleporter_map[entity.unit_number]
  if not teleporter_data then return end
  local network = get_network(force)
  -- The flying text can be gone (e.g. another mod ran rendering.clear()),
  -- so fall back to finding the entry by identity.
  local flying_text = teleporter_data.flying_text
  local caption = flying_text and flying_text.valid and flying_text.text
  if caption and network[caption] == teleporter_data then
    network[caption] = nil
  else
    for name, data in pairs (network) do
      if data == teleporter_data then
        network[name] = nil
        break
      end
    end
  end
  clear_teleporter_data(teleporter_data)
  script_data.teleporter_map[entity.unit_number] = nil

  -- Favorites/recents referencing the gone pad would otherwise leak forever.
  for _, favorites in pairs (script_data.favorites) do
    favorites[entity.unit_number] = nil
  end
  for _, recent in pairs (script_data.recent) do
    recent[entity.unit_number] = nil
  end

  script_data.to_be_removed[entity.unit_number] = true
  refresh_teleporter_frames()
  script_data.to_be_removed[entity.unit_number] = nil
end

local teleporter_triggered = function(entity, character)
  if not (entity and entity.valid and entity.name == teleporter_name) then return end
  if character.type ~= "character" then return end
  local player = character.player
  if not player then return end
  player.teleport(entity.position)
  entity.disabled_by_script = true
  entity.timeout = entity.prototype.timeout
  character.disabled_by_script = true
  script_data.remote_open[player.index] = nil
  script_data.player_linked_teleporter[player.index] = entity
  make_teleporter_gui(player, entity)
end

local on_entity_removed = function(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  on_teleporter_removed(entity)
end

local on_gui_action = function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player_script_data = script_data.button_actions[event.player_index]
  if not player_script_data then return end
  local action = player_script_data[element.index]
  if action then
    local handler = gui_actions[action.type]
    if not handler then return end
    handler(event, action)
    return true
  end
end

local on_gui_closed = function(event)
  local element = event.element
  if not element then return end

  local player = game.get_player(event.player_index)

  local rename_frame = get_rename_frame(player)
  if rename_frame and rename_frame == element then
    close_gui(rename_frame)
    check_player_linked_teleporter(player)
    return
  end

  local surface_rename_frame = get_surface_rename_frame(player)
  if surface_rename_frame and surface_rename_frame == element then
    close_gui(surface_rename_frame)
    check_player_linked_teleporter(player)
    return
  end

  local teleporter_frame = get_teleporter_frame(player)
  if teleporter_frame and teleporter_frame == element and not teleporter_frame.ignored_by_interaction then
    save_frame_location(player)
    close_gui(teleporter_frame)
    unlink_teleporter(player)
    return
  end

end

local on_player_removed = function(event)
  local player = game.get_player(event.player_index)
  close_gui(get_rename_frame(player))
  close_gui(get_surface_rename_frame(player))
  script_data.surface_filter[player.index] = nil
  script_data.sort_mode[player.index] = nil
  unlink_teleporter(player)
end

local resync_all_teleporters = function()
  for force, network in pairs (script_data.networks) do
    for name, teleporter_data in pairs (network) do
      local entity = teleporter_data.teleporter
      if entity and entity.valid then
        get_energy_interface(teleporter_data, entity)
      end
      resync_teleporter(name, teleporter_data)
    end
  end
end

local on_chart_tag_modified = function(event)
  local force = event.force
  local tag = event.tag
  if not (force and force.valid and tag and tag.valid) then return end
  local teleporter_data = script_data.tag_map[tag.tag_number]
  if not teleporter_data then
    return
  end
  local player = event.player_index and game.get_player(event.player_index)

  local old_name = event.old_text
  local new_name = tag.text
  if tag.icon and tag.icon.name ~= teleporter_name then
    if player and player.valid then player.print({"etech-tp-cant-change-icon"}) end
    tag.icon = {type = "item", name = teleporter_name}
  end
  if new_name == old_name then
    return
  end
  if new_name == "" or not is_name_available(force, new_name) then
    if player and player.valid then
      player.print({"etech-tp-name-already-taken"})
    end
    tag.text = old_name
    return
  end
  rename_teleporter(force, old_name, new_name)
end

local on_chart_tag_removed = function(event)
  local force = event.force
  local tag = event.tag
  if not (force and force.valid and tag and tag.valid) then return end
  local teleporter_data = script_data.tag_map[tag.tag_number]
  if not teleporter_data then
    return
  end
  local name = tag.text
  resync_teleporter(name, teleporter_data)
end

local on_chart_tag_added = function(event)
  if script_data.adding_tag then return end
  local tag = event.tag
  if not (tag and tag.valid) then
    return
  end
  local icon = tag.icon
  if icon and icon.type == "item" and icon.name == teleporter_name then
    local player = event.player_index and game.get_player(event.player_index)
    if player and player.valid then player.print({"etech-tp-cant-add-tag"}) end
    tag.destroy()
    return
  end
end

local toggle_search = function(player)
  local box = script_data.search_boxes[player.index]
  if not (box and box.valid) then return end
  box.visible = true
  box.focus()
end

local on_search_focused = function(event)
  local player = game.get_player(event.player_index)
  toggle_search(player)
end

local on_player_display_resolution_changed = function(event)
  local player = game.get_player(event.player_index)
  check_player_linked_teleporter(player)
end

local on_player_display_scale_changed = function(event)
  local player = game.get_player(event.player_index)
  check_player_linked_teleporter(player)
end

-- Wireless remote: open the destination GUI from anywhere. Gated on the
-- runtime setting and on the Teleporter technology being researched.
-- Reached from the toolbar shortcut and the SHIFT+T hotkey alike.
local open_remote = function(player)
  if not (player and player.valid) then return end
  if not settings.global["etech-teleporter-remote"].value then
    player.print({"etech-tp-remote-disabled"})
    return
  end
  local tech = player.force.technologies[teleporter_name]
  if tech and not tech.researched then
    player.print({"etech-tp-remote-not-researched"})
    return
  end
  if script_data.remote_open[player.index] and get_teleporter_frame(player) then
    unlink_teleporter(player)
    return
  end
  if script_data.player_linked_teleporter[player.index] then
    -- Standing on a pad with its GUI open — the shortcut just closes it.
    unlink_teleporter(player)
    return
  end
  script_data.remote_open[player.index] = true
  make_teleporter_gui(player, nil)
end

local on_lua_shortcut = function(event)
  if event.prototype_name ~= names.shortcuts.remote then return end
  open_remote(game.get_player(event.player_index))
end

local on_remote_hotkey = function(event)
  open_remote(game.get_player(event.player_index))
end

-- Unpowered-pad alert: a pad with an empty energy buffer can't be teleported
-- to, and you only find out by opening the GUI. Raise a custom alert for the
-- owning force while a pad sits at zero (only when teleports actually cost
-- energy, and gated by a map setting).
local check_pad_alerts = function()
  if not settings.global["etech-teleporter-alerts"].value then return end
  if settings.global["etech-teleporter-energy-mj"].value <= 0
     and settings.global["etech-teleporter-energy-distance-mj"].value <= 0 then
    return
  end
  for force_name, network in pairs (script_data.networks) do
    local force = game.forces[force_name]
    if force and force.valid and next(network) and #force.connected_players > 0 then
      for name, teleporter_data in pairs (network) do
        local entity = teleporter_data.teleporter
        local eei = teleporter_data.energy_interface
        if entity and entity.valid and eei and eei.valid and eei.energy <= 0 then
          for _, player in pairs (force.connected_players) do
            player.add_custom_alert(entity, {type = "item", name = teleporter_name}, {"etech-tp-alert-unpowered", name}, true)
          end
        end
      end
    end
  end
end

local on_surface_deleted = function(event)
  script_data.surface_aliases[event.surface_index] = nil
  for player_index, surface_index in pairs (script_data.surface_filter) do
    if surface_index == event.surface_index then
      script_data.surface_filter[player_index] = nil
    end
  end
  -- Return slots pointing at the deleted surface were only pruned lazily on
  -- the next GUI open; drop them eagerly.
  for player_index, rets in pairs (script_data.returns) do
    local kept = {}
    for _, ret in ipairs(rets) do
      if ret.surface_index ~= event.surface_index then
        kept[#kept + 1] = ret
      end
    end
    script_data.returns[player_index] = (#kept > 0) and kept or nil
  end
end

-- Networks are keyed by force name, so a force merge would otherwise strand
-- the source force's pads in a dead bucket: invisible in the destination
-- GUI, un-removable (mining looks them up under the new force), visuals
-- leaked. Move them over, renaming on collision, and resync so the flying
-- text / chart tag land on the destination force.
local on_forces_merged = function(event)
  local source_network = script_data.networks[event.source_name]
  if not source_network then return end
  script_data.networks[event.source_name] = nil
  local destination = event.destination
  if not (destination and destination.valid) then return end
  local network = get_network(destination)
  for name, teleporter_data in pairs (source_network) do
    local entity = teleporter_data.teleporter
    if entity and entity.valid then
      local target = name
      local n = 2
      while network[target] do
        target = name.." ("..n..")"
        n = n + 1
      end
      network[target] = teleporter_data
      resync_teleporter(target, teleporter_data)
    else
      clear_teleporter_data(teleporter_data)
    end
  end
  refresh_teleporter_frames()
end

-- The current display name of a placed pad (flying text first, network scan
-- as fallback when another mod wiped the renderings).
local get_pad_name = function(entity)
  local teleporter_data = script_data.teleporter_map[entity.unit_number]
  if not teleporter_data then return end
  local flying_text = teleporter_data.flying_text
  if flying_text and flying_text.valid then return flying_text.text end
  local network = script_data.networks[entity.force.name]
  if network then
    for name, data in pairs (network) do
      if data == teleporter_data then return name end
    end
  end
end

-- Write each pad's name into the blueprint as an entity tag, so pasted pads
-- keep their names (read back in on_built_entity via event.tags).
local on_player_setup_blueprint = function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local mapping = event.mapping.get()
  if not next(mapping) then return end
  local bp = player.blueprint_to_setup
  if not (bp and bp.valid_for_read) then
    bp = player.cursor_stack
  end
  if not (bp and bp.valid_for_read and bp.is_blueprint) then return end
  for index, entity in pairs (mapping) do
    if entity.valid and entity.name == teleporter_name then
      local name = get_pad_name(entity)
      if name then
        bp.set_blueprint_entity_tag(index, "etech_tp_name", name)
      end
    end
  end
end

local on_trigger_created_entity = function(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  if entity.name ~= teleporter_sticker then return end
  local source = event.source
  if not (source and source.valid) then return end
  local stuck_to = entity.sticked_to
  if not (stuck_to and stuck_to.valid) then return end
  teleporter_triggered(source, stuck_to)
end

-- One-shot migration from the original Teleporters mod: converts every
-- placed "teleporter" entity to ours, keeping position/force and recovering
-- custom pad names from the original's chart tags. Also converts teleporter
-- items in player inventories and carries over the researched tech. Run
-- while BOTH mods are installed (after removing the original its entities
-- are already gone from the save), then remove the original mod.
local migrate_from_original = function(command)
  local player = command.player_index and game.get_player(command.player_index)
  local out = function(msg)
    if player and player.valid then player.print(msg) else game.print(msg) end
  end

  if not prototypes.entity["teleporter"] then
    out({"etech-tp-migrate-no-original"})
    return
  end

  local pads = 0
  for _, surface in pairs (game.surfaces) do
    for _, og in pairs (surface.find_entities_filtered{name = "teleporter"}) do
      if og.valid then
        local force = og.force
        local position = og.position

        -- The original mod tags the map with icon = item "teleporter" and
        -- text = the pad's name. Read it before raise_destroy removes it.
        local og_name
        local area = {{position.x - 1, position.y - 1}, {position.x + 1, position.y + 1}}
        for _, tag in pairs (force.find_chart_tags(surface, area)) do
          local icon = tag.icon
          if icon and icon.name == "teleporter" and (icon.type == nil or icon.type == "item") then
            og_name = tag.text
            break
          end
        end

        og.destroy{raise_destroy = true}
        local new = surface.create_entity{name = teleporter_name, position = position, force = force, raise_built = true}
        if new then
          pads = pads + 1
          if og_name and og_name ~= "" then
            local target = og_name
            local n = 2
            while not is_name_available(force, target) do
              target = og_name.." ("..n..")"
              n = n + 1
            end
            rename_teleporter(force, "Teleporter "..new.unit_number, target)
          end
        end
      end
    end
  end

  local items = 0
  if prototypes.item["teleporter"] then
    for _, p in pairs (game.players) do
      local inventory = p.get_main_inventory()
      if inventory then
        local count = inventory.get_item_count("teleporter")
        if count > 0 then
          inventory.remove{name = "teleporter", count = count}
          items = items + inventory.insert{name = teleporter_name, count = count}
        end
      end
    end
  end

  for _, force in pairs (game.forces) do
    local og_tech = force.technologies["teleporter"]
    local our_tech = force.technologies[teleporter_name]
    if og_tech and our_tech and og_tech.researched and not our_tech.researched then
      our_tech.researched = true
    end
  end

  refresh_teleporter_frames()
  out({"etech-tp-migrate-done", pads, items})
end

local teleporters = {}

teleporters.add_commands = function()
  commands.add_command("etech-migrate-teleporters", {"etech-tp-migrate-help"}, migrate_from_original)
end

teleporters.events =
{
  [defines.events.on_built_entity] = on_built_entity,
  [defines.events.on_robot_built_entity] = on_built_entity,
  [defines.events.script_raised_built] = on_built_entity,
  [defines.events.script_raised_revive] = on_built_entity,
  [defines.events.on_entity_cloned] = on_built_entity,
  [defines.events.on_space_platform_built_entity] = on_built_entity,

  [defines.events.on_entity_died] = on_entity_removed,
  [defines.events.on_player_mined_entity] = on_entity_removed,
  [defines.events.on_robot_mined_entity] = on_entity_removed,
  [defines.events.script_raised_destroy] = on_entity_removed,
  [defines.events.on_space_platform_mined_entity] = on_entity_removed,

  [defines.events.on_gui_click] = on_gui_action,
  [defines.events.on_gui_text_changed] = on_gui_action,
  [defines.events.on_gui_confirmed] = on_gui_action,
  [defines.events.on_gui_selection_state_changed] = on_gui_action,
  [defines.events.on_gui_closed] = on_gui_closed,
  [names.hotkeys.focus_search] = on_search_focused,
  [defines.events.on_player_display_resolution_changed] = on_player_display_resolution_changed,
  [defines.events.on_player_display_scale_changed] = on_player_display_scale_changed,

  [defines.events.on_player_died] = on_player_removed,
  [defines.events.on_player_left_game] = on_player_removed,
  [defines.events.on_player_changed_force] = on_player_removed,

  [defines.events.on_chart_tag_modified] = on_chart_tag_modified,
  [defines.events.on_chart_tag_removed] = on_chart_tag_removed,
  [defines.events.on_chart_tag_added] = on_chart_tag_added,

  [defines.events.on_surface_deleted] = on_surface_deleted,
  [defines.events.on_forces_merged] = on_forces_merged,
  [defines.events.on_lua_shortcut] = on_lua_shortcut,
  [names.hotkeys.open_remote] = on_remote_hotkey,

  [defines.events.on_trigger_created_entity] = on_trigger_created_entity,
  [defines.events.on_player_setup_blueprint] = on_player_setup_blueprint,
}

teleporters.on_nth_tick =
{
  [601] = check_pad_alerts,
}

teleporters.on_init = function()
  storage.etech_teleporters = storage.etech_teleporters or script_data
end

teleporters.on_load = function()
  script_data = storage.etech_teleporters or script_data
end

teleporters.on_configuration_changed = function()
  if not storage.etech_teleporters then
    storage.etech_teleporters = script_data
  end
  local stored = storage.etech_teleporters
  stored.surface_aliases = stored.surface_aliases or {}
  stored.surface_filter = stored.surface_filter or {}
  stored.surface_rename_frames = stored.surface_rename_frames or {}
  stored.remote_open = stored.remote_open or {}
  stored.returns = stored.returns or {}
  stored.favorites = stored.favorites or {}
  stored.recent = stored.recent or {}
  stored.sort_mode = stored.sort_mode or {}
  stored.frame_locations = stored.frame_locations or {}
  stored.search_text = stored.search_text or {}
  -- 0.10.0: returns went from a single slot to a newest-first array.
  for player_index, ret in pairs (stored.returns) do
    if ret.surface_index then
      stored.returns[player_index] = {ret}
    end
  end
  -- 0.19.0: favorites/recents rekeyed player.name -> player.index (name
  -- keys broke on player rename). Unknown names are dropped.
  for _, key in ipairs({"favorites", "recent"}) do
    local per_player = stored[key]
    for k, v in pairs (per_player) do
      if type(k) == "string" then
        local p = game.get_player(k)
        if p then per_player[p.index] = per_player[p.index] or v end
        per_player[k] = nil
      end
    end
  end
  script_data = stored
  resync_all_teleporters()
end

return teleporters
