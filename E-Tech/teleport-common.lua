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
-- Also owns the per-player death location both features offer as a "teleport
-- to your body" jump (see the death-slot block below).

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

return M
