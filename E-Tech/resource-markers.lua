-- resource-markers.lua
-- Automatic map markers for resource patches. Written from scratch for
-- E-Tech (public domain like the rest of the mod) — the concept exists in
-- other mods, the code here shares nothing with them.
--
-- How it works: every charted chunk is scanned for resource entities and
-- recorded as one "cell" per (force, surface, resource). Touching cells
-- (8 directions) cluster into a patch, and each patch gets one chart tag at
-- its ore-weighted centroid: resource icon + total amount (or "N x ~P%" for
-- infinite resources like crude oil). Tags update as chunks are charted or
-- recharted, resources deplete, or chunks get deleted. Deleting one of our
-- tags on the map mutes that patch — we don't fight the player over it.
-- /etech-markers-rebuild wipes and rescans everything (also runs
-- automatically the first time the toggle is enabled on an existing save).

local RESCAN_TICKS = 1800 -- ignore rechart of a cell younger than 30 s with unchanged amount

local script_data =
{
  -- buckets[force_name][surface_index][resource_name] = {
  --   cells      = { [key] = {amount, count, sum_x, sum_y, tick} },
  --   cell_patch = { [key] = patch_id },
  --   patches    = { [patch_id] = {cells = {key = true}, tag = LuaCustomChartTag?, muted = bool} },
  --   next_id    = int,
  -- }
  buckets = {},
  -- tag_map[tag_number] = {force_name, surface_index, resource, patch_id}
  tag_map = {},
}

-- True while we create/destroy our own tags so on_chart_tag_removed can
-- tell player deletions from our own bookkeeping.
local suppress = false

local cell_key = function(cx, cy)
  return cx .. "," .. cy
end

local get_bucket = function(force_name, surface_index, resource_name)
  local fb = script_data.buckets[force_name]
  if not fb then fb = {} script_data.buckets[force_name] = fb end
  local sb = fb[surface_index]
  if not sb then sb = {} fb[surface_index] = sb end
  local bucket = sb[resource_name]
  if not bucket then
    bucket = {cells = {}, cell_patch = {}, patches = {}, next_id = 1}
    sb[resource_name] = bucket
  end
  return bucket
end

local fmt_amount = function(n)
  if n >= 1e9 then return string.format("%.1fG", n / 1e9) end
  if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
  if n >= 1e3 then return string.format("%.1fK", n / 1e3) end
  return tostring(math.floor(n))
end

local get_icon = function(resource_name)
  local proto = prototypes.entity[resource_name]
  if not proto then return end
  local mineable = proto.mineable_properties
  local products = mineable and mineable.products
  local product = products and products[1]
  if not product then return end
  return {type = product.type == "fluid" and "fluid" or "item", name = product.name}
end

local destroy_tag = function(patch)
  local tag = patch.tag
  if tag and tag.valid then
    script_data.tag_map[tag.tag_number] = nil
    suppress = true
    tag.destroy()
    suppress = false
  end
  patch.tag = nil
end

local retag = function(force, surface, resource_name, bucket, patch_id)
  local patch = bucket.patches[patch_id]
  if not patch then return end
  destroy_tag(patch)
  if patch.muted then return end

  local amount, count, sum_x, sum_y = 0, 0, 0, 0
  local first_cell
  for key in pairs (patch.cells) do
    local cell = bucket.cells[key]
    if cell then
      amount = amount + cell.amount
      count = count + cell.count
      sum_x = sum_x + cell.sum_x
      sum_y = sum_y + cell.sum_y
      first_cell = first_cell or cell
    end
  end
  if count == 0 then
    bucket.patches[patch_id] = nil
    return
  end
  if count < settings.global["etech-markers-min-size"].value then return end

  local text
  local proto = prototypes.entity[resource_name]
  if proto and proto.infinite_resource then
    local normal = proto.normal_resource_amount or 0
    local pct = normal > 0 and math.floor((amount / normal) * 100 / count + 0.5) or 0
    text = string.format("%d x ~%d%%", count, pct)
  else
    text = fmt_amount(amount)
  end

  local icon = get_icon(resource_name)
  suppress = true
  local tag = force.add_chart_tag(surface, {position = {x = sum_x / count, y = sum_y / count}, icon = icon, text = text})
  if not tag and first_cell and first_cell.count > 0 then
    -- centroid can land on an uncharted chunk of an L-shaped patch
    tag = force.add_chart_tag(surface, {position = {x = first_cell.sum_x / first_cell.count, y = first_cell.sum_y / first_cell.count}, icon = icon, text = text})
  end
  suppress = false
  if tag then
    patch.tag = tag
    script_data.tag_map[tag.tag_number] = {force_name = force.name, surface_index = surface.index, resource = resource_name, patch_id = patch_id}
  end
end

-- Attach a new cell to the patch structure: adopt a neighboring patch,
-- merging several if the cell bridges them, or start a new one.
local merge_into = function(bucket, key, cx, cy)
  local neighbor_patches = {}
  for dx = -1, 1 do
    for dy = -1, 1 do
      if not (dx == 0 and dy == 0) then
        local pid = bucket.cell_patch[cell_key(cx + dx, cy + dy)]
        if pid then neighbor_patches[pid] = true end
      end
    end
  end

  local target
  for pid in pairs (neighbor_patches) do
    if not target or pid < target then target = pid end
  end
  if not target then
    target = bucket.next_id
    bucket.next_id = target + 1
    bucket.patches[target] = {cells = {}, muted = false}
  end

  for pid in pairs (neighbor_patches) do
    if pid ~= target then
      local absorbed = bucket.patches[pid]
      destroy_tag(absorbed)
      for ck in pairs (absorbed.cells) do
        bucket.patches[target].cells[ck] = true
        bucket.cell_patch[ck] = target
      end
      if absorbed.muted then bucket.patches[target].muted = true end
      bucket.patches[pid] = nil
    end
  end

  bucket.patches[target].cells[key] = true
  bucket.cell_patch[key] = target
  return target
end

-- Note: removing a cell can in principle split a patch in two; we keep it
-- as one patch (one tag) — totals stay correct, only the grouping is
-- coarser. A /etech-markers-rebuild regroups everything exactly.
local remove_cell = function(force, surface, resource_name, bucket, key)
  local patch_id = bucket.cell_patch[key]
  bucket.cells[key] = nil
  bucket.cell_patch[key] = nil
  if not patch_id then return end
  local patch = bucket.patches[patch_id]
  if not patch then return end
  patch.cells[key] = nil
  if not next(patch.cells) then
    destroy_tag(patch)
    bucket.patches[patch_id] = nil
  else
    retag(force, surface, resource_name, bucket, patch_id)
  end
end

local scan_chunk = function(force, surface, cx, cy, area)
  if not (force and force.valid and surface and surface.valid) then return end
  if #force.players == 0 then return end
  local key = cell_key(cx, cy)

  local found = {}
  for _, entity in pairs (surface.find_entities_filtered{area = area, type = "resource"}) do
    local name = entity.name
    local totals = found[name]
    if not totals then
      totals = {amount = 0, count = 0, sum_x = 0, sum_y = 0}
      found[name] = totals
    end
    totals.amount = totals.amount + entity.amount
    totals.count = totals.count + 1
    local position = entity.position
    totals.sum_x = totals.sum_x + position.x
    totals.sum_y = totals.sum_y + position.y
  end

  local force_name = force.name
  local surface_index = surface.index

  for name, totals in pairs (found) do
    local bucket = get_bucket(force_name, surface_index, name)
    local old = bucket.cells[key]
    if old and old.tick and (game.tick - old.tick) < RESCAN_TICKS and old.amount == totals.amount then
      -- fresh and unchanged (radar rechart spam) — skip
    else
      totals.tick = game.tick
      bucket.cells[key] = totals
      local patch_id = bucket.cell_patch[key] or merge_into(bucket, key, cx, cy)
      retag(force, surface, name, bucket, patch_id)
    end
  end

  -- resources that used to be in this cell but are mined out now
  local fb = script_data.buckets[force_name]
  local sb = fb and fb[surface_index]
  if sb then
    for name, bucket in pairs (sb) do
      if bucket.cells[key] and not found[name] then
        remove_cell(force, surface, name, bucket, key)
      end
    end
  end
end

local full_rescan = function()
  for _, fb in pairs (script_data.buckets) do
    for _, sb in pairs (fb) do
      for _, bucket in pairs (sb) do
        for _, patch in pairs (bucket.patches) do
          destroy_tag(patch)
        end
      end
    end
  end
  script_data.buckets = {}
  script_data.tag_map = {}

  local chunks = 0
  for _, force in pairs (game.forces) do
    if #force.players > 0 then
      for _, surface in pairs (game.surfaces) do
        for chunk in surface.get_chunks() do
          if force.is_chunk_charted(surface, chunk) then
            scan_chunk(force, surface, chunk.x, chunk.y, chunk.area)
            chunks = chunks + 1
          end
        end
      end
    end
  end
  return chunks
end

local rebuild_command = function(command)
  local player = command.player_index and game.get_player(command.player_index)
  local chunks = full_rescan()
  local msg = {"etech-rm-rebuilt", chunks}
  if player and player.valid then player.print(msg) else game.print(msg) end
end

-- Legacy cleanup: other resource-marker mods (e.g. Resource Map Label
-- Marker) leave their chart tags in the save after removal — tags are map
-- data, not mod data. A leftover is recognized by all three of:
-- script-created (no last_user), not one of ours (tag_map), and an icon
-- that is some resource's mined product. Player-placed tags always have
-- last_user, so they are never touched.
local find_legacy_tags = function()
  local product_icons = {item = {}, fluid = {}}
  for _, proto in pairs (prototypes.get_entity_filtered{{filter = "type", type = "resource"}}) do
    local mineable = proto.mineable_properties
    for _, product in pairs (mineable and mineable.products or {}) do
      product_icons[product.type == "fluid" and "fluid" or "item"][product.name] = true
    end
  end

  local candidates = {}
  for _, force in pairs (game.forces) do
    if #force.players > 0 then
      for _, surface in pairs (game.surfaces) do
        for _, tag in pairs (force.find_chart_tags(surface)) do
          if tag.valid and not tag.last_user and not script_data.tag_map[tag.tag_number] then
            local icon = tag.icon
            if icon and icon.name then
              local icon_type = icon.type or "item"
              if (icon_type == "item" or icon_type == "fluid") and product_icons[icon_type][icon.name] then
                candidates[#candidates + 1] = tag
              end
            end
          end
        end
      end
    end
  end
  return candidates
end

local clean_legacy = function()
  local removed = 0
  suppress = true
  for _, tag in pairs (find_legacy_tags()) do
    if tag.valid then
      tag.destroy()
      removed = removed + 1
    end
  end
  suppress = false
  return removed
end

-- Dry-run by default; "confirm" deletes.
local clean_legacy_command = function(command)
  local player = command.player_index and game.get_player(command.player_index)
  local out = function(msg)
    if player and player.valid then player.print(msg) else game.print(msg) end
  end
  if command.parameter == "confirm" then
    out({"etech-rm-legacy-removed", clean_legacy()})
  else
    out({"etech-rm-legacy-found", #find_legacy_tags()})
  end
end

local on_chunk_charted = function(event)
  local surface = game.surfaces[event.surface_index]
  if not (surface and surface.valid) then return end
  scan_chunk(event.force, surface, event.position.x, event.position.y, event.area)
end

local on_resource_depleted = function(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  local surface = entity.surface
  local cx = math.floor(entity.position.x / 32)
  local cy = math.floor(entity.position.y / 32)
  local area = {{cx * 32, cy * 32}, {cx * 32 + 32, cy * 32 + 32}}
  for _, force in pairs (game.forces) do
    if #force.players > 0 and force.is_chunk_charted(surface, {x = cx, y = cy}) then
      scan_chunk(force, surface, cx, cy, area)
    end
  end
end

local on_chart_tag_removed = function(event)
  if suppress then return end
  local tag = event.tag
  if not (tag and tag.valid) then return end
  local info = script_data.tag_map[tag.tag_number]
  if not info then return end
  script_data.tag_map[tag.tag_number] = nil
  if not event.player_index then return end -- another mod's cleanup: just recreate later
  local fb = script_data.buckets[info.force_name]
  local sb = fb and fb[info.surface_index]
  local bucket = sb and sb[info.resource]
  local patch = bucket and bucket.patches[info.patch_id]
  if patch then
    patch.muted = true
    patch.tag = nil
  end
end

local on_surface_deleted = function(event)
  for _, fb in pairs (script_data.buckets) do
    fb[event.surface_index] = nil
  end
  for tag_number, info in pairs (script_data.tag_map) do
    if info.surface_index == event.surface_index then
      script_data.tag_map[tag_number] = nil
    end
  end
end

local on_chunk_deleted = function(event)
  local surface = game.surfaces[event.surface_index]
  if not (surface and surface.valid) then return end
  for force_name, fb in pairs (script_data.buckets) do
    local force = game.forces[force_name]
    local sb = fb[event.surface_index]
    if force and force.valid and sb then
      for _, position in pairs (event.positions) do
        local key = cell_key(position.x, position.y)
        for name, bucket in pairs (sb) do
          if bucket.cells[key] then
            remove_cell(force, surface, name, bucket, key)
          end
        end
      end
    end
  end
end

local on_forces_merged = function(event)
  script_data.buckets[event.source_name] = nil
  for tag_number, info in pairs (script_data.tag_map) do
    if info.force_name == event.source_name then
      script_data.tag_map[tag_number] = nil
    end
  end
end

local markers = {}

markers.events =
{
  [defines.events.on_chunk_charted] = on_chunk_charted,
  [defines.events.on_resource_depleted] = on_resource_depleted,
  [defines.events.on_chart_tag_removed] = on_chart_tag_removed,
  [defines.events.on_surface_deleted] = on_surface_deleted,
  [defines.events.on_chunk_deleted] = on_chunk_deleted,
  [defines.events.on_forces_merged] = on_forces_merged,
}

markers.add_commands = function()
  commands.add_command("etech-markers-rebuild", {"etech-rm-rebuild-help"}, rebuild_command)
  commands.add_command("etech-markers-clean-legacy", {"etech-rm-clean-legacy-help"}, clean_legacy_command)
end

-- Marker mods whose removal triggers an automatic sweep of their leftover
-- tags ("resourceMarker" is the original Resource Map Label Marker's
-- internal name, per the fork's incompatibility dependency).
local LEGACY_MARKER_MODS =
{
  "resource-map-label-marker-fork",
  "resourceMarker",
}

markers.on_init = function()
  storage.etech_markers = storage.etech_markers or script_data
  local removed = clean_legacy()
  if removed > 0 then
    game.print({"etech-rm-legacy-removed", removed})
  end
  full_rescan()
end

markers.on_load = function()
  script_data = storage.etech_markers or script_data
end

markers.on_configuration_changed = function(data)
  if not storage.etech_markers then
    -- toggle turned on mid-save: sweep other mods' leftovers, then
    -- backfill everything already charted
    storage.etech_markers = script_data
    local removed = clean_legacy()
    if removed > 0 then
      game.print({"etech-rm-legacy-removed", removed})
    end
    full_rescan()
    return
  end
  script_data = storage.etech_markers

  -- a known marker mod was just removed: sweep the tags it left behind
  local mod_changes = data and data.mod_changes
  if mod_changes then
    for _, mod_name in pairs (LEGACY_MARKER_MODS) do
      local change = mod_changes[mod_name]
      if change and change.old_version and not change.new_version then
        local removed = clean_legacy()
        if removed > 0 then
          game.print({"etech-rm-legacy-removed", removed})
        end
        break
      end
    end
  end
end

return markers
