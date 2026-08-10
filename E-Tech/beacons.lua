-- beacons.lua
-- Allow every module type in every beacon (productivity + quality included).
--
-- Two prototype fields gate what a beacon accepts:
--   allowed_effects           - which effect types it may transmit. Vanilla
--                               beacons omit "productivity" and "quality".
--   allowed_module_categories - optional whitelist of module categories. If
--                               present, only those categories fit. Clearing
--                               it lets any category in.
-- We open both on every beacon prototype (modded beacons too) - except the
-- script-driven ones, see below.

local ALL_EFFECTS = {"speed", "productivity", "consumption", "pollution", "quality"}

-- beacon-interface does not use allowed_module_categories as a gameplay
-- restriction; it uses it as an identity marker. Its control.lua looks for
-- beacon prototypes whose whitelist is exactly {"beacon-interface--module-category"}
-- and registers build handlers for those names. Clearing the field leaves it
-- with zero matches and it asserts on load:
--
--   beacon-interface 1.1.2 errored when running a required file.
--   __beacon-interface__/control.lua:63: ... [C]: in function 'assert'
--
-- Those beacons are hidden effect emitters driven by a remote interface and
-- only ever hold beacon-interface's own generated modules, so there is nothing
-- for us to open up anyway. Same applies to other mods that deepcopy one of
-- them (quality-condenser makes its own copy), which is why this matches on
-- the category rather than on prototype names.
local BEACON_INTERFACE_CATEGORY = "beacon-interface--module-category"

local function is_script_driven_interface(beacon)
  for _, category in pairs(beacon.allowed_module_categories or {}) do
    if category == BEACON_INTERFACE_CATEGORY then return true end
  end
  return false
end

local debug_log = settings.startup["etech-debug-log"].value

local count = 0
local skipped = 0
for name, beacon in pairs(data.raw["beacon"] or {}) do
  if is_script_driven_interface(beacon) then
    skipped = skipped + 1
    if debug_log then log("[E-Tech] left beacon-interface beacon alone: " .. name) end
  else
    -- deepcopy, not a shared reference: one later mod doing
    -- table.insert(beacon.allowed_effects, ...) would otherwise mutate every
    -- beacon in the game at once (0.21.1).
    beacon.allowed_effects = table.deepcopy(ALL_EFFECTS)
    beacon.allowed_module_categories = nil
    count = count + 1
    if debug_log then log("[E-Tech] opened all modules on beacon: " .. name) end
  end
end
log("[E-Tech] beacons opened for all modules: " .. count .. " (left alone: " .. skipped .. ")")
