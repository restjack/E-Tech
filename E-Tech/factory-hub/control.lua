-- factory-hub/control.lua
-- Runtime for the factory provider hub (event_handler lib). Every PULL_TICKS
-- ticks each hub teleports items out of the provider chests inside the
-- Factorissimo factories on its own surface (recursing into nested
-- factories) and offers them to the local logistic network as a passive
-- provider. One-way by design, with two "return to factory" flows added in
-- 0.12.0: mining a hub sends its buffered items back into the factories
-- (you pick up an empty chest), and anything above the per-item cap
-- (e.g. player-inserted items) gets pushed back too.
--
-- Bots can't cross surfaces, so physically moving the items into an outside
-- chest is the only way to make them visible to the outside network — same
-- trick Factorissimo itself uses (in reverse) for its construction-bot
-- support.
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
local PANEL_NAME = "etech-hub-panel"
local PULL_TICKS = 120     -- pull pass per hub, every 2 s (also GUI refresh)
local RESCAN_TICKS = 600   -- factory-list cache lifetime, 10 s
local MAX_DEPTH = 5        -- nested-factory recursion limit

local function hub_data()
    storage.etech_factory_hub = storage.etech_factory_hub or { hubs = {}, open = {} }
    storage.etech_factory_hub.open = storage.etech_factory_hub.open or {}
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

-- Every provider chest a hub can currently reach (fresh scan, no cache) —
-- used by the pull pass, the mining return, and the GUI panel.
local function all_provider_chests(hub, factories)
    factories = factories or factories_for_hub(hub)
    local active_only = settings.global["etech-hub-active-only"].value
    local chests = {}
    for _, factory in pairs(factories) do
        if factory_usable(factory) then
            for _, chest in pairs(provider_chests(factory, hub.force, active_only)) do
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

-- Insert a whole LuaItemStack into the first chests with room, preserving
-- spoilage/quality/ammo (mining return). Mutates the source stack down to
-- whatever couldn't be placed. Returns the number moved.
local function insert_stack_into_chests(chests, stack)
    local moved = 0
    for _, chest in pairs(chests) do
        if not stack.valid_for_read then break end
        if chest.valid then
            local inv = chest.get_inventory(defines.inventory.chest)
            if inv then
                local inserted = inv.insert(stack)
                if inserted > 0 then
                    moved = moved + inserted
                    stack.count = stack.count - inserted -- reaching 0 clears the stack
                end
            end
        end
    end
    return moved
end

-- Insert `count` of a plain item spec into the first chests with room
-- (overflow return; spec-based, so spoil timers restart — overflow is
-- player-inserted stock, almost never spoilable). Returns number inserted.
local function insert_spec_into_chests(chests, name, quality, count)
    local total = 0
    for _, chest in pairs(chests) do
        local remaining = count - total
        if remaining <= 0 then break end
        if chest.valid then
            local inv = chest.get_inventory(defines.inventory.chest)
            if inv then
                total = total + inv.insert({name = name, count = remaining, quality = quality})
            end
        end
    end
    return total
end

-- Anything in the hub above the per-item cap (player-inserted items, or the
-- cap setting was lowered) goes back into the factories — the hub only ever
-- holds what it's willing to provide. Requester-chest-trash equivalent.
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

    local chests = all_provider_chests(hub, record.factories)
    if #chests == 0 then return end

    local counts = {}
    for _, item in pairs(hub_inv.get_contents()) do
        counts[item.name .. "|" .. (item.quality or "normal")] = item.count
    end

    local cap_stacks = settings.global["etech-hub-stacks-per-item"].value
    return_overflow(hub_inv, chests, counts, cap_stacks)
    for _, chest in pairs(chests) do
        if chest.valid then
            if not drain_chest(chest, hub_inv, counts, cap_stacks) then
                return -- hub full, done until bots make room
            end
        end
    end
end

-- Mining a hub: send its buffered items back into the factories' provider
-- chests so the player picks up just the chest. Whatever doesn't fit stays
-- in the mining buffer (player gets it, vanilla behavior).
local function on_mined(event)
    local entity = event.entity
    if not (entity and entity.valid and entity.name == HUB_NAME) then return end
    local buffer = event.buffer
    if not (buffer and factorissimo_available()) then return end
    local chests = all_provider_chests(entity)
    if #chests == 0 then return end
    for i = 1, #buffer do
        local stack = buffer[i]
        -- skip the hub item itself (and any hub items it was buffering)
        if stack.valid_for_read and stack.name ~= HUB_NAME then
            insert_stack_into_chests(chests, stack)
        end
    end
end

-- GUI: panel next to the hub's chest window listing what's sitting in the
-- provider chests inside the factories this hub reaches.
local function ensure_panel(player)
    local panel = player.gui.relative[PANEL_NAME]
    if panel then return panel end
    panel = player.gui.relative.add {
        type = "frame",
        name = PANEL_NAME,
        direction = "vertical",
        caption = {"gui-etech-hub.panel-title"},
        anchor = {
            gui = defines.relative_gui_type.container_gui,
            position = defines.relative_gui_position.right,
            names = {HUB_NAME},
        },
    }
    local inner = panel.add {
        type = "frame",
        name = "inner",
        style = "inside_shallow_frame_with_padding",
        direction = "vertical",
    }
    local scroll = inner.add {type = "scroll-pane", name = "scroll"}
    scroll.style.maximal_height = 520
    return panel
end

local function refresh_panel(player, hub)
    local scroll = ensure_panel(player).inner.scroll
    scroll.clear()

    local totals = {} -- item name -> count, qualities merged for display
    for _, chest in pairs(all_provider_chests(hub)) do
        local inv = chest.get_inventory(defines.inventory.chest)
        if inv then
            for _, item in pairs(inv.get_contents()) do
                totals[item.name] = (totals[item.name] or 0) + item.count
            end
        end
    end

    local list = {}
    for name, count in pairs(totals) do
        list[#list + 1] = {name = name, count = count}
    end
    if #list == 0 then
        scroll.add {type = "label", caption = {"gui-etech-hub.panel-empty"}}
        return
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)

    local grid = scroll.add {type = "table", name = "grid", column_count = 8}
    for _, e in ipairs(list) do
        grid.add {
            type = "sprite-button",
            sprite = "item/" .. e.name,
            number = e.count,
            style = "slot_button",
            elem_tooltip = {type = "item", name = e.name},
        }
    end
end

local function on_gui_opened(event)
    local entity = event.entity
    if not (entity and entity.valid and entity.name == HUB_NAME) then return end
    if not factorissimo_available() then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    hub_data().open[event.player_index] = entity
    refresh_panel(player, entity)
end

local function on_gui_closed(event)
    local entity = event.entity
    if entity and entity.valid and entity.name == HUB_NAME then
        hub_data().open[event.player_index] = nil
    end
end

local function on_pull_tick()
    if not factorissimo_available() then return end
    local data = hub_data()
    for unit_number, record in pairs(data.hubs) do
        if record.entity.valid then
            pull_for_hub(record)
        else
            data.hubs[unit_number] = nil
        end
    end
    -- live refresh for anyone looking at a hub
    for player_index, hub in pairs(data.open) do
        local player = game.get_player(player_index)
        if player and player.valid and hub.valid and player.opened == hub then
            refresh_panel(player, hub)
        else
            data.open[player_index] = nil
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
    [defines.events.on_player_mined_entity] = on_mined,
    [defines.events.on_robot_mined_entity] = on_mined,
    [defines.events.on_space_platform_mined_entity] = on_mined,
    [defines.events.on_gui_opened] = on_gui_opened,
    [defines.events.on_gui_closed] = on_gui_closed,
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
