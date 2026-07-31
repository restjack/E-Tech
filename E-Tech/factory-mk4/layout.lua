-- factory-mk4/layout.lua
-- The Factorissimo layout table for factory-4 ("Mk4"). Control stage only:
-- layouts live in Factorissimo's `storage`, not in data.raw, and are handed
-- over with remote.call("factorissimo", "add_layout", ...).
--
-- DESIGN (decided 2026-07-30, see docs/FACTORY-MK4-HANDOFF.md):
-- 120x120 interior behind an UNCHANGED 16x16 exterior, so a Mk4 drops into
-- any slot already built for a factory-3. Every outside_x/outside_y below is
-- factory-3's verbatim; only the interior endpoints move out to the bigger
-- wall. That also means factory-power-input-16 and factory-3's port layout
-- are reused as-is - no new exterior prototypes.
--
-- WHY 120 AND NOT MORE. This is the largest interior Factorissimo supports
-- without patching it. create_factory_position() only marks chunks -2..2
-- around the interior origin as generated, and add_hidden_tile_rect() covers
-- the same +/-64 tiles. Our walls sit at +/-61 and the door corridor runs to
-- y = 63, one tile inside that limit. The 512-tile cell spacing would allow
-- far more, but the chunk loop is the real ceiling - anything past 122 needs
-- Factorissimo itself changed.
--
-- Interior geometry follows the pattern of every stock tier:
--   half = inside_size / 2 = 60
--   wall ring +/-(half+1) = +/-61      floor +/-half = +/-60
--   door corridor y = half .. half+3   inside_door_y = half+1 = 61
--   inside_energy = beside the door, as on every tier (see the note on it
--                   below for how the pole's 64-tile cap is worked around)

local north = defines.direction.north
local east = defines.direction.east
local south = defines.direction.south
local west = defines.direction.west

local opposite = {[north] = south, [east] = west, [south] = north, [west] = east}
local DX = {[north] = 0, [east] = 1, [south] = 0, [west] = -1}
local DY = {[north] = -1, [east] = 0, [south] = 1, [west] = 0}

-- Same signatures Factorissimo uses in script/layout.lua. Reimplemented here
-- rather than reached for, because that file is a local table in another mod's
-- control stage and nothing in it is exported.
local function make_connection(id, outside_x, outside_y, inside_x, inside_y, direction_out)
  return {
    id = id,
    outside_x = outside_x,
    outside_y = outside_y,
    inside_x = inside_x,
    inside_y = inside_y,
    indicator_dx = DX[direction_out],
    indicator_dy = DY[direction_out],
    direction_in = opposite[direction_out],
    direction_out = direction_out,
  }
end

local function make_quality_connection(id, outside_x, outside_y, inside_x, inside_y, direction_out, quality)
  local connection = make_connection(id, outside_x, outside_y, inside_x, inside_y, direction_out)
  connection.quality = quality
  return connection
end

-- Port positions ------------------------------------------------------------
-- OUT is factory-3's exterior offset, unchanged. IN is the same port's
-- position on the 120x120 wall, respaced from factory-3's spread on its 60x60
-- wall (same relative clustering, scaled to the longer run). Quality tiers are
-- copied exactly, so a Mk4 unlocks extra ports at the same quality levels a
-- factory-3 does: 32 base + 14 quality-gated = 46 at legendary.
--
-- Nothing lands within x = +/-11.5 on the south wall, keeping the door
-- corridor (x -3..3, y 60..63) clear.
local OUT = {-5.5, -4.5, -3.5, -2.5, 2.5, 3.5, 4.5, 5.5}
local IN = {-48.5, -40.5, -19.5, -11.5, 11.5, 19.5, 40.5, 48.5}

local WALL_OUT = 8.5  -- factory-3's exterior half-size + 0.5
local WALL_IN = 60.5  -- our interior half-size + 0.5

local connections = {}

for i = 1, 8 do
  connections["w" .. i] = make_connection("w" .. i, -WALL_OUT, OUT[i], -WALL_IN, IN[i], west)
  connections["e" .. i] = make_connection("e" .. i, WALL_OUT, OUT[i], WALL_IN, IN[i], east)
  connections["n" .. i] = make_connection("n" .. i, OUT[i], -WALL_OUT, IN[i], -WALL_IN, north)
  connections["s" .. i] = make_connection("s" .. i, OUT[i], WALL_OUT, IN[i], WALL_IN, south)
end

-- Quality-gated ports, at factory-3's quality levels.
connections.w9 = make_quality_connection("w9", -WALL_OUT, -1.5, -WALL_IN, -3.5, west, 2)
connections.w10 = make_quality_connection("w10", -WALL_OUT, 1.5, -WALL_IN, 3.5, west, 2)
connections.w11 = make_quality_connection("w11", -WALL_OUT, -6.5, -WALL_IN, -56.5, west, 3)
connections.w12 = make_quality_connection("w12", -WALL_OUT, 6.5, -WALL_IN, 56.5, west, 3)

connections.e9 = make_quality_connection("e9", WALL_OUT, -1.5, WALL_IN, -3.5, east, 2)
connections.e10 = make_quality_connection("e10", WALL_OUT, 1.5, WALL_IN, 3.5, east, 2)
connections.e11 = make_quality_connection("e11", WALL_OUT, -6.5, WALL_IN, -56.5, east, 3)
connections.e12 = make_quality_connection("e12", WALL_OUT, 6.5, WALL_IN, 56.5, east, 3)

connections.n9 = make_quality_connection("n9", -1.5, -WALL_OUT, -3.5, -WALL_IN, north, 1)
connections.n10 = make_quality_connection("n10", 1.5, -WALL_OUT, 3.5, -WALL_IN, north, 1)
connections.n11 = make_quality_connection("n11", -6.5, -WALL_OUT, -56.5, -WALL_IN, north, 4)
connections.n12 = make_quality_connection("n12", 6.5, -WALL_OUT, 56.5, -WALL_IN, north, 4)

connections.s9 = make_quality_connection("s9", -6.5, WALL_OUT, -56.5, WALL_IN, south, 5)
connections.s10 = make_quality_connection("s10", 6.5, WALL_OUT, 56.5, WALL_IN, south, 5)

-- The layout ----------------------------------------------------------------

return {
  name = "factory-4",
  tier = 4,
  inside_size = 120,
  outside_size = 16,
  inside_door_x = 0,
  inside_door_y = 61,
  outside_door_x = 0,
  outside_door_y = 8,
  -- Exterior is unchanged, so factory-3's power interface fits exactly. The
  -- requester/eject chests are ours (factory-mk4/data.lua) because
  -- Factorissimo generates its pair in a hardcoded per-tier loop.
  outside_energy_receiver_type = "factory-power-input-16",
  outside_requester_chest = "factory-requester-chest-factory-4",
  outside_ejector_chest = "factory-eject-chest-factory-4",
  -- Beside the door, same as every stock tier. inside_energy positions two
  -- things and nothing else in Factorissimo reads it: the interior power pole,
  -- at (x, y), and the interior construction roboport, at (-x, y).
  --
  -- The roboport is fine here - E-Tech raises its reach to 128, so from y = 62
  -- it covers to y = -66, past the far wall at -61.
  --
  -- The POWER POLE is not, and cannot be fixed here: factory-power-pole has
  -- supply_area_distance = 63 and THE ENGINE CAPS THAT FIELD AT 64, for every
  -- electric pole prototype that exists. From the door it supplies down to
  -- y = -1, so the northern half of a 120-wide floor gets no electricity at
  -- all - machines there read "No power" with nothing to trace, because the
  -- pole is hidden and draws no wire.
  --
  -- Moving the pole to the centre fixes it but drags the roboport along and
  -- parks both in the middle of the floor. Instead the visible pair stays at
  -- the door and a hidden relay pole is built at the interior centre and wired
  -- to this one - see the `upgrades` entry below.
  inside_energy_x = -4,
  inside_energy_y = 62,
  overlay_x = 0,
  overlay_y = 7,
  rectangles = {
    {x1 = -61, x2 = 61, y1 = -61, y2 = 61, tile = "factory-wall-4"},
    {x1 = -60, x2 = 60, y1 = -60, y2 = 60, tile = "factory-floor"},
    {x1 = -3, x2 = 3, y1 = 60, y2 = 63, tile = "factory-wall-4"},
    {x1 = -2, x2 = 2, y1 = 60, y2 = 63, tile = "factory-entrance"},
  },
  -- Floor logo, same 12x8 grid as the stock tiers: Factorissimo's "F" glyph
  -- in the left six columns, a "4" in the right six.
  mosaics = {
    {
      x1 = -6,
      x2 = 6,
      y1 = -4,
      y2 = 4,
      tile = "factory-pattern-4",
      pattern = {
        " ++++     ++",
        "++  ++   +++",
        "++  ++  ++++",
        "++ +++ ++ ++",
        "+++ ++++  ++",
        "++  ++++++++",
        "++  ++    ++",
        " ++++     ++",
      },
    },
  },
  connection_tile = "factory-floor",
  connections = connections,
  -- Factorissimo's own extension point: build_factory_upgrades() walks this
  -- list and, for any entry whose first element is not "factorissimo", calls
  -- remote.call(mod, function, factory) with the live factory table. It runs
  -- when a factory is built, for every existing factory on on_init and
  -- on_configuration_changed, and again on every research finish - so an entry
  -- here is self-healing and needs no event handlers of its own.
  --
  -- Setting this field REPLACES Factorissimo's DEFAULT_FACTORY_UPGRADES, so
  -- all four defaults have to be repeated or a Mk4 loses its lights,
  -- greenhouse, display and roboport.
  upgrades = {
    {"factorissimo", "build_lights_upgrade"},
    {"factorissimo", "build_greenhouse_upgrade"},
    {"factorissimo", "build_display_upgrade"},
    {"factorissimo", "build_roboport_upgrade"},
    {"etech-factory-mk4", "build_power_relay"},
  },
  overlays = {
    outside_x = 0,
    outside_y = -1,
    outside_w = 16,
    outside_h = 14,
    inside_x = -3.5,
    inside_y = 63.5,
  },
  -- Cerys heats a factory floor from these. The stock tiers use four, which
  -- is fine for a 60-wide floor; a Mk4 is four times the area, so four towers
  -- would leave the middle and the edges cold. Nine on a 3x3 grid at +/-40 and
  -- the centre keeps the spacing per tower roughly what a Mk3 has.
  cerys_radiative_towers = {
    {-40, -40}, {0, -40}, {40, -40},
    {-40, 0}, {0, 0}, {40, 0},
    {-40, 40}, {0, 40}, {40, 40},
  },
}
