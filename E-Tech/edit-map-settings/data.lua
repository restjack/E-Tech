-- edit-map-settings/data.lua
-- Data stage for the map-settings editor port: the toolbar shortcut that
-- opens it, plus the four GUI styles the original Edit Map Settings mod
-- defined.
--
-- The styles are etech- prefixed since 0.21.1. The original used bare generic
-- names (pusher, deep_frame, frame_in_deep_frame, b_inner_frame_no_border) in
-- the shared default style table, guarded with "define it only if nobody else
-- did". That guard protects the OTHER mod, not us: if some other mod defined
-- its own `pusher` first, this GUI silently rendered with whatever that mod
-- meant by it. Prefixed names cannot collide either way.

local styles = data.raw["gui-style"]["default"]

if not styles["etech-pusher"] then
  styles["etech-pusher"] =
  {
    type = "horizontal_flow_style",
    horizontally_stretchable = "on"
  }
end

if not styles["etech-deep_frame"] then
  styles["etech-deep_frame"] =
  {
    type = "frame_style",
    parent = "inside_deep_frame",
    vertical_flow_style =
    {
      type = "vertical_flow_style",
      vertical_spacing = 8
    }
  }
end

if not styles["etech-frame_in_deep_frame"] then
  styles["etech-frame_in_deep_frame"] =
  {
    type = "frame_style",
    parent = "frame",
    graphical_set =
    {
      base =
      {
        position = {51, 0}, corner_size = 8,
        center = {position = {76, 8}, size = {1, 1}},
        draw_type = "outer"
      },
      shadow = default_inner_shadow
    }
  }
end

-- 2.0 removed 'b_inner_frame' so this now defines its 'base' properties
-- instead of inheriting from 'b_inner_frame'.
-- It always changed the shadow.
if not styles["etech-b_inner_frame_no_border"] then
  styles["etech-b_inner_frame_no_border"] =
  {
    type = "frame_style",
    graphical_set =
    {
      base =
      {
        position = {17, 0},
        corner_size = 8,
        center = {position = {76, 8}, size = {1, 1}},
        draw_type = "outer"
      },
      -- we only show shadow on the top, to solve the problem of it not being casted from the subheader panel above
      shadow =
      {
        top =
        {
          position = {191, 128},
          size = {1, 8},
          tint = hard_shadow_color,
          draw_type = "inner"
        }
      }
    }
  }
end

data:extend({
  {
    type = "shortcut",
    name = "etech-map-settings",
    order = "z[etech]-b[map-settings]",
    action = "lua",
    toggleable = true,
    icon = "__base__/graphics/icons/radar.png",
    icon_size = 64,
    small_icon = "__base__/graphics/icons/radar.png",
    small_icon_size = 64,
    -- Locale keys, not inline English (0.21.1). These were the only two
    -- user-facing strings in the mod that could not be translated.
    localised_name = {"etech-map-settings-shortcut-name"},
    localised_description = {"etech-map-settings-shortcut-description"},
  },
})
