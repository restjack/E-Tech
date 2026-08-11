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
local FLUID_SENSOR_NAME = "etech-factory-fluid-sensor"
local EXPORT_FILTER_NAME = "etech-factory-export-filter"
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
local FILTER_SLOTS = 24    -- choose-elem filter slots in the outlet/inlet/sensor
                           -- panels. Laid out FILTER_COLUMNS wide to match the
                           -- stock grid above it; 15 in a 5-wide block left the
                           -- panel visibly narrower than its own contents.
local FILTER_COLUMNS = 8
-- Stock grid width. The panel is sized by the Factories tab, which is wider
-- than 8 item slots, so a narrow grid wasted half the window and made the
-- list twice as long as it needed to be. 16 overshot the other way and put a
-- HORIZONTAL scrollbar on a grid that is meant to be read at a glance - only
-- 9 of the 16 were visible. 12 slots is 480px of the ~560 the Factories tab
-- asks for, so it fills the width without ever driving it wider.
local STOCK_COLUMNS = 12
local SLOT_PX = 40  -- one item slot, base pixels (UI scale is applied on top)
local COOLDOWN_TICKS = 600 -- loop guard: 10 s lockout after an item is handed
                           -- back, so a want that flickers on and off between
                           -- passes can't pull the same stack out repeatedly
local STORAGE_LOCK_TICKS = 3600 -- loop guard: 60 s lockout on re-pulling an
                           -- item out of an interior STORAGE chest the outlet
                           -- itself just returned it to. Longer than
                           -- COOLDOWN_TICKS on purpose - storage is where
                           -- leftovers are supposed to come to rest.
local RATE_WINDOW = 3600   -- ticks of pull history for the items/min stat
local REQUESTER_TTL = 240  -- PULL_TICKS * 2: how long an outlet reuses its
                           -- requester-demand scan. Declared up here rather
                           -- than next to its first user because ghost_wants
                           -- is defined earlier in the file and needs it too.
local CELL_TTL = 1080      -- PULL_TICKS * 9: how long an outlet reuses the
                           -- roboport geometry of its network. Deliberately
                           -- NOT the same constant as REQUESTER_TTL - sharing
                           -- one meant both caches were written in the same
                           -- pass and therefore always expired in the same
                           -- pass, stacking their cost (profiled 0.21.1:
                           -- net-wants max went 7.7 -> 14.9 ms doing that).
                           -- Roboports are also built far more rarely than
                           -- logistic requests change, so this can be long.
                           -- 1080 is deliberately NOT a whole multiple of
                           -- REQUESTER_TTL (4.5x): a multiple would put the
                           -- two misses back on the same pass every cycle,
                           -- which is the thing being fixed.
local GHOST_INDEX_MAX = 20000   -- per surface+force: ghosts tracked precisely
                           -- (one storage entry + one destroy registration
                           -- each) before the index degrades to coarse mode
local GHOST_RESYNC_TICKS = 3600 -- how often a coarse index is rebuilt from the
                           -- world to shed the drift coarse mode accumulates
local MAX_SIGNALS = 1000   -- constant combinator / logistic section limit
-- Every factory is listed; the scroll pane is what makes that usable. Capping
-- at 20 and printing "+146 more" hid 88% of Eli's factories behind a number,
-- in the one list whose whole job is finding a factory. Cost is one row of four
-- elements per factory, built only when the panel is opened.
local MAX_FACTORY_ROWS = math.huge
local FACTORY_OVERLAY_ICONS = 4 -- overlay signals shown per factory row
local TOOLTIP_FACTORIES = 8 -- per-factory breakdown lines in an item tooltip

local KINDS = {
    [OUTLET_NAME] = "outlet",
    [INLET_NAME] = "inlet",
    [SENSOR_NAME] = "sensor",
    [FLUID_OUTLET_NAME] = "fluid-outlet",
    [FLUID_INLET_NAME] = "fluid-inlet",
    [FLUID_SENSOR_NAME] = "fluid-sensor",
    [EXPORT_FILTER_NAME] = "export-filter",
}

-- item|quality key convention used across caches, wants tables and GUI tags
local function item_key(name, quality)
    return name .. "|" .. (quality or "normal")
end

-- Per-device opt-in options: the four loop guards, the fluid outlet's guard,
-- the sensor's two broadcast options and circuit-set filters all live in one
-- table on the record. Every one of them is off by default, so an absent table
-- is the correct state for a device from before any of them existed and nothing
-- has to be migrated.
--
-- The loop guards are the reason this exists. An inlet with auto-request on is
-- a REQUESTER in the same logistic network the outlet provides to: the inlet
-- asks for whatever the factories' interior requester chests are short of, the
-- outlet reads that as network demand and pulls those same items back out of
-- those same factories, bots fly them to the inlet, the inlet pushes them
-- inside. Nothing is satisfied that wasn't already satisfiable and the items
-- ride in a circle for as long as both devices exist.
local function guards(record)
    local g = record.guards
    if not g then
        g = {}
        record.guards = g
    end
    return g
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
--
-- "Factory 7" is a label nobody remembers. Roboports, labs, locomotives, radars
-- and train stops all get a backer name from the engine when they are placed,
-- which is why a roboport is "Kaeya" rather than "Roboport 12" - but that is a
-- hard-coded list of five prototype TYPES (LuaEntity.backer_name), and a
-- Factorissimo factory building is a storage-tank. It cannot have one, and no
-- amount of prototype work changes that.
--
-- What IS available is the list the engine draws from: game.backer_names. So
-- the naming is done here instead, indexed by factory id rather than picked at
-- random - identical on every client, no storage, and stable across saves and
-- reloads. A player-typed name still wins, exactly like renaming a train stop.
local function backer_name_for(id)
    local names = game.backer_names
    local count = #names
    if count == 0 then return nil end
    return names[(id - 1) % count + 1]
end

local function factory_label(id)
    local name = hub_data().factory_names[id]
    if name and name ~= "" then return name end
    if settings.global["etech-hub-backer-names"].value then
        local backer = backer_name_for(id)
        if backer then return backer end
    end
    return {"gui-etech-hub.factory-n", id}
end

local function register_device(entity, copy_from)
    local data = hub_data()
    local record = {
        entity = entity,
        kind = KINDS[entity.name],
        filters = { mode = 1, items = {}, match_quality = false },
        guards = {},
        pins = {},
    }
    -- clone / blueprint: carry the source device's settings over
    if copy_from then
        if copy_from.filters then record.filters = table.deepcopy(copy_from.filters) end
        if copy_from.guards then record.guards = table.deepcopy(copy_from.guards) end
        if copy_from.pins then record.pins = table.deepcopy(copy_from.pins) end
        record.pull_storage = copy_from.pull_storage
        record.auto_request = copy_from.auto_request
        record.fluid_filter = copy_from.fluid_filter
        record.min_quality = copy_from.min_quality
    end
    -- Spread this device's pull across the four slot ticks of a PULL_TICKS
    -- cycle, deterministically from its unit_number. Two outlets built in the
    -- same second otherwise pull on the same tick forever, and their caches
    -- expire together too - see the scheduler in on_slot_tick.
    record.next_pull = game.tick + (entity.unit_number % 4) * SLOT_TICKS
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
-- (another_outlet_exists needs factory_interior_area, so it is defined
-- further down next to factory_usable and forward-declared below.)
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

-- Is this surface a Factorissimo interior? Only things built/mined INSIDE a
-- factory can change what a device sees, so this gates the cache-invalidation
-- bumps below. Before 0.21.1 every logistic container built anywhere on any
-- surface bumped chest_gen, which on a bot base pasting blueprints meant a
-- full interior re-scan for every device every maintenance pass - i.e. the
-- chest cache never paid off during exactly the construction it was meant to
-- survive.
--
-- Fails SAFE: factorissimo_call returns nil when the remote call errors, and
-- nil counts as "interior" so we invalidate rather than serve a stale cache.
local function surface_is_interior(surface)
    return factorissimo_call("is_factorissimo_surface", surface.index) ~= false
end

-- forward declarations: defined with the ghost index (on-demand section),
-- the factory-cache section, and next to factory_usable respectively
local gindex_on_ghost_built
local cached_factories
local another_outlet_exists

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
    elseif etype == "storage-tank" and is_factory_building(entity.name) then
        -- a Factorissimo building: invalidate every factory-list cache.
        -- Name-checked since 0.21.1 - every plain storage tank the player
        -- placed anywhere used to force a ~40 ms factory rescan.
        local data = hub_data()
        data.factory_gen = (data.factory_gen or 0) + 1
    elseif etype == "logistic-container" and surface_is_interior(entity.surface) then
        -- an interior chest: invalidate every device's chest cache
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

-- Is there already an outlet this one would duplicate? (assigns the forward
-- declaration above on_built)
--
-- "One per surface" means one per SURFACE outside, but one per interior CELL
-- inside a factory. Factorissimo interior surfaces are shared 8-wide grids of
-- unrelated factories, and factories_for_hub already scopes a device's reach
-- to its own cell - so before 0.21.1 the whole-surface search refused a second
-- outlet that could never have seen the first one's chests. Two players (or
-- two factories) whose interiors landed on the same grid meant only one of
-- them could ever have an outlet.
function another_outlet_exists(entity)
    local surface = entity.surface
    local filter = { name = OUTLET_NAME, force = entity.force }
    if factorissimo_call("is_factorissimo_surface", surface.index) then
        local parent = factorissimo_call(
            "find_surrounding_factory_by_surface_index", surface.index, entity.position)
        -- No surrounding factory: the device is on interior ground that
        -- belongs to no cell, so it reaches nothing and duplicates nothing.
        if not factory_usable(parent) then return false end
        filter.area = factory_interior_area(parent)
    end
    for _, found in pairs(surface.find_entities_filtered(filter)) do
        if found.unit_number ~= entity.unit_number then return true end
    end
    return false
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

-- may_rebuild = false: use whatever list we have, however stale, rather than
-- rebuilding here. The hot paths pass false and let maintenance_pass do the
-- rebuilding at a paced rate.
--
-- WHY (measured 0.21.1): a factory_gen bump invalidates EVERY device at once.
-- With every caller rebuilding on demand, one Factorissimo building placed or
-- mined meant every device ran a whole-surface factory scan plus a full
-- interior-chest rebuild in the same tick - profiled at 66-76 ms per
-- maintenance pass, once every 2 s, for as long as the player kept building.
-- Budgeting maintenance alone does not fix that; it just relocates the spike
-- into the pull pass, because that is the next thing to ask for the list. The
-- staleness is safe: reachable_chests re-checks chest.valid and
-- factory_usable on every single use, so a stale list can only ever contain
-- entries that get filtered, never wrong ones.
--
-- A device with NO list at all always builds one - there is nothing to be
-- stale with, and refusing would make a freshly placed device do nothing.
function cached_factories(record, may_rebuild) -- assigns the forward declaration
    local tick = game.tick
    local gen = hub_data().factory_gen or 0
    local stale = record.factory_gen ~= gen
        or tick - (record.scanned_tick or 0) >= RESCAN_TICKS
    if not record.factories or (stale and may_rebuild ~= false) then
        record.factories = factories_for_hub(record.entity)
        record.scanned_tick = tick
        record.factory_gen = gen
    end
    return record.factories
end

-- Would ensure_chest_cache rebuild right now? Asked by maintenance_pass so it
-- can spend its budget on the devices that actually need it.
local function chest_cache_stale(record)
    local cache = record.chest_cache
    if not cache then return true end
    return cache.gen ~= (hub_data().chest_gen or 0)
        or cache.scanned_tick ~= record.scanned_tick
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
local function ensure_chest_cache(record, may_rebuild)
    local data = hub_data()
    local gen = data.chest_gen or 0
    local cache = record.chest_cache
    -- may_rebuild = false: serve whatever we have. Same reasoning as
    -- cached_factories - every entry is re-validated on use, so a stale cache
    -- can only under-report, never mislead. Only maintenance_pass rebuilds,
    -- and it paces itself.
    if cache and (may_rebuild == false
        or (cache.gen == gen and cache.scanned_tick == record.scanned_tick)) then
        return cache
    end
    local entries = {}
    local force = record.entity.force
    for _, factory in pairs(cached_factories(record, may_rebuild)) do
        if factory_usable(factory) then
            -- The interior ends of the factory's own chest connections. A
            -- Factorissimo chest connection is not a special entity - it is an
            -- ordinary chest you place inside on a port, paired with one
            -- outside - so nothing about the chest itself says "Factorissimo is
            -- already moving things through me". factory.connections does.
            --
            -- This matters because the pairing that reads most naturally is a
            -- REQUESTER outside feeding a PASSIVE PROVIDER inside: that is how
            -- you get ore from your miners into a factory. Factorissimo sees
            -- requester-outside as an input and runs the connection inwards.
            -- The outlet, looking only at logistic modes, sees a passive
            -- provider full of ore and does its job - pulls it straight back
            -- out, where the requester asks for it again. The ore never reaches
            -- the machines and both mods are behaving exactly as designed.
            -- Deliberately a FRESH remote lookup rather than factory.connections
            -- off the cached table. Factory tables come across remote.call as
            -- snapshots, and this device's copy can be up to RESCAN_TICKS old -
            -- so a connection built since the last factory scan is simply
            -- absent from it, the chest looks like an ordinary provider, and the
            -- outlet drains it. Measured exactly that: 100 iron in a connection
            -- chest went to 8. Only runs while the chest cache is being rebuilt,
            -- which is already budgeted.
            local fresh = factorissimo_call("get_factory_by_entity", factory.building)
            local connected = {}
            for _, conn in pairs((fresh and fresh.connections) or factory.connections or {}) do
                local inside = conn.inside
                if inside and inside.valid and inside.unit_number then
                    connected[inside.unit_number] = true
                end
            end
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
                        connected = connected[chest.unit_number] or nil,
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

-- Chests eligible as give-back destinations: providers (the usual origin of
-- pulled items) plus storage chests, always — storage is the semantically
-- right home for leftovers even when the pull-from-storage toggle is off.
local function return_mode(mode)
    return provider_mode(mode) or mode == "storage"
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
    -- never rebuilds: the pull pass, the sensor and the GUI all read through
    -- here, and none of them should be the one paying for a cache miss
    for _, entry in ipairs(ensure_chest_cache(record, false).entries) do
        if entry.chest.valid and factory_usable(entry.factory)
            and accept_mode(entry.mode) then
            out[#out + 1] = { chest = entry.chest, factory = entry.factory,
                mode = entry.mode, connected = entry.connected }
        end
    end
    return out
end

-- Per-hub item filter --------------------------------------------------------

-- Filter slots hold item-with-quality picks since 0.23.0. Saves and blueprint
-- tags written before that hold a plain item-name string in the same place, so
-- both shapes are read here and nothing needs migrating: a name-only slot has
-- no quality and therefore matches every quality, which is exactly what it did
-- before the quality checkbox existed.
local function filter_entry(value)
    if type(value) == "string" then return value, nil end
    if type(value) == "table" and value.name then return value.name, value.quality end
    return nil, nil
end

-- elem_value for a filter button, whatever shape the slot was stored in.
-- A pre-0.23.0 slot has no quality at all, and the button has nowhere to show
-- that: it renders the normal-quality badge either way. So the value shown is a
-- lie the moment "Match quality" is ticked - the slot LOOKS like "normal only"
-- and still behaves as "every quality". filter_slot_tooltip below is what makes
-- the difference visible; re-picking the slot resolves it.
local function filter_elem_value(value)
    local name, quality = filter_entry(value)
    if not name then return nil end
    return { name = name, quality = quality or "normal" }
end

local function filter_slot_tooltip(value)
    if type(value) == "string" then return {"gui-etech-hub.legacy-slot"} end
    return nil
end

local function add_to_set(set, name, quality)
    set.names[name] = true
    if quality then
        set.keys[item_key(name, quality)] = true
    else
        set.any[name] = true
    end
end

-- "Set filters from circuit network": the connected red/green signals ARE the
-- filter slots. Every item signal with a positive count is one slot; the mode
-- dropdown still decides whether that list is a whitelist or a blacklist. This
-- is the vanilla-2.0 requester-chest idiom, and it is the only way to change
-- what an outlet pulls without a player standing in front of it.
--
-- No item signals reaching it is an EMPTY filter list, not "no filter" — under
-- whitelist that means the outlet pulls nothing, which is the same thing the
-- circuit gate already does when every signal is zero. The two agree.
local function circuit_filter_set(record)
    local entity = record.entity
    local set, seen = { names = {}, any = {}, keys = {} }, false
    for _, wire in pairs({defines.wire_connector_id.circuit_red,
                          defines.wire_connector_id.circuit_green}) do
        local net = entity.get_circuit_network(wire)
        for _, s in pairs(net and net.signals or {}) do
            local signal = s.signal
            if s.count > 0 and signal and signal.name
                and (signal.type == nil or signal.type == "item") then
                seen = true
                -- a signal's quality is only binding when the device is
                -- matching quality; otherwise it covers every quality, exactly
                -- like a quality-less filter slot
                add_to_set(set, signal.name,
                    record.filters.match_quality and signal.quality or nil)
            end
        end
    end
    return seen and set or nil
end

-- Generalised over a plain {mode, items, match_quality} table so the same
-- machinery drives the device's own filter and the per-factory ones below.
local function filter_set_of(filters)
    local set = nil
    for _, value in pairs(filters.items or {}) do
        local name, quality = filter_entry(value)
        if name then
            set = set or { names = {}, any = {}, keys = {} }
            add_to_set(set, name, quality)
        end
    end
    return set
end

local function filter_set(record)
    if guards(record).circuit_filters then return circuit_filter_set(record) end
    return filter_set_of(record.filters)
end

-- With "Match quality" off (the default, and how filters behaved before
-- 0.23.0) a slot matches its item at every quality. With it on, a slot matches
-- only the quality it was picked at — except a name-only slot, which has no
-- quality to match and keeps covering all of them.
local function filters_match(filters, name, quality, set)
    if not set then return false end
    if not filters.match_quality then return set.names[name] == true end
    return set.any[name] == true or set.keys[item_key(name, quality)] == true
end

-- Minimum quality to export.
--
-- Quality upcycling puts a recycler loop inside a factory: normal ore or plates
-- go in, the same item comes back out one tier better, round and round until it
-- is legendary. Every tier below the top is FEEDSTOCK - it has to stay inside -
-- and the top tier is the product, which has to leave. The item filters cannot
-- say that without a slot per item per tier, and they still would not follow you
-- when you decide to push one tier further.
--
-- Quality levels come from the prototype (normal 0, uncommon 1, ...), so this
-- works with modded tiers and with no quality mod at all. Session-local cache:
-- derived from prototypes, never from storage, so it is not a desync risk.
local quality_levels = {}
local function quality_level(name)
    local level = quality_levels[name]
    if level == nil then
        local proto = prototypes.quality[name]
        level = proto and proto.level or 0
        quality_levels[name] = level
    end
    return level
end

local function quality_allowed(record, quality)
    local minimum = record.min_quality
    if not minimum then return true end
    return quality_level(quality) >= quality_level(minimum)
end

local function filters_allow(filters, name, quality, set)
    local mode = filters.mode
    if mode == 2 then return filters_match(filters, name, quality, set) end
    if mode == 3 then return not filters_match(filters, name, quality, set) end
    return true
end

local function item_allowed(record, name, quality, set)
    return filters_allow(record.filters, name, quality, set)
end

-- Per-FACTORY export filters. The device filter answers "what may this outlet
-- pull"; this answers "what may leave THIS factory", which is a different
-- question and belongs to the factory rather than to whichever device happens to
-- be reading it. A factory running a recycler upcycling loop wants its feedstock
-- to stay put while everything else it makes still exports, and no device-wide
-- filter says that without also blocking the same item coming out of every other
-- factory on the surface.
--
-- Kept in hub_data keyed by factory id, not on the device, for the same reason:
-- rebuild or replace the outlet and the factory's own rule survives.
-- The rule is carried by a Factory export filter built INSIDE the factory, not
-- by a list on the outlet. It belongs to the factory: replace the outlet, or
-- have two of them, and the factory's own rule should not move or vanish.
--
-- The device is a constant combinator and its OWN signal list is the item list.
-- That hands the whole item-picking problem to the game - logistic groups,
-- quality on each entry, copy-paste between combinators, blueprints - and
-- leaves E-Tech to add only the two things the vanilla window has nowhere for:
-- whitelist vs blacklist, and whether quality is binding.
local function combinator_filter_set(entity, match_quality)
    local behavior = entity.get_or_create_control_behavior()
    local set, seen = { names = {}, any = {}, keys = {} }, false
    for _, section in pairs(behavior and behavior.sections or {}) do
        if section.active then
            for _, filter in pairs(section.filters) do
                local value = filter.value
                if value and value.name
                    and (value.type == nil or value.type == "item") then
                    seen = true
                    add_to_set(set, value.name, match_quality and value.quality or nil)
                end
            end
        end
    end
    return seen and set or nil
end

-- The icons Factorissimo paints on the OUTSIDE of the factory come from the
-- overlay controller's ACTIVE sections. Reading the same list lets the outlet's
-- factory list show each factory the way it looks on the map. The export rule's
-- own section is inactive, so it never shows up here - which is the same
-- property that keeps it off the building.
local function factory_overlay_signals(factory, limit)
    local controller = factory.inside_overlay_controller
    if not (controller and controller.valid) then return {} end
    local behavior = controller.get_or_create_control_behavior()
    local out = {}
    for _, section in pairs(behavior and behavior.sections or {}) do
        if section.active then
            for _, filter in pairs(section.filters) do
                local value = filter.value
                if value and value.name then
                    out[#out + 1] = { type = value.type or "item", name = value.name }
                    if #out >= limit then return out end
                end
            end
        end
    end
    return out
end

-- The export rule lives on a device of E-Tech's own, built into every factory.
--
-- It rode on Factorissimo's overlay controller in 0.30.x, which removed the
-- placement question and introduced two of its own: the controller only exists
-- once the interior display upgrade is researched, and anything in an ACTIVE
-- section of it gets painted on the outside of the building. Our own entity has
-- neither problem - nothing else reads its sections, so there is nothing to
-- leak, and it exists in every factory regardless of research.
--
-- Placement is solved rather than avoided: no collision box and one fixed tile
-- beside the power pole, so it can never be blocked, never block, and never sit
-- in a doorway. Searching for a free tile was what put it in odd places.
--
-- Its own signal list is the item list, so item picking stays the game's job -
-- logistic groups, quality per entry, copy-paste between combinators.
-- One fixed tile, just inside the room by the door.
--
-- MEASURED, not assumed. Factorissimo's layouts put inside_energy - the power
-- pole and roboport - OUTSIDE the floor: factory-1 has inside_size 30, so the
-- floor ends at 15, and the pole sits at y = 17, out in the door band past the
-- wall. Anchoring on the pole and stepping one tile further out (which is what
-- 0.29.1 and 0.31.0 did) put this device off the floor in the dark beside the
-- door, where it is invisible - though still findable by a whole-surface search,
-- which is why the headless test kept passing.
--
-- So it is anchored on the interior bounds instead: two tiles in from the wall
-- the door is on, three tiles to the side of the door opening. Inside the room
-- at every tier including a Mk4, never in the doorway, and always the same
-- place. With no collision box it cannot be blocked or block anything.
-- Placement, chosen in game 2026-08-10: alongside Factorissimo's own interior
-- fittings rather than out on the floor, where it competed with belts and
-- machines for space and got built over.
--
-- Measured from the DOOR-SIDE wall, not in screen directions. door_y is
-- positive in every tier (+16/+24/+31/+61), so the wall is BELOW the device
-- and a LARGER inset moves it UP; a NEGATIVE inset moves it down, past the
-- wall into the strip Factorissimo keeps its pole and overlay controller in.
-- Every tier puts those at the same offsets from the interior centre:
--     pole                 x = -4,   y = half + 2   (2x2, substation sprite)
--     overlay controller   x = -3.5, y = half + 3.5
-- -3.5 lands this on the overlay controller's row, in the tile to its left,
-- and clear of the pole's footprint - at -2 it sits UNDER the substation
-- graphic and cannot be seen at all.
local EXPORT_FILTER_INSET = -3.5 -- negative: out past the door wall, by the pole
local EXPORT_FILTER_SIDE = 5     -- tiles to the side of the door opening

local function export_filter_position(factory)
    local half = (factory.layout and factory.layout.inside_size or 30) / 2
    local door_y = (factory.layout and factory.layout.inside_door_y) or half
    -- the door is on whichever side inside_door_y points at; come in from it
    local sign = door_y >= 0 and 1 or -1
    -- Snap to the TILE CENTRE. The engine puts a 1x1 entity at x.5/y.5 no
    -- matter what create_entity is handed, so an unsnapped target here can
    -- never equal the resulting position - and the sweep below compares the
    -- two to decide whether to teleport. Unsnapped, that comparison was
    -- always true, so the same filters were teleported every pass, ate the
    -- whole per-pass budget, and no factory past the first two was ever
    -- fitted (0.32.0; fixed 0.32.1).
    return {
        x = math.floor(factory.inside_x - EXPORT_FILTER_SIDE) + 0.5,
        y = math.floor(factory.inside_y + sign * (half - EXPORT_FILTER_INSET)) + 0.5,
    }
end

local function ensure_export_filter(factory)
    local inside = factory.inside_surface
    if not (inside and inside.valid) then return end
    local entity = inside.create_entity {
        name = EXPORT_FILTER_NAME,
        position = export_filter_position(factory),
        force = factory.building.force,
    }
    if not entity then return end
    -- Belongs to the factory: the player cannot mine, shoot or deconstruct it
    -- away and leave the factory unable to carry a rule.
    entity.destructible = false
    entity.rotatable = false
    register_device(entity)
    -- known here for free; saves the lookup above ever running for this one
    local record = hub_data().hubs[entity.unit_number]
    if record then record.factory_id = factory.id end
    return entity
end

-- factory id -> the unit number of its filter, resolved from the DEVICE side.
-- Asking Factorissimo which factory surrounds each of a handful of devices is
-- cheap and always current; looking for a device inside every factory rides on
-- the chest cache, which is deliberately allowed to be stale - fine for chests,
-- wrong for a rule, because a stale miss means a filter you just placed silently
-- does nothing.
local function export_filters_by_factory()
    local out = {}
    for unit, device in pairs(hub_data().hubs) do
        if device.kind == "export-filter" and device.entity and device.entity.valid then
            -- Resolved ONCE and remembered on the record. A filter cannot move
            -- between factories, so re-asking Factorissimo every pass is a
            -- remote call per filter per pass that always returns the same
            -- answer: on a base with 150 factories that is ~300 calls every two
            -- seconds, forever, for information that never changes.
            local id = device.factory_id
            if not id then
                local entity = device.entity
                local factory = factorissimo_call("find_surrounding_factory_by_surface_index",
                    entity.surface.index, entity.position)
                id = factory and factory.id
                device.factory_id = id
            end
            if id then out[id] = unit end
        end
    end
    return out
end

-- nil when the factory has no filter, or its mode is "no restriction", or its
-- list is empty - so the pull pass skips the work rather than evaluating a
-- permissive filter once per stack. `cache` memoises for one pass.
local function factory_filter_active(record, factory_id, cache)
    if cache.by_factory == nil then cache.by_factory = export_filters_by_factory() end
    local hit = cache[factory_id]
    if hit ~= nil then
        if hit == false then return nil end
        return hit.filters, hit.set
    end
    local device = hub_data().hubs[cache.by_factory[factory_id] or 0]
    if not (device and device.entity and device.entity.valid) then
        cache[factory_id] = false
        return nil
    end
    -- Mode 1 is "no restriction" and is the default: a factory does not acquire
    -- a rule just because it has a filter fitted.
    local mode = device.filters.mode or 1
    if mode == 1 then
        cache[factory_id] = false
        return nil
    end
    -- Quality ALWAYS binds, and there is no toggle. Every signal carries a
    -- quality, so an entry for normal iron plate means normal - which is the
    -- point when the factory is upcycling and the better tiers must still leave.
    local filters = { mode = mode, match_quality = true }
    local behavior = device.entity.get_or_create_control_behavior()
    local set = nil
    for _, section in pairs(behavior and behavior.sections or {}) do
        -- read regardless of `active`: nothing else looks at these sections, so
        -- the tick is not load-bearing here the way it was on the overlay
        for _, filter in pairs(section.filters) do
            local value = filter.value
            if value and value.name and (value.type == nil or value.type == "item") then
                set = set or { names = {}, any = {}, keys = {} }
                add_to_set(set, value.name, value.quality)
            end
        end
    end
    if not set then
        cache[factory_id] = false
        return nil
    end
    cache[factory_id] = { filters = filters, set = set }
    return filters, set
end

-- Timestamped lockout tables (record.pull_cooldown / record.storage_cooldown).
-- Pruning is amortized: an expired key is dropped the next time it is asked
-- about. The tables only ever hold keys the outlet actually handed back, so
-- they are bounded by the number of item types passing through it.
local function locked_out(tbl, key, tick, window)
    local at = tbl and tbl[key]
    if not at then return false end
    if tick - at < window then return true end
    tbl[key] = nil
    return false
end

local function mark_lockout(record, field, key, tick)
    local tbl = record[field]
    if not tbl then
        tbl = {}
        record[field] = tbl
    end
    tbl[key] = tick
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

-- `by_key` is optional: item|quality -> amount moved in this pass. The panel
-- reported one number for everything, which tells you the device is alive and
-- nothing about WHICH item is flowing - and "which item stopped" is the actual
-- question when a factory stalls. Only recorded per pass, so the memory is the
-- same rolling window the total already used.
local function note_moved(record, moved, by_key, inside)
    local tick = game.tick
    local samples = record.moved_samples
    if not samples then
        samples = {}
        record.moved_samples = samples
    end
    samples[#samples + 1] = { tick = tick, moved = moved, by = by_key, inside = inside }
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

-- Items moved chest-to-chest INSIDE the factories, which never crossed the wall
-- and so are not part of the pull rate above.
local function inside_per_minute(record)
    local total = 0
    for _, s in pairs(record.moved_samples or {}) do total = total + (s.inside or 0) end
    return total
end

-- Same window, broken out per item|quality. Read by the panel's tooltips only,
-- deliberately NOT by the grid's dirty-check signature: a rate that ticks every
-- pass would rebuild the whole grid every pass, which is exactly the cost the
-- dirty check exists to avoid. Tooltip staleness of one refresh is already the
-- accepted trade for the per-factory breakdown next to it.
local function rates_by_key(record)
    local out = {}
    for _, s in pairs(record.moved_samples or {}) do
        for key, n in pairs(s.by or {}) do
            out[key] = (out[key] or 0) + n
        end
    end
    return out
end

-- Item transfer helpers ---------------------------------------------------------

local function split_key(key)
    return key:match("^(.-)|(.*)$")
end

-- Returned items (overflow, on-demand give-backs, mined-device dumps) must
-- not scatter into the first chest with a free slot — that fills factory
-- chests with items that never belonged there. Acceptable homes, in order:
-- a chest that already holds that exact item (its origin chest wins
-- naturally), then storage chests — filtered ones matching the item first,
-- then unfiltered empty, then unfiltered with space (vanilla "leftovers go
-- to storage" semantics). An empty PROVIDER chest is NOT acceptable: it's
-- usually a machine output that consumers momentarily drained, and dumping
-- a foreign item there is exactly the contamination Eli kept finding
-- (0.19.6). If nothing qualifies the item deliberately stays where it is
-- (outlet buffer / mining buffer) rather than mixing into someone else's
-- chest.
-- A storage chest's filter is an ItemFilter: name plus, since 2.0, a quality.
-- Both halves matter. Reading only the name (which is what this did until
-- 0.23.0) made a chest filtered for legendary iron plate read as the right home
-- for normal iron plate, and the player's filter silently didn't hold. A filter
-- with no quality set matches every quality, same as everywhere else in the mod.
local function storage_filter_spec(chest)
    local filter = chest.storage_filter
    if not filter then return nil end
    if type(filter) == "string" then return { name = filter } end
    local name = filter.name
    if type(name) == "table" then name = name.name end
    if type(name) ~= "string" then return nil end
    local quality = filter.quality
    if type(quality) == "table" then quality = quality.name end
    return { name = name, quality = quality }
end

local function storage_filter_matches(spec, name, quality)
    if not spec or spec.name ~= name then return false end
    return spec.quality == nil or spec.quality == quality
end

-- Snapshot the candidate return chests ONCE: inventory handle, logistic mode,
-- storage filter, contents and emptiness. Everything the preference order needs
-- is then plain Lua.
--
-- The old shape re-derived four predicate closures and swept every chest four
-- times FOR EVERY ITEM TYPE being returned, calling get_item_count per chest
-- per sweep. Handing 20 item types back across 90 chests was roughly 7 200 API
-- calls on a single tick. Snapshotting moves that to one pass over the chests,
-- full stop (0.21.1).
--
-- The snapshot goes stale as we insert into it, and that is fine: `counts` is
-- only consulted for the item being placed, and a chest that stops being empty
-- because we just filled it merely moves between two adjacent buckets that are
-- both "unfiltered storage".
local function return_snapshot(chests)
    local snapshot = {}
    for _, entry in pairs(chests) do
        local chest = entry.chest
        if chest.valid then
            local inv = chest.get_inventory(defines.inventory.chest)
            if inv then
                local counts = {}
                for _, item in pairs(inv.get_contents()) do
                    counts[item_key(item.name, item.quality)] = item.count
                end
                snapshot[#snapshot + 1] = {
                    chest = chest,
                    inv = inv,
                    mode = entry.mode,
                    counts = counts,
                    -- storage_filter is only meaningful on storage chests
                    filter = (entry.mode == "storage") and storage_filter_spec(chest) or nil,
                    empty = inv.is_empty(),
                }
            end
        end
    end
    return snapshot
end

-- The four acceptable homes for a returned item, best first:
--   1. a chest that already holds it (its origin chest wins naturally)
--   2. a storage chest filtered for exactly it
--   3. an empty unfiltered storage chest
--   4. any unfiltered storage chest with space
-- An empty PROVIDER chest is deliberately absent - that is a machine output a
-- consumer momentarily drained, and dumping a foreign item there is the
-- contamination 0.19.6 fixed.
local function return_buckets(snapshot, name, quality)
    local key = item_key(name, quality)
    local holds, filtered, empty_storage, any_storage = {}, {}, {}, {}
    for _, entry in ipairs(snapshot) do
        if entry.chest.valid then
            if (entry.counts[key] or 0) > 0 then
                holds[#holds + 1] = entry
            elseif entry.mode == "storage" then
                if storage_filter_matches(entry.filter, name, quality) then
                    filtered[#filtered + 1] = entry
                elseif entry.filter == nil then
                    if entry.empty then
                        empty_storage[#empty_storage + 1] = entry
                    else
                        any_storage[#any_storage + 1] = entry
                    end
                end
            end
        end
    end
    return {holds, filtered, empty_storage, any_storage}
end

-- Insert a whole LuaItemStack in return-preference order, preserving
-- spoilage/quality/ammo (mining return). Mutates the source stack down to
-- whatever couldn't be placed.
local function insert_stack_into_chests(snapshot, stack)
    if not stack.valid_for_read then return end
    for _, bucket in ipairs(return_buckets(snapshot, stack.name, stack.quality.name)) do
        for _, entry in ipairs(bucket) do
            if not stack.valid_for_read then return end
            if entry.chest.valid then
                local inserted = entry.inv.insert(stack)
                if inserted > 0 then
                    stack.count = stack.count - inserted -- reaching 0 clears the stack
                end
            end
        end
    end
end

-- Insert `count` of a plain item spec in return-preference order
-- (overflow/on-demand return; spec-based, so spoil timers restart).
-- Returns the number inserted, plus whether any of it landed in an interior
-- STORAGE chest — the no-storage-re-pull loop guard needs to know that, and
-- this is the only place that can tell. Callers that don't care ignore it.
local function insert_spec_into_chests(snapshot, name, quality, count)
    local total = 0
    local into_storage = false
    for _, bucket in ipairs(return_buckets(snapshot, name, quality)) do
        for _, entry in ipairs(bucket) do
            local remaining = count - total
            if remaining <= 0 then return total, into_storage end
            if entry.chest.valid then
                local put = entry.inv.insert({name = name, count = remaining, quality = quality})
                if put > 0 then
                    total = total + put
                    if entry.mode == "storage" then into_storage = true end
                end
            end
        end
    end
    return total, into_storage
end

-- Move `count` of one item between two inventories.
--
-- `preserve` picks the mechanism, and the difference is not cosmetic. A
-- spec-based insert ({name=, count=, quality=}) MAKES items: the ones that
-- arrive are brand new, with a full spoilage timer. That is how the inlet
-- distributed until 0.24.0, which meant feeding nearly-rotten Gleba produce
-- through an inlet handed it back fresh - an inlet was a spoilage launderer, and
-- nothing in the UI said so. Copying the source stacks slot by slot instead
-- carries spoilage, and durability and ammo with it, at the cost of touching
-- each stack individually.
--
-- Returns how many actually moved.
local function transfer_items(from_inv, to_inv, name, quality, count, preserve)
    if count < 1 then return 0 end
    if not preserve then
        local inserted = to_inv.insert({name = name, count = count, quality = quality})
        if inserted > 0 then
            from_inv.remove({name = name, count = inserted, quality = quality})
        end
        return inserted
    end
    local moved = 0
    for i = 1, #from_inv do
        if moved >= count then break end
        local stack = from_inv[i]
        if stack.valid_for_read and stack.name == name
            and stack.quality.name == quality then
            local original = stack.count
            local take = math.min(original, count - moved)
            -- Shrink the source stack to exactly what should move, insert the
            -- stack itself (which carries its spoilage), then put back whatever
            -- the destination could not take.
            if take < original then stack.count = take end
            local inserted = to_inv.insert(stack)
            stack.count = original - inserted
            moved = moved + inserted
            if inserted < take then break end -- destination full
        end
    end
    return moved
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
    -- Coarse mode above the cap. Precise mode costs a `storage` write and a
    -- destroy registration per ghost, which is the right trade for a normal
    -- base and the wrong one for a 10 000-entity blueprint paste: that is
    -- 10 000 of each, all of which have to be walked back as the ghosts revive.
    -- Past the cap the chunk totals still get this ghost's demand (plain Lua,
    -- no storage, no registration) and we simply lose the ability to subtract
    -- it again. The totals then drift HIGH as those ghosts get built — the
    -- outlet over-supplies and its own give-back pass returns the excess — until
    -- the periodic resync rebuilds the index from the world. Bounded memory,
    -- bounded event load, temporary over-reporting. That is the trade.
    if idx.count > GHOST_INDEX_MAX then
        if not idx.coarse then
            idx.coarse = true
            idx.resync_tick = game.tick + GHOST_RESYNC_TICKS
            log("[E-Tech] factory hub: ghost index " .. key .. " passed " ..
                GHOST_INDEX_MAX .. " ghosts - coarse mode until it drains")
        end
        return
    end
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

-- Rebuild a coarse index from the world so it sheds the drift coarse mode
-- accumulates. Called from the maintenance phase, never from a pull pass: the
-- rebuild runs the two expensive whole-surface finds, and the whole point of
-- the phase scheduler is that those never share a tick with pull work.
-- If the world still holds more than the cap the fresh index simply goes coarse
-- again and books the next resync, which is the correct behaviour while a huge
-- paste is still draining.
local function gindex_resync(surface, force)
    local data = hub_data()
    local key = gindex_key(surface, force)
    local idx = data.gindex and data.gindex[key]
    if not (idx and idx.coarse) then return end
    if game.tick < (idx.resync_tick or 0) then return end
    data.gindex[key] = nil
    for unit, g in pairs(data.gunit or {}) do
        if g.key == key then data.gunit[unit] = nil end
    end
    ghost_index(surface, force)
end

-- Item-request-proxies (module/fuel requests on built machines) have no
-- build event we can hook, so they keep a slow, area-limited periodic scan.
-- prewarm: refresh PULL_TICKS early (called from the maintenance phase) so
-- the ~23 ms rescan never lands on the same tick as a pull pass.
-- Sliced since 0.21.1. The whole-bbox sweep profiled at 32-36 ms, landing in
-- one tick roughly once a minute, forever - the single most predictable hitch
-- the module produced. Same total work, cut into vertical strips, one strip
-- per maintenance pass, accumulated into a shadow table that is swapped in only
-- when the sweep completes. Readers always see the last COMPLETE picture, never
-- a half-built one.
--
-- A proxy sitting exactly on a strip boundary is counted in both strips, since
-- find_entities_filtered areas are inclusive. That over-reports its demand
-- slightly; the outlet's give-back loop returns the excess on the next pass,
-- which is the same way the ghost index already handles boundary chunks.
local PROXY_SLICES = 6

local function surface_proxies(surface, force, prewarm)
    local data = hub_data()
    data.proxies = data.proxies or {}
    local key = gindex_key(surface, force)
    local entry = data.proxies[key]
    if not entry then
        -- Backdated so the first sweep starts on the next prewarm, but not far
        -- enough back for the stale-entry pruning in maintenance_pass to eat it.
        entry = { tick = game.tick - PROXY_TICKS, chunks = {} }
        data.proxies[key] = entry
    end
    -- Readers (ghost_wants) never scan - they take whatever is current.
    -- Scanning happens only on the maintenance phase's prewarm call.
    if not prewarm then return entry end

    local building = entry.building
    if not building and game.tick - entry.tick >= PROXY_TICKS - PULL_TICKS then
        local bbox = construction_bbox(surface, force)
        if not bbox then
            -- no construction coverage here at all: nothing to scan
            entry.tick, entry.chunks = game.tick, {}
            return entry
        end
        building = { bbox = bbox, slice = 0, chunks = {} }
        entry.building = building
    end
    if not building then return entry end

    local prof = data.profiling and helpers.create_profiler()
    local x1, y1 = building.bbox[1][1], building.bbox[1][2]
    local x2, y2 = building.bbox[2][1], building.bbox[2][2]
    local step = (x2 - x1) / PROXY_SLICES
    local sx1 = x1 + step * building.slice
    -- last strip runs to the true edge, so rounding can never leave a gap
    local sx2 = (building.slice == PROXY_SLICES - 1) and x2 or (sx1 + step)

    local floor = math.floor
    for _, proxy in pairs(surface.find_entities_filtered {
        area = {{sx1, y1}, {sx2, y2}}, type = "item-request-proxy", force = force,
    }) do
        local pos = proxy.position
        local cx, cy = floor(pos.x / 32), floor(pos.y / 32)
        local ck = cx .. ":" .. cy
        local b = building.chunks[ck]
        if not b then
            b = { x = cx * 32 + 16, y = cy * 32 + 16, items = {} }
            building.chunks[ck] = b
        end
        add_insert_plans(b.items, proxy.insert_plan)
    end

    building.slice = building.slice + 1
    if building.slice >= PROXY_SLICES then
        entry.chunks = building.chunks
        entry.tick = game.tick
        entry.building = nil
    end
    if prof then
        prof.stop()
        helpers.write_file(PROFILE_FILE,
            {"", game.tick, ",proxy-slice(", building.slice, "/", PROXY_SLICES, "),", prof, "\n"}, true)
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
    -- The cell list is every roboport in the network, rebuilt from scratch on
    -- every call before 0.21.1 - which profiling showed to be the bulk of this
    -- function's ~1.5 ms, not the merge below. Roboports are built rarely, so
    -- cache the geometry (NOT the demand) for a couple of passes. Ghost demand
    -- itself still recomputes every pass; only where bots can reach is reused.
    local cells
    local cell_cache = record.cell_cache
    if cell_cache and cell_cache.network_id == network.network_id
        and game.tick - cell_cache.tick < CELL_TTL then
        cells = cell_cache.cells
    else
        cells = {}
        for _, cell in pairs(network.cells) do
            local r = cell.construction_radius
            if r and r > 0 and cell.owner and cell.owner.valid then
                local p = cell.owner.position
                cells[#cells + 1] = { x = p.x, y = p.y, r = r + 16 }
            end
        end
        record.cell_cache = { tick = game.tick, network_id = network.network_id, cells = cells }
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
-- Requester-side demand: chests, players, spidertrons. Split out and cached
-- since 0.21.1, because this is the one part of a pull pass whose cost scales
-- with the size of the PLAYER'S LOGISTIC NETWORK rather than with anything the
-- outlet is doing. It walks every requester point in the network, and it used
-- to call get_item_count once per filter - on a megabase with a few thousand
-- requesters averaging three filters each, that is thousands of API calls
-- landing on one tick, every pass, forever, even for an outlet with a single
-- reachable chest.
--
-- Three changes, in order of how much they can surprise you:
--   * points with no sections are skipped before their filters are touched.
--     Exact: same answer, less work.
--   * get_item_count is memoized per owner+item+quality for the duration of
--     one scan, so a chest asking for the same item in several sections is
--     queried once instead of once per filter. Also exact - nothing mutates
--     inventories mid-scan, so the repeated calls always returned the same
--     number anyway.
--   * the whole result is reused for REQUESTER_TTL ticks. This one is NOT
--     exact: it trades up to REQUESTER_TTL of staleness in chest and player
--     demand. Bots take longer than that to cross a base, so an outlet
--     noticing a new chest request one pass late costs nothing real.
--
-- Ghost demand is deliberately NOT cached - see network_wants below.
-- (REQUESTER_TTL lives with the other constants at the top of the file.)

local function requester_wants(outlet, network, record)
    local tick = game.tick
    local cache = record.requester_cache
    -- network_id guards the case where the outlet is rewired into a different
    -- network mid-TTL, which would otherwise serve another network's demand.
    if cache and cache.network_id == network.network_id
        and tick - cache.tick < REQUESTER_TTL then
        return cache.wants
    end

    local wants = {}
    local have_cache = {}
    -- Loop guard 1: the managed AUTO_GROUP section is an inlet echoing the
    -- factories' own shortfall back at the network. Skipping just that section
    -- (rather than the whole inlet) leaves the player's own manual requests on
    -- an inlet working normally.
    local skip_auto = guards(record).ignore_inlet_requests == true
    for _, point in pairs(network.requester_points) do
        local owner = point.owner
        if owner.valid and owner ~= outlet then
            local sections = point.sections
            if sections and #sections > 0 then
                local owner_key = (owner.unit_number or 0) .. "|"
                for _, section in pairs(sections) do
                    if section.active and not (skip_auto and section.group == AUTO_GROUP) then
                        for _, filter in pairs(section.filters) do
                            local v = filter.value
                            if v and v.name and (v.type == nil or v.type == "item") then
                                local quality = v.quality or "normal"
                                local ck = owner_key .. v.name .. "|" .. quality
                                local have = have_cache[ck]
                                if have == nil then
                                    have = owner.get_item_count({name = v.name, quality = quality})
                                    have_cache[ck] = have
                                end
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
    end

    record.requester_cache = { tick = tick, network_id = network.network_id, wants = wants }
    return wants
end

local function network_wants(outlet, record)
    local network = outlet.logistic_network
    if not network then return nil end
    -- Copy, never alias: the cached requester table is reused across passes and
    -- ghost demand is added on top of this one.
    local wants = {}
    for key, count in pairs(requester_wants(outlet, network, record)) do
        wants[key] = count
    end
    -- Construction ghosts count as demand too (the whole point of the outlet:
    -- anything inside the factories is usable outside, ghosts included). This
    -- half is recomputed every pass and never cached - it is pure Lua math over
    -- the event-driven chunk index, it costs almost nothing, and it is the part
    -- that has to react the moment a blueprint lands.
    for key, count in pairs(ghost_wants(record, network)) do
        wants[key] = (wants[key] or 0) + count
    end
    return wants, network
end

-- Does this inventory hold anything currently needed? get_contents is ONE API
-- call; the slot walk in pull_on_demand is one call per slot plus three field
-- reads per filled stack. On a real base most interior chests hold nothing the
-- outlet wants right now, so this skips nearly all of that work (0.21.1).
local function holds_any(inv, need)
    for _, item in pairs(inv.get_contents()) do
        if need[item_key(item.name, item.quality)] then return true end
    end
    return false
end

-- Loop guard 2: every item the inlets on this surface are currently
-- auto-requesting. Those are, by definition, items that would be carried back
-- into the same factories they came out of, so the outlet refuses to
-- materialize them at all while the request stands — including for genuine
-- outside demand, which is the trade this guard makes. Walked fresh each pass:
-- it is a handful of inlets, not a network-wide scan.
local function inlet_auto_keys(record)
    local outlet = record.entity
    local surface = outlet.surface.index
    local force = outlet.force.index
    local keys = {}
    for _, other in pairs(hub_data().hubs) do
        if other.kind == "inlet" and other.entity.valid
            and other.entity.surface.index == surface
            and other.entity.force.index == force then
            local point = other.entity.get_requester_point()
            for _, section in pairs(point and point.sections or {}) do
                if section.group == AUTO_GROUP then
                    for _, filter in pairs(section.filters) do
                        local v = filter.value
                        if v and v.name then keys[item_key(v.name, v.quality)] = true end
                    end
                end
            end
        end
    end
    return keys
end

-- On-demand: keep only wanted items in the outlet (return the rest to the
-- factories), then materialize what the network can't already supply.
local function pull_on_demand(record, hub_inv, chests, return_snap, set)
    local prof = hub_data().profiling and helpers.create_profiler()
    local wants, network = network_wants(record.entity, record)
    if prof then
        prof.stop()
        helpers.write_file(PROFILE_FILE,
            {"", game.tick, ",net-wants,", prof, "\n"}, true)
    end
    local moved = 0
    local by_key = {}
    local g = guards(record)
    local tick = game.tick

    -- send back anything no longer wanted (bots occasionally re-route if we
    -- yank an item they were flying toward; the engine handles it)
    for key, count in pairs(inventory_counts(hub_inv)) do
        local wanted = wants and wants[key] or 0
        local excess = count - wanted
        if excess > 0 then
            local name, quality = split_key(key)
            local inserted, into_storage =
                insert_spec_into_chests(return_snap, name, quality, excess)
            if inserted > 0 then
                hub_inv.remove({name = name, count = inserted, quality = quality})
                -- Loop guards 3 and 4 are armed here, on the give-back, because
                -- that is the moment an item has demonstrably gone round once.
                if g.cooldown then mark_lockout(record, "pull_cooldown", key, tick) end
                if into_storage and g.no_storage_repull then
                    mark_lockout(record, "storage_cooldown", key, tick)
                end
            end
        end
    end

    if not wants then return 0, by_key end

    -- what the network can't already cover (its count includes our stock)
    local blocked = g.block_inlet_items and inlet_auto_keys(record) or nil
    local need = {}
    for key, want in pairs(wants) do
        if not (blocked and blocked[key])
            and not (g.cooldown
                and locked_out(record.pull_cooldown, key, tick, COOLDOWN_TICKS)) then
            local name, quality = split_key(key)
            local missing = want - network.get_item_count({name = name, quality = quality})
            if missing > 0 then need[key] = missing end
        end
    end
    if next(need) == nil then return 0, by_key end

    -- factory id -> factory, so the rule resolver can reach the overlay
    -- controller without another scan
    local policy_cache = { factories = {} }
    for _, entry in pairs(chests) do policy_cache.factories[entry.factory.id] = entry.factory end
    for _, entry in pairs(chests) do
        if next(need) == nil then break end
        local chest = entry.chest
        if chest.valid then
            local inv = chest.get_inventory(defines.inventory.chest)
            -- guard 4 only ever gates the storage half of the source list
            local storage_gated = g.no_storage_repull and entry.mode == "storage"
            -- resolved per chest, but only costs anything for factories that
            -- actually have a rule set
            local ffilters, fset =
                factory_filter_active(record, entry.factory.id, policy_cache)
            if inv and holds_any(inv, need) then
                for i = 1, #inv do
                    local stack = inv[i]
                    if stack.valid_for_read
                        and item_allowed(record, stack.name, stack.quality.name, set)
                        and quality_allowed(record, stack.quality.name)
                        and (not ffilters or filters_allow(ffilters,
                            stack.name, stack.quality.name, fset)) then
                        local key = item_key(stack.name, stack.quality.name)
                        local missing = need[key]
                        if storage_gated
                            and locked_out(record.storage_cooldown, key, tick, STORAGE_LOCK_TICKS) then
                            missing = nil
                        end
                        if missing and missing >= 1 then
                            local original = stack.count
                            local move = math.min(missing, original)
                            if move < original then stack.count = move end
                            local inserted = hub_inv.insert(stack)
                            stack.count = original - inserted
                            moved = moved + inserted
                            by_key[key] = (by_key[key] or 0) + inserted
                            need[key] = missing - inserted
                            if need[key] < 1 then need[key] = nil end
                        end
                    end
                end
            end
        end
    end
    return moved, by_key
end

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

-- Serve the factories' own requester chests from the factories' own provider
-- chests, without anything leaving the wall.
--
-- This is the root fix for the loop the guards above only blunt. The full
-- circle is: an interior provider holds an item, an interior requester wants it,
-- the inlet auto-requests it from the outside network, the outlet reads that as
-- demand and pulls the item out of the very factory that needs it, robots fly it
-- across the base to the inlet, and the inlet pushes it back inside. Six steps
-- to move an item between two chests on the same surface, and the loop guards
-- deal with it by refusing to do step four - which stops the circling but still
-- leaves the interior requester unfed.
--
-- Doing the transfer directly instead makes the deficit disappear at the source:
-- with nothing missing inside, the inlet has nothing to auto-request, the outlet
-- sees no demand, and there is no circle to break. Robots are never involved,
-- which also means it works in a factory with no interior roboport at all.
--
-- Shares proportionally for the same reason distribute_for_inlet does: filling
-- each chest to its full deficit in list order starves whatever is at the end of
-- a stable list whenever supply is short.
local function interior_fulfil(record, set)
    local sources = reachable_chests(record, outlet_source_mode(record))
    local targets = reachable_chests(record, requester_mode)
    if #sources == 0 or #targets == 0 then return 0 end

    -- what the interior still wants, and who wants it
    local demand = {}
    for _, entry in pairs(targets) do
        local chest = entry.chest
        if chest.valid then
            local wants = chest_requests(chest)
            if wants and next(wants) then
                local inv = chest.get_inventory(defines.inventory.chest)
                local current = inv and inventory_counts(inv) or {}
                for key, want in pairs(wants) do
                    local name, quality = split_key(key)
                    if inv and item_allowed(record, name, quality, set) then
                        local deficit = want - (current[key] or 0)
                        if deficit > 0 then
                            local d = demand[key]
                            if not d then
                                d = { total = 0, claims = {} }
                                demand[key] = d
                            end
                            d.total = d.total + deficit
                            d.claims[#d.claims + 1] = { inv = inv, want = deficit }
                        end
                    end
                end
            end
        end
    end
    if next(demand) == nil then return 0 end

    -- what the interior can cover, per item
    local supply = {}
    for _, entry in pairs(sources) do
        local chest = entry.chest
        if chest.valid then
            local inv = chest.get_inventory(defines.inventory.chest)
            if inv then
                for _, item in pairs(inv.get_contents()) do
                    local key = item_key(item.name, item.quality or "normal")
                    if demand[key] then
                        local s = supply[key]
                        if not s then
                            s = { total = 0, invs = {} }
                            supply[key] = s
                        end
                        s.total = s.total + item.count
                        s.invs[#s.invs + 1] = inv
                    end
                end
            end
        end
    end

    local moved = 0
    for key, d in pairs(demand) do
        local s = supply[key]
        if s and s.total > 0 then
            local name, quality = split_key(key)
            local pool = math.min(s.total, d.total)
            for _, claim in ipairs(d.claims) do
                -- The supply figure is a snapshot and is not decremented as we
                -- go: a source chest drained by an earlier claim simply returns
                -- 0 from the transfer and the next one is tried. A claim can
                -- therefore come up short within a pass, which the next pass
                -- picks up - the alternative is re-reading every source chest
                -- per claim, for an item that is about to be topped up anyway.
                local remaining = (pool >= d.total) and claim.want
                    or math.floor(pool * claim.want / d.total)
                for _, source_inv in ipairs(s.invs) do
                    if remaining < 1 then break end
                    -- slot-level, so spoilage and quality survive the hop
                    local put = transfer_items(source_inv, claim.inv,
                        name, quality, remaining, true)
                    remaining = remaining - put
                    moved = moved + put
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
    -- Leave the interior ends of the factory's chest connections alone.
    -- Factorissimo is already deciding what moves through those, and draining
    -- one competes with it: an inward connection re-fills the chest the instant
    -- the outlet empties it, forever. Skipping the CHEST rather than the item
    -- or the factory is what makes this safe to have on by default - everything
    -- else inside the same factory still exports normally, so the ore arriving
    -- through a connection stays put while the plates made from it leave.
    if not guards(record).pull_connection_chests then
        local usable = {}
        for _, entry in pairs(chests) do
            if not entry.connected then usable[#usable + 1] = entry end
        end
        chests = usable
    end
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

    -- Before anything leaves: fill the interior's own requests from the
    -- interior's own stock. Done first on purpose - whatever this satisfies is
    -- demand the pull below never has to see.
    local inside = 0
    if guards(record).interior_first then
        inside = interior_fulfil(record, set)
    end

    -- Snapshot the give-back candidates once for the whole pass, however many
    -- item types end up going back.
    local moved, by_key = pull_on_demand(record, hub_inv, chests,
        return_snapshot(reachable_chests(record, return_mode)), set)
    note_moved(record, moved, by_key, inside)
end

-- Inlet: distribute into interior requester/buffer chests ---------------------

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

-- An inlet already knows when the factories are asking for something it can't
-- supply - that is exactly the "Still missing inside" list in its window. Until
-- 0.24.0 that was the ONLY place it appeared, so a starving factory was
-- invisible unless you happened to walk over and open the right device.
--
-- Two things keep this from becoming noise. It needs the shortfall to PERSIST
-- for the grace period, because a factory is briefly short every time a machine
-- finishes a batch and alerting on that would fire constantly. And the alert is
-- re-raised every pass while it lasts, deliberately: a custom alert that stops
-- being re-added stops being shown, which is the same reason the teleporter's
-- unpowered-pad alert re-raises.
local function shortfall_alert(record)
    if not settings.global["etech-hub-shortfall-alerts"].value then
        record.short_since = nil
        return
    end
    if not record.last_remaining then
        record.short_since = nil
        return
    end
    local tick = game.tick
    record.short_since = record.short_since or tick
    local grace = settings.global["etech-hub-shortfall-grace"].value * 60
    if tick - record.short_since < grace then return end

    local entity = record.entity
    local force = entity.force
    local players = force.connected_players
    if #players == 0 then return end
    -- Name one missing item rather than a count: "the factories want copper
    -- plate" is actionable, "3 items missing" is not. Lowest key wins so the
    -- message is stable between passes instead of flickering between items.
    local pick
    for key in pairs(record.last_remaining) do
        if not pick or key < pick then pick = key end
    end
    if not pick then return end
    local name = split_key(pick)
    local icon = {type = "item", name = INLET_NAME}
    local message = {"gui-etech-hub.alert-shortfall", name}
    for _, player in pairs(players) do
        player.add_custom_alert(entity, icon, message, true)
    end
end

local function distribute_for_inlet(record)
    local inlet = record.entity
    local inlet_inv = inlet.get_inventory(defines.inventory.chest)
    if not inlet_inv then return end

    local have = inventory_counts(inlet_inv)
    local targets = reachable_chests(record, requester_mode)
    local moved = 0
    local by_key = {}
    local remaining = {} -- interior deficits left after this pass, for auto-request
    local set = filter_set(record) -- inlets filter like outlets since 0.19.0

    -- Pass 1: collect what every reachable chest is short of, grouped by item.
    -- Nothing is inserted yet, and that is the whole point. Inserting as each
    -- chest is met gives the first chest in the list its entire deficit before
    -- the second is even looked at, so whenever the inlet holds less than the
    -- factories want in total, the factories at the end of a stable list get
    -- nothing — not "less", nothing — pass after pass, indefinitely. That is
    -- invisible right up until supply tightens, and then it looks like the last
    -- factory's inlet is broken.
    local demand = {} -- key -> { total, claims = {{inv, want}, ...} }
    for _, entry in pairs(targets) do
        local chest = entry.chest
        if chest.valid then
            local wants = chest_requests(chest)
            if wants and next(wants) then
                local inv = chest.get_inventory(defines.inventory.chest)
                local current = inv and inventory_counts(inv)
                for key, want in pairs(wants or {}) do
                    local name, quality = split_key(key)
                    if inv and item_allowed(record, name, quality, set) then
                        local deficit = want - (current[key] or 0)
                        if deficit > 0 then
                            local d = demand[key]
                            if not d then
                                d = { total = 0, claims = {} }
                                demand[key] = d
                            end
                            d.total = d.total + deficit
                            d.claims[#d.claims + 1] = { inv = inv, want = deficit }
                        end
                    end
                end
            end
        end
    end

    -- Pass 2: hand out. Enough on hand for an item -> every claim gets its full
    -- deficit and this behaves exactly as it always did. Not enough -> each
    -- claim gets its proportional share, floored, and the units left over by
    -- the flooring are walked out one at a time from a rotating start so the
    -- same chest doesn't collect the odd unit every single pass.
    local turn = record.share_turn or 0
    local reset_spoilage = guards(record).reset_spoilage == true
    for key, d in pairs(demand) do
        local name, quality = split_key(key)
        local pool = math.min(have[key] or 0, d.total)
        local grants = {}
        if pool >= d.total then
            for i, claim in ipairs(d.claims) do grants[i] = claim.want end
        else
            local handed = 0
            for i, claim in ipairs(d.claims) do
                local share = math.floor(pool * claim.want / d.total)
                grants[i] = share
                handed = handed + share
            end
            local spare = pool - handed
            local n = #d.claims
            -- Sweeps, not one pass: a claim already at its want takes nothing,
            -- so a single lap can leave units unplaced. Stops the moment a whole
            -- lap places nothing, which also caps the work at n per sweep.
            while spare >= 1 do
                local placed = false
                for step = 0, n - 1 do
                    if spare < 1 then break end
                    local i = (turn + step) % n + 1
                    if grants[i] < d.claims[i].want then
                        grants[i] = grants[i] + 1
                        spare = spare - 1
                        placed = true
                    end
                end
                if not placed then break end
            end
        end
        for i, claim in ipairs(d.claims) do
            local short = claim.want
            if grants[i] >= 1 then
                local inserted = transfer_items(inlet_inv, claim.inv, name, quality,
                    grants[i], not reset_spoilage)
                if inserted > 0 then
                    have[key] = (have[key] or 0) - inserted
                    moved = moved + inserted
                    by_key[key] = (by_key[key] or 0) + inserted
                    short = short - inserted
                end
            end
            if short > 0 then remaining[key] = (remaining[key] or 0) + short end
        end
    end
    -- Bounded so the counter can't grow without limit in a long save.
    record.share_turn = (turn + 1) % 1000

    update_inlet_auto_requests(record, remaining)
    record.last_remaining = next(remaining) and remaining or nil
    note_moved(record, moved, by_key)
    shortfall_alert(record)
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

-- Total interior fluid stock the device can reach, per fluid name.
local function interior_fluids(record)
    local totals = {}
    for _, tank in pairs(reachable_tanks(record)) do
        if tank.valid then
            for name, amount in pairs(tank.get_fluid_contents()) do
                totals[name] = (totals[name] or 0) + amount
            end
        end
    end
    return totals
end


-- First (and, for these devices, only) fluid in an entity, or nil.
-- `next` says that outright; the old for-loop-with-an-unconditional-return
-- said it by accident, which is also what luacheck reported.
local function device_fluid(entity)
    return next(entity.get_fluid_contents())
end

-- The pull filter lives in record.fluid_filter (set via the small relative
-- panel next to the outlet's tank GUI — vanilla storage tanks expose no
-- player-settable filter slot of their own).

-- Push `amount` of `name` from the device into interior tanks that already
-- hold the same fluid. Shared by the fluid inlet and the outlet's
-- filter-change flush. Returns the amount moved.
local function push_fluid_to_tanks(record, device, name, amount)
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
    return moved
end

-- Fluid loop guard. The item devices got theirs in 0.23.0; the fluid pair has
-- the same shape and is worse, because fluid moves in bulk with no bots to
-- throttle it. Pipe a fluid outlet and a fluid inlet onto the same header — one
-- header per fluid is the normal way to plumb a base — and the outlet drains
-- the factories' tanks, the fluid runs down the header into the inlet, and the
-- inlet pushes it straight back into those same tanks. Nothing leaves, both
-- devices work forever.
--
-- The guard is on the pull side, where the circle starts: while a fluid inlet
-- on this surface is holding the fluid this outlet is picked for, the outlet
-- sits still. The inlet has no GUI of its own, so this is also the only device
-- of the pair that can carry a toggle.
local function inlet_holds_fluid(record, name)
    local outlet = record.entity
    local surface = outlet.surface.index
    local force = outlet.force.index
    for _, other in pairs(hub_data().hubs) do
        if other.kind == "fluid-inlet" and other.entity.valid
            and other.entity.surface.index == surface
            and other.entity.force.index == force then
            local held = device_fluid(other.entity)
            if held == name then return true end
        end
    end
    return false
end

local function pass_for_fluid_outlet(record)
    local device = record.entity
    -- 2.1: LuaEntity.fluidbox is gone; capacity/removal go through
    -- get_fluid_capacity / extract_fluid directly on the entity.
    -- NO pick = NO pulling (Eli's call: never grab a random fluid).
    local want = record.fluid_filter
    if not want then
        note_moved(record, 0)
        return
    end
    -- Evaluated before the flush, applied after it. A pick change still has to
    -- be able to hand the OLD fluid back even while the guard is holding the
    -- pull, or the outlet would sit forever holding a fluid it can't shed.
    record.fluid_looped =
        (guards(record).fluid_loop and inlet_holds_fluid(record, want)) or nil
    local capacity = device.get_fluid_capacity(1)
    local current_name, current_amount = device_fluid(device)
    local moved = 0

    -- Pick changed while holding a different fluid: flush the old fluid
    -- back into interior tanks that hold it, then start pulling the picked
    -- one. If nothing inside can take it, wait (the player can also just
    -- pump/empty it out).
    if current_name and current_name ~= want then
        moved = moved + push_fluid_to_tanks(record, device, current_name, current_amount)
        current_name, current_amount = device_fluid(device)
        if current_name and current_name ~= want then
            note_moved(record, math.floor(moved))
            return
        end
    end

    if record.fluid_looped then
        note_moved(record, math.floor(moved))
        return
    end

    local room = capacity - (current_amount or 0)
    if room < 1 then
        note_moved(record, math.floor(moved))
        return
    end
    for _, tank in pairs(reachable_tanks(record)) do
        if room < 1 then break end
        if tank.valid then
            local name, amount = device_fluid(tank)
            if name == want and amount and amount >= 1 then
                local take = math.min(room, amount)
                local removed = tank.extract_fluid{name = name, amount = take}
                if removed > 0 then
                    local inserted = device.insert_fluid{name = name, amount = removed}
                    -- overfill safety: give back what didn't fit
                    if inserted < removed then
                        tank.insert_fluid{name = name, amount = removed - inserted}
                    end
                    if inserted > 0 then
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
    note_moved(record, math.floor(push_fluid_to_tanks(record, device, name, amount)))
end

-- Sensor: broadcast interior provider totals as signals ------------------------

-- What the interior requester/buffer chests are still short of. Only walked
-- when the sensor's deficit option is on — it doubles the sensor's chest walk,
-- and most sensors just want stock. Same shape the inlet computes for its own
-- auto-requests, but a sensor has no inlet to read it from: an inlet is a
-- separate device and may not exist on this surface at all.
local function interior_deficits(record)
    local out = {}
    for _, entry in pairs(reachable_chests(record, requester_mode)) do
        local chest = entry.chest
        if chest.valid then
            local wants = chest_requests(chest)
            if wants and next(wants) then
                local inv = chest.get_inventory(defines.inventory.chest)
                local current = inv and inventory_counts(inv) or {}
                for key, want in pairs(wants) do
                    local deficit = want - (current[key] or 0)
                    if deficit > 0 then out[key] = (out[key] or 0) + deficit end
                end
            end
        end
    end
    return out
end

local function update_sensor(record)
    local totals = {}
    local set = filter_set(record)
    local opts = guards(record)
    local source = opts.sensor_storage and function(mode)
        return provider_mode(mode) or mode == "storage"
    end or provider_mode
    for _, entry in pairs(reachable_chests(record, source)) do
        local inv = entry.chest.get_inventory(defines.inventory.chest)
        if inv then
            for _, item in pairs(inv.get_contents()) do
                local quality = item.quality or "normal"
                if item_allowed(record, item.name, quality, set) then
                    local key = item_key(item.name, quality)
                    totals[key] = (totals[key] or 0) + item.count
                end
            end
        end
    end
    -- Deficits are SUBTRACTED from stock rather than emitted as their own
    -- signals: a signal can only carry one number per item, and "how much of
    -- this do the factories have spare" is the number a circuit actually wants.
    -- Positive = surplus sitting in provider chests, negative = the interior
    -- requesters are short by that much.
    if opts.sensor_deficits then
        for key, deficit in pairs(interior_deficits(record)) do
            local name, quality = split_key(key)
            if item_allowed(record, name, quality, set) then
                totals[key] = (totals[key] or 0) - deficit
            end
        end
        -- a net of exactly zero is not a signal, it is the absence of one
        for key, count in pairs(totals) do
            if count == 0 then totals[key] = nil end
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
        -- by magnitude, not by value: with deficits on, the most negative
        -- signals are the most interesting ones and a plain descending sort
        -- would truncate exactly those away first
        table.sort(list, function(a, b)
            local am, bm = math.abs(a.min), math.abs(b.min)
            if am ~= bm then return am > bm end
            return a.value.name < b.value.name
        end)
        for i = #list, MAX_SIGNALS + 1, -1 do list[i] = nil end
    end

    local behavior = record.entity.get_or_create_control_behavior()
    local section = behavior.get_section(1) or behavior.add_section()
    section.filters = list
end

-- Fluid sensor: the interior tanks' contents as signals. Completes the fluid
-- side, which had an outlet and an inlet and no way for a circuit to see what
-- was actually in there. Fluid signals only, so nothing here needs the item
-- filter machinery - a fluid device has one fluid per tank and the interesting
-- question is just "how much of each".
local function update_fluid_sensor(record)
    local totals = interior_fluids(record)

    -- Same dirty check as the item sensor: rewriting the section every pass was
    -- that device's entire steady-state cost. Amounts are floored first, so a
    -- tank drifting by a fraction of a unit doesn't count as a change.
    local sig = {}
    for name, amount in pairs(totals) do
        sig[#sig + 1] = name .. "=" .. math.floor(amount)
    end
    table.sort(sig)
    local snapshot = table.concat(sig, ";")
    if record.sensor_snapshot == snapshot then return end
    record.sensor_snapshot = snapshot

    local list = {}
    for name, amount in pairs(totals) do
        local floored = math.floor(amount)
        if floored > 0 then
            list[#list + 1] = {
                value = { type = "fluid", name = name, comparator = "=" },
                min = floored,
            }
        end
    end
    if #list > MAX_SIGNALS then
        table.sort(list, function(a, b)
            if a.min ~= b.min then return a.min > b.min end
            return a.value.name < b.value.name
        end)
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
    -- Same narrowing as on_built (0.21.1): only a real factory building or an
    -- interior chest can change what a device sees.
    if entity.type == "storage-tank" and is_factory_building(entity.name) then
        local data = hub_data()
        data.factory_gen = (data.factory_gen or 0) + 1
    elseif entity.type == "logistic-container" and surface_is_interior(entity.surface) then
        local data = hub_data()
        data.chest_gen = (data.chest_gen or 0) + 1
    end
    local kind = KINDS[entity.name]
    if not (kind == "outlet" or kind == "inlet") then return end
    local buffer = event.buffer
    if not (buffer and factorissimo_available()) then return end

    local record = hub_data().hubs[entity.unit_number]
        or { entity = entity, kind = kind, filters = { mode = 1, items = {} }, pins = {} }
    local snapshot = return_snapshot(reachable_chests(record, return_mode))
    if #snapshot == 0 then return end
    for i = 1, #buffer do
        local stack = buffer[i]
        -- skip the device item itself (and any of them it was buffering)
        if stack.valid_for_read and not KINDS[stack.name] then
            insert_stack_into_chests(snapshot, stack)
        end
    end
end

-- GPS helpers -------------------------------------------------------------------

local function gps_tag(factory)
    local building = factory.building
    -- %.0f, not %d: odd-sized prototypes legitimately sit on .5 coordinates.
    -- Lua 5.2 truncates those for %d, but 5.3+ raises on a non-integral float,
    -- so this was a live trap the moment Factorio moved runtimes (0.21.1).
    return string.format("[gps=%.0f,%.0f,%s]",
        building.position.x, building.position.y, building.surface.name)
end

-- Opening the interior chest itself, for players who turned that on. It has to
-- be remote view: the chest is on another surface, so the reach trick the
-- factory terminal uses (factory-hub/terminal.lua) cannot reach it at all.
--
-- Read terminal.lua's header before reusing this anywhere else. Remote view was
-- tried there and rejected, because it swaps the player's inventory panel for
-- the ghost-build palette - which is fatal when the point is moving items in and
-- out. Here the point is LOOKING at where something is, and shift-click still
-- takes a stack without moving the player at all, so the same trade lands the
-- other way. It is off by default regardless.
local function remote_view_at(player, entity)
    if not (player.character and entity and entity.valid) then return false end
    local ok = pcall(function()
        player.set_controller {
            type = defines.controllers.remote,
            position = entity.position,
            surface = entity.surface,
        }
    end)
    return ok
end

local function locate_item(player, record, name, quality)
    local per = {}
    local best, best_count = nil, 0
    for _, entry in pairs(reachable_chests(record, outlet_source_mode(record))) do
        local inv = entry.chest.get_inventory(defines.inventory.chest)
        if inv then
            local count = inv.get_item_count({name = name, quality = quality})
            if count > 0 then
                local id = entry.factory.id
                if not per[id] then per[id] = { factory = entry.factory, count = 0 } end
                per[id].count = per[id].count + count
                if count > best_count then best, best_count = entry.chest, count end
            end
        end
    end
    -- Per-player opt-in: jump the camera to the chest that holds the most of it
    -- rather than printing links. The chat lines are still printed either way,
    -- so the per-factory breakdown isn't lost by turning this on.
    if best and player.mod_settings["etech-hub-locate-remote"].value then
        remote_view_at(player, best)
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
-- The CHARACTER's main inventory, not the controller's. Opening a device
-- through the factory terminal puts the player in remote view, and a remote
-- controller is not a character - player.get_main_inventory() comes back nil
-- there, so taking a stack silently did nothing (0.22.0). The character is
-- still standing where it was and is what should receive the items.
local function character_inventory(player)
    local character = player.character
    if character and character.valid then
        return character.get_main_inventory()
    end
    return player.get_main_inventory()
end

-- Ask the player's OWN logistic requests for this item, rather than fetching it
-- by hand. The point of the outlet is that bots can do the walking; a panel that
-- can only hand you a stack in person is missing its own trick. Written into a
-- managed section so it never disturbs the request groups the player set up.
local PLAYER_REQUEST_GROUP = "etech-hub-requested"

local function request_item(player, name, quality)
    local character = player.character
    local point = character and character.valid and character.get_requester_point()
    if not point then
        player.print({"gui-etech-hub.request-no-character"})
        return
    end
    local proto = prototypes.item[name]
    if not proto then return end
    local target
    for _, section in pairs(point.sections) do
        if section.group == PLAYER_REQUEST_GROUP then
            target = section
            break
        end
    end
    if not target then target = point.add_section(PLAYER_REQUEST_GROUP) end
    if not target then
        player.print({"gui-etech-hub.request-failed", name})
        return
    end
    -- Repeat clicks top the same slot up by a stack instead of piling up
    -- duplicate slots for the same item.
    local filters = target.filters
    local slot, total = nil, proto.stack_size
    for i, filter in pairs(filters) do
        local value = filter.value
        if value and value.name == name and (value.quality or "normal") == quality then
            slot = i
            total = (filter.min or 0) + proto.stack_size
            break
        end
    end
    if not slot then slot = #filters + 1 end
    target.set_slot(slot, {
        value = { type = "item", name = name, quality = quality, comparator = "=" },
        min = total,
    })
    player.print({"gui-etech-hub.requested", total, name})
end

-- `all = true` takes as much as the player can carry instead of one stack.
local function take_item(player, record, name, quality, all)
    local player_inv = character_inventory(player)
    if not player_inv then
        player.print({"gui-etech-hub.take-no-inventory"})
        return
    end
    local proto = prototypes.item[name]
    if not proto then return end -- item removed by a mod change
    -- The loop below already stops on a full inventory (it clamps `wanted` down
    -- to what fit), so "everything" needs no separate capacity calculation.
    local wanted = all and math.huge or proto.stack_size
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

local SORT_ITEMS = {
    {"gui-etech-hub.sort-count"},
    {"gui-etech-hub.sort-name"},
    {"gui-etech-hub.sort-rate"},
}

-- The loop-guard checkboxes, in panel order. One table drives the build, the
-- state restore and the click handler, so adding a guard is one entry plus its
-- two locale keys.
local GUARD_CHECKS = {
    -- First on purpose: it is the only one that FIXES the loop rather than
    -- refusing to take part in it, so it is what someone should try first.
    {element = "etech-hub-interior-first", field = "interior_first",     loc = "interior-first"},
    {element = "etech-hub-guard-inlet",    field = "ignore_inlet_requests", loc = "guard-inlet"},
    {element = "etech-hub-guard-items",    field = "block_inlet_items",     loc = "guard-items"},
    {element = "etech-hub-guard-cooldown", field = "cooldown",              loc = "guard-cooldown"},
    {element = "etech-hub-guard-storage",  field = "no_storage_repull",     loc = "guard-storage"},
}

-- The fluid outlet's own loop guard. Same storage field convention, but it
-- lives on a different panel, so it is registered for the shared handler
-- without joining the outlet panel's checkbox list.
local FLUID_GUARD = {element = "etech-hub-guard-fluid", field = "fluid_loop", loc = "guard-fluid"}

-- Sits with the filter widgets rather than the loop guards — it changes where
-- the filter list comes from, it doesn't stop a loop.
local PULL_CONNECTIONS_OPT =
    {element = "etech-hub-pull-connections", field = "pull_connection_chests",
     loc = "pull-connections"}

local CIRCUIT_FILTER_OPT =
    {element = "etech-hub-circuit-filters", field = "circuit_filters", loc = "circuit-filters"}

-- Inlet only. Ticking it opts back IN to the pre-0.24.0 behaviour where
-- distributed items arrive with a fresh spoilage timer.
local SPOILAGE_OPT =
    {element = "etech-hub-reset-spoilage", field = "reset_spoilage", loc = "reset-spoilage"}

local GUARD_BY_ELEMENT = {
    [FLUID_GUARD.element] = FLUID_GUARD,
    [PULL_CONNECTIONS_OPT.element] = PULL_CONNECTIONS_OPT,
    [CIRCUIT_FILTER_OPT.element] = CIRCUIT_FILTER_OPT,
    [SPOILAGE_OPT.element] = SPOILAGE_OPT,
}
for _, guard in ipairs(GUARD_CHECKS) do GUARD_BY_ELEMENT[guard.element] = guard end

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
    -- TABS, since 0.24.1. Everything used to be one column: stock grid, then
    -- pull settings, then filters, then loop guards, then the factory list. Each addition was small and the total went off the
    -- bottom of the screen - a relative GUI does not scroll as a whole, so the
    -- factory list and half the settings were simply unreachable. Three tabs
    -- fix that permanently rather than by shaving pixels off each section.
    --
    -- The rate line stays OUTSIDE the tabs: it carries the pause reason, and a
    -- status line you can only see on one tab is a status line you miss.
    inner.add {type = "label", name = "rate"}
    -- NOT "tabs": LuaGuiElement already has a property of that name, and the engine
    -- rejects the element outright ("contains a property or method with the same
    -- name") the moment the panel is built. Cost a crash on opening an outlet.
    local tabs = inner.add {type = "tabbed-pane", name = "etech_tabs"}

    local contents_tab = tabs.add {type = "tab", caption = {"gui-etech-hub.tab-contents"}}
    local contents = tabs.add {type = "flow", name = "contents", direction = "vertical"}
    tabs.add_tab(contents_tab, contents)
    local search = contents.add {type = "textfield", name = "etech-hub-search"}
    search.style.horizontally_stretchable = true
    -- The grid was one flat list of everything on the surface, with the
    -- per-factory split available only by hovering each item in turn. These two
    -- make "what is in factory 7" and "what is there most of" answerable
    -- directly. Both are view state - neither changes what the outlet pulls.
    local views = contents.add {type = "flow", name = "views", direction = "horizontal"}
    views.add {type = "drop-down", name = "etech-hub-factory",
        tooltip = {"gui-etech-hub.factory-filter-tooltip"}}
    views.add {type = "drop-down", name = "etech-hub-sort",
        items = SORT_ITEMS, selected_index = 1,
        tooltip = {"gui-etech-hub.sort-tooltip"}}
    local scroll = contents.add {type = "scroll-pane", name = "scroll"}
    -- tall enough to visually match the 200-slot chest window next to it
    scroll.style.minimal_height = 420
    scroll.style.maximal_height = 640
    -- The tabbed pane is as wide as its widest tab, which is Factories (two
    -- buttons, a name and a rename field). Without this the stock grid kept
    -- its natural 8-column width and left the rest of that width blank.
    -- minimal_width guarantees the full STOCK_COLUMNS fit even if the
    -- Factories tab is ever narrower, so the grid never gets a horizontal
    -- scrollbar - a grid you have to scroll sideways is worse than a narrow
    -- one, because nothing lines up between rows.
    scroll.style.horizontally_stretchable = true
    scroll.style.minimal_width = STOCK_COLUMNS * SLOT_PX + 24

    local settings_tab = tabs.add {type = "tab", caption = {"gui-etech-hub.tab-settings"}}
    local pull = tabs.add {type = "flow", name = "settings", direction = "vertical"}
    tabs.add_tab(settings_tab, pull)
    pull.add {type = "label", name = "settings_label",
        caption = {"gui-etech-hub.pull-settings"}}
    local checks = pull.add {type = "flow", name = "checks", direction = "vertical"}
    checks.add {type = "checkbox", name = "etech-hub-storage", state = false,
        caption = {"gui-etech-hub.storage"}, tooltip = {"gui-etech-hub.storage-tooltip"}}
    -- Belongs with the other "where may I pull from" options, not under Loop
    -- guards: it does not break a loop, it opts OUT of the fix that stops one.
    checks.add {type = "checkbox", name = PULL_CONNECTIONS_OPT.element, state = false,
        caption = {"gui-etech-hub." .. PULL_CONNECTIONS_OPT.loc},
        tooltip = {"gui-etech-hub." .. PULL_CONNECTIONS_OPT.loc .. "-tooltip"}}
    pull.add {type = "label", name = "quality_label",
        caption = {"gui-etech-hub.min-quality"},
        tooltip = {"gui-etech-hub.min-quality-tooltip"}}
    pull.add {type = "drop-down", name = "etech-hub-min-quality",
        tooltip = {"gui-etech-hub.min-quality-tooltip"}}
    pull.add {type = "drop-down", name = "etech-hub-mode", items = MODE_ITEMS}
    local slots = pull.add {type = "table", name = "filter_slots", column_count = FILTER_COLUMNS}
    for i = 1, FILTER_SLOTS do
        slots.add {type = "choose-elem-button", name = "etech-hub-filter-" .. i,
            elem_type = "item-with-quality"}
    end
    pull.add {type = "checkbox", name = "etech-hub-match-quality", state = false,
        caption = {"gui-etech-hub.match-quality"},
        tooltip = {"gui-etech-hub.match-quality-tooltip"}}
    pull.add {type = "checkbox", name = CIRCUIT_FILTER_OPT.element, state = false,
        caption = {"gui-etech-hub." .. CIRCUIT_FILTER_OPT.loc},
        tooltip = {"gui-etech-hub." .. CIRCUIT_FILTER_OPT.loc .. "-tooltip"}}

    pull.add {type = "line", name = "guard_sep"}
    pull.add {type = "label", name = "guards_label",
        caption = {"gui-etech-hub.loop-guards"},
        tooltip = {"gui-etech-hub.loop-guards-tooltip"}}
    local gchecks = pull.add {type = "flow", name = "guard_checks", direction = "vertical"}
    for _, guard in ipairs(GUARD_CHECKS) do
        gchecks.add {type = "checkbox", name = guard.element, state = false,
            caption = {"gui-etech-hub." .. guard.loc},
            tooltip = {"gui-etech-hub." .. guard.loc .. "-tooltip"}}
    end

    local factories_tab = tabs.add {type = "tab", caption = {"gui-etech-hub.tab-factories"}}
    local factories = tabs.add {type = "flow", name = "factories", direction = "vertical"}
    tabs.add_tab(factories_tab, factories)
    factories.add {type = "label", name = "factories_label",
        caption = {"gui-etech-hub.factories"}}
    -- Scrolling 153 rows to find one factory is the real problem with listing
    -- them all; this narrows by name or by coordinate, and narrowing also means
    -- fewer rows get built.
    local fsearch = factories.add {type = "textfield", name = "etech-hub-factory-search"}
    fsearch.style.horizontally_stretchable = true
    local fscroll = factories.add {type = "scroll-pane", name = "fscroll"}
    -- Taller than the stock pane's 640 ON PURPOSE. The panel is as tall as
    -- its tallest tab, and the stock tab carries a search box and two
    -- dropdowns ABOVE its pane, so matching 640 here left a band of empty
    -- frame under the factory list exactly that header's height. This tab has
    -- only a search box, so it gets 640 plus the difference.
    fscroll.style.minimal_height = 420
    fscroll.style.maximal_height = 730
    fscroll.style.vertically_stretchable = true
    -- NOT horizontally stretchable. This tab's rows are what give the panel
    -- its width; stretching the pane instead let it shrink to the tabbed
    -- pane's own width and put a horizontal scrollbar under the factory list.
    fscroll.add {type = "table", name = "frows", column_count = 4}

    return panel
end

local refresh_factory_rows

-- Only the factory rows, so typing in the search box does not tear down and
-- rebuild the whole panel on every keystroke.
refresh_factory_rows = function(player, record)
    local panel = player.gui.relative[PANEL_NAME]
    if not panel then return end
    local factories = panel.inner.etech_tabs.factories
    local rows = factories.fscroll.frows
    rows.clear()
    local search = factories["etech-hub-factory-search"].text:lower()
    for _, factory in pairs(cached_factories(record)) do
        if factory_usable(factory) then
            local label = factory_label(factory.id)
            local position = factory.building.position
            local text = (type(label) == "string" and label or "")
                .. " " .. string.format("%.0f %.0f", position.x, position.y)
            if search == "" or text:lower():find(search, 1, true)
                or (type(label) ~= "string"
                    and tostring(factory.id):find(search, 1, true)) then
                local btn = rows.add {type = "button", caption = {"gui-etech-hub.locate"}}
                btn.style.minimal_width = 50
                btn.tags = { etech = "factory-locate", id = factory.id }
                local enter = rows.add {type = "button", caption = {"gui-etech-hub.enter"},
                    tooltip = {"gui-etech-hub.enter-tooltip"}}
                enter.style.minimal_width = 50
                enter.tags = { etech = "factory-enter", id = factory.id }
                local cell = rows.add {type = "flow", direction = "horizontal"}
                for _, signal in ipairs(factory_overlay_signals(factory, FACTORY_OVERLAY_ICONS)) do
                    local sprite = signal.type .. "/" .. signal.name
                    if signal.type == "virtual" then sprite = "virtual-signal/" .. signal.name end
                    if helpers.is_valid_sprite_path(sprite) then
                        local icon = cell.add {type = "sprite", sprite = sprite}
                        icon.style.size = 24
                    end
                end
                local name = cell.add {type = "label", caption = {"gui-etech-hub.factory-option",
                    label,
                    string.format("%.0f", position.x),
                    string.format("%.0f", position.y)}}
                name.style.minimal_width = 130
                local field = rows.add {type = "textfield",
                    text = hub_data().factory_names[factory.id] or "",
                    tooltip = {"gui-etech-hub.factory-rename-tooltip"}}
                field.tags = { etech = "factory-name", id = factory.id }
                field.style.horizontally_stretchable = true
            end
        end
    end
end

local function load_panel_settings(player, record)
    local panel = build_panel(player)
    local tabs = panel.inner.etech_tabs
    local pull, factories = tabs.settings, tabs.factories
    -- The panel is rebuilt from scratch on open and whenever a toggle changes
    -- what the other widgets should look like, so the tab has to be restored or
    -- ticking a Settings checkbox would throw you back to the stock list.
    tabs.selected_tab_index = math.min(record.panel_tab or 1, 3)
    pull.checks["etech-hub-storage"].state = record.pull_storage == true
    pull["etech-hub-mode"].selected_index = record.filters.mode or 1
    local g = guards(record)
    local from_circuit = g[CIRCUIT_FILTER_OPT.field] == true
    for i = 1, FILTER_SLOTS do
        local btn = pull.filter_slots["etech-hub-filter-" .. i]
        btn.elem_value = filter_elem_value(record.filters.items[i])
        btn.tooltip = filter_slot_tooltip(record.filters.items[i])
        -- the slots are not what the outlet reads while the circuit drives the
        -- filter list; greyed out beats silently ignored
        btn.enabled = not from_circuit
    end
    -- Built from the prototypes rather than hardcoded, so modded tiers appear
    -- and a game with no quality mod just shows "Any".
    local qualities, quality_names = {{"gui-etech-hub.min-quality-any"}}, {}
    local sorted = {}
    for name, proto in pairs(prototypes.quality) do
        if not proto.hidden then sorted[#sorted + 1] = {name = name, proto = proto} end
    end
    table.sort(sorted, function(a, b)
        if a.proto.level ~= b.proto.level then return a.proto.level < b.proto.level end
        return a.name < b.name
    end)
    local chosen = 1
    for i, entry in ipairs(sorted) do
        quality_names[i] = entry.name
        qualities[i + 1] = entry.proto.localised_name
        if entry.name == record.min_quality then chosen = i + 1 end
    end
    record.quality_names = quality_names
    local quality_picker = pull["etech-hub-min-quality"]
    quality_picker.items = qualities
    quality_picker.selected_index = chosen
    pull["etech-hub-match-quality"].state = record.filters.match_quality == true
    pull[CIRCUIT_FILTER_OPT.element].state = from_circuit
    for _, guard in ipairs(GUARD_CHECKS) do
        pull.guard_checks[guard.element].state = g[guard.field] == true
    end

    refresh_factory_rows(player, record)

    local usable = {}
    for _, factory in pairs(cached_factories(record)) do
        if factory_usable(factory) then usable[#usable + 1] = factory end
    end

    -- The factory dropdown lists every factory regardless of the row search:
    -- it filters the STOCK grid, and narrowing that should not depend on what
    -- happens to be typed in the Factories tab.
    -- is mapped back to a factory id through grid_factory_ids rather than by
    -- position: the list can change between opening the panel and clicking, and
    -- an index into a stale list would silently filter by the wrong factory.
    -- Names alone are not enough to pick from: a list of backer names tells you
    -- nothing about WHICH building on the map you are filtering to. The
    -- building's coordinates do. Not a [gps=] tag - those render as a clickable
    -- chat link, not as text, and a dropdown row is neither.
    local ids = {}
    local labels = {{"gui-etech-hub.factory-filter-all"}}
    for _, factory in ipairs(usable) do
        ids[#ids + 1] = factory.id
        local position = factory.building.position
        labels[#labels + 1] = {"gui-etech-hub.factory-option",
            factory_label(factory.id),
            string.format("%.0f", position.x),
            string.format("%.0f", position.y)}
    end
    record.grid_factory_ids = ids
    local picker = tabs.contents.views["etech-hub-factory"]
    picker.items = labels
    local selected = 1
    for i, id in ipairs(ids) do
        if id == record.grid_factory then selected = i + 1 end
    end
    if selected == 1 then record.grid_factory = nil end
    picker.selected_index = selected
    tabs.contents.views["etech-hub-sort"].selected_index = record.grid_sort or 1

end

-- Search used to compare the INTERNAL name only, so "iron plate" found nothing
-- and you had to know the string was "iron-plate". Both are matched now: the
-- internal name (still useful, and what a modded item is often only findable
-- by) and the translated display name.
--
-- Translation is per player and asynchronous in 2.x, so
-- prototypes.item[x].localised_name cannot simply be read as a string here.
-- helpers.is_valid_sprite_path-style shortcuts do not exist for names either.
-- What DOES work without a translation round trip is the prototype's own
-- `name` plus the hyphen-stripped form, which covers the case that actually
-- bites - a space typed where the internal name has a hyphen.
local function item_search_match(name, search)
    local lowered = name:lower()
    if lowered:find(search, 1, true) then return true end
    return (lowered:gsub("%-", " ")):find(search, 1, true) ~= nil
end

local function refresh_grid(player, record)
    local panel = player.gui.relative[PANEL_NAME]
    if not panel then return end
    local inner = panel.inner
    -- rate line carries the pause reason — "0/min" with no explanation
    -- looked broken whenever a circuit gated the outlet off
    local rate_caption = {"gui-etech-hub.rate", rate_per_minute(record)}
    local inside = inside_per_minute(record)
    if inside > 0 then
        rate_caption = {"", rate_caption, "  ", {"gui-etech-hub.rate-inside", inside}}
    end
    if not circuit_enabled(record) then
        rate_caption = {"", rate_caption, " ", {"gui-etech-hub.paused-circuit"}}
    end
    inner.rate.caption = rate_caption

    local contents = inner.etech_tabs.contents
    local search = contents["etech-hub-search"].text:lower()
    local scroll = contents.scroll

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
    local rates = rates_by_key(record)
    local only = record.grid_factory
    local list = {}
    for _, t in pairs(order) do
        -- Filtered to one factory, the number on the button becomes THAT
        -- factory's count. Showing the surface-wide total while claiming to
        -- show one factory would be worse than not filtering at all. `t` is
        -- rebuilt every refresh, so overwriting it here is safe.
        local visible = only and t.per[only] or t.count
        if visible and visible > 0
            and (search == "" or item_search_match(t.name, search)) then
            t.count = visible
            t.pinned = pins[item_key(t.name, t.quality)] == true
            t.rate = rates[item_key(t.name, t.quality)] or 0
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
        record.grid_snapshot = nil
        scroll.clear()
        scroll.add {type = "label", caption = msg}
        return
    end
    -- Pins always win, whatever the sort: the point of pinning is that the item
    -- stays where you can see it. Name is the final tiebreak everywhere so the
    -- order is total and stable rather than whatever table.sort happens to do
    -- with equal elements.
    local sort_mode = record.grid_sort or 1
    table.sort(list, function(a, b)
        if a.pinned ~= b.pinned then return a.pinned end
        if sort_mode == 2 then
            if a.name ~= b.name then return a.name < b.name end
        elseif sort_mode == 3 then
            if a.rate ~= b.rate then return a.rate > b.rate end
            if a.count ~= b.count then return a.count > b.count end
        else
            if a.count ~= b.count then return a.count > b.count end
        end
        if a.name ~= b.name then return a.name < b.name end
        return a.quality < b.quality
    end)

    -- Dirty check, same trick the sensor uses. Tearing down and rebuilding
    -- every button every 2 s profiled at up to 13 ms once a big factory set was
    -- in play, and most refreshes show exactly what the last one did. Only the
    -- rate label above (already updated) changes every pass.
    --
    -- The signature covers what a BUTTON shows - sprite, count, pin state - and
    -- the search term. It does not cover which factory holds what, so a stack
    -- moving between two factories without changing the total leaves the
    -- hover tooltip's breakdown up to one refresh stale. Cheap trade for not
    -- rebuilding the grid.
    local sig = {}
    for _, t in ipairs(list) do
        sig[#sig + 1] = t.name .. "|" .. t.quality .. "=" .. t.count .. (t.pinned and "*" or "")
    end
    -- View state joins the signature: change the factory filter or the sort and
    -- the item set or its order changes without any count changing, so without
    -- this the grid would keep showing the previous view.
    local snapshot = search .. "\0" .. tostring(only) .. "\0" .. sort_mode
        .. "\0" .. table.concat(sig, ";")
    if record.grid_snapshot == snapshot and scroll.grid and scroll.grid.valid then
        return
    end
    record.grid_snapshot = snapshot

    scroll.clear()
    local rates = rates_by_key(record)
    local grid = scroll.add {type = "table", name = "grid", column_count = STOCK_COLUMNS}
    for _, t in ipairs(list) do
        local lines = {"", t.name}
        if t.quality ~= "normal" then
            lines[#lines + 1] = " (" .. t.quality .. ")"
        end
        -- What this ITEM moved in the last minute, not what the device moved.
        -- Only shown when it is nonzero: a line of zeroes on every idle item
        -- would bury the handful that are actually flowing.
        local rate = rates[item_key(t.name, t.quality)]
        if rate and rate > 0 then
            lines[#lines + 1] = {"", "\n", {"gui-etech-hub.item-rate", rate}}
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
    inner.add {type = "checkbox", name = SPOILAGE_OPT.element,
        state = guards(record)[SPOILAGE_OPT.field] == true,
        caption = {"gui-etech-hub." .. SPOILAGE_OPT.loc},
        tooltip = {"gui-etech-hub." .. SPOILAGE_OPT.loc .. "-tooltip"}}

    -- Filter widgets (0.19.0 inlet parity): same element names as the
    -- outlet panel, so the shared name-based GUI handlers cover both.
    inner.add {type = "line", name = "sep"}
    inner.add {type = "label", name = "settings_label",
        caption = {"gui-etech-hub.inlet-filter"}}
    local mode = inner.add {type = "drop-down", name = "etech-hub-mode", items = MODE_ITEMS}
    mode.selected_index = record.filters and record.filters.mode or 1
    local slots = inner.add {type = "table", name = "filter_slots", column_count = FILTER_COLUMNS}
    for i = 1, FILTER_SLOTS do
        local btn = slots.add {type = "choose-elem-button", name = "etech-hub-filter-" .. i,
            elem_type = "item-with-quality"}
        btn.elem_value = record.filters and filter_elem_value(record.filters.items[i])
        btn.tooltip = record.filters and filter_slot_tooltip(record.filters.items[i])
    end
    inner.add {type = "checkbox", name = "etech-hub-match-quality",
        state = record.filters and record.filters.match_quality == true,
        caption = {"gui-etech-hub.match-quality"},
        tooltip = {"gui-etech-hub.match-quality-tooltip"}}

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

-- GUI: sensor panel ----------------------------------------------------------
-- The sensor broadcast everything it could see until 0.23.0, top 1000 by count.
-- On a real base that is a wall of signals nobody wired anything to. It gets the
-- same filter widgets as the outlet and inlet — same element names, so the
-- shared handlers already cover it — plus its two own options.

local SENSOR_PANEL_NAME = "etech-sensor-panel"

local SENSOR_OPTIONS = {
    {element = "etech-hub-sensor-storage",  field = "sensor_storage",  loc = "sensor-storage"},
    {element = "etech-hub-sensor-deficits", field = "sensor_deficits", loc = "sensor-deficits"},
}
for _, opt in ipairs(SENSOR_OPTIONS) do GUARD_BY_ELEMENT[opt.element] = opt end

local function build_sensor_panel(player, record)
    local old = player.gui.relative[SENSOR_PANEL_NAME]
    if old then old.destroy() end
    local panel = player.gui.relative.add {
        type = "frame",
        name = SENSOR_PANEL_NAME,
        direction = "vertical",
        caption = {"gui-etech-hub.sensor-title"},
        anchor = {
            gui = defines.relative_gui_type.constant_combinator_gui,
            position = defines.relative_gui_position.right,
            names = {SENSOR_NAME},
        },
    }
    local inner = panel.add {
        type = "frame",
        name = "inner",
        style = "inside_shallow_frame_with_padding",
        direction = "vertical",
    }
    for _, opt in ipairs(SENSOR_OPTIONS) do
        inner.add {type = "checkbox", name = opt.element,
            state = guards(record)[opt.field] == true,
            caption = {"gui-etech-hub." .. opt.loc},
            tooltip = {"gui-etech-hub." .. opt.loc .. "-tooltip"}}
    end
    inner.add {type = "line", name = "sep"}
    inner.add {type = "label", name = "settings_label",
        caption = {"gui-etech-hub.sensor-filter"}}
    local mode = inner.add {type = "drop-down", name = "etech-hub-mode", items = MODE_ITEMS}
    mode.selected_index = record.filters and record.filters.mode or 1
    local slots = inner.add {type = "table", name = "filter_slots", column_count = FILTER_COLUMNS}
    for i = 1, FILTER_SLOTS do
        local btn = slots.add {type = "choose-elem-button", name = "etech-hub-filter-" .. i,
            elem_type = "item-with-quality"}
        btn.elem_value = record.filters and filter_elem_value(record.filters.items[i])
        btn.tooltip = record.filters and filter_slot_tooltip(record.filters.items[i])
    end
    inner.add {type = "checkbox", name = "etech-hub-match-quality",
        state = record.filters and record.filters.match_quality == true,
        caption = {"gui-etech-hub.match-quality"},
        tooltip = {"gui-etech-hub.match-quality-tooltip"}}
end

-- GUI: export rule panel ------------------------------------------------------
-- Deliberately small. The item list is the device's own signal list, edited in
-- the vanilla window this sits beside, so the only thing missing is what that
-- list MEANS.

local EXPORT_PANEL_NAME = "etech-export-filter-panel"

local EXPORT_MODE_ITEMS = {
    {"gui-etech-hub.export-mode-off"},
    {"gui-etech-hub.export-mode-only"},
    {"gui-etech-hub.export-mode-block"},
}

local function build_export_panel(player, record)
    local old_panel = player.gui.relative[EXPORT_PANEL_NAME]
    if old_panel then old_panel.destroy() end
    local panel = player.gui.relative.add {
        type = "frame",
        name = EXPORT_PANEL_NAME,
        direction = "vertical",
        caption = {"gui-etech-hub.export-title"},
        anchor = {
            gui = defines.relative_gui_type.constant_combinator_gui,
            position = defines.relative_gui_position.right,
            names = {EXPORT_FILTER_NAME},
        },
    }
    local inner = panel.add {
        type = "frame", name = "inner",
        style = "inside_shallow_frame_with_padding", direction = "vertical",
    }
    local label = inner.add {type = "label", name = "export_help",
        caption = {"gui-etech-hub.export-help"}}
    label.style.single_line = false
    label.style.maximal_width = 260
    local mode = inner.add {type = "drop-down", name = "etech-hub-export-mode",
        items = EXPORT_MODE_ITEMS,
        tooltip = {"gui-etech-hub.export-mode-tooltip"}}
    mode.selected_index = record.filters.mode or 1
end

-- GUI: fluid outlet panel --------------------------------------------------------

local FLUID_PANEL_NAME = "etech-fluid-panel"

-- The "what's inside" grid: one button per interior fluid with the total
-- amount; clicking one sets it as the pull pick.
local function refresh_fluid_panel(player, record)
    local panel = player.gui.relative[FLUID_PANEL_NAME]
    if not panel then return end
    local inner = panel.inner
    local picker = inner["etech-fluid-filter"]
    if picker and picker.valid and picker.elem_value ~= record.fluid_filter then
        picker.elem_value = record.fluid_filter
    end
    -- A guarded outlet that has gone still looks identical to a broken one.
    -- Say which it is, the same way the item outlet reports its circuit pause.
    local note = inner.loop_note
    if note and note.valid then
        note.caption = record.fluid_looped and {"gui-etech-hub.fluid-paused-loop"} or ""
    end

    local scroll = inner.fscroll
    scroll.clear()
    local totals = interior_fluids(record)
    local list = {}
    for name, amount in pairs(totals) do
        list[#list + 1] = {name = name, amount = amount}
    end
    if #list == 0 then
        scroll.add {type = "label", caption = {"gui-etech-hub.fluid-none"}}
        return
    end
    table.sort(list, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.name < b.name
    end)
    local grid = scroll.add {type = "table", name = "fgrid", column_count = 5}
    for _, t in ipairs(list) do
        local sprite = "fluid/" .. t.name
        if not helpers.is_valid_sprite_path(sprite) then sprite = "utility/questionmark" end
        local btn = grid.add {
            type = "sprite-button",
            sprite = sprite,
            number = math.floor(t.amount),
            style = "slot_button",
            tooltip = {"gui-etech-hub.fluid-stock-tooltip", t.name, math.floor(t.amount)},
        }
        btn.toggled = record.fluid_filter == t.name
        btn.tags = { etech = "fluid-pick", name = t.name }
    end
end

-- Small relative panel next to the fluid outlet's tank GUI: the pull pick
-- (a fluid choose-elem-button) plus a live view of every fluid inside the
-- reachable factories with total amounts. Storage tanks in 2.x open the
-- unified pipe/fluid GUI (relative_gui_type.pipe_gui) and have no filter
-- slot of their own.
local function build_fluid_panel(player, record)
    local old = player.gui.relative[FLUID_PANEL_NAME]
    if old then old.destroy() end
    local panel = player.gui.relative.add {
        type = "frame",
        name = FLUID_PANEL_NAME,
        direction = "vertical",
        caption = {"gui-etech-hub.fluid-title"},
        anchor = {
            gui = defines.relative_gui_type.pipe_gui,
            position = defines.relative_gui_position.right,
            names = {FLUID_OUTLET_NAME},
        },
    }
    local inner = panel.add {
        type = "frame",
        name = "inner",
        style = "inside_shallow_frame_with_padding",
        direction = "vertical",
    }
    inner.add {type = "label", name = "filter_label",
        caption = {"gui-etech-hub.fluid-filter"},
        tooltip = {"gui-etech-hub.fluid-filter-tooltip"}}
    local btn = inner.add {type = "choose-elem-button", name = "etech-fluid-filter",
        elem_type = "fluid", tooltip = {"gui-etech-hub.fluid-filter-tooltip"}}
    btn.elem_value = record.fluid_filter
    inner.add {type = "checkbox", name = FLUID_GUARD.element,
        state = guards(record)[FLUID_GUARD.field] == true,
        caption = {"gui-etech-hub." .. FLUID_GUARD.loc},
        tooltip = {"gui-etech-hub." .. FLUID_GUARD.loc .. "-tooltip"}}
    inner.add {type = "label", name = "loop_note", caption = ""}
    inner.add {type = "label", name = "stock_label",
        caption = {"gui-etech-hub.fluid-stock"}}
    local scroll = inner.add {type = "scroll-pane", name = "fscroll"}
    scroll.style.maximal_height = 300
    refresh_fluid_panel(player, record)
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
    if not (kind == "outlet" or kind == "inlet" or kind == "sensor"
        or kind == "fluid-outlet" or kind == "export-filter") then return end
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
    elseif kind == "inlet" then
        build_inlet_panel(player, record)
        refresh_inlet_panel(player, record)
    elseif kind == "sensor" then
        build_sensor_panel(player, record)
    elseif kind == "export-filter" then
        build_export_panel(player, record)
    else
        build_fluid_panel(player, record)
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
    local name = event.element.name
    if name == "etech-hub-factory" or name == "etech-hub-sort" then
        local record = open_record(event.player_index)
        local player = game.get_player(event.player_index)
        if not (record and player) then return end
        if name == "etech-hub-sort" then
            record.grid_sort = event.element.selected_index
        else
            local index = event.element.selected_index
            record.grid_factory = index > 1 and (record.grid_factory_ids or {})[index - 1] or nil
        end
        refresh_grid(player, record)
        return
    end
    if name == "etech-hub-export-mode" then
        local record = open_record(event.player_index)
        if record then record.filters.mode = event.element.selected_index end
        return
    end
    if name == "etech-hub-min-quality" then
        local record = open_record(event.player_index)
        if not record then return end
        local index = event.element.selected_index
        record.min_quality = index > 1 and (record.quality_names or {})[index - 1] or nil
        return
    end
    if name ~= "etech-hub-mode" then return end
    local record = open_record(event.player_index)
    if record then
        record.filters.mode = event.element.selected_index
        -- the sensor only rewrites its section when its totals change, and a
        -- filter change alters them without anything in the world moving
        record.sensor_snapshot = nil
    end
end

local function on_gui_elem_changed(event)
    if not (event.element and event.element.valid) then return end
    local record = open_record(event.player_index)
    if not record then return end
    if event.element.name == "etech-fluid-filter" then
        record.fluid_filter = event.element.elem_value
        local player = game.get_player(event.player_index)
        if player then refresh_fluid_panel(player, record) end
        return
    end
    local slot = event.element.name:match("^etech%-hub%-filter%-(%d+)$")
    if slot then
        record.filters.items[tonumber(slot)] = event.element.elem_value
        record.sensor_snapshot = nil
    end
end

local function on_gui_checked_state_changed(event)
    if not (event.element and event.element.valid) then return end
    local name = event.element.name
    local record = open_record(event.player_index)
    if not record then return end
    if name == "etech-hub-storage" then
        record.pull_storage = event.element.state
    elseif name == "etech-hub-match-quality" then
        record.filters.match_quality = event.element.state
        record.sensor_snapshot = nil
    elseif name == "etech-inlet-auto" then
        record.auto_request = event.element.state
        if not record.auto_request then
            update_inlet_auto_requests(record, nil) -- clear the managed section
        end
    else
        local guard = GUARD_BY_ELEMENT[name]
        if guard then
            guards(record)[guard.field] = event.element.state or nil
            record.sensor_snapshot = nil
            -- the demand scan is cached for REQUESTER_TTL and the ignore-inlet
            -- guard changes what that scan returns: drop it so the toggle takes
            -- effect on the next pass instead of up to 4 s later
            record.requester_cache = nil
            -- this one changes whether the filter slots are live, so the panel
            -- has to be rebuilt to grey them (invalidates event.element)
            if guard == CIRCUIT_FILTER_OPT and record.kind == "outlet" then
                local player = game.get_player(event.player_index)
                if player then
                    load_panel_settings(player, record)
                    refresh_grid(player, record)
                end
            end
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
    elseif element.name == "etech-hub-factory-search" then
        local player = game.get_player(event.player_index)
        if player then refresh_factory_rows(player, record) end
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

    if tags.etech == "fluid-pick" then
        -- clicking a stock button toggles it as the pull pick
        record.fluid_filter = (record.fluid_filter ~= tags.name) and tags.name or nil
        refresh_fluid_panel(player, record)
        return
    end

    if tags.etech == "item" then
        if event.button == defines.mouse_button_type.right then
            record.pins = record.pins or {}
            local key = item_key(tags.name, tags.quality)
            record.pins[key] = not record.pins[key] or nil
            refresh_grid(player, record)
        elseif event.alt then
            request_item(player, tags.name, tags.quality)
        elseif event.control then
            take_item(player, record, tags.name, tags.quality, true)
            refresh_grid(player, record)
        elseif event.shift then
            take_item(player, record, tags.name, tags.quality)
            refresh_grid(player, record)
        else
            locate_item(player, record, tags.name, tags.quality)
        end
    elseif tags.etech == "factory-enter" then
        for _, factory in pairs(cached_factories(record)) do
            if factory.id == tags.id and factory_usable(factory) then
                -- Land just inside the door rather than on it, and let the
                -- engine pick a free tile: the doorway has the pole and the
                -- roboport either side of it.
                local inside = factory.inside_surface
                local target = inside.find_non_colliding_position("character",
                    { x = factory.inside_door_x or factory.inside_x,
                      y = (factory.inside_door_y or factory.inside_y) - 2 }, 8, 0.5)
                if target and player.teleport(target, inside) then
                    player.print({"gui-etech-hub.entered", factory_label(factory.id)})
                else
                    player.print({"gui-etech-hub.enter-failed"})
                end
                return
            end
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
                    guards = record.guards,
                    pull_storage = record.pull_storage,
                    auto_request = record.auto_request,
                    fluid_filter = record.fluid_filter,
                    min_quality = record.min_quality,
                })
            end
        end
    end
end

-- Copying an entity's settings with the copy tool (shift + right-click, then
-- shift + left-click) is a different code path from blueprinting, and until
-- 0.24.0 the hub only handled the blueprint one. Filters and every toggle
-- survived a blueprint and vanished on a copy-paste, which is the shape of
-- inconsistency you rediscover every time rather than remember.
local function on_entity_settings_pasted(event)
    local source, destination = event.source, event.destination
    if not (source and source.valid and destination and destination.valid) then return end
    local kind = KINDS[destination.name]
    -- Only between the same kind of device: an outlet's filters mean something
    -- different on a fluid outlet, and pasting a sensor onto an inlet should do
    -- nothing rather than something surprising.
    if not kind or KINDS[source.name] ~= kind then return end
    local hubs = hub_data().hubs
    local from = hubs[source.unit_number]
    if not from then return end
    local to = hubs[destination.unit_number] or register_device(destination)
    to.filters = table.deepcopy(from.filters)
    to.guards = table.deepcopy(from.guards or {})
    to.pins = table.deepcopy(from.pins or {})
    to.pull_storage = from.pull_storage
    to.auto_request = from.auto_request
    to.fluid_filter = from.fluid_filter
    to.min_quality = from.min_quality
    -- caches keyed to the OLD settings
    to.requester_cache = nil
    to.sensor_snapshot = nil
    to.grid_snapshot = nil
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
            elseif record.kind == "fluid-outlet" or record.kind == "fluid-inlet"
                or record.kind == "fluid-sensor" then
                fluids[#fluids + 1] = record
            elseif record.kind == "sensor" then
                sensors[#sensors + 1] = record
            end
            -- Anything else (the export filter) is passive configuration and
            -- gets no work pass at all. This used to be an `else` that swept
            -- every unrecognised kind into the sensor list, so the export
            -- filter was run as a sensor and had the player's item list
            -- overwritten with interior stock totals every two seconds - the
            -- rule looked empty no matter what you put in it.
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
    -- ONE budget covering both reasons to rescan. Until 0.21.1 a gen bump was
    -- exempt from the budget, so a single Factorissimo building placed or
    -- mined made every device rescan in the same tick: profiled at 66-76 ms
    -- per maintenance pass, once every 2 s, for as long as the player kept
    -- building. Devices that miss their turn keep a stale factory_gen and are
    -- simply first in line next pass - the hot paths tolerate a stale list
    -- (see cached_factories), so nothing has to happen this instant.
    local rescan_budget = 1
    local chest_budget = 2
    for _, group in pairs({ outlets, inlets, sensors, fluids or {} }) do
        for _, record in pairs(group) do
            local expired = tick - (record.scanned_tick or 0) >= RESCAN_TICKS - PULL_TICKS * 4
            if (record.factory_gen ~= gen or expired) and rescan_budget > 0 then
                rescan_budget = rescan_budget - 1
                record.factories = factories_for_hub(record.entity)
                record.scanned_tick = tick
                record.factory_gen = gen
            end
            if record.kind == "fluid-outlet" or record.kind == "fluid-inlet"
                or record.kind == "fluid-sensor" then
                reachable_tanks(record)
            elseif chest_cache_stale(record) and chest_budget > 0 then
                chest_budget = chest_budget - 1
                ensure_chest_cache(record, true)
            end
        end
    end
    for _, record in pairs(outlets) do
        surface_proxies(record.entity.surface, record.entity.force, true)
        gindex_resync(record.entity.surface, record.entity.force)
        -- Fit any factory that has not got a filter yet, and move one that an
        -- earlier version left elsewhere onto the fixed tile. Teleported, never
        -- rebuilt: the signal list is the rule. Driven from the OUTLET, so a
        -- surface with no outlet gets no devices it has no reader for.
        --
        -- TWO budgets, because the two jobs do not cost the same. Creating a
        -- device raises build events and registers a record, so it stays at
        -- two per pass and hundreds of factories spread the work. Moving one
        -- is a teleport of a collision-free entity - near free, and it only
        -- ever happens after a version changes the anchor, so rationing it at
        -- the same rate just meant a 200-factory base spent minutes visibly
        -- half-migrated (measured on Eli's save: 214 filters, ~3.5 min).
        local existing = export_filters_by_factory()
        local budget = 2
        local move_budget = 20
        for _, factory in pairs(cached_factories(record, false)) do
            if budget <= 0 and move_budget <= 0 then break end
            if factory_usable(factory) then
                local device = hub_data().hubs[existing[factory.id] or 0]
                local entity = device and device.entity
                if not (entity and entity.valid) then
                    if budget > 0 and ensure_export_filter(factory) then
                        budget = budget - 1
                    end
                else
                    local want = export_filter_position(factory)
                    local at = entity.position
                    if math.abs(at.x - want.x) > 0.01 or math.abs(at.y - want.y) > 0.01 then
                        entity.teleport(want)
                        budget = budget - 1
                    end
                end
            end
        end
    end

    -- drop proxy caches nothing refreshed for two lifetimes (outlet gone,
    -- surface deleted) so storage doesn't accumulate dead surface entries
    if data.proxies then
        for key, entry in pairs(data.proxies) do
            -- never drop one mid-sweep: entry.tick is the last COMPLETED
            -- sweep, so a slow in-progress scan would otherwise look stale
            if not entry.building and tick - entry.tick >= PROXY_TICKS * 2 then
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
                elseif record.kind == "fluid-outlet" then
                    refresh_fluid_panel(player, record)
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
    local outlets, inlets, sensors, fluids = collect_records()

    -- Outlets are scheduled PER DEVICE rather than all together on one phase.
    -- Each still pulls once every PULL_TICKS; they just no longer do it on the
    -- same tick as each other. Profiling a live base showed two outlets landing
    -- together turning a 9 ms pass into a 28 ms one - and because their caches
    -- were seeded at the same moment they also expired in lockstep, so the
    -- expensive uncached scan of BOTH outlets stacked on that one tick.
    --
    -- next_pull is seeded from unit_number at registration, so the spread is
    -- deterministic - identical on every client, unlike anything random.
    local due = {}
    for _, record in pairs(outlets) do
        if event.tick >= (record.next_pull or 0) then
            due[#due + 1] = record
            record.next_pull = event.tick + PULL_TICKS
        end
    end
    if #due > 0 then
        local pull_prof = data.profiling and helpers.create_profiler()
        for _, record in pairs(due) do pull_for_outlet(record) end
        if pull_prof then
            pull_prof.stop()
            helpers.write_file(PROFILE_FILE,
                {"", event.tick, ",pull-pass(outlets=", #due, "),", pull_prof, "\n"}, true)
        end
    end

    -- Phase 0 is now left free for outlet pulls; the other three keep their
    -- slots. collect_records above also sweeps records whose entity is gone.
    local prof = data.profiling and helpers.create_profiler()
    local label
    if phase == 1 then
        for _, record in pairs(inlets) do distribute_for_inlet(record) end
        for _, record in pairs(sensors) do update_sensor(record) end
        for _, record in pairs(fluids) do
            if record.kind == "fluid-outlet" then
                pass_for_fluid_outlet(record)
            elseif record.kind == "fluid-sensor" then
                update_fluid_sensor(record)
            else
                pass_for_fluid_inlet(record)
            end
        end
        label = "inlet-pass(inlets=" .. #inlets .. " sensors=" .. #sensors
            .. " fluids=" .. #fluids .. ")"
    elseif phase == 2 then
        maintenance_pass(outlets, inlets, sensors, fluids)
        label = "maintenance"
    elseif phase == 3 then
        refresh_open_guis()
        label = "gui-refresh"
    end
    if label and prof then
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
                    record.filters = record.filters
                        or { mode = 1, items = {}, match_quality = false }
                    -- loop guards (0.23.0): absent on older devices, and an
                    -- empty table is "every guard off" — no migration needed
                    record.guards = record.guards or {}
                    record.pins = record.pins or {}
                    -- Devices from before 0.21.1 have no schedule slot yet.
                    -- Seed the same way a fresh one would, so an existing save
                    -- gets the stagger without needing anything rebuilt.
                    record.next_pull = record.next_pull
                        or (game.tick + (entity.unit_number % 4) * SLOT_TICKS)
                    -- (The 0.17.0 legacy-field cleanup that lived here was
                    -- dropped in 0.21.1, per its own two-minor-version
                    -- policy. Those fields are never read, so any save still
                    -- carrying them is unaffected.)
                end
            end
        end
    end
    for _, player in pairs(game.players) do
        for _, panel_name in pairs({PANEL_NAME, INLET_PANEL_NAME, "etech-sensor-panel",
                                    "etech-fluid-panel", "etech-export-filter-panel"}) do
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
    [defines.events.on_entity_settings_pasted] = on_entity_settings_pasted,
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
