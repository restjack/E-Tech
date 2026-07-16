-- Luacheck config for E-Tech (Factorio 2.1 mod).
-- Goal: catch real errors (syntax, undefined globals, shadowed upvalues used
-- wrong) without fighting Factorio idiom or the ported third-party files.

std = "lua52"

-- Factorio runtime/data-stage globals (read-only).
read_globals = {
  "mods",
  "settings",
  "script",
  "defines",
  "prototypes",
  "helpers",
  "rendering",
  "remote",
  "commands",
  "serpent",
  "log",
  "localised_print",
  "table_size",
  "util",
  -- data-stage style globals used by base-game gui styles
  "default_inner_shadow",
  "hard_shadow_color",
  -- AAI Industry publishes its resolved item names as data-stage globals
  "aai_glass_name",
  "aai_sand_name",
  -- Factorio core unit constants (weights/time) available in the data stage
  "kg", "grams", "tons", "second", "minute", "hour",
}

-- Mutable globals: editing data.raw, storage, and game.map_settings and
-- friends is legitimate runtime/data-stage API.
globals = {
  "data",
  "storage",
  "game",
  -- table.deepcopy / table.unpack extensions land on the table lib
  table = { fields = { "deepcopy", "unpack" } },
}

-- Style noise off — ports keep their upstream formatting.
max_line_length = false
unused = false
unused_args = false
redefined = false
-- 61x: whitespace-only / trailing-whitespace lines (upstream formatting)
-- 542: empty if branch (used deliberately with a comment for skip cases)
ignore = { "611", "612", "613", "614", "542" }

exclude_files = {
  "E-Tech/releases",
}
