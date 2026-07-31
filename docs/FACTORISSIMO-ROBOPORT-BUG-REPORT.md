# Upstream bug report draft — Factorissimo 3 interior roboport cannot charge robots

Paste target: https://mods.factorio.com/mod/factorissimo-2-notnotmelon (discussion tab)
or https://github.com/notnotmelon/factorissimo-2-notnotmelon/issues

Verified against Factorissimo 3.12.2, Factorio 2.1, in a Krastorio 2 + Space Age pack.
Written 2026-07-30.

---

**Title:** `factory-construction-roboport` uses a void energy source, so it can never charge robots

**Body:**

The interior roboport (`factory-construction-roboport`) is built in
`prototypes/roboport.lua` as `table.deepcopy(data.raw["roboport"]["roboport"])`
with its energy source replaced:

```lua
roboport.energy_source = {type = "void"}
```

Robot charging is paid out of a roboport's *stored* energy. A void source stores
nothing, so this roboport cannot charge a robot at all — not slowly, never.

Symptom: any robot that ends up inside a factory drains to empty and then crawls.
Parking a bot on the roboport shows its energy falling, never rising.

Reproduction:
1. Research the roboport interior upgrade, enter a factory
2. Put logistic robots into the factory's interior network
3. Watch any robot's energy bar — it only ever decreases

This is easy to miss because the mod's own hidden robots
(`factory-hidden-construction-robot`) are defined with
`energy_per_move = nil` and `energy_per_tick = nil`, so they never need charging.
The limitation only shows up once *player* robots operate inside a factory —
which happens as soon as anyone raises `logistics_radius` above its stock 2,
and to a lesser extent whenever a player's own construction bots work in there.

There is a second, independent blocker on the same prototype. The deepcopy
inherits vanilla's `recharge_minimum = "40MJ"`, which vanilla satisfies from its
100 MJ electric buffer. A void source has no buffer, so that threshold can never
be met either. Notably `factory-hidden-construction-roboport`, which is
hand-written rather than copied, sets `recharge_minimum = "1W"` and
`energy_usage = "1W"` — so the pairing was clearly understood there and just
didn't carry over to the deepcopy.

**Suggested fix:** give `factory-construction-roboport` a real electric energy
source. It already shares an electric network with the outside world —
`script/electricity.lua` wires the interior pole to an exterior pole with copper,
and nested factories chain through their parent — so there is a grid available
to draw from at any nesting depth. Something like:

```lua
roboport.energy_source = {
    type = "electric",
    usage_priority = "secondary-input",
    input_flow_limit = "100MW",
    buffer_capacity = "200MJ",
}
roboport.energy_usage = "50kW"
roboport.recharge_minimum = "1MJ"
```

`secondary-input` matches the vanilla roboport, so charging yields to primary
consumers and an under-supplied grid throttles bot charging rather than stalling
machines. A `recharge_minimum` well under vanilla's 40 MJ makes it resume
charging promptly after a dip instead of refilling 40 MJ first.

Measured cost with this change in a ~1600-robot base: roughly 1–2 MW per busy
factory, ~29 MW across 16 factories. It scales with airborne robots, not with
charging pad count.

Note the engine rejects `recharge_minimum < energy_usage` ("otherwise during low
power the roboport will toggle on and off every tick"), so both fields have to
move together.

**Minor, same prototype:** `roboport.icon` is set to
`graphics/icon/construction-chest.png`. Harmless while the roboport is a hidden
entity, but once it draws real power it appears in the electric network screen
as a chest consuming tens of MW.
