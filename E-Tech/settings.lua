-- settings.lua
-- The recipe restore is unconditional (the mod's whole purpose), so it has
-- no toggle. Everything else is opt-in/opt-out here.
--
-- All display strings live in locale/en/settings.cfg
-- ([mod-setting-name] / [mod-setting-description]) - no inline
-- localised_name/localised_description in this file.
--
-- Order scheme (lexicographic per settings tab):
--   Startup tab:   a* = core vanilla/AAI tweaks, b* = absorbed-mod features,
--                  c* = teleport features
--   Map tab:       t* = teleporter tuning, m* = resource markers
--   Per-player:    u*
-- Keep file order matching the order strings.

data:extend({
  ----------------------------------------------------------------------------
  -- Core vanilla/AAI tweaks (startup, a*)
  ----------------------------------------------------------------------------
  {
    type = "bool-setting",
    name = "etech-pickup-crashed-ship",
    setting_type = "startup",
    default_value = true,
    order = "aa",
  },
  {
    type = "bool-setting",
    name = "etech-beacon-all-modules",
    setting_type = "startup",
    default_value = true,
    order = "ab",
  },
  {
    type = "bool-setting",
    name = "etech-quality-asteroid",
    setting_type = "startup",
    default_value = true,
    order = "ac",
  },
  {
    type = "bool-setting",
    name = "etech-quality-module-slots",
    setting_type = "startup",
    default_value = true,
    order = "ad",
  },
  {
    type = "int-setting",
    name = "etech-nuclear-fuel-stack",
    setting_type = "startup",
    default_value = 1,
    minimum_value = 1,
    maximum_value = 1000,
    order = "ae",
  },
  {
    type = "int-setting",
    name = "etech-artillery-shell-stack",
    setting_type = "startup",
    default_value = 1,
    minimum_value = 1,
    maximum_value = 1000,
    order = "af",
  },
  {
    type = "bool-setting",
    name = "etech-ag-science-spoils",
    setting_type = "startup",
    default_value = true,
    order = "ag",
  },
  {
    type = "bool-setting",
    name = "etech-restore-nuclear-fuel",
    setting_type = "startup",
    default_value = false,
    order = "ah",
  },
  {
    type = "bool-setting",
    name = "etech-restore-engine-cosmetics",
    setting_type = "startup",
    default_value = true,
    order = "ai",
  },
  {
    type = "bool-setting",
    name = "etech-debug-log",
    setting_type = "startup",
    default_value = false,
    order = "aj",
  },

  ----------------------------------------------------------------------------
  -- Absorbed-mod features (startup, b*)
  ----------------------------------------------------------------------------
  {
    type = "bool-setting",
    name = "etech-gleba-uranium",
    setting_type = "startup",
    default_value = false,
    order = "ba",
  },
  {
    type = "bool-setting",
    name = "etech-void",
    setting_type = "startup",
    default_value = false,
    order = "bb",
  },
  {
    type = "double-setting",
    name = "etech-void-tint-r",
    setting_type = "startup",
    minimum_value = 0,
    maximum_value = 1,
    default_value = 0.75,
    order = "bb1",
  },
  {
    type = "double-setting",
    name = "etech-void-tint-g",
    setting_type = "startup",
    minimum_value = 0,
    maximum_value = 1,
    default_value = 0,
    order = "bb2",
  },
  {
    type = "double-setting",
    name = "etech-void-tint-b",
    setting_type = "startup",
    minimum_value = 0,
    maximum_value = 1,
    default_value = 1,
    order = "bb3",
  },
  {
    type = "bool-setting",
    name = "etech-void-filtered",
    setting_type = "startup",
    default_value = false,
    order = "bb4",
  },
  {
    type = "int-setting",
    name = "etech-void-slots",
    setting_type = "startup",
    minimum_value = 1,
    maximum_value = 10,
    default_value = 4,
    order = "bb5",
  },
  {
    type = "bool-setting",
    name = "etech-fps-thrusters",
    setting_type = "startup",
    default_value = false,
    order = "bc",
  },
  {
    type = "bool-setting",
    name = "etech-fusion-passthrough",
    setting_type = "startup",
    default_value = false,
    order = "bd",
  },
  {
    type = "bool-setting",
    name = "etech-colorful-biochamber",
    setting_type = "startup",
    default_value = false,
    order = "be",
  },
  {
    type = "bool-setting",
    name = "etech-copy-paste-modules",
    setting_type = "startup",
    default_value = false,
    order = "bf",
  },
  {
    type = "bool-setting",
    name = "etech-total-productivity",
    setting_type = "startup",
    default_value = false,
    order = "bg",
  },
  {
    type = "bool-setting",
    name = "etech-prod-logistics",
    setting_type = "startup",
    default_value = true,
    order = "bg1",
  },
  {
    type = "bool-setting",
    name = "etech-prod-buildings",
    setting_type = "startup",
    default_value = true,
    order = "bg2",
  },
  {
    type = "bool-setting",
    name = "etech-prod-military",
    setting_type = "startup",
    default_value = true,
    order = "bg3",
  },
  {
    type = "bool-setting",
    name = "etech-prod-misc",
    setting_type = "startup",
    default_value = true,
    order = "bg4",
  },
  {
    type = "bool-setting",
    name = "etech-jetpack-ui",
    setting_type = "startup",
    default_value = false,
    order = "bh",
  },
  {
    type = "bool-setting",
    name = "etech-map-settings",
    setting_type = "startup",
    default_value = false,
    order = "bi",
  },
  {
    type = "bool-setting",
    name = "etech-resource-markers",
    setting_type = "startup",
    default_value = false,
    order = "bj",
  },
  {
    type = "bool-setting",
    name = "etech-factory-hub",
    setting_type = "startup",
    default_value = false,
    order = "bk",
  },
  -- The former factory-hub tuning settings (slots, stacks per item, active
  -- providers only, energy per item, range, nested reach) are fixed values
  -- since 0.17.0 - see factory-hub/data.lua and factory-hub/control.lua.

  ----------------------------------------------------------------------------
  -- Teleport features (startup, c*)
  ----------------------------------------------------------------------------
  {
    type = "bool-setting",
    name = "etech-teleporters",
    setting_type = "startup",
    default_value = false,
    order = "ca",
  },
  {
    type = "bool-setting",
    name = "etech-teleport-shortcut",
    setting_type = "startup",
    default_value = false,
    order = "cb",
  },

  ----------------------------------------------------------------------------
  -- Teleporter tuning (runtime-global, t*) + markers (m*)
  ----------------------------------------------------------------------------
  {
    type = "double-setting",
    name = "etech-teleporter-energy-mj",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 0,
    maximum_value = 200,
    order = "ta",
  },
  {
    type = "double-setting",
    name = "etech-teleporter-energy-distance-mj",
    setting_type = "runtime-global",
    default_value = 0,
    minimum_value = 0,
    maximum_value = 100,
    order = "tb",
  },
  {
    type = "bool-setting",
    name = "etech-teleporter-cross-surface",
    setting_type = "runtime-global",
    default_value = true,
    order = "tc",
  },
  {
    type = "double-setting",
    name = "etech-teleporter-cross-surface-multiplier",
    setting_type = "runtime-global",
    default_value = 1,
    minimum_value = 0,
    maximum_value = 100,
    order = "td",
  },
  {
    type = "bool-setting",
    name = "etech-teleporter-remote",
    setting_type = "runtime-global",
    default_value = true,
    order = "te",
  },
  {
    type = "double-setting",
    name = "etech-teleporter-remote-multiplier",
    setting_type = "runtime-global",
    default_value = 2,
    minimum_value = 0,
    maximum_value = 100,
    order = "tf",
  },
  {
    type = "bool-setting",
    name = "etech-teleporter-return-enabled",
    setting_type = "runtime-global",
    default_value = true,
    order = "tg",
  },
  {
    type = "double-setting",
    name = "etech-teleporter-return-grace-min",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 0,
    maximum_value = 1440,
    order = "th",
  },
  {
    type = "bool-setting",
    name = "etech-teleporter-players-section",
    setting_type = "runtime-global",
    default_value = true,
    order = "ti",
  },
  {
    type = "bool-setting",
    name = "etech-teleporter-alerts",
    setting_type = "runtime-global",
    default_value = true,
    order = "tj",
  },
  {
    type = "int-setting",
    name = "etech-markers-min-size",
    setting_type = "runtime-global",
    default_value = 1,
    minimum_value = 1,
    maximum_value = 10000,
    order = "ma",
  },

  ----------------------------------------------------------------------------
  -- Per-player (u*)
  ----------------------------------------------------------------------------
  {
    type = "bool-setting",
    name = "etech-cpm-enabled",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "ua",
  },
  {
    type = "double-setting",
    name = "etech-teleporter-sound-volume",
    setting_type = "runtime-per-user",
    default_value = 1,
    minimum_value = 0,
    maximum_value = 2,
    order = "ub",
  },
  {
    type = "int-setting",
    name = "etech-teleporter-preview-size",
    setting_type = "runtime-per-user",
    default_value = 200,
    minimum_value = 96,
    maximum_value = 512,
    order = "uc",
  },
  {
    type = "bool-setting",
    name = "etech-teleporter-hide-platforms",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "ud",
  },
})
