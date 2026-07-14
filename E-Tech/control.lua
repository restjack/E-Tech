-- control.lua
-- Runtime logic for the teleport-to-player shortcut (prototype in data.lua,
-- gated by the etech-teleport-shortcut startup setting; when the setting is
-- off the shortcut doesn't exist and these handlers never match anything).
--
-- Behavior: exactly one other connected player -> teleport straight to them.
-- More than one -> a picker window (one button per player). Zero -> message.

local SHORTCUT = "etech-teleport-to-player"
local FRAME = "etech-tp-frame"
local BTN_PREFIX = "etech-tp-player-"
local CANCEL = "etech-tp-cancel"

-- Teleport `player` next to `target`. Uses the target's physical position and
-- surface so it works while the target is in remote view or on another
-- surface (character cross-surface teleport is supported since 2.0).
local function teleport_to(player, target)
  local surface = target.physical_surface or target.surface
  local pos = target.physical_position or target.position
  local dest = surface.find_non_colliding_position("character", pos, 16, 0.5) or pos
  local ok, err = pcall(function()
    if player.character then
      player.character.teleport(dest, surface)
    else
      player.teleport(dest, surface)
    end
  end)
  if ok then
    player.print("[E-Tech] Teleported to " .. target.name .. ".")
  else
    player.print("[E-Tech] Teleport failed: " .. tostring(err))
  end
end

local function close_picker(player)
  local frame = player.gui.screen[FRAME]
  if frame then frame.destroy() end
end

local function open_picker(player, others)
  close_picker(player)
  local frame = player.gui.screen.add{
    type = "frame",
    name = FRAME,
    caption = "Teleport to player",
    direction = "vertical",
  }
  frame.auto_center = true
  for _, p in pairs(others) do
    frame.add{type = "button", name = BTN_PREFIX .. p.index, caption = p.name}
  end
  frame.add{type = "button", name = CANCEL, caption = "Cancel"}
  player.opened = frame -- lets E / Escape close it via on_gui_closed
end

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= SHORTCUT then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local others = {}
  for _, p in pairs(game.connected_players) do
    if p.index ~= player.index then others[#others + 1] = p end
  end
  if #others == 0 then
    player.print("[E-Tech] No other players online.")
  elseif #others == 1 then
    teleport_to(player, others[1])
  else
    open_picker(player, others)
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local el = event.element
  if not (el and el.valid) then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  if el.name == CANCEL then
    close_picker(player)
  elseif el.name:sub(1, #BTN_PREFIX) == BTN_PREFIX then
    local target = game.get_player(tonumber(el.name:sub(#BTN_PREFIX + 1)))
    close_picker(player)
    if target and target.connected then
      teleport_to(player, target)
    else
      player.print("[E-Tech] That player is no longer online.")
    end
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local el = event.element
  if el and el.valid and el.name == FRAME then el.destroy() end
end)
