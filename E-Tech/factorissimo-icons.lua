-- factorissimo-icons.lua
-- Map markers for Factorissimo factory buildings. Factorissimo's display
-- upgrade draws overlay signals on the building sprite in the world, but
-- those are rendering objects — the map never shows them. This module
-- mirrors the FIRST overlay signal of each factory building as a chart tag
-- so factories are identifiable in map view, like machines' recipe icons.
--
-- Reads factory data through Factorissimo's own remote interface
-- ("factorissimo": get_factory_by_entity, has_layout). Only loaded when
-- both the etech-factorissimo-icons setting is on and
-- factorissimo-2-notnotmelon is present (checked in control.lua).
--
-- Deleting one of these tags on the map mutes the building until its
-- overlay signal is changed — change the signal to get the tag back.

local UPDATE_TICKS = 300 -- 5 s poll; factory buildings are few

local script_data =
{
  -- [unit_number] = {entity, tag, icon_key, muted}
  buildings = {},
  -- [tag_number] = unit_number; also read by resource-markers' legacy
  -- cleaner so it never mistakes our factory tags for another mod's litter
  tag_numbers = {},
}

local suppress = false

-- has_layout(name) is deterministic per prototype set, so a per-load local
-- cache is multiplayer-safe.
local layout_cache = {}
local is_factory_building = function(entity)
  if entity.type ~= "storage-tank" then return false end
  local name = entity.name
  local cached = layout_cache[name]
  if cached ~= nil then return cached end
  local ok, result = pcall(remote.call, "factorissimo", "has_layout", name)
  result = ok and result or false
  layout_cache[name] = result
  return result
end

local destroy_tag = function(data)
  local tag = data.tag
  if tag and tag.valid then
    script_data.tag_numbers[tag.tag_number] = nil
    suppress = true
    tag.destroy()
    suppress = false
  end
  data.tag = nil
end

-- First signal of the factory's overlay controller (the combinator the
-- display upgrade adds inside) plus the factory id, or nil.
local get_overlay_icon = function(building)
  local ok, factory = pcall(remote.call, "factorissimo", "get_factory_by_entity", building)
  if not (ok and factory) then return end
  local controller = factory.inside_overlay_controller
  if not (controller and controller.valid) then return end
  local behavior = controller.get_control_behavior()
  if not (behavior and behavior.enabled) then return end
  for _, section in pairs (behavior.sections) do
    if section.active then
      for _, filter in pairs (section.filters) do
        local value = filter.value
        if value and value.name then
          return {type = value.type or "item", name = value.name, quality = value.quality}, factory.id
        end
      end
    end
  end
end

local check_building = function(unit_number, data)
  local building = data.entity
  if not (building and building.valid) then
    destroy_tag(data)
    script_data.buildings[unit_number] = nil
    return
  end

  if not settings.global["etech-factorissimo-icons-visible"].value then
    destroy_tag(data)
    data.icon_key = nil
    return
  end

  local icon, factory_id = get_overlay_icon(building)
  local icon_key = icon and ((icon.type or "item") .. ":" .. icon.name .. ":" .. (icon.quality or "")) or nil
  if icon_key == data.icon_key then return end

  -- signal changed: any player mute is lifted on purpose
  data.icon_key = icon_key
  data.muted = false
  destroy_tag(data)
  if not icon_key then return end

  -- A text label matters beyond looks: icon-only chart tags render at the
  -- engine's big map-icon size, icon+text tags render in the compact pin
  -- style. There is no API to scale a tag's icon directly.
  suppress = true
  local tag = building.force.add_chart_tag(building.surface, {
    position = building.position,
    icon = icon,
    text = "Factory" .. (factory_id and (" " .. factory_id) or ""),
  })
  suppress = false
  if tag then
    data.tag = tag
    script_data.tag_numbers[tag.tag_number] = unit_number
  end
end

local scan_all = function()
  local old = script_data.buildings
  script_data.buildings = {}
  for _, surface in pairs (game.surfaces) do
    for _, entity in pairs (surface.find_entities_filtered{type = "storage-tank"}) do
      if entity.unit_number and is_factory_building(entity) then
        script_data.buildings[entity.unit_number] = old[entity.unit_number] or {entity = entity}
        old[entity.unit_number] = nil
      end
    end
  end
  for _, data in pairs (old) do
    destroy_tag(data)
  end
  for unit_number, data in pairs (script_data.buildings) do
    -- forget the cached key so every tag is recreated with the current
    -- format (scan_all runs on init/config-change, not in the hot path)
    data.icon_key = nil
    check_building(unit_number, data)
  end
end

local on_built = function(event)
  local entity = event.created_entity or event.entity or event.destination
  if not (entity and entity.valid and entity.unit_number) then return end
  if not is_factory_building(entity) then return end
  local data = {entity = entity}
  script_data.buildings[entity.unit_number] = data
  check_building(entity.unit_number, data)
end

local on_removed = function(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.unit_number) then return end
  local data = script_data.buildings[entity.unit_number]
  if not data then return end
  destroy_tag(data)
  script_data.buildings[entity.unit_number] = nil
end

local on_chart_tag_removed = function(event)
  if suppress then return end
  local tag = event.tag
  if not (tag and tag.valid) then return end
  local unit_number = script_data.tag_numbers[tag.tag_number]
  if not unit_number then return end
  script_data.tag_numbers[tag.tag_number] = nil
  local data = script_data.buildings[unit_number]
  if data and event.player_index then
    data.muted = true
    data.tag = nil
  end
end

local update_all = function()
  for unit_number, data in pairs (script_data.buildings) do
    if not data.muted then
      check_building(unit_number, data)
    end
  end
end

-- apply the visibility setting the moment it's flipped
local on_setting_changed = function(event)
  if event.setting ~= "etech-factorissimo-icons-visible" then return end
  for unit_number, data in pairs (script_data.buildings) do
    data.icon_key = nil
    check_building(unit_number, data)
  end
end

local icons = {}

icons.events =
{
  [defines.events.on_built_entity] = on_built,
  [defines.events.on_robot_built_entity] = on_built,
  [defines.events.script_raised_built] = on_built,
  [defines.events.script_raised_revive] = on_built,
  [defines.events.on_entity_cloned] = on_built,
  [defines.events.on_space_platform_built_entity] = on_built,

  [defines.events.on_entity_died] = on_removed,
  [defines.events.on_player_mined_entity] = on_removed,
  [defines.events.on_robot_mined_entity] = on_removed,
  [defines.events.script_raised_destroy] = on_removed,
  [defines.events.on_space_platform_mined_entity] = on_removed,

  [defines.events.on_chart_tag_removed] = on_chart_tag_removed,
  [defines.events.on_runtime_mod_setting_changed] = on_setting_changed,
}

icons.on_nth_tick =
{
  [UPDATE_TICKS] = update_all,
}

icons.on_init = function()
  storage.etech_factorissimo_icons = storage.etech_factorissimo_icons or script_data
  scan_all()
end

icons.on_load = function()
  script_data = storage.etech_factorissimo_icons or script_data
end

icons.on_configuration_changed = function()
  if not storage.etech_factorissimo_icons then
    storage.etech_factorissimo_icons = script_data
  else
    script_data = storage.etech_factorissimo_icons
  end
  scan_all()
end

return icons
