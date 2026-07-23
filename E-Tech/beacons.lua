-- beacons.lua
-- Allow every module type in every beacon (productivity + quality included).
--
-- Two prototype fields gate what a beacon accepts:
--   allowed_effects           - which effect types it may transmit. Vanilla
--                               beacons omit "productivity" and "quality".
--   allowed_module_categories - optional whitelist of module categories. If
--                               present, only those categories fit. Clearing
--                               it lets any category in.
-- We open both on every beacon prototype (modded beacons too).

local ALL_EFFECTS = {"speed", "productivity", "consumption", "pollution", "quality"}

local debug_log = settings.startup["etech-debug-log"].value

local count = 0
for name, beacon in pairs(data.raw["beacon"] or {}) do
  beacon.allowed_effects = ALL_EFFECTS
  beacon.allowed_module_categories = nil
  count = count + 1
  if debug_log then log("[E-Tech] opened all modules on beacon: " .. name) end
end
log("[E-Tech] beacons opened for all modules: " .. count)
