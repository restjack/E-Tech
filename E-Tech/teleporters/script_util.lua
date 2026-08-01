-- teleporters/script_util.lua
-- Small helpers for the teleporter control stage.
--
-- Adapted from "Teleporters" 2.0.x by Klonan (LGPLv3 — see
-- LICENSE-third-party.txt).
--
-- 0.21.1: this file used to do `local util = require("util")` — which returns
-- the CACHED core util module — and then bolt its own functions onto it. That
-- silently handed every other file in the mod a mutated `util`, and a future
-- base-game addition with any of these names would have collided invisibly.
-- It now builds and returns its own table. Only the three functions the
-- teleporter control stage actually calls survived the move; the rest
-- (center, radius, clear_item, copy, first_key, first_value, angle, and a
-- gui_action_handler whose body began with error("don't actually use me"))
-- were dead code carried over from the original mod.

local script_util = {}

-- GUI action registry -------------------------------------------------------
-- Maps a live GUI element to the action table the click handler should run,
-- keyed [player_index][element.index]. Lives in storage via script_data.

local deregister_gui_internal
deregister_gui_internal = function(gui_element, data)
  data[gui_element.index] = nil
  for _, child in pairs (gui_element.children) do
    deregister_gui_internal(child, data)
  end
end

script_util.deregister_gui = function(gui_element, data)
  local player_data = data[gui_element.player_index]
  if not player_data then return end
  deregister_gui_internal(gui_element, player_data)
end

script_util.register_gui = function(data, gui_element, param)
  local player_data = data[gui_element.player_index]
  if not player_data then
    player_data = {}
    data[gui_element.player_index] = player_data
  end
  player_data[gui_element.index] = param
end

-- Geometry ------------------------------------------------------------------

script_util.distance = function(p1, p2)
  return (((p1.x - p2.x) ^ 2) + ((p1.y - p2.y) ^ 2)) ^ 0.5
end

return script_util
