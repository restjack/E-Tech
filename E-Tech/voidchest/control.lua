-- voidchest/control.lua
-- Runtime half of the void chest/pipe port (prototypes in voidchest/data.lua,
-- gated by the etech-void startup setting). Void chests are infinity
-- containers set to remove everything; void pipes are infinity pipes drained
-- every 2 seconds. Mod storage does NOT carry over from the original Easy
-- Void mod (storage is per-mod), so init_voids rescans all surfaces on
-- init/configuration-changed — that is what migrates an existing save.
--
-- Returned as an event_handler lib (registered from control.lua).
-- Credits to JDOGG, Optera, kendfrey, Rseding91 for their original void mods.

-- Fluid voided by each pipe in the last drain pass, keyed by unit_number.
-- Shown as local flying text when a player hovers a void pipe. Kept in
-- storage (rebuilt from nothing on init; pruned with the pipe list).
local function pipe_stats()
    storage.etech_void_pipe_stats = storage.etech_void_pipe_stats or {}
    return storage.etech_void_pipe_stats
end

local function processPipes()
    local pipes = storage.pipes
    if pipes == nil then return end
    local stats = pipe_stats()
    -- compact-in-place: the old table.remove-inside-pairs skipped the pipe
    -- after any removed one for that pass
    local n = #pipes
    local write = 0
    for i = 1, n do
        local pipe = pipes[i]
        if pipe.valid then
            local voided = 0
            for _, amount in pairs(pipe.get_fluid_contents()) do
                voided = voided + amount
            end
            stats[pipe.unit_number] = voided
            pipe.clear_fluid_inside()
            write = write + 1
            if write ~= i then pipes[write] = pipe end
        end
    end
    for i = n, write + 1, -1 do pipes[i] = nil end
    if write == 0 then
        storage.pipes = nil
        storage.etech_void_pipe_stats = nil
    end
end

local function createEntity(entity)
    if not (entity and entity.valid) then return end
    if entity.name == "void-chest" then
        entity.infinity_container_filters = {}
        entity.remove_unfiltered_items = true
    end
    -- void-chest-filtered: deliberately untouched — the player sets the
    -- infinity filters ("exactly 0" per item to void); unfiltered items sit.
    if entity.name == "void-chest-filtered" then
        entity.remove_unfiltered_items = false
    end
    if entity.name == "void-pipe" then
        if storage.pipes == nil then
            storage.pipes = {}
        end
        table.insert(storage.pipes, entity)
    end
end

-- on_entity_cloned carries the new entity in `destination` — cloned void
-- pipes never joined the drain list before 0.19.0 (and cloned chests missed
-- their filter setup).
local function on_built(event)
    createEntity(event.entity or event.created_entity or event.destination)
end

-- Hovering a void pipe shows what it voided in the last drain pass (local
-- flying text — display only, per player).
local function on_selected_entity_changed(event)
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return end
    local selected = player.selected
    if not (selected and selected.valid and selected.name == "void-pipe") then return end
    local voided = storage.etech_void_pipe_stats and storage.etech_void_pipe_stats[selected.unit_number]
    if not voided then return end
    player.create_local_flying_text{
        text = {"etech-void-pipe-rate", string.format("%.1f", voided / 2)},
        position = selected.position,
    }
end

-- First time a player opens the filtered void chest, explain the infinity
-- filter workflow in chat (the entity GUI is the stock infinity-container
-- one — nothing of ours can be drawn inside it).
local function on_gui_opened(event)
    if event.gui_type ~= defines.gui_type.entity then return end
    local entity = event.entity
    if not (entity and entity.valid and entity.name == "void-chest-filtered") then return end
    storage.etech_void_hinted = storage.etech_void_hinted or {}
    if storage.etech_void_hinted[event.player_index] then return end
    storage.etech_void_hinted[event.player_index] = true
    local player = game.get_player(event.player_index)
    if player and player.valid then
        player.print({"etech-void-filtered-hint"})
    end
end

-- Re-apply the remove-everything filter to every placed void chest and
-- rebuild the pipe list. Runs on init and on any mod-set change, which also
-- covers migrating a save from the original Easy Void mod to this port.
local function init_voids()
    storage.pipes = nil
    storage.etech_void_pipe_stats = nil
    for _, surface in pairs(game.surfaces) do
        for _, chest in pairs(surface.find_entities_filtered{name = "void-chest"}) do
            chest.infinity_container_filters = {}
            chest.remove_unfiltered_items = true
        end
        for _, pipe in pairs(surface.find_entities_filtered{name = "void-pipe"}) do
            if storage.pipes == nil then storage.pipes = {} end
            table.insert(storage.pipes, pipe)
        end
    end
end

local lib = {}

lib.events =
{
    [defines.events.on_built_entity] = on_built,
    [defines.events.on_robot_built_entity] = on_built,
    [defines.events.script_raised_built] = on_built,
    [defines.events.script_raised_revive] = on_built,
    [defines.events.on_entity_cloned] = on_built,
    [defines.events.on_space_platform_built_entity] = on_built,
    [defines.events.on_selected_entity_changed] = on_selected_entity_changed,
    [defines.events.on_gui_opened] = on_gui_opened,
}

lib.on_nth_tick =
{
    [120] = processPipes,
}

lib.on_init = init_voids
lib.on_configuration_changed = init_voids

return lib
