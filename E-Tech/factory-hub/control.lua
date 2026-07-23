-- factory-hub/control.lua
-- Runtime for the factory outlet / inlet / sensor (event_handler lib).
-- Every PULL_TICKS ticks:
--   outlet - teleports items out of the provider chests (optionally storage
--            chests) inside the Factorissimo factories on its surface into
--            itself (passive provider). ONE outlet per surface per force —
--            placing a second is refunded. Always on-demand: sits empty and
--            materializes items only when the local logistic network has
--            unmet demand (requesters, players, spidertrons, construction
--            ghosts in build range). Per-outlet item filters; a connected
--            circuit wire gates it (nonzero signal = run, no wire = always
--            run).
--   inlet  - distributes its own contents into the requester/buffer chests
--            inside those factories, up to their request targets; optionally
--            auto-requests the factories' remaining deficits from the
--            outside network (managed logistic section "etech-inlet-auto").
--   sensor - writes the totals sitting in the factories' provider chests to
--            its constant-combinator section as circuit signals.
-- Mining an outlet/inlet returns its buffered items to the factories first.
--
-- Bots can't cross surfaces, so physically moving items is the only bridge —
-- same trick Factorissimo itself uses (in reverse) for construction bots.
--
-- Factorissimo internals used (verified against 3.12.2):
--   remote "factorissimo": get_factory_by_entity, has_layout,
--     is_factorissimo_surface, find_surrounding_factory_by_surface_index
--   factory table: id, building, inactive, built, inside_surface,
--     inside_x/inside_y, layout.inside_size
--   factory buildings are type "storage-tank" entities whose name passes
--     has_layout.

local M = {}

local OUTLET_NAME = "etech-factory-provider-hub"
local INLET_NAME = "etech-factory-inlet"
local SENSOR_NAME = "etech-factory-sensor"
local FLUID_OUTLET_NAME = "etech-factory-fluid-outlet"
local FLUID_INLET_NAME = "etech-factory-fluid-inlet"
local PANEL_NAME = "etech-hub-panel"
local INLET_PANEL_NAME = "etech-inlet-panel"
local AUTO_GROUP = "etech-inlet-auto"
local PULL_TICKS = 120     -- work pass per device, every 2 s (also GUI refresh)
local SLOT_TICKS = 30      -- scheduler step: the PULL_TICKS cycle is split
                           -- into 4 phases (outlets / inlets+sensors /
                           -- cache maintenance / GUI refresh) on separate
                           -- ticks, so no single tick pays for everything.
                           -- Per-device cadence is still PULL_TICKS.
local RESCAN_TICKS = 18000 -- factory-list cache fallback lifetime, 5 min
                           -- (build/mine of any storage-tank invalidates
                           -- instantly via data.factory_gen, and dead
                           -- factories are filtered by factory_usable, so
                           -- the fallback only catches exotic script edits;
                           -- the whole-surface storage-tank find costs
                           -- ~40 ms on a big map — keep it off short timers)
local PROXY_TICKS = 3600   -- item-request-proxy rescan, 60 s (~23 ms find
                           -- on a big map; module requests can wait a minute)
local PROFILE_FILE = "etech-profile.csv" -- /etech-hub-profile output (script-output/)
local MAX_DEPTH = 5        -- nested-factory recursion limit
local FILTER_SLOTS = 15    -- choose-elem filter slots in the outlet/inlet panels
local RATE_WINDOW = 3600   -- ticks of pull history for the items/min stat
local MAX_SIGNALS = 1000   -- constant combinator / logistic section limit
local MAX_FACTORY_ROWS = 20
local TOOLTIP_FACTORIES = 8 -- per-factory breakdown lines in an item tooltip

local KINDS = {
    [OUTLET_NAME] = "outlet",
    [INLET_NAME] = "inlet",
    [SENSOR_NAME] = "sensor",
    [FLUID_OUTLET_NAME] = "fluid-outlet",
    [FLUID_INLET_NAME] = "fluid-inlet",
}

-- item|quality key convention used across caches, wants tables and GUI tags
local function item_key(name, quality)
    return name .. "|" .. (quality or "normal")
end

local function hub_data()
    storage.etech_factory_hub = storage.etech_factory_hub or { hubs = {}, open = {} }
    local data = storage.etech_factory_hub
    data.open = data.open or {}
    data.factory_names = data.factory_names or {}
    return data
end

local function factorissimo_available()
    return remote.interfaces["factorissimo"] ~= nil
end

-- All Factorissimo remote calls go through this pcall wrapper: a renamed or
-- changed function in a future Factorissimo version degrades to "no
-- factories seen" instead of hard-crashing mid pull pass. Failures log once
-- per function name.
local remote_failed = {}
local function factorissimo_call(fn, ...)
    local ok, result = pcall(remote.call, "factorissimo", fn, ...)
    if ok then return result end
    if not remote_failed[fn] then
        remote_failed[fn] = true
        log("[E-Tech] factory hub: remote call factorissimo." .. fn ..
            " failed (" .. tostring(result) .. ") - Factorissimo API changed?")
    end
    return nil
end

-- has_layout is a remote call per candidate entity; memoize per prototype
-- name for the session (not in storage — cheap to rebuild).
local layout_name_cache = {}
local function is_factory_building(name)
    local cached = layout_name_cache[name]
    if cached == nil then
        cached = factorissimo_call("has_layout", name) or false
        layout_name_cache[name] = cached
    end
    return cached
end

-- LocalisedString; custom names are plain text, the fallback is localized.
local function factory_label(id)
    local name = hub_data().factory_names[id]
    if name and name ~= "" then return name end
    return {"gui-etech-hub.factory-n", id}
end

local function register_device(entity, copy_from)
    local data = hub_data()
    local record = {
        entity = entity,
        kind = KINDS[entity.name],
        filters = { mode = 1, items = {} },
        pins = {},
    }
    -- clone / blueprint: carry the source device's settings over
    if copy_from then
        if copy_from.filters then record.filters = table.deepcopy(copy_from.filters) end
        if copy_from.pins then record.pins = table.deepcopy(copy_from.pins) end
        record.pull_storage = copy_from.pull_storage
        record.auto_request = copy_from.auto_request
    end
    data.hubs[entity.unit_number] = record
    -- devices are logistic-containers themselves (an inlet placed inside a
    -- factory is a valid requester target) — invalidate chest caches too
    data.chest_gen = (data.chest_gen or 0) + 1
    script.register_on_object_destroyed(entity)
    return record
end

-- One factory outlet per surface (per force). A second placement is
-- refunded on the spot: to the placing player's inventory, otherwise
-- spilled at the build position (robot/script builds).
local function another_outlet_exists(entity)
    for _, found in pairs(entity.surface.find_entities_filtered {
        name = OUTLET_NAME, force = entity.force,
    }) do
        if found.unit_number ~= entity.unit_number then return true end
    end
    return false
end

local function deny_second_outlet(entity, event)
    local surface = entity.surface
    local position = entity.position
    local player = event.player_index and game.get_player(event.player_index)
    entity.destroy()
    local stack = { name = OUTLET_NAME, count = 1 }
    if not (player and player.insert(stack) > 0) then
        surface.spill_item_stack { position = position, stack = stack }
    end
    if player then
        player.create_local_flying_text {
            text = {"gui-etech-hub.one-per-surface"},
            position = position,
        }
    end
end

-- forward declarations: defined with the ghost index (on-demand section)
-- and the factory-cache section respectively
local gindex_on_ghost_built
local cached_factories

local function on_built(event)
    local entity = event.entity or event.destination
    if not (entity and entity.valid) then return end
    local etype = entity.type
    if KINDS[entity.name] then
        if entity.name == OUTLET_NAME and another_outlet_exists(entity) then
            deny_second_outlet(entity, event)
            return
        end
        -- clone: copy the source device's settings; blueprint: restore the
        -- settings carried in the blueprint's entity tags
        local copy_from
        if event.source and event.source.valid then
            copy_from = hub_data().hubs[event.source.unit_number]
        elseif event.tags and event.tags.etech_hub then
            copy_from = event.tags.etech_hub
        end
        local record = register_device(entity, copy_from)
        -- placement feedback: a device with zero reachable factories does
        -- nothing — say so instead of sitting silently empty
        if factorissimo_available() then
            local factories = cached_factories(record)
            if #factories == 0 then
                local player = event.player_index and game.get_player(event.player_index)
                if player and player.valid then
                    player.create_local_flying_text {
                        text = {"gui-etech-hub.no-factories"},
                        position = entity.position,
                    }
                end
            end
        end
    elseif etype == "entity-ghost" or etype == "tile-ghost" then
        gindex_on_ghost_built(entity)
    elseif etype == "storage-tank" then
        -- possible Factorissimo building: invalidate every factory-list cache
        local data = hub_data()
        data.factory_gen = (data.factory_gen or 0) + 1
    elseif etype == "logistic-container" then
        -- possible interior chest: invalidate every device's chest cache
        local data = hub_data()
        data.chest_gen = (data.chest_gen or 0) + 1
    end
end

-- Interior bounds of a factory, with 1 tile of slack (walls hold no chests).
local function factory_interior_area(factory)
    local r = factory.layout.inside_size / 2 + 1
    return {
        {factory.inside_x - r, factory.inside_y - r},
        {factory.inside_x + r, factory.inside_y + r},
    }
end

local function factory_usable(factory)
    return factory
        and not factory.inactive
        and factory.built ~= false
        and factory.building and factory.building.valid
        and factory.inside_surface and factory.inside_surface.valid
end

-- Factories reachable from a list of candidate building entities, recursing
-- into factories placed inside them. visited guards against repeats when two
-- candidates resolve to the same factory.
local function collect_factories(candidates, force, out, visited, depth)
    if depth > MAX_DEPTH then return end
    for _, building in pairs(candidates) do
        if building.valid and is_factory_building(building.name) then
            local factory = factorissimo_call("get_factory_by_entity", building)
            if factory_usable(factory) and not visited[factory.id] then
                visited[factory.id] = true
                out[#out + 1] = factory
                local nested = factory.inside_surface.find_entities_filtered {
                    area = factory_interior_area(factory),
                    type = "storage-tank",
                    force = force,
                }
                collect_factories(nested, force, out, visited, depth + 1)
            end
        end
    end
end

-- Top-level factory buildings the device can see. On a normal surface: every
-- factory on the surface. On a Factorissimo
-- interior surface (device placed inside a factory): only factories within
-- the surrounding factory's own interior cell — interior surfaces are shared
-- 8-wide grids of unrelated factories and the device must not reach across
-- cells.
local function factories_for_hub(hub)
    local surface = hub.surface
    local candidates
    if factorissimo_call("is_factorissimo_surface", surface.index) then
        local parent = factorissimo_call(
            "find_surrounding_factory_by_surface_index", surface.index, hub.position)
        if not factory_usable(parent) then return {} end
        candidates = surface.find_entities_filtered {
            area = factory_interior_area(parent),
            type = "storage-tank",
            force = hub.force,
        }
    else
        candidates = surface.find_entities_filtered {
            type = "storage-tank",
            force = hub.force,
        }
    end
    local out, visited = {}, {}
    collect_factories(candidates, hub.force, out, visited, 1)
    return out
end

function cached_factories(record) -- assigns the forward declaration
    local tick = game.tick
    local gen = hub_data().factory_gen or 0
    if not record.factories or record.factory_gen ~= gen
        or tick - (record.scanned_tick or 0) >= RESCAN_TICKS then
        record.factories = factories_for_hub(record.entity)
        record.scanned_tick = tick
        record.factory_gen = gen
    end
    return record.factories
end

-- Interior-chest cache. Profiling showed the per-pass
-- find_entities_filtered over every factory interior was the steady
-- baseline cost of the pull pass (~3-5 ms at ~90 chests, every pass,
-- forever), so the chest list is cached per device and only rebuilt when
-- something can actually have changed: any logistic-container built or
-- mined anywhere (data.chest_gen bump — coarse but those events are rare)
-- or the device's factory list itself refreshed (scanned_tick moved).
-- Chests destroyed without a mine event (biters) leave stale entries; they
-- fail the per-use valid check and get swept out on the next rebuild.
-- The prototype logistic_mode is frozen at build time so filtering by mode
-- costs no API calls.
local function ensure_chest_cache(record)
    local data = hub_data()
    local gen = data.chest_gen or 0
    local cache = record.chest_cache
    if cache and cache.gen == gen and cache.scanned_tick == record.scanned_tick then
        return cache
    end
    local entries = {}
    local force = record.entity.force
    for _, factory in pairs(cached_factories(record)) do
        if factory_usable(factory) then
            local found = factory.inside_surface.find_entities_filtered {
                area = factory_interior_area(factory),
                type = "logistic-container",
                force = force,
            }
            for _, chest in pairs(found) do
                if chest.name ~= OUTLET_NAME then
                    entries[#entries + 1] = {
                        chest = chest,
                        mode = chest.prototype.logistic_mode,
                        factory = factory,
                    }
                end
            end
        end
    end
    -- read scanned_tick AFTER cached_factories: it may have refreshed it
    cache = { gen = gen, scanned_tick = record.scanned_tick, entries = entries }
    record.chest_cache = cache
    return cache
end

local function provider_mode(mode)
    return mode == "active-provider" or mode == "passive-provider"
end

-- Outlets can optionally also drain yellow storage chests (deconstruction
-- leftovers etc.); the toggle is per outlet.
local function outlet_source_mode(record)
    return function(mode)
        if mode == "storage" then return record.pull_storage == true end
        return provider_mode(mode)
    end
end

local function requester_mode(mode)
    return mode == "requester" or mode == "buffer"
end

-- Every interior chest a device can currently reach. Includes the owning
-- factory in each entry for the GUI's per-factory breakdown.
local function reachable_chests(record, accept_mode)
    local out = {}
    for _, entry in ipairs(ensure_chest_cache(record).entries) do
        if entry.chest.valid and factory_usable(entry.factory)
            and accept_mode(entry.mode) then
            out[#out + 1] = { chest = entry.chest, factory = entry.factory }
        end
    end
    return out
end

-- Per-hub item filter --------------------------------------------------------

local function filter_set(record)
    local set = nil
    for _, name in pairs(record.filters.items) do
        set = set or {}
        set[name] = true
    end
    return set
end

local function item_allowed(record, name, set)
    local mode = record.filters.mode
    if mode == 2 then return set ~= nil and set[name] == true end
    if mode == 3 then return not (set and set[name]) end
    return true
end

-- Circuit gate -----------------------------------------------------------------

-- Automatic, no checkbox: with no circuit wire connected the outlet always
-- runs; with a wire connected it only runs while any nonzero signal reaches
-- it (red or green).
local function circuit_enabled(record)
    local entity = record.entity
    local wired = false
    for _, wire in pairs({defines.wire_connector_id.circuit_red,
                          defines.wire_connector_id.circuit_green}) do
        local net = entity.get_circuit_network(wire)
        if net then
            wired = true
            for _, s in pairs(net.signals or {}) do
                if s.count ~= 0 then return true end
            end
        end
    end
    return not wired
end

-- Pull rate stat ---------------------------------------------------------------
-- (the energy-per-item cost and its hidden companion entity were removed in
-- 0.17.0)

local function note_moved(record, moved)
    local tick = game.tick
    local samples = record.moved_samples
    if not samples then
        samples = {}
        record.moved_samples = samples
    end
    samples[#samples + 1] = { tick = tick, moved = moved }
    -- Amortized prune: only rebuild when the oldest entry actually expired
    -- (the old full copy every pass was pure allocation churn).
    if samples[1] and tick - samples[1].tick > RATE_WINDOW then
        local pruned = {}
        for _, s in ipairs(samples) do
            if tick - s.tick <= RATE_WINDOW then pruned[#pruned + 1] = s end
        end
        record.moved_samples = pruned
    end
end

local function rate_per_minute(record)
    local total = 0
    for _, s in pairs(record.moved_samples or {}) do total = total + s.moved end
    return total
end

-- Item transfer helpers ---------------------------------------------------------

local function split_key(key)
    return key:match("^(.-)|(.*)$")
end

-- Returned items (overflow, on-demand give-backs, mined-device dumps) must
-- not scatter into the first chest with a free slot — that fills factory
-- chests with items that never belonged there. Only two acceptable homes:
-- a chest that already holds that exact item (its origin chest wins
-- naturally), then a completely EMPTY chest (nothing to contaminate). If
-- neither exists the item deliberately stays where it is (outlet buffer /
-- mining buffer) rather than mixing into someone else's chest.
local function return_passes(name, quality)
    return {
        function(chest) return chest.get_item_count({name = name, quality = quality}) > 0 end,
        function(chest)
            local inv = chest.get_inventory(defines.inventory.chest)
            return inv and inv.is_empty()
        end,
    }
end

-- Insert a whole LuaItemStack into chests in return-preference order,
-- preserving spoilage/quality/ammo (mining return). Mutates the source
-- stack down to whatever couldn't be placed.
local function insert_stack_into_chests(chests, stack)
    if not stack.valid_for_read then return end
    for _, accept in ipairs(return_passes(stack.name, stack.quality.name)) do
        for _, entry in pairs(chests) do
            if not stack.valid_for_read then return end
            local chest = entry.chest
            if chest.valid and accept(chest) then
                local inv = chest.get_inventory(defines.inventory.chest)
                if inv then
                    local inserted = inv.insert(stack)
                    if inserted > 0 then
                        stack.count = stack.count - inserted -- reaching 0 clears the stack
                    end
                end
            end
        end
    end
end

-- Insert `count` of a plain item spec into chests in return-preference
-- order (overflow/on-demand return; spec-based, so spoil timers restart).
-- Returns number inserted.
local function insert_spec_into_chests(chests, name, quality, count)
    local total = 0
    for _, accept in ipairs(return_passes(name, quality)) do
        for _, entry in pairs(chests) do
            local remaining = count - total
            if remaining <= 0 then return total end
            local chest = entry.chest
            if chest.valid and accept(chest) then
                local inv = chest.get_inventory(defines.inventory.chest)
                if inv then
                    total = total + inv.insert({name = name, count = remaining, quality = quality})
                end
            end
        end
    end
    return total
end

local function inventory_counts(inv)
    local counts = {}
    for _, item in pairs(inv.get_contents()) do
        counts[item_key(item.name, item.quality)] = item.count
    end
    return counts
end

-- Outlet: on-demand pull ---------------------------------------------------------
-- (the buffer mode - keep N stacks of everything on hand - was removed in
-- 0.17.0: the outlet panel already shows the factories' stock, so
-- pre-staging items in the outlet bought nothing but clutter)

-- Construction-ghost demand. Ghosts aren't logistic requests, so the engine
-- never surfaces them through requester_points — an on-demand outlet would
-- sit empty while construction bots starve. We derive the demand ourselves.
--
-- EVENT-DRIVEN INDEX (profiling on a megabase killed every periodic-scan
-- design: each whole-ish-surface find_entities_filtered costs ~23 ms
-- regardless of matches, so any rescan cadence hitches):
--   - storage.…gindex[surface|force] = per-32x32-chunk demand totals,
--     built ONCE via full scan on first use, then maintained incrementally:
--     ghost built (on_built branch) adds it, ghost gone (on_object_destroyed,
--     which fires for revive, deconstruct, decay and scripted removal alike)
--     subtracts exactly what it added (recorded in …gunit[unit_number]).
--     Steady-state periodic cost: zero.
--   - item-request-proxies (module/fuel requests on BUILT machines) have no
--     reliable build event, so they keep a slow periodic scan (PROXY_TICKS,
--     area-limited to construction coverage). They're rare; it's cheap.
--   - per pull pass, ghost_wants intersects the chunk buckets with the
--     outlet network's construction squares — pure Lua math, no API calls.
-- All state lives in storage: a session-local cache would desync MP joiners.

-- Per-prototype ghost info, memoized (pure prototype data, so a local cache
-- is deterministic — same trick as layout_name_cache):
--   place    - first items_to_place_this entry (what bots deliver), or false
--   requests - whether this prototype can carry an insert_plan worth reading
--              (modules/fuel/equipment-grid/turret ammo). Reading insert_plan
--              is an API call per ghost; gating it out for belts, walls,
--              rails etc. is most of the scan cost on big blueprint pastes.
local ghost_info_cache = {}
local function ghost_info(key, ghost)
    local info = ghost_info_cache[key]
    if info == nil then
        local proto = ghost.ghost_prototype
        local spec = proto.items_to_place_this
        spec = spec and spec[1]
        local requests = false
        if proto.object_name == "LuaEntityPrototype" then
            requests = (proto.module_inventory_size or 0) > 0
                or proto.burner_prototype ~= nil
                or proto.grid_prototype ~= nil
                or proto.type == "ammo-turret"
                or proto.type == "artillery-turret"
        end
        info = {
            place = spec and { name = spec.name, count = spec.count or 1 } or false,
            requests = requests,
        }
        ghost_info_cache[key] = info
    end
    return info
end

-- Total items of a BlueprintInsertPlan list into an item|quality counts dict
-- (module/fuel/ammo requests on ghosts and on already-built machines via
-- item-request-proxy). ItemStackLocation carries no count: one per slot.
local function add_insert_plans(items, plans)
    for _, plan in pairs(plans or {}) do
        local p = plan.items
        local count = p.grid_count or 0
        for _ in pairs(p.in_inventory or {}) do
            count = count + 1
        end
        if count > 0 then
            local quality = plan.id.quality
            if type(quality) ~= "string" then
                quality = quality and quality.name or "normal"
            end
            local key = item_key(plan.id.name, quality)
            items[key] = (items[key] or 0) + count
        end
    end
end

-- Bounding box of everywhere this force's construction bots can build on a
-- surface (union of all logistic cells' construction squares). nil when the
-- force has no construction coverage there. Whole-surface find calls crawl
-- the entire generated chunk grid of a megabase surface (profiled at ~40 ms
-- EACH regardless of match count) — the area limit is what makes the ghost
-- scan cheap, ghosts outside bot range can't be built anyway.
local function construction_bbox(surface, force)
    local networks = force.logistic_networks[surface.name]
    if not networks then return nil end
    local x1, y1, x2, y2
    for _, network in pairs(networks) do
        for _, cell in pairs(network.cells) do
            local r = cell.construction_radius
            if r and r > 0 and cell.owner and cell.owner.valid then
                local p = cell.owner.position
                if not x1 then
                    x1, y1, x2, y2 = p.x - r, p.y - r, p.x + r, p.y + r
                else
                    if p.x - r < x1 then x1 = p.x - r end
                    if p.y - r < y1 then y1 = p.y - r end
                    if p.x + r > x2 then x2 = p.x + r end
                    if p.y + r > y2 then y2 = p.y + r end
                end
            end
        end
    end
    if not x1 then return nil end
    return {{x1 - 1, y1 - 1}, {x2 + 1, y2 + 1}}
end

local function gindex_key(surface, force)
    return surface.index .. "|" .. force.index
end

-- Add one ghost's demand to its chunk bucket and remember exactly what it
-- contributed (gunit) so the destroy event can subtract it precisely.
local function gindex_add(idx, key, ghost, is_tile)
    local info = ghost_info((is_tile and "t|" or "e|") .. ghost.ghost_name, ghost)
    if not (info.place or info.requests) then return end
    local items = {}
    if info.place then
        local quality = is_tile and "normal" or ghost.quality.name
        items[item_key(info.place.name, quality)] = info.place.count
    end
    if info.requests then
        add_insert_plans(items, ghost.insert_plan)
    end
    if next(items) == nil then return end
    local pos = ghost.position
    local cx, cy = math.floor(pos.x / 32), math.floor(pos.y / 32)
    local ck = cx .. ":" .. cy
    local chunk = idx.chunks[ck]
    if not chunk then
        chunk = { x = cx * 32 + 16, y = cy * 32 + 16, items = {} }
        idx.chunks[ck] = chunk
    end
    for k, n in pairs(items) do
        chunk.items[k] = (chunk.items[k] or 0) + n
    end
    idx.count = idx.count + 1
    hub_data().gunit[ghost.unit_number] = { key = key, ck = ck, items = items }
    script.register_on_object_destroyed(ghost)
end

-- Ghost index for a surface+force: chunk_key -> {x, y (chunk center),
-- items = {item|quality -> count}}. Full scan once (the only time the
-- expensive finds run), incremental forever after.
local function ghost_index(surface, force)
    local data = hub_data()
    data.gindex = data.gindex or {}
    data.gunit = data.gunit or {}
    local key = gindex_key(surface, force)
    local idx = data.gindex[key]
    if not idx then
        local prof = data.profiling and helpers.create_profiler()
        idx = { chunks = {}, count = 0 }
        data.gindex[key] = idx
        for _, ghost in pairs(surface.find_entities_filtered {
            type = "entity-ghost", force = force,
        }) do
            gindex_add(idx, key, ghost, false)
        end
        for _, ghost in pairs(surface.find_entities_filtered {
            type = "tile-ghost", force = force,
        }) do
            gindex_add(idx, key, ghost, true)
        end
        if prof then
            prof.stop()
            helpers.write_file(PROFILE_FILE,
                {"", game.tick, ",index-build(", surface.name, " ghosts=", idx.count, "),", prof, "\n"}, true)
        end
    end
    return idx
end

-- Called from on_built for every new ghost: index it if we're tracking its
-- surface+force (if we aren't yet, the eventual full scan will catch it).
-- Assigns the forward declaration above on_built.
function gindex_on_ghost_built(ghost)
    local data = hub_data()
    local idx = data.gindex and data.gindex[gindex_key(ghost.surface, ghost.force)]
    if idx then
        gindex_add(idx, gindex_key(ghost.surface, ghost.force), ghost,
            ghost.type == "tile-ghost")
    end
end

-- Called from on_object_destroyed (fires on revive, deconstruction, decay
-- and scripted removal alike): subtract what this ghost contributed.
local function gindex_on_ghost_gone(unit_number)
    local data = hub_data()
    local g = data.gunit and data.gunit[unit_number]
    if not g then return end
    data.gunit[unit_number] = nil
    local idx = data.gindex and data.gindex[g.key]
    if not idx then return end
    local chunk = idx.chunks[g.ck]
    if chunk then
        for k, n in pairs(g.items) do
            local left = (chunk.items[k] or 0) - n
            if left > 0 then chunk.items[k] = left else chunk.items[k] = nil end
        end
        if next(chunk.items) == nil then idx.chunks[g.ck] = nil end
    end
    if idx.count > 0 then idx.count = idx.count - 1 end
end

-- Item-request-proxies (module/fuel requests on built machines) have no
-- build event we can hook, so they keep a slow, area-limited periodic scan.
-- prewarm: refresh PULL_TICKS early (called from the maintenance phase) so
-- the ~23 ms rescan never lands on the same tick as a pull pass.
local function surface_proxies(surface, force, prewarm)
    local data = hub_data()
    data.proxies = data.proxies or {}
    local key = gindex_key(surface, force)
    local entry = data.proxies[key]
    local ttl = prewarm and (PROXY_TICKS - PULL_TICKS) or PROXY_TICKS
    if not entry or game.tick - entry.tick >= ttl then
        local prof = data.profiling and helpers.create_profiler()
        local chunks = {}
        local bbox = construction_bbox(surface, force)
        if bbox then
            local floor = math.floor
            for _, proxy in pairs(surface.find_entities_filtered {
                area = bbox, type = "item-request-proxy", force = force,
            }) do
                local pos = proxy.position
                local cx, cy = floor(pos.x / 32), floor(pos.y / 32)
                local ck = cx .. ":" .. cy
                local b = chunks[ck]
                if not b then
                    b = { x = cx * 32 + 16, y = cy * 32 + 16, items = {} }
                    chunks[ck] = b
                end
                add_insert_plans(b.items, proxy.insert_plan)
            end
        end
        entry = { tick = game.tick, chunks = chunks }
        data.proxies[key] = entry
        if prof then
            prof.stop()
            helpers.write_file(PROFILE_FILE,
                {"", game.tick, ",proxy-scan,", prof, "\n"}, true)
        end
    end
    return entry
end

-- Ghost demand visible to this outlet's network, per item|quality.
-- Membership = chunk center inside any cell's construction square (+16
-- half-chunk slack; construction areas are square). Boundary chunks
-- over-fetch a little, the give-back loop returns the excess. Cheap pure
-- math — recomputed every pass, no memo needed.
local function ghost_wants(record, network)
    local hub = record.entity
    local idx = ghost_index(hub.surface, hub.force)
    local proxies = surface_proxies(hub.surface, hub.force)
    local wants = {}
    if next(idx.chunks) == nil and next(proxies.chunks) == nil then
        return wants
    end
    local cells = {}
    for _, cell in pairs(network.cells) do
        local r = cell.construction_radius
        if r and r > 0 and cell.owner and cell.owner.valid then
            local p = cell.owner.position
            cells[#cells + 1] = { x = p.x, y = p.y, r = r + 16 }
        end
    end
    if #cells == 0 then return wants end
    local function merge(chunks)
        for _, chunk in pairs(chunks) do
            for _, c in pairs(cells) do
                if math.abs(chunk.x - c.x) <= c.r and math.abs(chunk.y - c.y) <= c.r then
                    for k, n in pairs(chunk.items) do
                        wants[k] = (wants[k] or 0) + n
                    end
                    break
                end
            end
        end
    end
    merge(idx.chunks)
    merge(proxies.chunks)
    return wants
end

-- Unmet demand on the outlet's own logistic network, per item|quality:
-- how much requesters (chests, players, spidertrons) still want beyond
-- what they hold, plus construction ghosts in the network's build range.
-- Returns nil when the outlet isn't in a network.
local function network_wants(outlet, record)
    local network = outlet.logistic_network
    if not network then return nil end
    local wants = {}
    for _, point in pairs(network.requester_points) do
        local owner = point.owner
        if owner.valid and owner ~= outlet then
            for _, section in pairs(point.sections) do
                if section.active then
                    for _, filter in pairs(section.filters) do
                        local v = filter.value
                        if v and v.name and (v.type == nil or v.type == "item") then
                            local quality = v.quality or "normal"
                            local have = owner.get_item_count({name = v.name, quality = quality})
                            local deficit = (filter.min or 0) - have
                            if deficit > 0 then
                                local key = item_key(v.name, quality)
                                wants[key] = (wants[key] or 0) + deficit
                            end
                        end
                    end
                end
            end
        end
    end
    -- construction ghosts count as demand too (the whole point of the
    -- outlet: anything inside the factories is usable outside, ghosts
    -- included)
    for key, count in pairs(ghost_wants(record, network)) do
        wants[key] = (wants[key] or 0) + count
    end
    return wants, network
end

-- On-demand: keep only wanted items in the outlet (return the rest to the
-- factories), then materialize what the network can't already supply.
local function pull_on_demand(record, hub_inv, chests, set)
    local prof = hub_data().profiling and helpers.create_profiler()
    local wants, network = network_wants(record.entity, record)
    if prof then
        prof.stop()
        helpers.write_file(PROFILE_FILE,
            {"", game.tick, ",net-wants,", prof, "\n"}, true)
    end
    local moved = 0

    -- send back anything no longer wanted (bots occasionally re-route if we
    -- yank an item they were flying toward; the engine handles it)
    for key, count in pairs(inventory_counts(hub_inv)) do
        local wanted = wants and wants[key] or 0
        local excess = count - wanted
        if excess > 0 then
            local name, quality = split_key(key)
            local inserted = insert_spec_into_chests(chests, name, quality, excess)
            if inserted > 0 then
                hub_inv.remove({name = name, count = inserted, quality = quality})
            end
        end
    end

    if not wants then return 0 end

    -- what the network can't already cover (its count includes our stock)
    local need = {}
    for key, want in pairs(wants) do
        local name, quality = split_key(key)
        local missing = want - network.get_item_count({name = name, quality = quality})
        if missing > 0 then need[key] = missing end
    end
    if next(need) == nil then return 0 end

    for _, entry in pairs(chests) do
        if next(need) == nil then break end
        local chest = entry.chest
        if chest.valid then
            local inv = chest.get_inventory(defines.inventory.chest)
            if inv then
                for i = 1, #inv do
                    local stack = inv[i]
                    if stack.valid_for_read and item_allowed(record, stack.name, set) then
                        local key = item_key(stack.name, stack.quality.name)
                        local missing = need[key]
                        if missing and missing >= 1 then
                            local original = stack.count
                            local move = math.min(missing, original)
                            if move < original then stack.count = move end
                            local inserted = hub_inv.insert(stack)
                            stack.count = original - inserted
                            moved = moved + inserted
                            need[key] = missing - inserted
                            if need[key] < 1 then need[key] = nil end
                        end
                    end
                end
            end
        end
    end
    return moved
end

local function pull_for_outlet(record)
    local hub = record.entity
    local hub_inv = hub.get_inventory(defines.inventory.chest)
    if not hub_inv then return end
    if not circuit_enabled(record) then
        note_moved(record, 0)
        return
    end

    local prof = hub_data().profiling and helpers.create_profiler()
    local chests = reachable_chests(record, outlet_source_mode(record))
    if prof then
        prof.stop()
        helpers.write_file(PROFILE_FILE,
            {"", game.tick, ",reach-chests(n=", #chests, "),", prof, "\n"}, true)
    end
    if #chests == 0 then
        note_moved(record, 0)
        return
    end

    local set = filter_set(record)
    note_moved(record, pull_on_demand(record, hub_inv, chests, set))
end

-- Inlet: distribute into interior requester/buffer chests ---------------------

-- Requested amounts of a chest from its logistic point sections.
local function chest_requests(chest)
    local point = chest.get_requester_point()
    if not point then return nil end
    local wants = {}
    for _, section in pairs(point.sections) do
        if section.active then
            for _, filter in pairs(section.filters) do
                local value = filter.value
                if value and value.name and (value.type == nil or value.type == "item") then
                    local key = item_key(value.name, value.quality)
                    wants[key] = (wants[key] or 0) + (filter.min or 0)
                end
            end
        end
    end
    return wants
end

-- Write the factories' remaining deficits as this inlet's own bot requests
-- (managed section, group "etech-inlet-auto"; the player's own sections are
-- never touched).
local function update_inlet_auto_requests(record, remaining)
    local point = record.entity.get_requester_point()
    if not point then return end
    local target
    for _, section in pairs(point.sections) do
        if section.group == AUTO_GROUP then
            target = section
            break
        end
    end
    if not record.auto_request then
        if target then target.filters = {} end
        return
    end
    if not target then target = point.add_section(AUTO_GROUP) end
    if not target then return end

    local list = {}
    for key, count in pairs(remaining or {}) do
        local name, quality = split_key(key)
        list[#list + 1] = {
            value = { type = "item", name = name, quality = quality, comparator = "=" },
            min = count,
        }
        if #list >= MAX_SIGNALS then break end
    end
    target.filters = list
end

local function distribute_for_inlet(record)
    local inlet = record.entity
    local inlet_inv = inlet.get_inventory(defines.inventory.chest)
    if not inlet_inv then return end

    local have = inventory_counts(inlet_inv)
    local targets = reachable_chests(record, requester_mode)
    local moved = 0
    local remaining = {} -- interior deficits left after this pass, for auto-request
    local set = filter_set(record) -- inlets filter like outlets since 0.19.0

    for _, entry in pairs(targets) do
        local chest = entry.chest
        if chest.valid then
            local wants = chest_requests(chest)
            if wants and next(wants) then
                local inv = chest.get_inventory(defines.inventory.chest)
                local current = inventory_counts(inv)
                for key, want in pairs(wants) do
                    local name, quality = split_key(key)
                    if item_allowed(record, name, set) then
                        local deficit = want - (current[key] or 0)
                        if deficit > 0 then
                            local available = have[key] or 0
                            local move = math.min(available, deficit)
                            if move >= 1 then
                                -- spec-based transfer: spoil timers restart
                                local inserted = inv.insert({name = name, count = move, quality = quality})
                                if inserted > 0 then
                                    inlet_inv.remove({name = name, count = inserted, quality = quality})
                                    have[key] = available - inserted
                                    moved = moved + inserted
                                    deficit = deficit - inserted
                                end
                            end
                            if deficit > 0 then
                                remaining[key] = (remaining[key] or 0) + deficit
                            end
                        end
                    end
                end
            end
        end
    end

    update_inlet_auto_requests(record, remaining)
    record.last_remaining = next(remaining) and remaining or nil
    note_moved(record, moved)
end

-- Fluid outlet / inlet ---------------------------------------------------------
-- Storage-tank devices bridging fluids across the factory wall (0.19.0).
-- One fluid per device at a time: the outlet locks onto whatever fluid it
-- currently holds (or the first interior fluid it finds) and keeps topping
-- itself up from interior storage tanks; the inlet pushes its own fluid
-- into interior tanks that already hold the same fluid (never into empty
-- or foreign tanks — no contamination).

-- Interior plain storage tanks (factory BUILDINGS are storage-tanks too —
-- excluded via has_layout). Cached alongside the factory list.
local function reachable_tanks(record)
    local data = hub_data()
    local gen = data.factory_gen or 0
    local cache = record.tank_cache
    if cache and cache.gen == gen and cache.scanned_tick == record.scanned_tick then
        return cache.tanks
    end
    local tanks = {}
    local force = record.entity.force
    for _, factory in pairs(cached_factories(record)) do
        if factory_usable(factory) then
            for _, tank in pairs(factory.inside_surface.find_entities_filtered {
                area = factory_interior_area(factory),
                type = "storage-tank",
                force = force,
            }) do
                if not is_factory_building(tank.name)
                    and tank.name ~= FLUID_OUTLET_NAME and tank.name ~= FLUID_INLET_NAME then
                    tanks[#tanks + 1] = tank
                end
            end
        end
    end
    record.tank_cache = { gen = gen, scanned_tick = record.scanned_tick, tanks = tanks }
    return tanks
end

local function device_fluid(entity)
    for name, amount in pairs(entity.get_fluid_contents()) do
        return name, amount
    end
end

local function pass_for_fluid_outlet(record)
    local device = record.entity
    -- 2.1: LuaEntity.fluidbox is gone; capacity/removal go through
    -- get_fluid_capacity / extract_fluid directly on the entity.
    local capacity = device.get_fluid_capacity(1)
    local current_name, current_amount = device_fluid(device)
    local room = capacity - (current_amount or 0)
    if room < 1 then return end
    local moved = 0
    for _, tank in pairs(reachable_tanks(record)) do
        if room < 1 then break end
        if tank.valid then
            local name, amount = device_fluid(tank)
            if name and amount and amount >= 1 and (current_name == nil or name == current_name) then
                local take = math.min(room, amount)
                local removed = tank.extract_fluid{name = name, amount = take}
                if removed > 0 then
                    local inserted = device.insert_fluid{name = name, amount = removed}
                    -- overfill safety: give back what didn't fit
                    if inserted < removed then
                        tank.insert_fluid{name = name, amount = removed - inserted}
                    end
                    if inserted > 0 then
                        current_name = name
                        room = room - inserted
                        moved = moved + inserted
                    end
                end
            end
        end
    end
    note_moved(record, math.floor(moved))
end

local function pass_for_fluid_inlet(record)
    local device = record.entity
    local name, amount = device_fluid(device)
    if not (name and amount and amount >= 1) then
        note_moved(record, 0)
        return
    end
    local moved = 0
    for _, tank in pairs(reachable_tanks(record)) do
        if amount < 1 then break end
        if tank.valid then
            local tank_fluid, tank_amount = device_fluid(tank)
            if tank_fluid == name then
                local room = tank.get_fluid_capacity(1) - (tank_amount or 0)
                if room >= 1 then
                    local give = math.min(room, amount)
                    local inserted = tank.insert_fluid{name = name, amount = give}
                    if inserted > 0 then
                        device.extract_fluid{name = name, amount = inserted}
                        amount = amount - inserted
                        moved = moved + inserted
                    end
                end
            end
        end
    end
    note_moved(record, math.floor(moved))
end

-- Sensor: broadcast interior provider totals as signals ------------------------

local function update_sensor(record)
    local totals = {}
    for _, entry in pairs(reachable_chests(record, provider_mode)) do
        local inv = entry.chest.get_inventory(defines.inventory.chest)
        if inv then
            for _, item in pairs(inv.get_contents()) do
                local key = item_key(item.name, item.quality)
                totals[key] = (totals[key] or 0) + item.count
            end
        end
    end

    -- Dirty check: rewriting the whole section every pass was the sensor's
    -- entire steady-state cost. Totals are compared as a sorted signature;
    -- unchanged -> no section write.
    local sig = {}
    for key, count in pairs(totals) do
        sig[#sig + 1] = key .. "=" .. count
    end
    table.sort(sig)
    local snapshot = table.concat(sig, ";")
    if record.sensor_snapshot == snapshot then return end
    record.sensor_snapshot = snapshot

    local list = {}
    for key, count in pairs(totals) do
        local name, quality = split_key(key)
        list[#list + 1] = {
            value = { type = "item", name = name, quality = quality, comparator = "=" },
            min = count,
        }
    end
    if #list > MAX_SIGNALS then
        table.sort(list, function(a, b) return a.min > b.min end)
        for i = #list, MAX_SIGNALS + 1, -1 do list[i] = nil end
    end

    local behavior = record.entity.get_or_create_control_behavior()
    local section = behavior.get_section(1) or behavior.add_section()
    section.filters = list
end

-- Mining an outlet/inlet: send its buffered items back into the factories'
-- provider chests so the player picks up just the chest. Whatever doesn't
-- fit stays in the mining buffer (player gets it, vanilla behavior).
local function on_mined(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end
    if entity.type == "storage-tank" then -- possible Factorissimo building
        local data = hub_data()
        data.factory_gen = (data.factory_gen or 0) + 1
    elseif entity.type == "logistic-container" then
        local data = hub_data()
        data.chest_gen = (data.chest_gen or 0) + 1
    end
    local kind = KINDS[entity.name]
    if not (kind == "outlet" or kind == "inlet") then return end
    local buffer = event.buffer
    if not (buffer and factorissimo_available()) then return end

    local record = hub_data().hubs[entity.unit_number]
        or { entity = entity, kind = kind, filters = { mode = 1, items = {} }, pins = {} }
    local chests = reachable_chests(record, provider_mode)
    if #chests == 0 then return end
    for i = 1, #buffer do
        local stack = buffer[i]
        -- skip the device item itself (and any of them it was buffering)
        if stack.valid_for_read and not KINDS[stack.name] then
            insert_stack_into_chests(chests, stack)
        end
    end
end

-- GPS helpers -------------------------------------------------------------------

local function gps_tag(factory)
    local building = factory.building
    return string.format("[gps=%d,%d,%s]",
        building.position.x, building.position.y, building.surface.name)
end

local function locate_item(player, record, name, quality)
    local per = {}
    for _, entry in pairs(reachable_chests(record, outlet_source_mode(record))) do
        local inv = entry.chest.get_inventory(defines.inventory.chest)
        if inv then
            local count = inv.get_item_count({name = name, quality = quality})
            if count > 0 then
                local id = entry.factory.id
                if not per[id] then per[id] = { factory = entry.factory, count = 0 } end
                per[id].count = per[id].count + count
            end
        end
    end
    local found = false
    for id, info in pairs(per) do
        found = true
        player.print({"gui-etech-hub.locate-line", name, factory_label(id), info.count, gps_tag(info.factory)})
    end
    if not found then
        player.print({"gui-etech-hub.locate-none", name})
    end
end

-- Shift-click: teleport up to one stack of the item straight from the
-- factories into the player's inventory (slot-level transfer, spoil/quality
-- preserved).
local function take_item(player, record, name, quality)
    local player_inv = player.get_main_inventory()
    if not player_inv then return end
    local proto = prototypes.item[name]
    if not proto then return end -- item removed by a mod change
    local wanted = proto.stack_size
    local taken = 0
    for _, entry in pairs(reachable_chests(record, outlet_source_mode(record))) do
        if taken >= wanted then break end
        local inv = entry.chest.valid and entry.chest.get_inventory(defines.inventory.chest)
        if inv then
            for i = 1, #inv do
                if taken >= wanted then break end
                local stack = inv[i]
                if stack.valid_for_read and stack.name == name
                    and stack.quality.name == quality then
                    local original = stack.count
                    local move = math.min(original, wanted - taken)
                    if move < original then stack.count = move end
                    local inserted = player_inv.insert(stack)
                    stack.count = original - inserted
                    taken = taken + inserted
                    if inserted < move then -- player inventory full
                        wanted = taken
                        break
                    end
                end
            end
        end
    end
    if taken > 0 then
        player.print({"gui-etech-hub.took", taken, name})
    else
        player.print({"gui-etech-hub.take-failed", name})
    end
end

-- GUI: outlet panel --------------------------------------------------------------

local MODE_ITEMS = {
    {"gui-etech-hub.mode-all"},
    {"gui-etech-hub.mode-whitelist"},
    {"gui-etech-hub.mode-blacklist"},
}

local function build_panel(player)
    local old = player.gui.relative[PANEL_NAME]
    if old then old.destroy() end
    local panel = player.gui.relative.add {
        type = "frame",
        name = PANEL_NAME,
        direction = "vertical",
        caption = {"gui-etech-hub.panel-title"},
        anchor = {
            gui = defines.relative_gui_type.container_gui,
            position = defines.relative_gui_position.right,
            names = {OUTLET_NAME},
        },
    }
    local inner = panel.add {
        type = "frame",
        name = "inner",
        style = "inside_shallow_frame_with_padding",
        direction = "vertical",
    }
    inner.add {type = "label", name = "rate"}
    local search = inner.add {type = "textfield", name = "etech-hub-search"}
    search.style.horizontally_stretchable = true
    local scroll = inner.add {type = "scroll-pane", name = "scroll"}
    -- tall enough to visually match the 200-slot chest window next to it
    scroll.style.minimal_height = 420
    scroll.style.maximal_height = 640

    inner.add {type = "line", name = "sep"}
    inner.add {type = "label", name = "settings_label",
        caption = {"gui-etech-hub.pull-settings"}}
    local checks = inner.add {type = "flow", name = "checks", direction = "vertical"}
    checks.add {type = "checkbox", name = "etech-hub-storage", state = false,
        caption = {"gui-etech-hub.storage"}, tooltip = {"gui-etech-hub.storage-tooltip"}}
    inner.add {type = "drop-down", name = "etech-hub-mode", items = MODE_ITEMS}
    local slots = inner.add {type = "table", name = "filter_slots", column_count = 5}
    for i = 1, FILTER_SLOTS do
        slots.add {type = "choose-elem-button", name = "etech-hub-filter-" .. i,
            elem_type = "item"}
    end

    inner.add {type = "label", name = "factories_label",
        caption = {"gui-etech-hub.factories"}}
    local fscroll = inner.add {type = "scroll-pane", name = "fscroll"}
    fscroll.style.maximal_height = 220
    fscroll.add {type = "table", name = "frows", column_count = 2}
    return panel
end

local function load_panel_settings(player, record)
    local panel = build_panel(player)
    local inner = panel.inner
    inner.checks["etech-hub-storage"].state = record.pull_storage == true
    inner["etech-hub-mode"].selected_index = record.filters.mode or 1
    for i = 1, FILTER_SLOTS do
        inner.filter_slots["etech-hub-filter-" .. i].elem_value = record.filters.items[i]
    end

    -- factory rows: locate button + rename field (rebuilt on open only, so
    -- typing a name never gets clobbered by the 2 s refresh)
    local rows = inner.fscroll.frows
    rows.clear()
    local usable = {}
    for _, factory in pairs(cached_factories(record)) do
        if factory_usable(factory) then usable[#usable + 1] = factory end
    end
    for i = 1, math.min(#usable, MAX_FACTORY_ROWS) do
        local factory = usable[i]
        local btn = rows.add {type = "button", caption = {"gui-etech-hub.locate"}}
        btn.style.minimal_width = 50
        btn.tags = { etech = "factory-locate", id = factory.id }
        local field = rows.add {type = "textfield",
            text = hub_data().factory_names[factory.id] or ""}
        field.tags = { etech = "factory-name", id = factory.id }
        field.style.horizontally_stretchable = true
    end
    if #usable > MAX_FACTORY_ROWS then
        rows.add {type = "label", caption = {"gui-etech-hub.more-factories", #usable - MAX_FACTORY_ROWS}}
        rows.add {type = "label", caption = ""}
    end
end

local function refresh_grid(player, record)
    local panel = player.gui.relative[PANEL_NAME]
    if not panel then return end
    local inner = panel.inner
    -- rate line carries the pause reason — "0/min" with no explanation
    -- looked broken whenever a circuit gated the outlet off
    local rate_caption = {"gui-etech-hub.rate", rate_per_minute(record)}
    if not circuit_enabled(record) then
        rate_caption = {"", rate_caption, " ", {"gui-etech-hub.paused-circuit"}}
    end
    inner.rate.caption = rate_caption

    local search = inner["etech-hub-search"].text:lower()
    local scroll = inner.scroll
    scroll.clear()

    -- totals per item+quality with per-factory breakdown
    local reachable = reachable_chests(record, outlet_source_mode(record))
    local totals, order = {}, {}
    for _, entry in pairs(reachable) do
        local inv = entry.chest.get_inventory(defines.inventory.chest)
        if inv then
            for _, item in pairs(inv.get_contents()) do
                local quality = item.quality or "normal"
                local key = item_key(item.name, quality)
                local t = totals[key]
                if not t then
                    t = {name = item.name, quality = quality, count = 0, per = {}}
                    totals[key] = t
                    order[#order + 1] = t
                end
                t.count = t.count + item.count
                t.per[entry.factory.id] = (t.per[entry.factory.id] or 0) + item.count
            end
        end
    end

    local pins = record.pins or {}
    local list = {}
    for _, t in pairs(order) do
        if search == "" or t.name:lower():find(search, 1, true) then
            t.pinned = pins[item_key(t.name, t.quality)] == true
            list[#list + 1] = t
        end
    end
    if #list == 0 then
        -- say WHY the grid is empty instead of a generic "nothing found"
        local msg
        if #reachable == 0 then
            msg = {"gui-etech-hub.panel-no-chests"}
        elseif #order > 0 and search ~= "" then
            msg = {"gui-etech-hub.panel-no-match"}
        else
            msg = {"gui-etech-hub.panel-empty"}
        end
        scroll.add {type = "label", caption = msg}
        return
    end
    table.sort(list, function(a, b)
        if a.pinned ~= b.pinned then return a.pinned end
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)

    local grid = scroll.add {type = "table", name = "grid", column_count = 8}
    for _, t in ipairs(list) do
        local lines = {"", t.name}
        if t.quality ~= "normal" then
            lines[#lines + 1] = " (" .. t.quality .. ")"
        end
        -- one nested LocalisedString per factory line (factory_label may be
        -- localized, and the top-level {"",...} parameter cap is 20)
        local shown, total_factories = 0, table_size(t.per)
        for factory_id, n in pairs(t.per) do
            shown = shown + 1
            if shown > TOOLTIP_FACTORIES then
                lines[#lines + 1] = {"", "\n", {"gui-etech-hub.more-factories", total_factories - TOOLTIP_FACTORIES}}
                break
            end
            lines[#lines + 1] = {"", "\n", factory_label(factory_id), ": " .. n}
        end
        lines[#lines + 1] = {"gui-etech-hub.item-hint"}
        -- an item removed by a mod change would crash the GUI build here
        local sprite = "item/" .. t.name
        if not helpers.is_valid_sprite_path(sprite) then sprite = "utility/questionmark" end
        local btn = grid.add {
            type = "sprite-button",
            sprite = sprite,
            number = t.count,
            style = "slot_button",
            tooltip = lines,
        }
        btn.toggled = t.pinned
        btn.tags = { etech = "item", name = t.name, quality = t.quality }
    end
end

-- GUI: inlet panel ---------------------------------------------------------------

local function build_inlet_panel(player, record)
    local old = player.gui.relative[INLET_PANEL_NAME]
    if old then old.destroy() end
    local panel = player.gui.relative.add {
        type = "frame",
        name = INLET_PANEL_NAME,
        direction = "vertical",
        caption = {"gui-etech-hub.inlet-title"},
        anchor = {
            gui = defines.relative_gui_type.container_gui,
            position = defines.relative_gui_position.right,
            names = {INLET_NAME},
        },
    }
    local inner = panel.add {
        type = "frame",
        name = "inner",
        style = "inside_shallow_frame_with_padding",
        direction = "vertical",
    }
    inner.add {type = "label", name = "rate"}
    inner.add {type = "checkbox", name = "etech-inlet-auto",
        state = record.auto_request == true,
        caption = {"gui-etech-hub.auto-request"},
        tooltip = {"gui-etech-hub.auto-request-tooltip"}}

    -- Filter widgets (0.19.0 inlet parity): same element names as the
    -- outlet panel, so the shared name-based GUI handlers cover both.
    inner.add {type = "line", name = "sep"}
    inner.add {type = "label", name = "settings_label",
        caption = {"gui-etech-hub.inlet-filter"}}
    local mode = inner.add {type = "drop-down", name = "etech-hub-mode", items = MODE_ITEMS}
    mode.selected_index = record.filters and record.filters.mode or 1
    local slots = inner.add {type = "table", name = "filter_slots", column_count = 5}
    for i = 1, FILTER_SLOTS do
        local btn = slots.add {type = "choose-elem-button", name = "etech-hub-filter-" .. i,
            elem_type = "item"}
        btn.elem_value = record.filters and record.filters.items[i]
    end

    inner.add {type = "label", name = "deficit_label",
        caption = {"gui-etech-hub.inlet-deficits"}}
    local dscroll = inner.add {type = "scroll-pane", name = "dscroll"}
    dscroll.style.maximal_height = 220
end

local function refresh_inlet_panel(player, record)
    local panel = player.gui.relative[INLET_PANEL_NAME]
    if not panel then return end
    panel.inner.rate.caption = {"gui-etech-hub.inlet-rate", rate_per_minute(record)}

    -- Interior deficits left after the last pass — what the factories still
    -- want that the inlet couldn't supply.
    local dscroll = panel.inner.dscroll
    if not dscroll then return end
    dscroll.clear()
    local remaining = record.last_remaining
    if not (remaining and next(remaining)) then
        dscroll.add {type = "label", caption = {"gui-etech-hub.inlet-no-deficits"}}
        return
    end
    local list = {}
    for key, count in pairs(remaining) do
        local name, quality = split_key(key)
        list[#list + 1] = {name = name, quality = quality, count = count}
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    local grid = dscroll.add {type = "table", name = "dgrid", column_count = 8}
    for i = 1, math.min(#list, 64) do
        local t = list[i]
        local sprite = "item/" .. t.name
        if not helpers.is_valid_sprite_path(sprite) then sprite = "utility/questionmark" end
        grid.add {
            type = "sprite-button",
            sprite = sprite,
            number = t.count,
            style = "slot_button",
            tooltip = {"gui-etech-hub.deficit-tooltip", t.name, t.count},
        }
    end
end

-- GUI events ---------------------------------------------------------------------

local function open_record(player_index)
    local data = hub_data()
    local hub = data.open[player_index]
    if not (hub and hub.valid) then return nil end
    return data.hubs[hub.unit_number]
end

local function on_gui_opened(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end
    local kind = KINDS[entity.name]
    if not (kind == "outlet" or kind == "inlet") then return end
    if not factorissimo_available() then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    hub_data().open[event.player_index] = entity
    local record = hub_data().hubs[entity.unit_number]
    if not record then
        register_device(entity)
        record = hub_data().hubs[entity.unit_number]
    end
    if kind == "outlet" then
        load_panel_settings(player, record)
        refresh_grid(player, record)
    else
        build_inlet_panel(player, record)
        refresh_inlet_panel(player, record)
    end
end

local function on_gui_closed(event)
    local entity = event.entity
    if entity and entity.valid and KINDS[entity.name] then
        hub_data().open[event.player_index] = nil
    end
end

local function on_gui_selection_state_changed(event)
    -- event.element can already be invalid: another module's handler for the
    -- same event may have rebuilt its GUI (e.g. the teleporter list rebuilds
    -- on its sort dropdown) — touching .name then hard-crashes the game.
    if not (event.element and event.element.valid) then return end
    if event.element.name ~= "etech-hub-mode" then return end
    local record = open_record(event.player_index)
    if record then record.filters.mode = event.element.selected_index end
end

local function on_gui_elem_changed(event)
    if not (event.element and event.element.valid) then return end
    local slot = event.element.name:match("^etech%-hub%-filter%-(%d+)$")
    if not slot then return end
    local record = open_record(event.player_index)
    if record then record.filters.items[tonumber(slot)] = event.element.elem_value end
end

local function on_gui_checked_state_changed(event)
    if not (event.element and event.element.valid) then return end
    local name = event.element.name
    local record = open_record(event.player_index)
    if not record then return end
    if name == "etech-hub-storage" then
        record.pull_storage = event.element.state
    elseif name == "etech-inlet-auto" then
        record.auto_request = event.element.state
        if not record.auto_request then
            update_inlet_auto_requests(record, nil) -- clear the managed section
        end
    end
end

local function on_gui_text_changed(event)
    local element = event.element
    if not (element and element.valid) then return end
    local tags = element.tags
    if tags and tags.etech == "factory-name" then
        local text = element.text
        hub_data().factory_names[tags.id] = text ~= "" and text or nil
        return
    end
    local record = open_record(event.player_index)
    if not record then return end
    if element.name == "etech-hub-search" then
        local player = game.get_player(event.player_index)
        if player then refresh_grid(player, record) end
    end
end

local function on_gui_click(event)
    local element = event.element
    if not (element and element.valid) then return end
    local tags = element.tags
    if not (tags and tags.etech) then return end
    local player = game.get_player(event.player_index)
    local record = open_record(event.player_index)
    if not (player and record) then return end

    if tags.etech == "item" then
        if event.button == defines.mouse_button_type.right then
            record.pins = record.pins or {}
            local key = item_key(tags.name, tags.quality)
            record.pins[key] = not record.pins[key] or nil
            refresh_grid(player, record)
        elseif event.shift then
            take_item(player, record, tags.name, tags.quality)
            refresh_grid(player, record)
        else
            locate_item(player, record, tags.name, tags.quality)
        end
    elseif tags.etech == "factory-locate" then
        for _, factory in pairs(cached_factories(record)) do
            if factory.id == tags.id and factory_usable(factory) then
                player.print({"", factory_label(factory.id), " ", gps_tag(factory)})
                return
            end
        end
    end
end

-- Blueprint support: write each device's settings into the blueprint as an
-- entity tag, so pasted/rebuilt devices keep filters/mode/toggles (read back
-- in on_built via event.tags).
local function on_player_setup_blueprint(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local mapping = event.mapping.get()
    if not next(mapping) then return end
    local bp = player.blueprint_to_setup
    if not (bp and bp.valid_for_read) then
        bp = player.cursor_stack
    end
    if not (bp and bp.valid_for_read and bp.is_blueprint) then return end
    local hubs = hub_data().hubs
    for index, entity in pairs(mapping) do
        if entity.valid and KINDS[entity.name] then
            local record = hubs[entity.unit_number]
            if record then
                bp.set_blueprint_entity_tag(index, "etech_hub", {
                    filters = record.filters,
                    pull_storage = record.pull_storage,
                    auto_request = record.auto_request,
                })
            end
        end
    end
end

-- Tick dispatch ----------------------------------------------------------------

-- Scheduler ---------------------------------------------------------------------
-- One SLOT_TICKS step, 4 phases round-robin; each phase recurs every
-- PULL_TICKS. The old single on_pull_tick did all of this in one tick and
-- profiled at 10-46 ms every 2 s (a visible hitch); spreading the phases —
-- and pre-warming the expensive caches in their own phase — is the fix.

local function collect_records()
    local data = hub_data()
    local outlets, inlets, sensors, fluids = {}, {}, {}, {}
    for unit_number, record in pairs(data.hubs) do
        if record.entity.valid then
            if record.kind == "outlet" then outlets[#outlets + 1] = record
            elseif record.kind == "inlet" then inlets[#inlets + 1] = record
            elseif record.kind == "fluid-outlet" or record.kind == "fluid-inlet" then
                fluids[#fluids + 1] = record
            else sensors[#sensors + 1] = record end
        else
            data.hubs[unit_number] = nil
        end
    end
    return outlets, inlets, sensors, fluids
end

-- Pre-warm every cache a pull pass would otherwise rebuild inline: factory
-- lists near expiry (or gen-invalidated), chest caches, the proxy scan.
-- Runs on its own tick so the ~40 ms factory rescan and ~23 ms proxy scan
-- never share a tick with the pull work. The inline rebuild paths still
-- exist as fallbacks (first use after placement, gen bump mid-cycle).
local function maintenance_pass(outlets, inlets, sensors, fluids)
    local data = hub_data()
    local tick = game.tick
    local gen = data.factory_gen or 0
    -- At most ONE TTL-expiry factory rescan (~40 ms each on a big map) per
    -- maintenance pass, so several devices expiring together still refresh
    -- one blink at a time. The 4*PULL_TICKS early-refresh margin gives the
    -- rotation up to 4 passes of headroom before any device would fall back
    -- to an inline rescan during its pull. Gen-bump refreshes (a factory
    -- building was placed/removed - rare, player-visible) stay immediate.
    local rescan_budget = 1
    for _, group in pairs({ outlets, inlets, sensors, fluids or {} }) do
        for _, record in pairs(group) do
            local expired = tick - (record.scanned_tick or 0) >= RESCAN_TICKS - PULL_TICKS * 4
            if record.factory_gen ~= gen or (expired and rescan_budget > 0) then
                if record.factory_gen == gen then rescan_budget = rescan_budget - 1 end
                record.factories = factories_for_hub(record.entity)
                record.scanned_tick = tick
                record.factory_gen = gen
            end
            if record.kind == "fluid-outlet" or record.kind == "fluid-inlet" then
                reachable_tanks(record)
            else
                ensure_chest_cache(record)
            end
        end
    end
    for _, record in pairs(outlets) do
        surface_proxies(record.entity.surface, record.entity.force, true)
    end
    -- drop proxy caches nothing refreshed for two lifetimes (outlet gone,
    -- surface deleted) so storage doesn't accumulate dead surface entries
    if data.proxies then
        for key, entry in pairs(data.proxies) do
            if tick - entry.tick >= PROXY_TICKS * 2 then
                data.proxies[key] = nil
            end
        end
    end
end

-- live refresh for anyone looking at an outlet/inlet
local function refresh_open_guis()
    local data = hub_data()
    for player_index, hub in pairs(data.open) do
        local player = game.get_player(player_index)
        if player and player.valid and hub.valid and player.opened == hub then
            local record = data.hubs[hub.unit_number]
            if record then
                if record.kind == "outlet" then
                    refresh_grid(player, record)
                else
                    refresh_inlet_panel(player, record)
                end
            end
        else
            data.open[player_index] = nil
        end
    end
end

local function on_slot_tick(event)
    if not factorissimo_available() then return end
    local data = hub_data()
    local phase = math.floor(event.tick / SLOT_TICKS) % 4
    local prof = data.profiling and helpers.create_profiler()
    -- outlets first, then inlets, then sensors (one outlet per surface, so
    -- there is no cross-outlet competition to order)
    local outlets, inlets, sensors, fluids = collect_records()
    local label
    if phase == 0 then
        for _, record in pairs(outlets) do pull_for_outlet(record) end
        label = "pull-pass(outlets=" .. #outlets .. ")"
    elseif phase == 1 then
        for _, record in pairs(inlets) do distribute_for_inlet(record) end
        for _, record in pairs(sensors) do update_sensor(record) end
        for _, record in pairs(fluids) do
            if record.kind == "fluid-outlet" then
                pass_for_fluid_outlet(record)
            else
                pass_for_fluid_inlet(record)
            end
        end
        label = "inlet-pass(inlets=" .. #inlets .. " sensors=" .. #sensors
            .. " fluids=" .. #fluids .. ")"
    elseif phase == 2 then
        maintenance_pass(outlets, inlets, sensors, fluids)
        label = "maintenance"
    else
        refresh_open_guis()
        label = "gui-refresh"
    end
    if prof then
        prof.stop()
        helpers.write_file(PROFILE_FILE,
            {"", event.tick, ",", label, ",", prof, "\n"}, true)
    end
end

-- Debug ------------------------------------------------------------------------

local function debug_command(cmd)
    local player = game.get_player(cmd.player_index)
    if not player then return end
    if not factorissimo_available() then
        player.print("[factory-outlet] Factorissimo not active")
        return
    end
    local count = 0
    for _, record in pairs(hub_data().hubs) do
        local entity = record.entity
        if entity.valid then
            count = count + 1
            record.factories, record.scanned_tick = factories_for_hub(entity), game.tick
            local accept = record.kind == "inlet" and requester_mode
                or (record.kind == "outlet" and outlet_source_mode(record) or provider_mode)
            local chests = reachable_chests(record, accept)
            local mode = record.kind
            if record.kind == "outlet" and not circuit_enabled(record) then
                mode = mode .. " PAUSED by circuit"
            end
            player.print(string.format(
                "[factory-outlet] %s #%d at %s (%.0f, %.0f): %d factories, %d chests, %d items/min",
                mode, entity.unit_number, entity.surface.name,
                entity.position.x, entity.position.y,
                #record.factories, #chests, rate_per_minute(record)))
            if record.kind == "outlet" then
                local network = entity.logistic_network
                if not network then
                    player.print("  not in a logistic network — on-demand sees no demand")
                else
                    local lines = 0
                    for key, count in pairs(ghost_wants(record, network)) do
                        lines = lines + 1
                        if lines > 20 then
                            player.print("  ... (ghost list capped at 20 item types)")
                            break
                        end
                        local name, quality = split_key(key)
                        player.print("  ghost demand: " .. name ..
                            (quality ~= "normal" and ("(" .. quality .. ")") or "") ..
                            " x" .. count)
                    end
                    if lines == 0 then
                        player.print("  no construction-ghost demand in build range")
                    end
                end
            end
        end
    end
    if count == 0 then player.print("[factory-outlet] no outlets/inlets/sensors placed") end
end

-- Lifecycle --------------------------------------------------------------------

-- Mid-save enable / config change: adopt devices that already exist in the
-- world but aren't registered, keep old records' settings, and rebuild any
-- stale GUI panels from previous versions.
local function adopt_existing()
    -- drop ghost/proxy caches: mod versions may change what counts as
    -- demand, and the index re-registers destroy hooks on rebuild anyway.
    -- gunit entries whose destroy events fire later no-op harmlessly.
    local data = hub_data()
    data.gindex, data.gunit, data.proxies, data.ghosts = nil, nil, nil, nil
    -- invalidate every device's interior-chest cache too (prototype
    -- logistic_mode is frozen into the entries; mods may have changed it)
    data.chest_gen = (data.chest_gen or 0) + 1
    local hubs = data.hubs
    for _, surface in pairs(game.surfaces) do
        for name in pairs(KINDS) do
            for _, entity in pairs(surface.find_entities_filtered {name = name}) do
                local record = hubs[entity.unit_number]
                if not record then
                    register_device(entity)
                else
                    record.kind = KINDS[name]
                    record.filters = record.filters or { mode = 1, items = {} }
                    record.pins = record.pins or {}
                    -- Legacy-field cleanup, one line per retired field.
                    -- Policy: keep each line for two minor versions after
                    -- the field is retired, then delete it (saves older
                    -- than that must pass through an intermediate version
                    -- anyway). All five below retired in 0.17.0 — drop
                    -- this whole block in 0.21.x.
                    record.companion = nil
                    record.priority = nil
                    record.cap_override = nil
                    record.on_demand = nil
                    record.circuit_enable = nil
                end
            end
        end
    end
    for _, player in pairs(game.players) do
        for _, panel_name in pairs({PANEL_NAME, INLET_PANEL_NAME}) do
            local panel = player.gui.relative[panel_name]
            if panel then panel.destroy() end
        end
    end
end

M.on_init = adopt_existing
M.on_configuration_changed = adopt_existing

-- Toggle per-pass timing capture. Each pull pass (and each ghost scan)
-- appends a line to script-output/etech-profile.csv: tick, phase, duration.
-- LuaProfiler is the only wall-clock a mod can touch; it can't be read from
-- Lua, only printed — hence the file, parsed offline.
local function profile_command(cmd)
    local player = game.get_player(cmd.player_index)
    local data = hub_data()
    data.profiling = not data.profiling
    if data.profiling then
        helpers.write_file(PROFILE_FILE, "tick,phase,duration\n", false)
    end
    local msg = "[factory-outlet] profiling " ..
        (data.profiling and ("ON -> script-output/" .. PROFILE_FILE) or "OFF")
    if player then player.print(msg) else game.print(msg) end
end

M.add_commands = function()
    commands.add_command("etech-hub-debug",
        "Print factory outlet/inlet/sensor diagnostics", debug_command)
    commands.add_command("etech-hub-profile",
        "Toggle per-pass timing capture to script-output/etech-profile.csv", profile_command)
end

M.events = {
    [defines.events.on_built_entity] = on_built,
    [defines.events.on_robot_built_entity] = on_built,
    [defines.events.on_space_platform_built_entity] = on_built,
    [defines.events.script_raised_built] = on_built,
    [defines.events.script_raised_revive] = on_built,
    [defines.events.on_entity_cloned] = on_built,
    [defines.events.on_player_mined_entity] = on_mined,
    [defines.events.on_robot_mined_entity] = on_mined,
    [defines.events.on_space_platform_mined_entity] = on_mined,
    [defines.events.on_gui_opened] = on_gui_opened,
    [defines.events.on_gui_closed] = on_gui_closed,
    [defines.events.on_gui_selection_state_changed] = on_gui_selection_state_changed,
    [defines.events.on_gui_elem_changed] = on_gui_elem_changed,
    [defines.events.on_gui_checked_state_changed] = on_gui_checked_state_changed,
    [defines.events.on_gui_text_changed] = on_gui_text_changed,
    [defines.events.on_gui_click] = on_gui_click,
    [defines.events.on_player_setup_blueprint] = on_player_setup_blueprint,
    [defines.events.on_object_destroyed] = function(event)
        if event.useful_id then
            gindex_on_ghost_gone(event.useful_id)
            hub_data().hubs[event.useful_id] = nil
        end
    end,
}

M.on_nth_tick = {
    [SLOT_TICKS] = on_slot_tick,
}

return M
