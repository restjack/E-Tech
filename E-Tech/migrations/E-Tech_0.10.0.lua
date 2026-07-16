-- One-time cleanup for saves that ran the short-lived Factorissimo map
-- icons experiment (removed 2026-07-14). Lived in control.lua's
-- on_configuration_changed until 0.10.0 (where it ran on EVERY mod-set
-- change); as a migration it runs exactly once per save.
local leftover = storage.etech_factorissimo_icons
if leftover then
  for _, data in pairs (leftover.buildings or {}) do
    local tag = data.tag
    if tag and tag.valid then tag.destroy() end
  end
  storage.etech_factorissimo_icons = nil
end
