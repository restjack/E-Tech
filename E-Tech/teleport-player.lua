-- teleport-player.lua
-- Runtime logic for the teleport-to-player shortcut (prototype in data.lua,
-- gated by the etech-teleport-shortcut startup setting; when the setting is
-- off the shortcut doesn't exist and these handlers never match anything).
--
-- Behavior: exactly one other connected player -> teleport straight to them.
-- More than one -> a picker window (one button per player). Zero -> message.
-- When the "teleport to your body" setting is on and the player has a fresh
-- death location, the picker always opens (with a body button on top), since
-- a straight jump to the only other player would hide that choice.
--
-- The death location itself is recorded here (on_player_died) rather than in
-- the teleporter-pad module: this lib is registered unconditionally, so the
-- body jump works with either teleport feature - or both.
--
-- Returned as an event_handler lib (registered from control.lua) so it can
-- share on_gui_click etc. with the teleporters module without the handlers
-- overwriting each other.

local common = require("teleport-common")

local SHORTCUT = "etech-teleport-to-player"
local FRAME = "etech-tp-frame"
local BTN_PREFIX = "etech-tp-player-"
local BODY = "etech-tp-body-button"
local CANCEL = "etech-tp-cancel"
local CLOSE = "etech-tp-close"

-- Teleport flash at both ends, when the explosion prototypes exist (they're
-- part of the teleporter-pads toggle; this shortcut can be enabled alone).
local FLASH = "etech-teleporter-explosion"
local function flash_at(surface, position)
  if prototypes.entity[FLASH] then
    surface.create_entity{name = FLASH, position = position}
  end
end

-- Teleport `player` next to `target`. Uses the target's physical position and
-- surface so it works while the target is in remote view or on another
-- surface (character cross-surface teleport is supported since 2.0).
local function teleport_to(player, target)
  local surface = target.physical_surface or target.surface
  local pos = target.physical_position or target.position
  local from_surface = player.physical_surface or player.surface
  local from_position = player.physical_position or player.position
  local ok, result = common.teleport_player(player, surface, pos)
  if ok then
    flash_at(from_surface, from_position)
    flash_at(surface, result)
    common.play_sound(player)
    player.print({"etech-tp2p-done", target.name})
  elseif result == "train" then
    player.print({"etech-tp-in-train"})
  else
    player.print({"etech-tp2p-failed"})
  end
end

-- Teleport `player` back to where they last died. Free, one-shot: the slot is
-- cleared once the jump actually happened.
local function teleport_to_body(player)
  local slot = common.get_death_slot(player)
  if not slot then
    player.print({"etech-tp-body-expired"})
    return
  end
  local surface = game.surfaces[slot.surface_index]
  local from_surface = player.physical_surface or player.surface
  local from_position = player.physical_position or player.position
  local ok, result = common.teleport_player(player, surface, slot.position)
  if ok then
    flash_at(from_surface, from_position)
    flash_at(surface, result)
    common.play_sound(player)
    common.clear_death_slot(player)
    player.print({"etech-tp-body-done"})
  elseif result == "train" then
    player.print({"etech-tp-in-train"})
  else
    player.print({"etech-tp2p-failed"})
  end
end

local function close_picker(player)
  local frame = player.gui.screen[FRAME]
  if frame then frame.destroy() end
end

local function open_picker(player, others, body)
  close_picker(player)
  local frame = player.gui.screen.add{
    type = "frame",
    name = FRAME,
    direction = "vertical",
  }
  frame.auto_center = true
  local title_flow = frame.add{type = "flow", direction = "horizontal"}
  title_flow.style.vertical_align = "center"
  local title = title_flow.add{type = "label", style = "frame_title", caption = {"etech-tp2p-title"}}
  title.drag_target = frame
  local pusher = title_flow.add{type = "empty-widget", style = "draggable_space_header"}
  pusher.style.horizontally_stretchable = true
  pusher.style.vertically_stretchable = true
  pusher.drag_target = frame
  title_flow.add{type = "sprite-button", name = CLOSE, style = "frame_action_button", sprite = "utility/close"}
  if body then
    frame.add{
      type = "button",
      name = BODY,
      caption = {"etech-tp-body"},
      tooltip = {"etech-tp-body-tooltip-plain", common.death_age_minutes(body)},
    }
  end
  for _, p in pairs(others) do
    frame.add{type = "button", name = BTN_PREFIX .. p.index, caption = p.name}
  end
  frame.add{type = "button", name = CANCEL, caption = {"etech-tp2p-cancel"}}
  player.opened = frame -- lets E / Escape close it via on_gui_closed
end

local function on_lua_shortcut(event)
  if event.prototype_name ~= SHORTCUT then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local others = {}
  for _, p in pairs(game.connected_players) do
    if p.index ~= player.index then others[#others + 1] = p end
  end
  local body = common.get_death_slot(player)
  if body then
    -- One choice only (dead body, nobody online): jump straight there.
    if #others == 0 then
      teleport_to_body(player)
    else
      open_picker(player, others, body)
    end
  elseif #others == 0 then
    player.print({"etech-tp2p-nobody"})
  elseif #others == 1 then
    teleport_to(player, others[1])
  else
    open_picker(player, others)
  end
end

local function on_gui_click(event)
  local el = event.element
  if not (el and el.valid) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  if el.name == CANCEL or el.name == CLOSE then
    close_picker(player)
  elseif el.name == BODY then
    close_picker(player)
    teleport_to_body(player)
  elseif el.name:sub(1, #BTN_PREFIX) == BTN_PREFIX then
    local target = game.get_player(tonumber(el.name:sub(#BTN_PREFIX + 1)))
    close_picker(player)
    if target and target.connected then
      teleport_to(player, target)
    else
      player.print({"etech-tp-player-offline"})
    end
  end
end

local function on_gui_closed(event)
  local el = event.element
  if el and el.valid and el.name == FRAME then el.destroy() end
end

local lib = {}

lib.events =
{
  [defines.events.on_lua_shortcut] = on_lua_shortcut,
  [defines.events.on_gui_click] = on_gui_click,
  [defines.events.on_gui_closed] = on_gui_closed,
  -- Death bookkeeping for BOTH teleport features (see the header): this lib is
  -- the only one registered unconditionally.
  [defines.events.on_player_died] = common.on_player_died,
  [defines.events.on_character_corpse_expired] = common.on_character_corpse_expired,
}

return lib
