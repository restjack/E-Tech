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

-- The teleport sound the traveling player themselves hears (per-player
-- volume setting).
M.play_sound = function(player)
  player.play_sound{
    path = "etech-teleporter-sound",
    volume_modifier = settings.get_player_settings(player)["etech-teleporter-sound-volume"].value,
  }
end

return M
