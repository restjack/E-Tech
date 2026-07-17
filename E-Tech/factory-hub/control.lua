-- factory-hub/control.lua
-- Runtime for the factory provider hub (event_handler lib). Every PULL_TICKS
-- ticks each hub teleports items out of the provider chests inside the
-- Factorissimo factories on its own surface (recursing into nested
-- factories) and offers them to the local logistic network as a passive
-- provider. One-way: items only ever leave factories. Bots can't cross
-- surfaces, so physically moving the items into an outside chest is the only
-- way to make them visible to the outside network — same trick Factorissimo
-- itself uses (in reverse) for its construction-bot support.
--
-- Factorissimo internals used (verified against 3.12.2):
--   remote "factorissimo": get_factory_by_entity, has_layout,
--     is_factorissimo_surface, find_surrounding_factory_by_surface_index
--   factory table: building, inactive, built, inside_surface,
--     inside_x/inside_y, layout.inside_size
--   factory buildings are type "storage-tank" entities whose name passes
--     has_layout.

local M = {}

local HUB_NAME = "etech-factory-provider-hub"
local PULL_TICKS = 120     -- pull pass per hub, every 2 s
local RESCAN_TICKS = 600   -- factory-list cache lifetime, 10 s
local MAX_DEPTH = 5        -- nested-factory recursion limit

local function hub_data()
    storage.etech_factory_hub = storage.etech_factory_hub or { hubs = {} }
    return storage.etech_factory_hub
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

local function register_hub(entity)
    hub_data().hubs[entity.unit_number] = { entity = entity }
    script.register_on_object_destroyed(entity)
end

local function on_built(event)
    local entity = event.entity or event.destination
    if entity and entity.valid and entity.name == HUB_NAME then
        register_hub(entity)
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

-- Top-level factory buildings the hub can see. On a normal surface: every
-- factory on the surface. On a Factorissimo interior surface (hub placed
-- inside a factory): only factories within the surrounding factory's own
-- interior cell — interior surfaces are shared 8-wide grids of unrelated
-- factories and the hub must not reach across cells.
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
    end
    local out, visited = {}, {}
    collect_factories(candidates, hub.force, out, visited, 1)
    return out
end

local function provider_chests(factory, force, active_only)
    local chests = {}
    local found = factory.inside_surface.find_entities_filtered {
        area = factory_interior_area(factory),
        type = "logistic-container",
        force = force,
    }
    for _, chest in pairs(found) do
        if chest.name ~= HUB_NAME then -- never drain another hub (it serves ITS surface)
            local mode = chest.prototype.logistic_mode
            if mode == "active-provider" or (mode == "passive-provider" and not active_only) then
                chests[#chests + 1] = chest
            end
        end
    end
    return chests
end

-- Move items from one provider chest into the hub, at most `cap_stacks`
-- stacks of each item+quality in the hub at a time. Slot-by-slot via
-- LuaItemStack so spoilage, ammo, durability and quality all survive the
-- teleport. Returns false when the hub is completely full.
local function drain_chest(chest, hub_inv, counts, cap_stacks)
    local inv = chest.get_inventory(defines.inventory.chest)
    if not inv then return true end
    for i = 1, #inv do
        local stack = inv[i]
        if stack.valid_for_read then
            local key = stack.name .. "|" .. stack.quality.name
            local room = cap_stacks * stack.prototype.stack_size - (counts[key] or 0)
            if room >= 1 then
                local original = stack.count
                local move = math.min(room, original)
                if move < original then stack.count = move end
                local inserted = hub_inv.insert(stack)
                stack.count = original - inserted
                counts[key] = (counts[key] or 0) + inserted
                if inserted < move and hub_inv.count_empty_stacks() == 0 then
                    return false
                end
            end
        end
    end
    return true
end

local function pull_for_hub(record)
    local hub = record.entity
    local hub_inv = hub.get_inventory(defines.inventory.chest)
    if not hub_inv then return end

    local tick = game.tick
    if not record.factories or tick - (record.scanned_tick or 0) >= RESCAN_TICKS then
        record.factories = factories_for_hub(hub)
        record.scanned_tick = tick
    end
    if #record.factories == 0 then return end

    local counts = {}
    for _, item in pairs(hub_inv.get_contents()) do
        counts[item.name .. "|" .. (item.quality or "normal")] = item.count
    end

    local cap_stacks = settings.global["etech-hub-stacks-per-item"].value
    local active_only = settings.global["etech-hub-active-only"].value
    for _, factory in pairs(record.factories) do
        if factory_usable(factory) then
            for _, chest in pairs(provider_chests(factory, hub.force, active_only)) do
                if not drain_chest(chest, hub_inv, counts, cap_stacks) then
                    return -- hub full, done until bots make room
                end
            end
        end
    end
end

local function on_pull_tick()
    if not factorissimo_available() then return end
    local hubs = hub_data().hubs
    for unit_number, record in pairs(hubs) do
        if record.entity.valid then
            pull_for_hub(record)
        else
            hubs[unit_number] = nil
        end
    end
end

-- Mid-save enable / config change: adopt hubs that already exist in the
-- world but aren't registered (per-mod storage doesn't carry across
-- enable/disable cycles — same lesson as the voidchest port).
local function adopt_existing_hubs()
    local hubs = hub_data().hubs
    for _, surface in pairs(game.surfaces) do
        for _, entity in pairs(surface.find_entities_filtered {name = HUB_NAME}) do
            if not hubs[entity.unit_number] then
                register_hub(entity)
            end
        end
    end
end

M.on_init = adopt_existing_hubs
M.on_configuration_changed = adopt_existing_hubs

M.events = {
    [defines.events.on_built_entity] = on_built,
    [defines.events.on_robot_built_entity] = on_built,
    [defines.events.on_space_platform_built_entity] = on_built,
    [defines.events.script_raised_built] = on_built,
    [defines.events.script_raised_revive] = on_built,
    [defines.events.on_entity_cloned] = on_built,
    [defines.events.on_object_destroyed] = function(event)
        if event.useful_id then
            hub_data().hubs[event.useful_id] = nil
        end
    end,
}

M.on_nth_tick = {
    [PULL_TICKS] = on_pull_tick,
}

return M
