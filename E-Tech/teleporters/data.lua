-- teleporters/data.lua
-- Teleporter prototypes: entity (a land-mine clone whose trigger applies a
-- sticker; the sticker's creation fires on_trigger_created_entity in the
-- control stage), item, recipe, technology, teleport-flash explosions, and
-- the Ctrl+F search hotkey for the destination GUI.
--
-- Adapted from "Teleporters" 2.0.x by Klonan (LGPLv3 — see
-- LICENSE-third-party.txt). Prototype names are etech-prefixed so both mods
-- can be installed at once. Sprites are the original's HR set, inlined
-- (the 1.1-era hr_version wrapper is gone in 2.x).

local names = require("teleporters/shared")
local path = "__E-Tech__/teleporters/graphics/"
local name = names.entities.teleporter
local localised_name = {"etech-tp-name"}

local teleporter = util.table.deepcopy(data.raw["land-mine"]["land-mine"])
teleporter.name = name
teleporter.localised_name = localised_name
teleporter.trigger_radius = 1
teleporter.timeout = 5 * 60
teleporter.max_health = 200
teleporter.dying_explosion = nil
teleporter.action =
{
  type = "direct",
  action_delivery =
  {
    type = "instant",
    target_effects =
    {
      {
        type = "create-sticker",
        sticker = names.entities.teleporter_sticker,
        trigger_created_entity = true
      }
    }
  }
}
teleporter.force_die_on_attack = false
teleporter.trigger_force = "all"
teleporter.order = name
teleporter.picture_safe =
{
  filename = path.."hr-teleporter-closed.png",
  priority = "medium",
  width = 160,
  height = 160,
  scale = 0.5,
}
teleporter.picture_set =
{
  filename = path.."hr-teleporter-open.png",
  priority = "medium",
  width = 160,
  height = 160,
  scale = 0.5,
}
teleporter.picture_set_enemy = util.table.deepcopy(teleporter.picture_set)
teleporter.minable = {result = name, mining_time = 3}
teleporter.flags =
{
  "placeable-neutral",
  "placeable-player",
  "player-creation",
  "not-upgradable"
}
teleporter.collision_box = {{-1, -1}, {1, 1}}
teleporter.selection_box = {{-1, -1}, {1, 1}}
teleporter.map_color = {r = 0.5, g = 1, b = 1}

local sticker =
{
  type = "sticker",
  name = names.entities.teleporter_sticker,
  flags = {},
  animation = util.empty_sprite(),
  duration_in_ticks = 1,
}

local teleporter_item = util.table.deepcopy(data.raw.item["land-mine"])
teleporter_item.name = name
teleporter_item.localised_name = localised_name
teleporter_item.place_result = name
teleporter_item.icon = path.."teleporter-icon.png"
teleporter_item.icon_size = 64
teleporter_item.subgroup = "circuit-network"

-- Teleport flash: the original's fire-style animation (base-game fire
-- pictures recolored), one copy with sound + silent copies layered on top.
local flash_animation =
{
  {
    filename = path.."hr-teleporter-explosion.png",
    draw_as_glow = true,
    priority = "high",
    line_length = 6,
    width = 88,
    height = 178,
    frame_count = 24,
    shift = util.by_pixel(-1, 6),
    blend_mode = "additive",
    animation_speed = 0.3,
    scale = 0.5,
  },
}

local teleporter_explosion = util.table.deepcopy(data.raw.explosion.explosion)
teleporter_explosion.name = names.explosions.flash
teleporter_explosion.animations = flash_animation
teleporter_explosion.sound =
{
  filename = path.."teleporter-explosion.ogg",
  volume = 0.45
}

local teleporter_explosion_2 = util.table.deepcopy(teleporter_explosion)
teleporter_explosion_2.name = names.explosions.flash_no_sound
teleporter_explosion_2.sound = nil

local recipe =
{
  type = "recipe",
  name = name,
  localised_name = localised_name,
  enabled = false,
  ingredients =
  {
    {type = "item", name = "steel-plate", amount = 45},
    {type = "item", name = "advanced-circuit", amount = 20},
    {type = "item", name = "battery", amount = 25},
  },
  energy_required = 5,
  results = {{type = "item", name = name, amount = 1}}
}

local technology =
{
  type = "technology",
  name = name,
  localised_name = localised_name,
  icon_size = 256,
  icon = path.."teleporter-technology.png",
  effects =
  {
    {
      type = "unlock-recipe",
      recipe = name
    }
  },
  unit =
  {
    count = 500,
    ingredients =
    {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
      {"chemical-science-pack", 1},
    },
    time = 30
  },
  prerequisites = {"advanced-circuit", "battery"},
  order = "y-a"
}

local hotkey =
{
  type = "custom-input",
  name = names.hotkeys.focus_search,
  linked_game_control = "focus-search",
  -- 2.1 rejects "Control" — modifier must be spelled CONTROL
  key_sequence = "CONTROL + F"
}

-- Keyboard alternative to the toolbar remote shortcut.
local remote_hotkey =
{
  type = "custom-input",
  name = names.hotkeys.open_remote,
  key_sequence = "SHIFT + T",
  localised_name = {"etech-tp-remote-hotkey-name"},
  localised_description = {"etech-tp-remote-hotkey-description"},
}

-- Invisible electric buffer placed on top of each pad by the control stage.
-- Teleporting drains the DESTINATION pad's buffer, so an unpowered pad can't
-- be teleported to (when an energy cost is configured). No collision, not
-- selectable, not blueprintable — pure companion entity.
local energy_interface =
{
  type = "electric-energy-interface",
  name = names.entities.energy_interface,
  localised_name = localised_name,
  icon = path.."teleporter-icon.png",
  icon_size = 64,
  flags =
  {
    "not-on-map",
    "not-blueprintable",
    "not-deconstructable",
    "placeable-off-grid",
    "not-upgradable",
  },
  hidden = true,
  max_health = 1,
  collision_box = {{-0.9, -0.9}, {0.9, 0.9}},
  collision_mask = {layers = {}},
  energy_source =
  {
    type = "electric",
    buffer_capacity = "200MJ",
    usage_priority = "secondary-input",
    input_flow_limit = "4MW",
    output_flow_limit = "0W",
  },
  energy_production = "0W",
  energy_usage = "0W",
}

-- Toolbar shortcut: open the teleporter destination list from anywhere
-- ("wireless remote"). Runtime gating (setting + tech researched) happens
-- in the control stage.
local remote_shortcut =
{
  type = "shortcut",
  name = names.shortcuts.remote,
  order = "z[etech]-b[teleporter-remote]",
  action = "lua",
  icon = path.."teleporter-icon.png",
  icon_size = 64,
  small_icon = path.."teleporter-icon.png",
  small_icon_size = 64,
  localised_name = {"etech-tp-remote-title"},
  localised_description = {"etech-tp-remote-description"},
}

data:extend
{
  teleporter,
  teleporter_item,
  teleporter_explosion,
  teleporter_explosion_2,
  recipe,
  technology,
  hotkey,
  remote_hotkey,
  sticker,
  energy_interface,
  remote_shortcut
}
