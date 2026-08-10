-- etech-runtime-test/control.lua
--
-- WHAT THIS IS. E-Tech has a data-stage safety net (verify.ps1 --dump-data and
-- verify-matrix.ps1 across six mod combinations) and nothing at all for the
-- control stage. Every runtime change to the factory hub - the thing that
-- actually moves items across a surface boundary - has been verified by a human
-- opening the game and looking at a chest. This mod is the missing half: it
-- builds a real Factorissimo factory, stocks it, places the hub devices around
-- it, lets the game run, and asserts that items ended up where the mod promises
-- they end up.
--
-- It is deliberately NOT shipped. Scenarios and test mods inside the released
-- zip would show up in players' menus; this lives in tools/ and is copied into
-- a throwaway mod directory by tools/verify-runtime.ps1.
--
-- HOW IT REPORTS. One `log()` line per assertion, prefixed [ETECH-TEST], so the
-- result lands in factorio-current.log and the runner can grep it. No
-- script-output, no save inspection, nothing that depends on the run mode.
--
-- WHAT IT DOES NOT COVER. Anything that can only be reached through the mod's
-- GUI: the filter slots, the loop-guard checkboxes, circuit-set filters and the
-- sensor's options all live in E-Tech's own `storage`, which another mod cannot
-- write to. Those are still eyeball-tested. What is covered is the default path
-- every one of those options modifies: pull, deliver, distribute, give back,
-- broadcast.

local FACTORY = "factory-1"
local IRON = "iron-plate"
local COPPER = "copper-plate"
local SPARE = "stone"

local ORIGIN = {0, 0}
local ROBOPORT = {14, 0}
local OUT_REQUESTER = {18, 0}
local OUTLET = {14, 5}
local INLET = {14, 8}
local SENSOR = {14, 11}
local FLUID_SENSOR = {14, 14}
local FLUID = "water"

local STOCK = 200      -- iron plates placed in the interior provider chest
local OUT_WANT = 60    -- what the outside requester asks for
local IN_WANT = 40     -- what the interior requester asks for
local SPARE_COUNT = 50 -- unwanted items pushed into the outlet, to be given back

local SETTLE_TICK = 300  -- world is built and running by here
local ASSERT_TICK = 1500 -- 12.5 s: ~12 hub passes plus bot flight time

local passes, failures = 0, 0

local function check(name, ok, detail)
    if ok then
        passes = passes + 1
        log("[ETECH-TEST] PASS " .. name)
    else
        failures = failures + 1
        log("[ETECH-TEST] FAIL " .. name .. (detail and (" - " .. detail) or ""))
    end
end

local function count(entity, item)
    if not (entity and entity.valid) then return -1 end
    return entity.get_item_count(item)
end

-- Factorissimo builds the interior when the building is built, so the factory
-- table only exists after the raise_built event has been through its handler.
local function factory_of(building)
    local ok, factory = pcall(remote.call, "factorissimo", "get_factory_by_entity", building)
    if ok then return factory end
    return nil
end

local function request_for(chest, item, amount)
    local point = chest.get_requester_point()
    local section = point.add_section()
    section.set_slot(1, {
        value = { type = "item", name = item, quality = "normal", comparator = "=" },
        min = amount,
    })
end

-- Defined below the clock that calls it; declared here so it stays a local.
local assert_all

-- Deliberately NOT on_init. Every device here is registered by E-Tech from a
-- build event, and raise_built during on_init is not a build event any player
-- can produce: mods' on_init run in dependency order in the same tick, before
-- the game is really running. Building from the clock instead is both closer to
-- what a player does and free of that ordering question.
local function build_world()
    storage.t = {}
    local t = storage.t
    local surface = game.surfaces[1]
    local force = game.forces.player

    -- Anything the map generator left here would fight the placements below.
    for _, entity in pairs(surface.find_entities_filtered {
        area = {{-20, -20}, {40, 40}},
        type = {"tree", "simple-entity", "cliff"},
    }) do
        entity.destroy()
    end

    -- raise_built on every placement: E-Tech registers its devices from build
    -- events and invalidates its interior-chest cache the same way, and a plain
    -- create_entity raises nothing. Testing with the events suppressed would be
    -- testing a code path players never take.
    t.building = surface.create_entity {
        name = FACTORY, position = ORIGIN, force = force, raise_built = true,
    }
    if not t.building then
        check("factory building placed", false, "create_entity returned nil")
        return
    end

    local factory = factory_of(t.building)
    if not (factory and factory.inside_surface) then
        check("factorissimo built an interior", false, "no factory table")
        return
    end
    check("factorissimo built an interior", true)

    local inside = factory.inside_surface
    local ix, iy = factory.inside_x, factory.inside_y

    t.provider = inside.create_entity {
        name = "passive-provider-chest", position = {ix, iy},
        force = force, raise_built = true,
    }
    t.provider.insert {name = IRON, count = STOCK}

    t.in_requester = inside.create_entity {
        name = "requester-chest", position = {ix + 2, iy},
        force = force, raise_built = true,
    }
    request_for(t.in_requester, COPPER, IN_WANT)

    -- Give-back target. The outlet never PULLS from storage unless told to, so
    -- this chest only ever receives; it cannot feed the pull assertions.
    t.in_storage = inside.create_entity {
        name = "storage-chest", position = {ix - 2, iy},
        force = force, raise_built = true,
    }

    -- Outside: a powered roboport with bots, something that wants iron, and the
    -- three item devices.
    t.roboport = surface.create_entity {
        name = "roboport", position = ROBOPORT, force = force, raise_built = true,
    }
    t.roboport.insert {name = "logistic-robot", count = 20}

    t.out_requester = surface.create_entity {
        name = "requester-chest", position = OUT_REQUESTER,
        force = force, raise_built = true,
    }
    request_for(t.out_requester, IRON, OUT_WANT)

    t.outlet = surface.create_entity {
        name = "etech-factory-provider-hub", position = OUTLET,
        force = force, raise_built = true,
    }
    t.inlet = surface.create_entity {
        name = "etech-factory-inlet", position = INLET,
        force = force, raise_built = true,
    }
    t.inlet.insert {name = COPPER, count = IN_WANT * 2}
    t.sensor = surface.create_entity {
        name = "etech-factory-sensor", position = SENSOR,
        force = force, raise_built = true,
    }

    -- Fluid half: a plain storage tank inside with something in it, and a fluid
    -- sensor outside that should end up broadcasting it. A plain storage tank is
    -- safe to put inside even though factory BUILDINGS are storage tanks too -
    -- the hub tells them apart with Factorissimo's has_layout, and this is
    -- exactly the distinction worth having a test hold down.
    t.tank = inside.create_entity {
        name = "storage-tank", position = {ix, iy + 4},
        force = force, raise_built = true,
    }
    if t.tank then t.tank.insert_fluid {name = FLUID, amount = 5000} end
    t.fluid_sensor = surface.create_entity {
        name = "etech-factory-fluid-sensor", position = FLUID_SENSOR,
        force = force, raise_built = true,
    }

    check("hub devices placed",
        t.outlet ~= nil and t.inlet ~= nil and t.sensor ~= nil)
end

-- One clock, explicit tick arithmetic, deliberately NOT three on_nth_tick
-- handlers. tick 0 satisfies `tick % N == 0` for every N, so on_nth_tick(30),
-- on_nth_tick(300) and on_nth_tick(1500) all fire together on the first tick of
-- a fresh map: the first version of this file built the world, dropped the
-- spare items in and asserted, in that order, before E-Tech had run a single
-- pass. Every assertion failed and the mod was innocent.
script.on_nth_tick(60, function()
    local t = storage.t
    if not t then
        build_world()
        t = storage.t
        if t then t.built = game.tick end
        return
    end
    if not t.built then return end

    if t.roboport and t.roboport.valid then t.roboport.energy = 1e9 end

    local age = game.tick - t.built
    if age >= SETTLE_TICK and not t.spared and t.outlet and t.outlet.valid then
        t.spared = true
        -- Nothing in the network wants stone, so the next pull pass has to hand
        -- it back rather than sit on it.
        t.outlet.insert {name = SPARE, count = SPARE_COUNT}
    end
    if age >= ASSERT_TICK and not t.asserted then
        t.asserted = true
        assert_all(t)
    end
end)

-- Dumped before the assertions so a failure comes with the state that produced
-- it. Cheaper than another run with print statements bolted on, which is what
-- the alternative always turns into.
local function diagnostics(t)
    local function state(label, entity)
        if not (entity and entity.valid) then
            log("[ETECH-TEST] DIAG " .. label .. ": missing/invalid")
            return
        end
        log("[ETECH-TEST] DIAG " .. label .. ": " .. entity.name ..
            " at " .. math.floor(entity.position.x) .. "," .. math.floor(entity.position.y) ..
            " surface=" .. entity.surface.name)
    end
    state("building", t.building)
    state("provider", t.provider)
    state("in_requester", t.in_requester)
    state("in_storage", t.in_storage)
    state("roboport", t.roboport)
    state("out_requester", t.out_requester)
    state("outlet", t.outlet)
    state("inlet", t.inlet)
    state("sensor", t.sensor)

    log("[ETECH-TEST] DIAG provider iron=" .. count(t.provider, IRON) ..
        " outlet iron=" .. count(t.outlet, IRON) ..
        " outlet spare=" .. count(t.outlet, SPARE) ..
        " inlet copper=" .. count(t.inlet, COPPER))

    if t.roboport and t.roboport.valid then
        log("[ETECH-TEST] DIAG roboport energy=" .. math.floor(t.roboport.energy) ..
            " robots=" .. t.roboport.get_item_count("logistic-robot"))
    end
    local net = t.outlet and t.outlet.valid and t.outlet.logistic_network
    log("[ETECH-TEST] DIAG outlet network=" .. tostring(net ~= nil) ..
        (net and (" robots=" .. #net.robots ..
                  " iron=" .. net.get_item_count(IRON)) or ""))
    if t.sensor and t.sensor.valid then
        local behavior = t.sensor.get_control_behavior()
        local section = behavior and behavior.get_section(1)
        log("[ETECH-TEST] DIAG sensor behavior=" .. tostring(behavior ~= nil) ..
            " section=" .. tostring(section ~= nil) ..
            " filters=" .. tostring(section and #section.filters or -1))
    end
end

assert_all = function(t)
    diagnostics(t)

    local left = count(t.provider, IRON)
    check("outlet pulled from the interior provider chest",
        left >= 0 and left < STOCK,
        "provider still holds " .. left .. " of " .. STOCK)

    local delivered = count(t.out_requester, IRON)
    check("bots delivered the pulled items to the outside requester",
        delivered > 0, "outside requester holds " .. delivered)

    local inside_got = count(t.in_requester, COPPER)
    check("inlet distributed into the interior requester chest",
        inside_got > 0, "interior requester holds " .. inside_got)

    local returned = count(t.in_storage, SPARE)
    check("outlet gave unwanted items back to interior storage",
        returned > 0,
        "interior storage holds " .. returned .. ", outlet still holds " ..
        count(t.outlet, SPARE))

    local broadcasting = false
    if t.sensor and t.sensor.valid then
        local behavior = t.sensor.get_control_behavior()
        local section = behavior and behavior.get_section(1)
        for _, filter in pairs(section and section.filters or {}) do
            if filter.value and filter.value.name == IRON then broadcasting = true end
        end
    end
    check("sensor broadcasts the interior stock as signals", broadcasting)

    local fluid_signal = 0
    if t.fluid_sensor and t.fluid_sensor.valid then
        local behavior = t.fluid_sensor.get_control_behavior()
        local section = behavior and behavior.get_section(1)
        for _, filter in pairs(section and section.filters or {}) do
            if filter.value and filter.value.name == FLUID then
                fluid_signal = filter.min or 0
            end
        end
    end
    check("fluid sensor broadcasts the interior tanks", fluid_signal > 0,
        FLUID .. " signal reads " .. fluid_signal)

    log("[ETECH-TEST] DONE " .. passes .. " passed, " .. failures .. " failed")
end
