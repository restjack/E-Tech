-- teleport-common.lua
-- Shared player-teleport core used by both the teleporter pads
-- (teleporters/control.lua) and the teleport-to-player shortcut
-- (teleport-player.lua) - the two used to carry near-duplicate logic.
--
-- Handles the cases a bare player.teleport gets wrong:
--  * player driving a car/tank/spidertron: the VEHICLE teleports (with its
--    passengers) to a non-colliding spot, instead of the player being
--    yanked out / stranded.
--  * player in rolling stock: refused (reason "train") - trains need rails.
--  * character prototype swapped by mods (Jetpack etc.): the collision
--    check uses the actual character prototype name.
--  * anything the engine still refuses is caught by pcall (reason "error")
--    instead of crashing the GUI handler.
--
-- Also owns two things both features share and neither should own alone:
--  * the per-player death location behind the "teleport to your body" jump
--  * teleport-to-player consent (ask the target first), including the prompt,
--    the remembered answers and the in-game settings window that manages them

local M = {}

-- Teleport `player` (or the vehicle they're driving) to `position` on
-- `surface`. opts.exact skips the find_non_colliding_position search for the
-- on-foot case (used for pad-to-pad jumps that land exactly on the pad).
-- Returns ok(boolean), result: the landing position on success, or a reason
-- string ("train" | "error") on failure.
M.teleport_player = function(player, surface, position, opts)
  opts = opts or {}
  local vehicle = player.vehicle
  if vehicle and vehicle.valid then
    if vehicle.type == "car" or vehicle.type == "spider-vehicle" then
      local dest = surface.find_non_colliding_position(vehicle.name, position, 16, 0.5) or position
      local ok = pcall(vehicle.teleport, vehicle, dest, surface)
      if ok then return true, dest end
      return false, "error"
    end
    return false, "train"
  end
  local character = player.character
  local dest = position
  if not opts.exact then
    local cname = character and character.name or "character"
    dest = surface.find_non_colliding_position(cname, position, 16, 0.5) or position
  end
  local ok = pcall(function()
    if character then
      character.teleport(dest, surface)
    else
      player.teleport(dest, surface)
    end
  end)
  if ok then return true, dest end
  return false, "error"
end

--------------------------------------------------------------------------------
-- Death location ("teleport to your body")
--------------------------------------------------------------------------------
-- One slot per player, overwritten by the next death. It lives in its own
-- storage key rather than in the teleporter module's script_data because both
-- teleport features offer the jump and either can be enabled alone - the pad
-- module isn't even required when only the shortcut is on.
--
-- Recorded unconditionally on death; the ENABLED setting is read when the slot
-- is asked for, so turning the feature on mid-save works for a death that
-- already happened.
local DEATH_KEY = "etech_death_slots"

M.record_death = function(player)
  local slots = storage[DEATH_KEY]
  if not slots then
    slots = {}
    storage[DEATH_KEY] = slots
  end
  slots[player.index] = {
    surface_index = (player.physical_surface or player.surface).index,
    position = player.physical_position or player.position,
    tick = game.tick,
  }
end

-- The player's still-usable death slot (feature on, surface alive, grace not
-- expired), or nil. Prunes the dead entry as a side effect - same shape as the
-- teleporter module's get_valid_returns.
M.get_death_slot = function(player)
  local slots = storage[DEATH_KEY]
  local slot = slots and slots[player.index]
  if not slot then return nil end
  if not settings.global["etech-teleport-body-enabled"].value then return nil end
  local surface = game.surfaces[slot.surface_index]
  local grace = settings.global["etech-teleport-body-grace-min"].value
  if not (surface and surface.valid)
    or (grace > 0 and game.tick > slot.tick + grace * 60 * 60) then
    slots[player.index] = nil
    return nil
  end
  return slot
end

M.clear_death_slot = function(player)
  local slots = storage[DEATH_KEY]
  if slots then slots[player.index] = nil end
end

-- Whole minutes since the recorded death, for the button tooltip.
M.death_age_minutes = function(slot)
  return math.floor((game.tick - slot.tick) / 3600)
end

M.on_player_died = function(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then M.record_death(player) end
end

-- The corpse decayed, so there is nothing left to walk back to. Matched on the
-- death TICK, not just the player: an older corpse expiring must not clear the
-- slot of a more recent death.
M.on_character_corpse_expired = function(event)
  local corpse = event.corpse
  if not (corpse and corpse.valid) then return end
  local index = corpse.character_corpse_player_index
  if not index then return end
  local slots = storage[DEATH_KEY]
  local slot = slots and slots[index]
  if not slot then return end
  if math.abs(corpse.character_corpse_tick_of_death - slot.tick) <= 60 then
    slots[index] = nil
  end
end

-- The teleport sound the traveling player themselves hears (per-player
-- volume setting).
M.play_sound = function(player)
  player.play_sound{
    path = "etech-teleporter-sound",
    volume_modifier = settings.get_player_settings(player)["etech-teleporter-sound-volume"].value,
  }
end

-- Teleport flash, when the explosion prototype exists (it ships with the
-- teleporter pads; the shortcut can be enabled without them).
local FLASH = "etech-teleporter-explosion"
M.flash_at = function(surface, position)
  if surface and surface.valid and prototypes.entity[FLASH] then
    surface.create_entity{name = FLASH, position = position}
  end
end

--------------------------------------------------------------------------------
-- Teleport-to-player consent
--------------------------------------------------------------------------------
-- Landing on top of someone unannounced is fine with friends and rude with
-- strangers, so the target decides. Four answers, because "yes" and "no" both
-- come in a one-off and a standing flavour:
--
--   Yes, once | Yes, always | No, once | No, always
--
-- The two "always" answers are remembered per (target, requester) pair and can
-- be taken back any time in the settings window (the gear in either teleport
-- window) - a standing answer you cannot revoke is a trap, not a convenience.
-- A target with no standing answer for that requester is asked; unanswered
-- prompts expire on their own so a requester is never left hanging.
--
-- Lives here rather than in either feature because both offer the jump and
-- either can be enabled alone.

local CONSENT_KEY = "etech_consent"
local PROMPT_FRAME = "etech-tp-consent-frame"
local SETTINGS_FRAME = "etech-tp-consent-settings"
local TIMEOUT_TICKS = 30 * 60

local ANSWER_BUTTONS = {
  ["etech-tp-consent-yes-once"] = { allow = true },
  ["etech-tp-consent-yes-always"] = { allow = true, remember = true },
  ["etech-tp-consent-no-once"] = { allow = false },
  ["etech-tp-consent-no-always"] = { allow = false, remember = true },
}

-- Policy dropdown order, and the value each index maps to.
local POLICIES = {"ask", "allow", "deny"}
local POLICY_INDEX = { ask = 1, allow = 2, deny = 3 }

local function consent_data()
  local data = storage[CONSENT_KEY]
  if not data then
    data = { policy = {}, players = {}, pending = {} }
    storage[CONSENT_KEY] = data
  end
  data.policy = data.policy or {}
  data.players = data.players or {}
  data.pending = data.pending or {}
  return data
end

local function consent_required()
  return settings.global["etech-teleporter-consent"].value
end

local function close_frame(player, name)
  local frame = player.gui.screen[name]
  if frame and frame.valid then frame.destroy() end
end

-- Flash, sound, and the arrival message - the part every path shares once a
-- jump to a player is actually going ahead.
M.do_player_teleport = function(player, target)
  if not (player.valid and target.valid and target.connected) then
    if player.valid then player.print({"etech-tp-player-offline"}) end
    return false
  end
  local surface = target.physical_surface or target.surface
  local position = target.physical_position or target.position
  local from_surface = player.physical_surface or player.surface
  local from_position = player.physical_position or player.position
  local ok, result = M.teleport_player(player, surface, position)
  if not ok then
    player.print(result == "train" and {"etech-tp-in-train"} or {"etech-tp2p-failed"})
    return false
  end
  M.flash_at(from_surface, from_position)
  M.flash_at(surface, result)
  M.play_sound(player)
  player.print({"etech-tp2p-done", target.name})
  target.print({"etech-tp-consent-arrived", player.name})
  return true
end

local function open_prompt(target, requester)
  close_frame(target, PROMPT_FRAME)
  local frame = target.gui.screen.add{type = "frame", name = PROMPT_FRAME, direction = "vertical"}
  frame.auto_center = true
  local title_flow = frame.add{type = "flow", direction = "horizontal"}
  title_flow.style.vertical_align = "center"
  local title = title_flow.add{type = "label", style = "frame_title", caption = {"etech-tp-consent-title"}}
  title.drag_target = frame
  local pusher = title_flow.add{type = "empty-widget", style = "draggable_space_header"}
  pusher.style.horizontally_stretchable = true
  pusher.drag_target = frame
  frame.add{type = "label", caption = {"etech-tp-consent-question", requester.name}}
  local buttons = frame.add{type = "table", column_count = 2}
  buttons.style.horizontal_spacing = 8
  buttons.style.vertical_spacing = 4
  buttons.add{type = "button", name = "etech-tp-consent-yes-once", caption = {"etech-tp-consent-yes-once"}}
  buttons.add{type = "button", name = "etech-tp-consent-yes-always", caption = {"etech-tp-consent-yes-always"}}
  buttons.add{type = "button", name = "etech-tp-consent-no-once", caption = {"etech-tp-consent-no-once"}}
  buttons.add{type = "button", name = "etech-tp-consent-no-always", caption = {"etech-tp-consent-no-always"}}
  frame.add{type = "label", caption = {"etech-tp-consent-expires", math.floor(TIMEOUT_TICKS / 60)}}
end

-- May `player` land on `target`? Returns "allowed" | "denied" | "pending" |
-- "busy". "pending" means the target has been asked and will decide; the
-- teleport then happens from the answer handler, not from the caller.
M.request_teleport = function(player, target)
  if not consent_required() then return "allowed" end
  if player.index == target.index then return "allowed" end
  local data = consent_data()
  local remembered = data.players[target.index] and data.players[target.index][player.index]
  local decision = remembered or data.policy[target.index] or "ask"
  if decision == "allow" then return "allowed" end
  if decision == "deny" then return "denied" end
  local pending = data.pending[target.index]
  if pending and game.tick - pending.tick < TIMEOUT_TICKS then
    return pending.requester == player.index and "pending" or "busy"
  end
  data.pending[target.index] = { requester = player.index, tick = game.tick }
  open_prompt(target, player)
  return "pending"
end

local function answer(target, spec)
  local data = consent_data()
  local pending = data.pending[target.index]
  close_frame(target, PROMPT_FRAME)
  data.pending[target.index] = nil
  if not pending then return end
  local requester = game.get_player(pending.requester)
  if spec.remember then
    local per_player = data.players[target.index]
    if not per_player then
      per_player = {}
      data.players[target.index] = per_player
    end
    per_player[pending.requester] = spec.allow and "allow" or "deny"
  end
  if not (requester and requester.valid and requester.connected) then return end
  if spec.allow then
    M.do_player_teleport(requester, target)
  else
    requester.print({"etech-tp-consent-refused", target.name})
  end
end

-- Settings window: the standing answers, and what happens to requests from
-- anyone without one.
local function refresh_settings(player)
  local frame = player.gui.screen[SETTINGS_FRAME]
  if not (frame and frame.valid) then return end
  local list = frame["etech-tp-consent-list"]
  if not (list and list.valid) then return end
  list.clear()
  local data = consent_data()
  local per_player = data.players[player.index] or {}
  local any = false
  for requester_index, decision in pairs(per_player) do
    local other = game.get_player(requester_index)
    if other then
      any = true
      list.add{type = "label", caption = other.name}
      list.add{type = "label", caption = (decision == "allow")
        and {"etech-tp-consent-remembered-allow"} or {"etech-tp-consent-remembered-deny"}}
      list.add{type = "button",
        caption = {"etech-tp-consent-forget"},
        tags = {etech_consent = "forget", player_index = requester_index}}
    end
  end
  if not any then
    list.add{type = "label", caption = {"etech-tp-consent-none"}}
  end
end

M.open_consent_settings = function(player)
  if player.gui.screen[SETTINGS_FRAME] then
    close_frame(player, SETTINGS_FRAME)
    return
  end
  local frame = player.gui.screen.add{type = "frame", name = SETTINGS_FRAME, direction = "vertical"}
  frame.auto_center = true
  local title_flow = frame.add{type = "flow", direction = "horizontal"}
  title_flow.style.vertical_align = "center"
  local title = title_flow.add{type = "label", style = "frame_title", caption = {"etech-tp-consent-settings-title"}}
  title.drag_target = frame
  local pusher = title_flow.add{type = "empty-widget", style = "draggable_space_header"}
  pusher.style.horizontally_stretchable = true
  pusher.drag_target = frame
  title_flow.add{type = "sprite-button", name = "etech-tp-consent-settings-close",
    style = "frame_action_button", sprite = "utility/close"}

  frame.add{type = "label", caption = {"etech-tp-consent-policy"}}
  local policy = consent_data().policy[player.index] or "ask"
  frame.add{type = "drop-down", name = "etech-tp-consent-policy",
    items = {{"etech-tp-consent-policy-ask"}, {"etech-tp-consent-policy-allow"}, {"etech-tp-consent-policy-deny"}},
    selected_index = POLICY_INDEX[policy] or 1}
  frame.add{type = "label", caption = {"etech-tp-consent-remembered"}}
  local list = frame.add{type = "table", name = "etech-tp-consent-list", column_count = 3}
  list.style.horizontal_spacing = 8
  refresh_settings(player)
  player.opened = frame
end

-- Click routing for every consent window. Returns true when the click was
-- ours, so the caller's own handler can stop looking.
M.handle_gui_click = function(player, element)
  local name = element.name
  local spec = ANSWER_BUTTONS[name]
  if spec then
    answer(player, spec)
    return true
  end
  if name == "etech-tp-consent-settings-close" then
    close_frame(player, SETTINGS_FRAME)
    return true
  end
  local tags = element.tags
  if tags and tags.etech_consent == "forget" then
    local per_player = consent_data().players[player.index]
    if per_player then per_player[tags.player_index] = nil end
    refresh_settings(player)
    return true
  end
  return false
end

M.handle_gui_selection = function(player, element)
  if element.name ~= "etech-tp-consent-policy" then return false end
  consent_data().policy[player.index] = POLICIES[element.selected_index] or "ask"
  return true
end

M.handle_gui_closed = function(player, element)
  if not (element and element.valid) then return false end
  if element.name == SETTINGS_FRAME then
    element.destroy()
    return true
  end
  return false
end

-- An unanswered prompt must not pin the target forever, nor leave the
-- requester waiting on a window someone alt-tabbed away from.
M.expire_consent_prompts = function()
  local data = storage[CONSENT_KEY]
  if not data or not data.pending then return end
  for target_index, pending in pairs(data.pending) do
    if game.tick - pending.tick >= TIMEOUT_TICKS then
      data.pending[target_index] = nil
      local target = game.get_player(target_index)
      if target then close_frame(target, PROMPT_FRAME) end
      local requester = game.get_player(pending.requester)
      if requester and requester.connected then
        requester.print({"etech-tp-consent-expired", target and target.name or "?"})
      end
    end
  end
end

return M
