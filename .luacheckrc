-- Luacheck config for E-Tech (Factorio 2.1 mod).
-- Goal: catch real errors (syntax, undefined globals, shadowed upvalues used
-- wrong) without fighting Factorio idiom or the ported third-party files.

std = "lua52"

-- Factorio runtime/data-stage globals.
read_globals = {
  "data",
  "mods",
  "settings",
  "script",
  "game",
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
}

globals = {
  "storage",
  -- table.deepcopy / table.unpack extensions land on the table lib
  table = { fields = { "deepcopy", "unpack" } },
}

-- Style noise off — ports keep their upstream formatting.
max_line_length = false
unused = false
unused_args = false
redefined = false

exclude_files = {
  "E-Tech/releases",
}
