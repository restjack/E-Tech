-- factory-hub/control.lua
-- Runtime for the factory outlet / inlet / sensor (event_handler lib).
-- Every PULL_TICKS ticks:
--   outlet - teleports items out of the provider chests inside the
--            Factorissimo factories on its surface into itself (passive
--            provider), honoring per-item caps, per-hub filters and the
--            optional energy cost. Anything above the cap goes back.
--   inlet  - distributes its own contents into the requester/buffer chests
--            inside those factories, up to their request targets.
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
local PULL_TICKS = 120     -- work pass per device, every 2 s (also GUI refresh)
local RESCAN_TICKS = 600   -- factory-list cache lifetime, 10 s
local MAX_DEPTH = 5        -- nested-factory recursion limit
local FILTER_SLOTS = 10
local RATE_WINDOW = 3600   -- ticks of pull history for the items/min stat
local MAX_SIGNALS = 1000   -- constant combinator section limit

local KINDS = {
    [OUTLET_NAME] = "outlet",
    [INLET_NAME] = "inlet",
    [SENSOR_NAME] = "sensor",
}

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

local function register_device(entity)
    hub_data().hubs[entity.unit_number] = {
        entity = entity,
        kind = KINDS[entity.name],
        filters = { mode = 1, items = {} },
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

-- Outlet: pull + overflow ------------------------------------------------------

-- Move items from one provider chest into the outlet, at most cap_stacks
-- stacks of each item+quality in the outlet at a time. Slot-by-slot via
-- LuaItemStack so spoilage, ammo, durability and quality all survive.
-- Returns moved count; sets state.full when the outlet is completely full.
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

-- Insert a whole LuaItemStack into the first chests with room, preserving
-- spoilage/quality/ammo (mining return). Mutates the source stack down to
-- whatever couldn't be placed.
local function insert_stack_into_chests(chests, stack)
    for _, entry in pairs(chests) do
        if not stack.valid_for_read then break end
        local chest = entry.chest
        if chest.valid then
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

-- Insert `count` of a plain item spec into the first chests with room
-- (overflow return; spec-based, so spoil timers restart — overflow is
-- player-inserted stock, almost never spoilable). Returns number inserted.
local function insert_spec_into_chests(chests, name, quality, count)
    local total = 0
    for _, entry in pairs(chests) do
        local remaining = count - total
        if remaining <= 0 then break end
        local chest = entry.chest
        if chest.valid then
            local inv = chest.get_inventory(defines.inventory.chest)
            if inv then
                total = total + inv.insert({name = name, count = remaining, quality = quality})
            end
        end
    end
    return total
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

local function pull_for_outlet(record)
    local hub = record.entity
    local hub_inv = hub.get_inventory(defines.inventory.chest)
    if not hub_inv then return end

    local chests = reachable_chests(record, provider_mode)
    if #chests == 0 then
        note_moved(record, 0)
        return
    end

    local counts = {}
    for _, item in pairs(hub_inv.get_contents()) do
        counts[item.name .. "|" .. (item.quality or "normal")] = item.count
    end

    local cap_stacks = cap_stacks_for(record)
    return_overflow(hub_inv, chests, counts, cap_stacks)

    local set = filter_set(record)
    local state = { budget = energy_budget(record), full = false }
    local moved = 0
    for _, entry in pairs(chests) do
        if entry.chest.valid then
            moved = moved + drain_chest(entry.chest, hub_inv, counts, cap_stacks, record, set, state)
            if state.full or state.budget <= 0 then break end
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

local function distribute_for_inlet(record)
    local inlet = record.entity
    local inlet_inv = inlet.get_inventory(defines.inventory.chest)
    if not inlet_inv then return end

    local have = {}
    for _, item in pairs(inlet_inv.get_contents()) do
        have[item.name .. "|" .. (item.quality or "normal")] = item.count
    end
    if next(have) == nil then
        note_moved(record, 0)
        return
    end

    local targets = reachable_chests(record, requester_mode)
    local budget = energy_budget(record)
    local moved = 0
    for _, entry in pairs(targets) do
        if budget <= 0 then break end
        local chest = entry.chest
        if chest.valid then
            local wants = chest_requests(chest)
            if wants and next(wants) then
                local inv = chest.get_inventory(defines.inventory.chest)
                local current = {}
                for _, item in pairs(inv.get_contents()) do
                    current[item.name .. "|" .. (item.quality or "normal")] = item.count
                end
                for key, want in pairs(wants) do
                    local available = have[key] or 0
                    local deficit = want - (current[key] or 0)
                    local move = math.min(available, deficit, budget)
                    if move >= 1 then
                        local name, quality = key:match("^(.-)|(.*)$")
                        -- spec-based transfer: spoil timers restart (note in README)
                        local inserted = inv.insert({name = name, count = move, quality = quality})
                        if inserted > 0 then
                            inlet_inv.remove({name = name, count = inserted, quality = quality})
                            have[key] = available - inserted
                            moved = moved + inserted
                            budget = budget - inserted
                        end
                    end
                end
            end
        end
    end
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
        local name, quality = key:match("^(.-)|(.*)$")
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
        or { entity = entity, kind = kind, filters = { mode = 1, items = {} } }
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

-- GUI: panel next to the outlet's chest window --------------------------------

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
    scroll.style.maximal_height = 400

    inner.add {type = "line", name = "sep"}
    inner.add {type = "label", name = "settings_label",
        caption = {"gui-etech-hub.pull-settings"}}
    inner.add {type = "drop-down", name = "etech-hub-mode", items = MODE_ITEMS}
    local slots = inner.add {type = "table", name = "filter_slots", column_count = 5}
    for i = 1, FILTER_SLOTS do
        slots.add {type = "choose-elem-button", name = "etech-hub-filter-" .. i,
            elem_type = "item"}
    end
    local cap_flow = inner.add {type = "flow", name = "cap_flow", direction = "horizontal"}
    cap_flow.add {type = "label", name = "cap_label", caption = {"gui-etech-hub.cap-label"},
        tooltip = {"gui-etech-hub.cap-tooltip"}}
    local cap = cap_flow.add {type = "textfield", name = "etech-hub-cap",
        numeric = true, allow_decimal = false, allow_negative = false}
    cap.style.width = 50
    return panel
end

local function load_panel_settings(player, record)
    local panel = build_panel(player)
    local inner = panel.inner
    inner["etech-hub-mode"].selected_index = record.filters.mode or 1
    for i = 1, FILTER_SLOTS do
        inner.filter_slots["etech-hub-filter-" .. i].elem_value = record.filters.items[i]
    end
    inner.cap_flow["etech-hub-cap"].text = record.cap_override and tostring(record.cap_override) or ""
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
    for _, entry in pairs(reachable_chests(record, provider_mode)) do
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

    local list = {}
    for _, t in pairs(order) do
        if search == "" or t.name:lower():find(search, 1, true) then
            list[#list + 1] = t
        end
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
            lines[#lines + 1] = "\nFactory " .. factory_id .. ": " .. n
        end
        grid.add {
            type = "sprite-button",
            sprite = "item/" .. t.name,
            number = t.count,
            style = "slot_button",
            tooltip = lines,
        }
    end
end

local function open_record(player_index)
    local data = hub_data()
    local hub = data.open[player_index]
    if not (hub and hub.valid) then return nil end
    return data.hubs[hub.unit_number]
end

local function on_gui_opened(event)
    local entity = event.entity
    if not (entity and entity.valid and entity.name == OUTLET_NAME) then return end
    if not factorissimo_available() then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    hub_data().open[event.player_index] = entity
    local record = hub_data().hubs[entity.unit_number]
    if not record then
        register_device(entity)
        record = hub_data().hubs[entity.unit_number]
    end
    load_panel_settings(player, record)
    refresh_grid(player, record)
end

local function on_gui_closed(event)
    local entity = event.entity
    if entity and entity.valid and entity.name == OUTLET_NAME then
        hub_data().open[event.player_index] = nil
    end
end

local function on_gui_selection_state_changed(event)
    if event.element.name ~= "etech-hub-mode" then return end
    local record = open_record(event.player_index)
    if record then record.filters.mode = event.element.selected_index end
end

local function on_gui_elem_changed(event)
    local slot = event.element.name:match("^etech%-hub%-filter%-(%d+)$")
    if not slot then return end
    local record = open_record(event.player_index)
    if record then record.filters.items[tonumber(slot)] = event.element.elem_value end
end

local function on_gui_text_changed(event)
    local name = event.element.name
    local record = open_record(event.player_index)
    if not record then return end
    if name == "etech-hub-cap" then
        local n = tonumber(event.element.text)
        record.cap_override = (n and n >= 1) and math.floor(n) or nil
    elseif name == "etech-hub-search" then
        local player = game.get_player(event.player_index)
        if player then refresh_grid(player, record) end
    end
end

-- Tick dispatch ----------------------------------------------------------------

local function on_pull_tick()
    if not factorissimo_available() then return end
    local data = hub_data()
    for unit_number, record in pairs(data.hubs) do
        if record.entity.valid then
            if record.kind == "outlet" then
                pull_for_outlet(record)
            elseif record.kind == "inlet" then
                distribute_for_inlet(record)
            elseif record.kind == "sensor" then
                update_sensor(record)
            end
        else
            if record.companion and record.companion.valid then
                record.companion.destroy()
            end
            data.hubs[unit_number] = nil
        end
    end
    -- live refresh for anyone looking at an outlet
    for player_index, hub in pairs(data.open) do
        local player = game.get_player(player_index)
        if player and player.valid and hub.valid and player.opened == hub then
            local record = data.hubs[hub.unit_number]
            if record then refresh_grid(player, record) end
        else
            data.open[player_index] = nil
        end
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
            local factories = factories_for_hub(entity)
            record.factories, record.scanned_tick = factories, game.tick
            local accept = record.kind == "inlet" and requester_mode or provider_mode
            local chests = reachable_chests(record, accept)
            player.print(string.format(
                "[factory-outlet] %s #%d at %s (%.0f, %.0f): %d factories, %d chests, %d items/min, energy budget %s",
                record.kind, entity.unit_number, entity.surface.name,
                entity.position.x, entity.position.y,
                #factories, #chests, rate_per_minute(record),
                energy_per_item() > 0 and tostring(energy_budget(record)) or "off"))
            if record.kind == "outlet" then
                local hub_inv = entity.get_inventory(defines.inventory.chest)
                local counts = {}
                for _, item in pairs(hub_inv.get_contents()) do
                    counts[item.name .. "|" .. (item.quality or "normal")] = item.count
                end
                local cap_stacks = cap_stacks_for(record)
                local set = filter_set(record)
                local reported = {}
                local lines = 0
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
                end
            end
        end
    end
    for _, player in pairs(game.players) do
        local panel = player.gui.relative[PANEL_NAME]
        if panel then panel.destroy() end
    end
end

M.on_init = adopt_existing
M.on_configuration_changed = adopt_existing

M.add_commands = function()
    commands.add_command("etech-hub-debug",
        "Print factory outlet/inlet/sensor diagnostics", debug_command)
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
    [defines.events.on_gui_text_changed] = on_gui_text_changed,
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
