-- factory-hub/terminal.lua
-- The factory terminal: a toolbar shortcut that lists every factory
-- outlet/inlet/sensor on the surface you are standing on, with a button per
-- device that opens that device's own GUI from wherever you are. Written for
-- E-Tech (public domain). Registered from the root control.lua only when
-- Factorissimo, the factory-hub feature and the terminal toggle are all on.
--
-- HOW THE REMOTE OPEN WORKS. The outlet/inlet panels are RELATIVE GUIs
-- anchored to the entity's own container GUI (factory-hub/control.lua), so
-- there is nothing to "open" without opening the container itself - and the
-- engine range-checks that for a character controller.
--
-- The first implementation used Remote View (set_controller with
-- defines.controllers.remote), which is the 2.0-supported way to open a
-- distant entity. It worked, and it was wrong for this: remote view replaces
-- the player's inventory panel with the ghost-cursor palette, so the window
-- that opened beside the factory's contents was not the inventory you wanted
-- to move things into - which is most of the point of opening a chest.
--
-- So it does what the 1.1-era mods did after all: raise the character's REACH
-- for as long as the device GUI is open. The player stays in their body, the
-- normal inventory panel is right there, and the engine allows the ordinary
-- transfers (click, shift-click, drag) as well as the panel's own take
-- button. Only reach distance is touched - not build or resource reach - and
-- the previous value is put back exactly, rather than reset to a constant
-- that would silently eat another mod's bonus.
--
-- Reads control.lua's storage (storage.etech_factory_hub.hubs) but never
-- writes it: device records stay owned by control.lua, including cleanup of
-- invalid ones. This module's own state lives under its own key.

local OUTLET_NAME = "etech-factory-provider-hub"
local INLET_NAME = "etech-factory-inlet"
local SENSOR_NAME = "etech-factory-sensor"
local FLUID_OUTLET_NAME = "etech-factory-fluid-outlet"
local FLUID_INLET_NAME = "etech-factory-fluid-inlet"

local SHORTCUT = "etech-factory-terminal"
local TECH = "etech-factory-terminal"
local LINK = "etech-factory-link"

local FRAME = "etech-terminal-frame"
local CLOSE = "etech-terminal-close"
local INNER = "etech-terminal-inner"
local SCROLL = "etech-terminal-scroll"
local LIST = "etech-terminal-list"
local ENERGY = "etech-terminal-energy"

-- Energy off the factory link, in joules. The link holds 2 MJ, so a full
-- charge is a bit over half an hour of having the terminal open.
local OPEN_COST = 100000   -- 100 kJ to open the list
local UPKEEP = 20000       -- 20 kJ per refresh tick (= 20 kW while open)
local REFRESH_TICKS = 60

-- Devices that are worth a row, in list order.
local ROW_ORDER = {OUTLET_NAME, INLET_NAME, FLUID_OUTLET_NAME, FLUID_INLET_NAME, SENSOR_NAME}
local ROW_RANK = {}
for rank, name in ipairs(ROW_ORDER) do ROW_RANK[name] = rank end

-- Tables are ensured on every read, never assumed to have been created by a
-- migration: on_configuration_changed does not run when a save is reloaded
-- with a rebuild of the same mod version, which cost the teleporter module a
-- crash in 0.22.0.
local function terminal_data()
    local data = storage.etech_factory_terminal
    if not data then
        data = {}
        storage.etech_factory_terminal = data
    end
    data.open = data.open or {}
    -- Reach bonus held per player while a device GUI is open through the
    -- terminal, so it can be restored to exactly what it was.
    data.reach = data.reach or {}
    return data
end

-- control.lua's records, or an empty table before the first device is built.
local function device_records()
    local hub = storage.etech_factory_hub
    return (hub and hub.hubs) or {}
end

-- The player's factory link, or nil. Read from the character on purpose: the
-- whole point is that the suit you are wearing powers this.
local function find_link(player)
    local character = player.character
    local grid = character and character.valid and character.grid
    if not grid then return nil end
    return grid.find(LINK)
end

local function researched(player)
    local tech = player.force.technologies[TECH]
    return tech and tech.researched
end

-- Charge the link, or explain what is missing. Returns true when the caller
-- may proceed.
local function spend(player, amount, quiet)
    if not researched(player) then
        if not quiet then player.print({"gui-etech-terminal.not-researched"}) end
        return false
    end
    local link = find_link(player)
    if not link then
        if not quiet then player.print({"gui-etech-terminal.no-link"}) end
        return false
    end
    if link.energy < amount then
        if not quiet then player.print({"gui-etech-terminal.no-power"}) end
        return false
    end
    link.energy = link.energy - amount
    return true
end

local function get_frame(player)
    local frame = player.gui.screen[FRAME]
    if frame and frame.valid then return frame end
    return nil
end

-- Every container in the window is named, so the row table is reached by name
-- rather than by child index - index math breaks the moment a row is added.
local function get_list(frame)
    if not (frame and frame.valid) then return nil end
    local inner = frame[INNER]
    local scroll = inner and inner.valid and inner[SCROLL]
    local list = scroll and scroll.valid and scroll[LIST]
    if list and list.valid then return list end
    return nil
end

local function close_terminal(player)
    local frame = get_frame(player)
    if frame then frame.destroy() end
    terminal_data().open[player.index] = nil
end

-- Items moved in control.lua's rate window, rounded down to whole items.
local function rate_of(record)
    local total = 0
    for _, sample in pairs(record.moved_samples or {}) do
        total = total + (sample.moved or 0)
    end
    return math.floor(total)
end

local function status_of(record)
    if record.kind == "fluid-outlet" or record.kind == "fluid-inlet" then
        local fluid = record.fluid_filter
        if not fluid then return {"gui-etech-terminal.status-no-fluid"} end
        return {"gui-etech-terminal.status-fluid", fluid}
    end
    if record.kind == "sensor" then
        return {"gui-etech-terminal.status-sensor"}
    end
    local rate = rate_of(record)
    if rate > 0 then
        return {"gui-etech-terminal.status-rate", rate}
    end
    return {"gui-etech-terminal.status-idle"}
end

-- Every device record on this surface, sorted by kind then position so the
-- list does not reshuffle between refreshes.
local function rows_for(player)
    local surface = player.physical_surface or player.surface
    local rows = {}
    for unit_number, record in pairs(device_records()) do
        local entity = record.entity
        if entity and entity.valid and entity.surface == surface and ROW_RANK[entity.name] then
            rows[#rows + 1] = { unit_number = unit_number, record = record, entity = entity }
        end
    end
    table.sort(rows, function(a, b)
        local rank_a, rank_b = ROW_RANK[a.entity.name], ROW_RANK[b.entity.name]
        if rank_a ~= rank_b then return rank_a < rank_b end
        local pa, pb = a.entity.position, b.entity.position
        if pa.y ~= pb.y then return pa.y < pb.y end
        if pa.x ~= pb.x then return pa.x < pb.x end
        return a.unit_number < b.unit_number
    end)
    return rows
end

local function fill_rows(player, table_element)
    table_element.clear()
    local rows = rows_for(player)
    for _, row in ipairs(rows) do
        local entity = row.entity
        local position = entity.position
        table_element.add{
            type = "sprite-button",
            sprite = "entity/" .. entity.name,
            style = "slot_button",
            tooltip = prototypes.entity[entity.name].localised_name,
        }
        local label = table_element.add{
            type = "label",
            caption = {"gui-etech-terminal.row-position",
                string.format("%.0f", position.x), string.format("%.0f", position.y)},
        }
        label.style.minimal_width = 110
        table_element.add{type = "label", caption = status_of(row.record)}
        local open = table_element.add{
            type = "button",
            caption = {"gui-etech-terminal.open"},
            tags = {etech_terminal = "open", unit_number = row.unit_number},
            tooltip = {"gui-etech-terminal.open-tooltip"},
        }
        open.style.minimal_width = 80
    end
    if #rows == 0 then
        table_element.add{type = "label", caption = {"gui-etech-terminal.empty"}}
    end
    return #rows
end

local function refresh_energy_label(player, frame)
    local label = frame[ENERGY]
    if not (label and label.valid) then return end
    local link = find_link(player)
    local stored = link and link.energy or 0
    label.caption = {"gui-etech-terminal.energy", string.format("%.0f", stored / 1000)}
end

local function open_terminal(player)
    if get_frame(player) then
        close_terminal(player)
        return
    end
    if not spend(player, OPEN_COST) then return end

    local frame = player.gui.screen.add{type = "frame", name = FRAME, direction = "vertical"}
    frame.auto_center = true
    local title_flow = frame.add{type = "flow", direction = "horizontal"}
    title_flow.style.vertical_align = "center"
    local title = title_flow.add{type = "label", style = "frame_title", caption = {"gui-etech-terminal.title"}}
    title.drag_target = frame
    local pusher = title_flow.add{type = "empty-widget", style = "draggable_space_header"}
    pusher.style.horizontally_stretchable = true
    pusher.style.vertically_stretchable = true
    pusher.drag_target = frame
    title_flow.add{type = "sprite-button", name = CLOSE, style = "frame_action_button", sprite = "utility/close"}

    local inner = frame.add{type = "frame", name = INNER, style = "inside_shallow_frame_with_padding"}
    local scroll = inner.add{type = "scroll-pane", name = SCROLL, direction = "vertical"}
    scroll.style.maximal_height = (player.display_resolution.height / player.display_scale) * 0.6
    local list = scroll.add{type = "table", name = LIST, column_count = 4}
    list.style.horizontal_spacing = 8
    list.style.vertical_spacing = 4
    fill_rows(player, list)

    frame.add{type = "label", name = ENERGY}
    refresh_energy_label(player, frame)

    player.opened = frame
    terminal_data().open[player.index] = true
end

-- Open the device from where the player is standing, by TEMPORARILY EXTENDING
-- THEIR REACH rather than putting them in Remote View.
--
-- Remote View was the first implementation and it worked, but it swaps the
-- player's inventory panel for the ghost-cursor palette - so the window that
-- opened next to the device's contents was not the inventory you wanted to
-- drag things into, which is most of the point of opening a chest. Staying in
-- your body keeps the normal inventory panel, and with reach extended the
-- engine allows the ordinary transfers (click, shift-click, drag) as well.
--
-- Only reach distance is raised, not build or resource reach: this is meant to
-- let you handle a distant chest's contents, not to build or mine across the
-- base. The bonus is restored the moment the device GUI closes.
local function open_device(player, entity)
    local character = player.character
    if not (character and character.valid) then
        player.print({"gui-etech-terminal.no-character"})
        return
    end
    -- Same surface is guaranteed by the list (physical surface only), so a
    -- plain distance is all the reach that is needed, plus a margin.
    local dx = entity.position.x - character.position.x
    local dy = entity.position.y - character.position.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local data = terminal_data()
    data.reach[player.index] = character.character_reach_distance_bonus
    character.character_reach_distance_bonus = math.ceil(distance) + 8
    player.opened = entity
end

-- Put the reach bonus back exactly as it was. Anything else (another mod's
-- armor bonus, say) would be quietly stolen by writing a constant here.
local function restore_reach(player)
    local data = terminal_data()
    local previous = data.reach[player.index]
    if previous == nil then return end
    data.reach[player.index] = nil
    local character = player.character
    if character and character.valid then
        character.character_reach_distance_bonus = previous
    end
end

local function on_lua_shortcut(event)
    if event.prototype_name ~= SHORTCUT then return end
    local player = game.get_player(event.player_index)
    if player then open_terminal(player) end
end

local function on_gui_click(event)
    local element = event.element
    if not (element and element.valid) then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    if element.name == CLOSE then
        close_terminal(player)
        return
    end
    local tags = element.tags
    if not (tags and tags.etech_terminal == "open") then return end
    local record = device_records()[tags.unit_number]
    local entity = record and record.entity
    if not (entity and entity.valid) then
        player.print({"gui-etech-terminal.device-gone"})
        local list = get_list(get_frame(player))
        if list then fill_rows(player, list) end
        return
    end
    close_terminal(player)
    open_device(player, entity)
end

local function on_gui_closed(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local element = event.element
    if element and element.valid and element.name == FRAME then
        close_terminal(player)
        return
    end
    -- The device GUI we reached across the base for was closed: hand the
    -- player's reach back.
    if event.entity then restore_reach(player) end
end

-- While a terminal is open: refresh the rows (rates move) and bill the link.
-- A flat link closes the window rather than showing stale numbers for free.
local function on_refresh()
    local data = terminal_data()
    for player_index in pairs(data.open) do
        local player = game.get_player(player_index)
        local frame = player and get_frame(player)
        if not (player and frame) then
            data.open[player_index] = nil
        elseif not spend(player, UPKEEP, true) then
            close_terminal(player)
            player.print({"gui-etech-terminal.power-lost"})
        else
            local list = get_list(frame)
            if list then fill_rows(player, list) end
            refresh_energy_label(player, frame)
        end
    end
end

local terminal = {}

terminal.events =
{
    [defines.events.on_lua_shortcut] = on_lua_shortcut,
    [defines.events.on_gui_click] = on_gui_click,
    [defines.events.on_gui_closed] = on_gui_closed,
}

terminal.on_nth_tick =
{
    [REFRESH_TICKS] = on_refresh,
}

return terminal
