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

local function processPipes()
    if storage.pipes ~= nil then
        for k, pipe in pairs(storage.pipes) do
            if pipe.valid then
                pipe.clear_fluid_inside()
            else
                table.remove(storage.pipes, k)
                if #storage.pipes == 0 then
                    storage.pipes = nil
                end
            end
        end
    end
end

local function createEntity(entity)
    if not (entity and entity.valid) then return end
    if entity.name == "void-chest" then
        entity.infinity_container_filters = {}
        entity.remove_unfiltered_items = true
    end
    if entity.name == "void-pipe" then
        if storage.pipes == nil then
            storage.pipes = {}
        end
        table.insert(storage.pipes, entity)
    end
end

local function on_built(event)
    createEntity(event.entity or event.created_entity)
end

-- Re-apply the remove-everything filter to every placed void chest and
-- rebuild the pipe list. Runs on init and on any mod-set change, which also
-- covers migrating a save from the original Easy Void mod to this port.
local function init_voids()
    storage.pipes = nil
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
}

lib.on_nth_tick =
{
    [120] = processPipes,
}

lib.on_init = init_voids
lib.on_configuration_changed = init_voids

return lib
