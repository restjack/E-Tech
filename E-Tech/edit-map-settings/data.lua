-- edit-map-settings/data.lua
-- Data stage for the map-settings editor port: the toolbar shortcut that
-- opens it, plus the four GUI styles the original Edit Map Settings mod
-- defined. The styles keep their original (global) names, guarded so nothing
-- breaks if another mod defines the same helper styles.

local styles = data.raw["gui-style"]["default"]

if not styles["pusher"] then
  styles["pusher"] =
  {
    type = "horizontal_flow_style",
    horizontally_stretchable = "on"
  }
end

if not styles["deep_frame"] then
  styles["deep_frame"] =
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

if not styles["frame_in_deep_frame"] then
  styles["frame_in_deep_frame"] =
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
if not styles["b_inner_frame_no_border"] then
  styles["b_inner_frame_no_border"] =
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
    localised_name = {"", "Edit map settings"},
    localised_description = {"", "Open the map settings editor: pollution, evolution, enemy expansion, peaceful/no-enemies mode, spoilage rate, and per-surface map generation settings. Applying changes requires admin."},
  },
})
