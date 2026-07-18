-- factory-hub/control.lua
-- Runtime for the factory outlet / inlet / sensor (event_handler lib).
-- Every PULL_TICKS ticks:
--   outlet - teleports items out of the provider chests (optionally storage
--            chests) inside the Factorissimo factories on its surface into
--            itself (passive provider). Two modes per outlet:
--              buffer (default): keep N stacks of each item on hand
--              on-demand: sit empty; materialize items only when the local
--                logistic network has unmet demand (requesters, players,
--                spidertrons, and construction ghosts in build range)
--            plus per-outlet filters, priority ordering, circuit enable and
--            the optional energy cost.
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
local ENERGY_NAME = "etech-hub-energy"
local PANEL_NAME = "etech-hub-panel"
local INLET_PANEL_NAME = "etech-inlet-panel"
local AUTO_GROUP = "etech-inlet-auto"
local PULL_TICKS = 120     -- work pass per device, every 2 s (also GUI refresh)
local RESCAN_TICKS = 600   -- factory-list cache lifetime, 10 s
local GHOST_TICKS = 300    -- ghost-demand cache lifetime, 5 s
local PROFILE_FILE = "etech-profile.csv" -- /etech-hub-profile output (script-output/)
local MAX_DEPTH = 5        -- nested-factory recursion limit
local FILTER_SLOTS = 10
local RATE_WINDOW = 3600   -- ticks of pull history for the items/min stat
local MAX_SIGNALS = 1000   -- constant combinator / logistic section limit
local MAX_FACTORY_ROWS = 20

local KINDS = {
    [OUTLET_NAME] = "outlet",
    [INLET_NAME] = "inlet",
    [SENSOR_NAME] = "sensor",
}

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

-- has_layout is a remote call per candidate entity; memoize per prototype
-- name for the session (not in storage — cheap to rebuild).
local layout_name_cache = {}
local function is_factory_building(name)
    local cached = layout_name_cache[name]
    if cached == nil then
        cached = remote.call("factorissimo", "has_layout", name)
        layout_name_cache[name] = cached
    end
    return cached
end

local function factory_label(id)
    local name = hub_data().factory_names[id]
    if name and name ~= "" then return name end
    return "Factory " .. id
end

local function register_device(entity)
    hub_data().hubs[entity.unit_number] = {
        entity = entity,
        kind = KINDS[entity.name],
        filters = { mode = 1, items = {} },
        pins = {},
        on_demand = KINDS[entity.name] == "outlet", -- lean default; buffer mode is the opt-in
    }
    script.register_on_object_destroyed(entity)
end

local function on_built(event)
    local entity = event.entity or event.destination
    if entity and entity.valid and KINDS[entity.name] then
        register_device(entity)
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
            local factory = remote.call("factorissimo", "get_factory_by_entity", building)
            if factory_usable(factory) and not visited[factory.id] then
                visited[factory.id] = true
                out[#out + 1] = factory
                if settings.global["etech-hub-nested"].value then
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
end

-- Top-level factory buildings the device can see. On a normal surface: every
-- factory on the surface (optionally range-limited). On a Factorissimo
-- interior surface (device placed inside a factory): only factories within
-- the surrounding factory's own interior cell — interior surfaces are shared
-- 8-wide grids of unrelated factories and the device must not reach across
-- cells.
local function factories_for_hub(hub)
    local surface = hub.surface
    local candidates
    if remote.call("factorissimo", "is_factorissimo_surface", surface.index) then
        local parent = remote.call("factorissimo",
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
        local range = settings.global["etech-hub-range"].value
        if range > 0 then
            local px, py = hub.position.x, hub.position.y
            local near = {}
            for _, building in pairs(candidates) do
                local dx, dy = building.position.x - px, building.position.y - py
                if dx * dx + dy * dy <= range * range then
                    near[#near + 1] = building
                end
            end
            candidates = near
        end
    end
    local out, visited = {}, {}
    collect_factories(candidates, hub.force, out, visited, 1)
    return out
end

local function cached_factories(record)
    local tick = game.tick
    if not record.factories or tick - (record.scanned_tick or 0) >= RESCAN_TICKS then
        record.factories = factories_for_hub(record.entity)
        record.scanned_tick = tick
    end
    return record.factories
end

-- Interior logistic chests of one factory matching a mode predicate.
local function interior_chests(factory, force, accept_mode)
    local chests = {}
    local found = factory.inside_surface.find_entities_filtered {
        area = factory_interior_area(factory),
        type = "logistic-container",
        force = force,
    }
    for _, chest in pairs(found) do
        if chest.name ~= OUTLET_NAME and accept_mode(chest.prototype.logistic_mode) then
            chests[#chests + 1] = chest
        end
    end
    return chests
end

local function provider_mode(mode)
    if mode == "active-provider" then return true end
    return mode == "passive-provider" and not settings.global["etech-hub-active-only"].value
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
    for _, factory in pairs(cached_factories(record)) do
        if factory_usable(factory) then
            for _, chest in pairs(interior_chests(factory, record.entity.force, accept_mode)) do
                out[#out + 1] = { chest = chest, factory = factory }
            end
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

-- Circuit enable ---------------------------------------------------------------

-- When the checkbox is on, the outlet only works while any nonzero circuit
-- signal reaches it (red or green wire). No wire = paused.
local function circuit_enabled(record)
    if not record.circuit_enable then return true end
    local entity = record.entity
    for _, wire in pairs({defines.wire_connector_id.circuit_red,
                          defines.wire_connector_id.circuit_green}) do
        local net = entity.get_circuit_network(wire)
        if net then
            for _, s in pairs(net.signals or {}) do
                if s.count ~= 0 then return true end
            end
        end
    end
    return false
end

-- Energy cost ----------------------------------------------------------------

local function energy_per_item()
    return settings.global["etech-hub-energy-kj"].value * 1000 -- J
end

local function ensure_companion(record)
    local cost = energy_per_item()
    if cost <= 0 then
        if record.companion and record.companion.valid then record.companion.destroy() end
        record.companion = nil
        return nil
    end
    if not (record.companion and record.companion.valid) then
        local hub = record.entity
        local found = hub.surface.find_entities_filtered {
            name = ENERGY_NAME, position = hub.position, radius = 0.2,
        }
        record.companion = found[1] or hub.surface.create_entity {
            name = ENERGY_NAME, position = hub.position, force = hub.force,
        }
    end
    return record.companion
end

-- Items the device may still move this pass given stored energy; math.huge
-- when the cost setting is off.
local function energy_budget(record)
    local cost = energy_per_item()
    if cost <= 0 then return math.huge end
    local companion = ensure_companion(record)
    return math.floor(companion.energy / cost)
end

local function spend_energy(record, items_moved)
    local cost = energy_per_item()
    if cost > 0 and items_moved > 0 and record.companion and record.companion.valid then
        record.companion.energy = math.max(0, record.companion.energy - items_moved * cost)
    end
end

-- Pull rate stat ---------------------------------------------------------------

local function note_moved(record, moved)
    local tick = game.tick
    local samples = record.moved_samples or {}
    samples[#samples + 1] = { tick = tick, moved = moved }
    local pruned = {}
    for _, s in pairs(samples) do
        if tick - s.tick <= RATE_WINDOW then pruned[#pruned + 1] = s end
    end
    record.moved_samples = pruned
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
        counts[item.name .. "|" .. (item.quality or "normal")] = item.count
    end
    return counts
end

-- Outlet: buffer mode ------------------------------------------------------------

-- Move items from one provider chest into the outlet, at most cap_stacks
-- stacks of each item+quality in the outlet at a time. Slot-by-slot via
-- LuaItemStack so spoilage, ammo, durability and quality all survive.
local function drain_chest(chest, hub_inv, counts, cap_stacks, record, set, state)
    local inv = chest.get_inventory(defines.inventory.chest)
    if not inv then return 0 end
    local moved = 0
    for i = 1, #inv do
        if state.budget <= 0 then break end
        local stack = inv[i]
        if stack.valid_for_read and item_allowed(record, stack.name, set) then
            local key = stack.name .. "|" .. stack.quality.name
            local room = cap_stacks * stack.prototype.stack_size - (counts[key] or 0)
            room = math.min(room, state.budget)
            if room >= 1 then
                local original = stack.count
                local move = math.min(room, original)
                if move < original then stack.count = move end
                local inserted = hub_inv.insert(stack)
                stack.count = original - inserted
                counts[key] = (counts[key] or 0) + inserted
                moved = moved + inserted
                state.budget = state.budget - inserted
                if inserted < move and hub_inv.count_empty_stacks() == 0 then
                    state.full = true
                    break
                end
            end
        end
    end
    return moved
end

-- Anything in the outlet above the per-item cap (player-inserted items, or
-- the cap setting was lowered) goes back into the factories — the outlet
-- only ever holds what it's willing to provide. Requester-trash equivalent.
local function return_overflow(hub_inv, chests, counts, cap_stacks)
    local over = {}
    for _, item in pairs(hub_inv.get_contents()) do
        local quality = item.quality or "normal"
        local cap = cap_stacks * prototypes.item[item.name].stack_size
        if item.count > cap then
            over[#over + 1] = {name = item.name, quality = quality, excess = item.count - cap}
        end
    end
    for _, o in pairs(over) do
        local inserted = insert_spec_into_chests(chests, o.name, o.quality, o.excess)
        if inserted > 0 then
            hub_inv.remove({name = o.name, count = inserted, quality = o.quality})
            local key = o.name .. "|" .. o.quality
            counts[key] = (counts[key] or 0) - inserted
        end
    end
end

local function cap_stacks_for(record)
    local override = record.cap_override
    if override and override >= 1 then return override end
    return settings.global["etech-hub-stacks-per-item"].value
end

-- Outlet: on-demand mode ---------------------------------------------------------

-- Construction-ghost demand. Ghosts aren't logistic requests, so the engine
-- never surfaces them through requester_points — an on-demand outlet would
-- sit empty while construction bots starve. We derive the demand ourselves:
--   1. per surface+force, every GHOST_TICKS: one find_entities_filtered for
--      entity/tile ghosts (+ item-request-proxies for module requests) and
--      flatten each into {x, y, item|quality, count}. Cached in storage —
--      a session-local cache here would desync multiplayer joiners.
--   2. per outlet, once per scan generation: keep only ghosts inside this
--      network's construction range (pure math against the cells'
--      construction squares — no per-ghost API calls) and aggregate into
--      wants. Reused by every 2 s pull pass until the next scan.

-- Item that places a ghost prototype; memoized per name (pure prototype
-- data, so a local cache is deterministic — same trick as layout_name_cache).
local place_item_cache = {}
local function ghost_place_item(ghost)
    local key = ghost.type .. "|" .. ghost.ghost_name
    local cached = place_item_cache[key]
    if cached == nil then
        local spec = ghost.ghost_prototype.items_to_place_this
        spec = spec and spec[1] -- what bots actually deliver
        cached = spec and { name = spec.name, count = spec.count or 1 } or false
        place_item_cache[key] = cached
    end
    return cached or nil
end

-- Total items in a BlueprintInsertPlan list (module requests on ghosts and
-- on already-built machines via item-request-proxy).
local function add_insert_plans(list, plans, x, y)
    for _, plan in pairs(plans or {}) do
        local items = plan.items
        local count = items.grid_count or 0
        for _, pos in pairs(items.in_inventory or {}) do
            count = count + (pos.count or 1)
        end
        if count > 0 then
            local quality = plan.id.quality
            if type(quality) ~= "string" then
                quality = quality and quality.name or "normal"
            end
            list[#list + 1] = {
                x = x, y = y,
                key = plan.id.name .. "|" .. quality,
                count = count,
            }
        end
    end
end

local function scan_surface_ghosts(surface, force)
    local list = {}
    for _, ghost in pairs(surface.find_entities_filtered {
        type = {"entity-ghost", "tile-ghost"}, force = force,
    }) do
        local pos = ghost.position
        local item = ghost_place_item(ghost)
        if item then
            list[#list + 1] = {
                x = pos.x, y = pos.y,
                key = item.name .. "|" .. ghost.quality.name,
                count = item.count,
            }
        end
        if ghost.type == "entity-ghost" then
            add_insert_plans(list, ghost.insert_plan, pos.x, pos.y)
        end
    end
    for _, proxy in pairs(surface.find_entities_filtered {
        type = "item-request-proxy", force = force,
    }) do
        add_insert_plans(list, proxy.insert_plan, proxy.position.x, proxy.position.y)
    end
    return list
end

-- Cached ghost list for a surface+force; entries untouched for two
-- lifetimes (surface deleted, outlets gone) are pruned by on_pull_tick.
local function surface_ghosts(surface, force)
    local data = hub_data()
    data.ghosts = data.ghosts or {}
    local key = surface.index .. "|" .. force.index
    local entry = data.ghosts[key]
    if not entry or game.tick - entry.tick >= GHOST_TICKS then
        local prof = data.profiling and game.create_profiler()
        entry = { tick = game.tick, list = scan_surface_ghosts(surface, force) }
        data.ghosts[key] = entry
        if prof then
            prof.stop()
            helpers.write_file(PROFILE_FILE,
                {"", game.tick, ",ghost-scan(", surface.name, " ghosts=", #entry.list, "),", prof, "\n"}, true)
        end
    end
    return entry
end

-- Ghost demand visible to this outlet's network, per item|quality.
-- Membership = inside any cell's construction square (construction areas
-- are square). Memoized per scan generation on the record.
local function ghost_wants(record, network)
    local hub = record.entity
    local entry = surface_ghosts(hub.surface, hub.force)
    if record.ghost_tick == entry.tick and record.ghost_wants then
        return record.ghost_wants
    end
    local wants = {}
    if #entry.list > 0 then
        local cells = {}
        for _, cell in pairs(network.cells) do
            local r = cell.construction_radius
            if r and r > 0 and cell.owner and cell.owner.valid then
                local p = cell.owner.position
                cells[#cells + 1] = { x = p.x, y = p.y, r = r }
            end
        end
        if #cells > 0 then
            for _, g in pairs(entry.list) do
                for _, c in pairs(cells) do
                    if math.abs(g.x - c.x) <= c.r and math.abs(g.y - c.y) <= c.r then
                        wants[g.key] = (wants[g.key] or 0) + g.count
                        break
                    end
                end
            end
        end
    end
    record.ghost_wants = wants
    record.ghost_tick = entry.tick
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
                                local key = v.name .. "|" .. quality
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
local function pull_on_demand(record, hub_inv, chests, set, state)
    local wants, network = network_wants(record.entity, record)
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
        if state.budget <= 0 or next(need) == nil then break end
        local chest = entry.chest
        if chest.valid then
            local inv = chest.get_inventory(defines.inventory.chest)
            if inv then
                for i = 1, #inv do
                    if state.budget <= 0 then break end
                    local stack = inv[i]
                    if stack.valid_for_read and item_allowed(record, stack.name, set) then
                        local key = stack.name .. "|" .. stack.quality.name
                        local missing = need[key]
                        if missing and missing >= 1 then
                            local original = stack.count
                            local move = math.min(missing, original, state.budget)
                            if move < original then stack.count = move end
                            local inserted = hub_inv.insert(stack)
                            stack.count = original - inserted
                            moved = moved + inserted
                            state.budget = state.budget - inserted
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

    local chests = reachable_chests(record, outlet_source_mode(record))
    if #chests == 0 then
        note_moved(record, 0)
        return
    end

    local set = filter_set(record)
    local state = { budget = energy_budget(record), full = false }
    local moved

    if record.on_demand then
        moved = pull_on_demand(record, hub_inv, chests, set, state)
    else
        local counts = inventory_counts(hub_inv)
        local cap_stacks = cap_stacks_for(record)
        return_overflow(hub_inv, chests, counts, cap_stacks)
        moved = 0
        for _, entry in pairs(chests) do
            if entry.chest.valid then
                moved = moved + drain_chest(entry.chest, hub_inv, counts, cap_stacks, record, set, state)
                if state.full or state.budget <= 0 then break end
            end
        end
    end
    spend_energy(record, moved)
    note_moved(record, moved)
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
                    local key = value.name .. "|" .. (value.quality or "normal")
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
    local budget = energy_budget(record)
    local moved = 0
    local remaining = {} -- interior deficits left after this pass, for auto-request

    for _, entry in pairs(targets) do
        local chest = entry.chest
        if chest.valid then
            local wants = chest_requests(chest)
            if wants and next(wants) then
                local inv = chest.get_inventory(defines.inventory.chest)
                local current = inventory_counts(inv)
                for key, want in pairs(wants) do
                    local deficit = want - (current[key] or 0)
                    if deficit > 0 then
                        local available = have[key] or 0
                        local move = math.min(available, deficit, budget)
                        if move >= 1 then
                            local name, quality = split_key(key)
                            -- spec-based transfer: spoil timers restart
                            local inserted = inv.insert({name = name, count = move, quality = quality})
                            if inserted > 0 then
                                inlet_inv.remove({name = name, count = inserted, quality = quality})
                                have[key] = available - inserted
                                moved = moved + inserted
                                budget = budget - inserted
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
        if budget <= 0 then
            -- still collect the rest of the deficits for auto-request
            budget = 0
        end
    end

    update_inlet_auto_requests(record, remaining)
    spend_energy(record, moved)
    note_moved(record, moved)
end

-- Sensor: broadcast interior provider totals as signals ------------------------

local function update_sensor(record)
    local totals = {}
    for _, entry in pairs(reachable_chests(record, provider_mode)) do
        local inv = entry.chest.get_inventory(defines.inventory.chest)
        if inv then
            for _, item in pairs(inv.get_contents()) do
                local key = item.name .. "|" .. (item.quality or "normal")
                totals[key] = (totals[key] or 0) + item.count
            end
        end
    end

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
        player.print(name .. " — " .. factory_label(id) .. ": " .. info.count ..
            " " .. gps_tag(info.factory))
    end
    if not found then
        player.print(name .. " — nothing in reachable factories right now")
    end
end

-- Shift-click: teleport up to one stack of the item straight from the
-- factories into the player's inventory (slot-level transfer, spoil/quality
-- preserved).
local function take_item(player, record, name, quality)
    local player_inv = player.get_main_inventory()
    if not player_inv then return end
    local wanted = prototypes.item[name].stack_size
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
        player.print("Took " .. taken .. " " .. name .. " from the factories")
    else
        player.print("Couldn't take " .. name .. " (nothing found or inventory full)")
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
    scroll.style.maximal_height = 320

    inner.add {type = "line", name = "sep"}
    inner.add {type = "label", name = "settings_label",
        caption = {"gui-etech-hub.pull-settings"}}
    local checks = inner.add {type = "flow", name = "checks", direction = "vertical"}
    checks.add {type = "checkbox", name = "etech-hub-ondemand", state = false,
        caption = {"gui-etech-hub.on-demand"}, tooltip = {"gui-etech-hub.on-demand-tooltip"}}
    checks.add {type = "checkbox", name = "etech-hub-circuit", state = false,
        caption = {"gui-etech-hub.circuit"}, tooltip = {"gui-etech-hub.circuit-tooltip"}}
    checks.add {type = "checkbox", name = "etech-hub-storage", state = false,
        caption = {"gui-etech-hub.storage"}, tooltip = {"gui-etech-hub.storage-tooltip"}}
    inner.add {type = "drop-down", name = "etech-hub-mode", items = MODE_ITEMS}
    local slots = inner.add {type = "table", name = "filter_slots", column_count = 5}
    for i = 1, FILTER_SLOTS do
        slots.add {type = "choose-elem-button", name = "etech-hub-filter-" .. i,
            elem_type = "item"}
    end
    local numbers = inner.add {type = "flow", name = "numbers", direction = "horizontal"}
    numbers.add {type = "label", name = "cap_label", caption = {"gui-etech-hub.cap-label"},
        tooltip = {"gui-etech-hub.cap-tooltip"}}
    local cap = numbers.add {type = "textfield", name = "etech-hub-cap",
        numeric = true, allow_decimal = false, allow_negative = false}
    cap.style.width = 50
    numbers.add {type = "label", name = "prio_label", caption = {"gui-etech-hub.prio-label"},
        tooltip = {"gui-etech-hub.prio-tooltip"}}
    local prio = numbers.add {type = "textfield", name = "etech-hub-priority",
        numeric = true, allow_decimal = false, allow_negative = false}
    prio.style.width = 50

    inner.add {type = "label", name = "factories_label",
        caption = {"gui-etech-hub.factories"}}
    local fscroll = inner.add {type = "scroll-pane", name = "fscroll"}
    fscroll.style.maximal_height = 150
    fscroll.add {type = "table", name = "frows", column_count = 2}
    return panel
end

local function load_panel_settings(player, record)
    local panel = build_panel(player)
    local inner = panel.inner
    inner.checks["etech-hub-ondemand"].state = record.on_demand == true
    inner.checks["etech-hub-circuit"].state = record.circuit_enable == true
    inner.checks["etech-hub-storage"].state = record.pull_storage == true
    inner["etech-hub-mode"].selected_index = record.filters.mode or 1
    for i = 1, FILTER_SLOTS do
        inner.filter_slots["etech-hub-filter-" .. i].elem_value = record.filters.items[i]
    end
    inner.numbers["etech-hub-cap"].text =
        record.cap_override and tostring(record.cap_override) or ""
    inner.numbers["etech-hub-priority"].text =
        record.priority and tostring(record.priority) or ""

    -- factory rows: locate button + rename field (rebuilt on open only, so
    -- typing a name never gets clobbered by the 2 s refresh)
    local rows = inner.fscroll.frows
    rows.clear()
    local shown = 0
    for _, factory in pairs(cached_factories(record)) do
        if factory_usable(factory) then
            shown = shown + 1
            if shown > MAX_FACTORY_ROWS then break end
            local btn = rows.add {type = "button", caption = {"gui-etech-hub.locate"}}
            btn.style.minimal_width = 50
            btn.tags = { etech = "factory-locate", id = factory.id }
            local field = rows.add {type = "textfield",
                text = hub_data().factory_names[factory.id] or ""}
            field.tags = { etech = "factory-name", id = factory.id }
            field.style.horizontally_stretchable = true
        end
    end
    if shown > MAX_FACTORY_ROWS then
        rows.add {type = "label", caption = "..."}
        rows.add {type = "label", caption = ""}
    end
end

local function refresh_grid(player, record)
    local panel = player.gui.relative[PANEL_NAME]
    if not panel then return end
    local inner = panel.inner
    inner.rate.caption = {"gui-etech-hub.rate", rate_per_minute(record)}

    local search = inner["etech-hub-search"].text:lower()
    local scroll = inner.scroll
    scroll.clear()

    -- totals per item+quality with per-factory breakdown
    local totals, order = {}, {}
    for _, entry in pairs(reachable_chests(record, outlet_source_mode(record))) do
        local inv = entry.chest.get_inventory(defines.inventory.chest)
        if inv then
            for _, item in pairs(inv.get_contents()) do
                local quality = item.quality or "normal"
                local key = item.name .. "|" .. quality
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
            t.pinned = pins[t.name .. "|" .. t.quality] == true
            list[#list + 1] = t
        end
    end
    if #list == 0 then
        scroll.add {type = "label", caption = {"gui-etech-hub.panel-empty"}}
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
        local shown = 0
        for factory_id, n in pairs(t.per) do
            shown = shown + 1
            if shown > 8 then
                lines[#lines + 1] = "\n..."
                break
            end
            lines[#lines + 1] = "\n" .. factory_label(factory_id) .. ": " .. n
        end
        lines[#lines + 1] = {"gui-etech-hub.item-hint"}
        local btn = grid.add {
            type = "sprite-button",
            sprite = "item/" .. t.name,
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
end

local function refresh_inlet_panel(player, record)
    local panel = player.gui.relative[INLET_PANEL_NAME]
    if not panel then return end
    panel.inner.rate.caption = {"gui-etech-hub.inlet-rate", rate_per_minute(record)}
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
    if name == "etech-hub-ondemand" then
        record.on_demand = event.element.state
    elseif name == "etech-hub-circuit" then
        record.circuit_enable = event.element.state
    elseif name == "etech-hub-storage" then
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
    local name = element.name
    if name == "etech-hub-cap" then
        local n = tonumber(element.text)
        record.cap_override = (n and n >= 1) and math.floor(n) or nil
    elseif name == "etech-hub-priority" then
        local n = tonumber(element.text)
        record.priority = (n and n >= 1) and math.floor(n) or nil
    elseif name == "etech-hub-search" then
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
            local key = tags.name .. "|" .. tags.quality
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
                player.print(factory_label(factory.id) .. " " .. gps_tag(factory))
                return
            end
        end
    end
end

-- Tick dispatch ----------------------------------------------------------------

local function on_pull_tick()
    if not factorissimo_available() then return end
    local data = hub_data()
    local prof = data.profiling and game.create_profiler()

    -- outlets in priority order (1 = first), then inlets, then sensors
    local outlets, inlets, sensors = {}, {}, {}
    for unit_number, record in pairs(data.hubs) do
        if record.entity.valid then
            if record.kind == "outlet" then outlets[#outlets + 1] = record
            elseif record.kind == "inlet" then inlets[#inlets + 1] = record
            else sensors[#sensors + 1] = record end
        else
            if record.companion and record.companion.valid then
                record.companion.destroy()
            end
            data.hubs[unit_number] = nil
        end
    end
    table.sort(outlets, function(a, b)
        return (a.priority or 100) < (b.priority or 100)
    end)

    -- drop ghost caches nothing refreshed for two lifetimes (outlet gone,
    -- surface deleted) so storage doesn't accumulate dead surface entries
    if data.ghosts then
        local tick = game.tick
        for key, entry in pairs(data.ghosts) do
            if tick - entry.tick >= GHOST_TICKS * 2 then
                data.ghosts[key] = nil
            end
        end
    end

    for _, record in pairs(outlets) do pull_for_outlet(record) end
    for _, record in pairs(inlets) do distribute_for_inlet(record) end
    for _, record in pairs(sensors) do update_sensor(record) end

    -- live refresh for anyone looking at an outlet/inlet
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

    if prof then
        prof.stop()
        helpers.write_file(PROFILE_FILE,
            {"", game.tick, ",pull-pass(outlets=", #outlets, " inlets=", #inlets,
             " sensors=", #sensors, "),", prof, "\n"}, true)
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
            if record.kind == "outlet" then
                mode = record.on_demand and "outlet (on-demand)" or "outlet (buffer)"
                if record.circuit_enable and not circuit_enabled(record) then
                    mode = mode .. " PAUSED by circuit"
                end
            end
            player.print(string.format(
                "[factory-outlet] %s #%d at %s (%.0f, %.0f): %d factories, %d chests, %d items/min, energy budget %s",
                mode, entity.unit_number, entity.surface.name,
                entity.position.x, entity.position.y,
                #record.factories, #chests, rate_per_minute(record),
                energy_per_item() > 0 and tostring(energy_budget(record)) or "off"))
            if record.kind == "outlet" and record.on_demand then
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
            if record.kind == "outlet" and not record.on_demand then
                local hub_inv = entity.get_inventory(defines.inventory.chest)
                local counts = inventory_counts(hub_inv)
                local cap_stacks = cap_stacks_for(record)
                local set = filter_set(record)
                local reported, lines = {}, 0
                for _, entry in pairs(chests) do
                    local inv = entry.chest.valid and entry.chest.get_inventory(defines.inventory.chest)
                    if inv then
                        for _, item in pairs(inv.get_contents()) do
                            local quality = item.quality or "normal"
                            local key = item.name .. "|" .. quality
                            if not reported[key] and lines < 20 then
                                reported[key] = true
                                local reason
                                if not item_allowed(record, item.name, set) then
                                    reason = "SKIP filtered out"
                                else
                                    local cap = cap_stacks * prototypes.item[item.name].stack_size
                                    local held = counts[key] or 0
                                    if held >= cap then
                                        reason = "SKIP cap met (" .. held .. "/" .. cap .. ")"
                                    else
                                        reason = "pull ok (holding " .. held .. "/" .. cap .. ")"
                                    end
                                end
                                lines = lines + 1
                                player.print("  " .. item.name ..
                                    (quality ~= "normal" and ("(" .. quality .. ")") or "") ..
                                    " x" .. item.count .. " -> " .. reason)
                            end
                        end
                    end
                end
                if lines >= 20 then player.print("  ... (list capped at 20 item types)") end
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
    local hubs = hub_data().hubs
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
    [defines.events.on_object_destroyed] = function(event)
        if event.useful_id then
            local hubs = hub_data().hubs
            local record = hubs[event.useful_id]
            if record then
                if record.companion and record.companion.valid then
                    record.companion.destroy()
                end
                hubs[event.useful_id] = nil
            end
        end
    end,
}

M.on_nth_tick = {
    [PULL_TICKS] = on_pull_tick,
}

return M
