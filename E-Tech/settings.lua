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
    default_value = true,
    order = "ba",
  },
  {
    type = "bool-setting",
    name = "etech-void",
    setting_type = "startup",
    default_value = true,
    order = "bb",
  },
  -- 0.21.1: was three separate 0-1 sliders (etech-void-tint-r/g/b) - three
  -- rows in the settings list for one colour. One hex string instead; the old
  -- settings are simply forgotten, and a save that had them keeps working
  -- because startup settings only affect prototypes, not world state.
  {
    type = "string-setting",
    name = "etech-void-tint",
    setting_type = "startup",
    default_value = "BF00FF",
    allow_blank = false,
    order = "bb1",
  },
  {
    type = "bool-setting",
    name = "etech-void-filtered",
    setting_type = "startup",
    default_value = true,
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
    default_value = true,
    order = "bc",
  },
  {
    type = "bool-setting",
    name = "etech-fusion-passthrough",
    setting_type = "startup",
    default_value = true,
    order = "bd",
  },
  {
    type = "bool-setting",
    name = "etech-colorful-biochamber",
    setting_type = "startup",
    default_value = true,
    order = "be",
  },
  {
    type = "bool-setting",
    name = "etech-copy-paste-modules",
    setting_type = "startup",
    default_value = true,
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
    default_value = true,
    order = "bh",
  },
  {
    type = "bool-setting",
    name = "etech-map-settings",
    setting_type = "startup",
    default_value = true,
    order = "bi",
  },
  {
    type = "bool-setting",
    name = "etech-resource-markers",
    setting_type = "startup",
    default_value = true,
    order = "bj",
  },
  {
    type = "bool-setting",
    name = "etech-factory-hub",
    setting_type = "startup",
    default_value = true,
    order = "bk",
  },
  -- The former factory-hub tuning settings (slots, stacks per item, active
  -- providers only, energy per item, range, nested reach) are fixed values
  -- since 0.17.0 - see factory-hub/data.lua and factory-hub/control.lua.
  {
    type = "bool-setting",
    name = "etech-factory-terminal",
    setting_type = "startup",
    default_value = true,
    order = "bk1",
  },
  {
    type = "bool-setting",
    name = "etech-factory-roboport",
    setting_type = "startup",
    default_value = true,
    order = "bl",
  },
  {
    type = "bool-setting",
    name = "etech-factory-mk4",
    setting_type = "startup",
    default_value = true,
    order = "bm",
  },

  ----------------------------------------------------------------------------
  -- Factorissimo interior roboport tuning (startup, r*)
  -- Defaults reproduce the absorbed factorissimo-roboport-buff (radius 64,
  -- 7/7 slots) and add the charging fix it never had. See misc-tweaks.lua.
  ----------------------------------------------------------------------------
  {
    type = "int-setting",
    name = "etech-factory-roboport-logistics-radius",
    setting_type = "startup",
    default_value = 64,
    minimum_value = 2,
    maximum_value = 512,
    order = "ra",
  },
  {
    type = "int-setting",
    name = "etech-factory-roboport-robot-slots",
    setting_type = "startup",
    default_value = 7,
    minimum_value = 0,
    maximum_value = 100,
    order = "rb",
  },
  {
    type = "int-setting",
    name = "etech-factory-roboport-material-slots",
    setting_type = "startup",
    default_value = 7,
    minimum_value = 1,
    maximum_value = 100,
    order = "rc",
  },
  {
    type = "int-setting",
    name = "etech-factory-roboport-pads",
    setting_type = "startup",
    default_value = 16,
    minimum_value = 0,
    maximum_value = 512,
    order = "rd",
  },
  {
    type = "int-setting",
    name = "etech-factory-roboport-kw",
    setting_type = "startup",
    default_value = 4000,
    minimum_value = 0,
    maximum_value = 100000,
    order = "re",
  },
  {
    type = "double-setting",
    name = "etech-factory-roboport-pad-radius",
    setting_type = "startup",
    default_value = 0.75,
    minimum_value = 0.25,
    maximum_value = 8,
    order = "rf",
  },
  {
    type = "bool-setting",
    name = "etech-factory-roboport-electric",
    setting_type = "startup",
    default_value = true,
    order = "rg",
  },
  {
    type = "int-setting",
    name = "etech-factory-roboport-input-mw",
    setting_type = "startup",
    default_value = 100,
    minimum_value = 1,
    maximum_value = 10000,
    order = "rh",
  },

  ----------------------------------------------------------------------------
  -- Teleport features (startup, c*)
  ----------------------------------------------------------------------------
  {
    type = "bool-setting",
    name = "etech-teleporters",
    setting_type = "startup",
    default_value = true,
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
  -- Body jump: shared by the pad/remote GUI and the teleport-to-player
  -- shortcut, hence the etech-teleport-* name rather than etech-teleporter-*.
  {
    type = "bool-setting",
    name = "etech-teleport-body-enabled",
    setting_type = "runtime-global",
    default_value = true,
    order = "th1",
  },
  {
    type = "double-setting",
    name = "etech-teleport-body-grace-min",
    setting_type = "runtime-global",
    default_value = 15,
    minimum_value = 0,
    maximum_value = 1440,
    order = "th2",
  },
  {
    type = "bool-setting",
    name = "etech-teleporter-players-section",
    setting_type = "runtime-global",
    default_value = true,
    order = "ti",
  },
  {
    type = "int-setting",
    name = "etech-teleporter-recent-slots",
    setting_type = "runtime-global",
    default_value = 8,
    minimum_value = 1,
    maximum_value = 50,
    order = "th5",
  },
  {
    type = "bool-setting",
    name = "etech-teleporter-express",
    setting_type = "runtime-global",
    default_value = true,
    order = "th6",
  },
  {
    type = "double-setting",
    name = "etech-teleporter-recall-multiplier",
    setting_type = "runtime-global",
    default_value = 3,
    minimum_value = 0,
    maximum_value = 100,
    order = "th7",
  },
  {
    type = "double-setting",
    name = "etech-teleporter-recall-cooldown-min",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 0,
    maximum_value = 240,
    order = "th8",
  },
  {
    type = "bool-setting",
    name = "etech-teleporter-respawn-home",
    setting_type = "runtime-global",
    default_value = false,
    order = "th9",
  },
  {
    type = "bool-setting",
    name = "etech-teleporter-consent",
    setting_type = "runtime-global",
    default_value = true,
    order = "ti1",
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
