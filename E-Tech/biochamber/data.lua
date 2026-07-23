-- biochamber/data.lua
-- Per-recipe RGB recolor of the biochamber (pools, dome, windows), ported
-- from the abandoned Colorful Biochamber mod's support/space-age.lua
-- (public domain / Unlicense - see LICENSE-third-party.txt). Sprite paths
-- rewritten to __E-Tech__/biochamber/; restructured 0.19.0 into the
-- nil-safe tint() helper (a recipe removed by another mod used to crash the
-- load), tint values unchanged. Gated by the etech-colorful-biochamber
-- startup setting + Space Age; skipped when the original mod is enabled.

local biochamber = data.raw["assembling-machine"]["biochamber"]
if not biochamber then
  log("[E-Tech] colorful biochamber: no biochamber prototype found - skipped")
  return
end

local function deep_replace(insrc, inorg, intarget)
  for k, v in pairs(insrc) do
    if type(v) == "table" then
      deep_replace(v, inorg, intarget)
    elseif v == inorg then
      insrc[k] = table.deepcopy(intarget)
    end
  end
end

-- Merge `changes` into the recipe's crafting_machine_tint (created when the
-- recipe has none). Missing recipes - removed or renamed by other mods - are
-- skipped with a log line instead of crashing the data stage.
local function tint(recipe_name, changes)
  local recipe = data.raw.recipe[recipe_name]
  if not recipe then
    log("[E-Tech] colorful biochamber: recipe " .. recipe_name .. " not found - skipped")
    return
  end
  local target = recipe.crafting_machine_tint
  if not target then
    target = {}
    recipe.crafting_machine_tint = target
  end
  for k, v in pairs(changes) do
    if type(v) == "table" then
      target[k] = table.deepcopy(v)
    else
      target[k] = v
    end
  end
end

-- In a chemical plant the tint slots mean: primary/secondary = the checking
-- window, tertiary = outer smoke, quaternary = inner smoke. The biochamber
-- remap below repurposes them: primary = sludge pool, secondary = checking
-- window, tertiary = main pool, quaternary = secondary pool.

-- Lamp / default tint.
biochamber.graphics_set.default_recipe_tint = {
  primary = {r = 0.75, g = 0.75, b = 1, a = 1},
  secondary = {r = 1, g = 0.5, b = 0, a = 1},
  tertiary = {r = 1, g = 0.85, b = 0.75, a = 1},
  quaternary = {r = 1, g = 1, b = 0, a = 1},
}
local vis = biochamber.graphics_set.working_visualisations
vis[5].apply_recipe_tint = "none"

-- primary: now the sludge pool.
table.insert(vis, 6, {
  animation = {
    filename = "__E-Tech__/biochamber/biochamber-sluge.png",
    animation_speed = 0.75, frame_count = 64, height = 144, line_length = 8,
    priority = "extra-high", scale = 0.5, shift = {0.734375, -0.296875}, width = 92,
  },
  apply_recipe_tint = "primary",
})
-- secondary: the checking window.
vis[4].apply_recipe_tint = "secondary"
deep_replace(vis[4], "__space-age__/graphics/entity/biochamber/biochamber-glow-2.png", "__E-Tech__/biochamber/biochamber-glow-2.png")
-- tertiary: the main pool color.
vis[1].apply_recipe_tint = "tertiary"
deep_replace(vis[1], "__space-age__/graphics/entity/biochamber/biochamber-animation-dome.png", "__E-Tech__/biochamber/biochamber-animation-dome.png")
-- quaternary: the secondary pool color.
vis[3].apply_recipe_tint = "quaternary"
deep_replace(vis[3], "__space-age__/graphics/entity/biochamber/biochamber-glow.png", "__E-Tech__/biochamber/biochamber-glow.png")

-- And finally add gray windows.
table.insert(vis, 1, {
  animation = {
    filename = "__E-Tech__/biochamber/biochamber-windows.png",
    animation_speed = 0.75, frame_count = 64, height = 144, line_length = 8,
    priority = "extra-high", scale = 0.5, shift = {0.734375, -0.296875}, width = 92,
  },
  fadeout = true,
})

tint("rocket-fuel", {
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 1, g = 0.5, b = 0.5, a = 1},
})

tint("biochamber", {
  primary = {r = 0.75, g = 1, b = 0.75, a = 1},
  secondary = {r = 1, g = 1, b = 1, a = 1},
  tertiary = {r = 0.75, g = 0.65, b = 0.50, a = 1},
  quaternary = {r = 0, g = 1, b = 0, a = 1},
})

tint("agricultural-science-pack", {
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 1, g = 1, b = 0, a = 1},
})

tint("bioflux", {
  primary = {r = 0.5, g = 0, b = 0.5, a = 1},
  secondary = {r = 1, g = 0.35, b = 0.2, a = 1},
  tertiary = {r = 1, g = 0.2, b = 0, a = 1},
  quaternary = {r = 0, g = 1, b = 0, a = 1},
})

tint("yumako-processing", {
  tertiary = {r = 1, g = 1, b = 0, a = 1},
  quaternary = {r = 1, g = 0, b = 0, a = 1},
})
tint("jellynut-processing", {
  tertiary = {r = 0.35, g = 1, b = 0.35, a = 1},
  quaternary = {r = 0.75, g = 0, b = 0.75, a = 1},
})
tint("tree-seed", {
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 1, g = 0.7, b = 0.5, a = 1},
})

tint("iron-bacteria", {
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 0, g = 0.25, b = 0.5, a = 1},
})
tint("iron-bacteria-cultivation", {
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 0, g = 0.5, b = 1, a = 1},
})

tint("copper-bacteria", {
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 1, g = 0.5, b = 0, a = 1},
})
tint("copper-bacteria-cultivation", {
  tertiary = {r = 1, g = 0.7, b = 0.2, a = 1},
  quaternary = {r = 1, g = 0.5, b = 0, a = 1},
})

tint("rocket-fuel-from-jelly", {
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 1, g = 0.5, b = 0.5, a = 1},
})
tint("biolubricant", {
  tertiary = {r = 0.9, g = 1, b = 0.9, a = 1},
  quaternary = {r = 0, g = 0.2, b = 0, a = 1},
})
tint("bioplastic", {
  tertiary = {r = 1, g = 1, b = 1, a = 0},
  quaternary = {r = 1, g = 1, b = 1, a = 0},
})
tint("biosulfur", {
  tertiary = {r = 1, g = 1, b = 0, a = 1},
  quaternary = {r = 1, g = 1, b = 1, a = 1},
})
tint("burnt-spoilage", {
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 0, g = 0, b = 0, a = 1},
})

tint("carbon-fiber", {
  tertiary = {r = 0, g = 0, b = 1, a = 1},
  quaternary = {r = 1, g = 0, b = 0, a = 1},
})

-- pentapod-egg keeps its own original primary as the new secondary (the
-- deepcopy must happen BEFORE primary is overwritten).
do
  local egg = data.raw.recipe["pentapod-egg"]
  local egg_primary = egg and egg.crafting_machine_tint and egg.crafting_machine_tint.primary
  tint("pentapod-egg", {
    primary = {r = 0.8, g = 0.9, b = 1, a = 1},
    secondary = egg_primary and table.deepcopy(egg_primary) or {r = 1, g = 1, b = 1, a = 1},
    tertiary = {r = 1, g = 1, b = 1, a = 1},
    quaternary = {r = 0, g = 1, b = 0, a = 1},
  })
end
tint("fish-breeding", {
  primary = {r = 0.8, g = 0.9, b = 1, a = 1},
  secondary = {r = 1, g = 0, b = 0, a = 1},
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 0.5, g = 0.5, b = 1, a = 1},
})

-- Nutrients.
tint("nutrients-from-spoilage", {
  primary = {r = 0.8, g = 0.9, b = 1, a = 1},
  secondary = {r = 0, g = 0, b = 0, a = 1},
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 1, g = 1, b = 1, a = 1},
})
tint("nutrients-from-yumako-mash", {
  primary = {r = 0.8, g = 0.9, b = 1, a = 1},
  secondary = {r = 1, g = 0.5, b = 0, a = 1},
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 1, g = 1, b = 1, a = 1},
})
tint("nutrients-from-bioflux", {
  primary = {r = 0.8, g = 0.9, b = 1, a = 1},
  secondary = {r = 1, g = 0.35, b = 0.2, a = 1},
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 1, g = 1, b = 1, a = 1},
})

tint("nutrients-from-biter-egg", {
  primary = {r = 0.8, g = 0.9, b = 1, a = 1},
  secondary = {r = 1, g = 0.5, b = 0, a = 1},
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 1, g = 1, b = 1, a = 1},
})
tint("nutrients-from-fish", {
  primary = {r = 0.8, g = 0.9, b = 1, a = 1},
  secondary = {r = 1, g = 0, b = 0, a = 1},
  tertiary = {r = 1, g = 1, b = 1, a = 1},
  quaternary = {r = 1, g = 1, b = 1, a = 1},
})
