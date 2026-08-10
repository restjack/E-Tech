# Factory hub overhaul — session record, 2026-08-09

E-Tech **0.22.0 → 0.32.0** in one session. Read this before touching
`E-Tech/factory-hub/`; several designs here were arrived at by elimination and
the rejected ones are listed on purpose.

Everything below was pushed to `main` (github.com/restjack/E-Tech), last commit
`4294d9e`. `tools/verify.ps1` is clean end to end: syntax, changelog, locale,
GUI names, luacheck, `--dump-data`, and 11 runtime assertions.

---

## Deploy state

| Where | Version | Notes |
|---|---|---|
| This PC's mods folder | 0.32.0 | older E-Tech zips still present, harmless (newest loads) |
| AMP `factorio01` | **0.32.0 on disk** | **needs an instance restart to take effect** — it is still RUNNING 0.31.0 from an open file handle. Clients need 0.32.0 before rejoining after that restart. |
| AMP `game202601` | unknown | container was stopped; not checked |
| Factorio mod portal | 0.31.0 | Eli uploaded. **Page copy is stale** — see below |

**Portal follow-up:** `docs/PORTAL-PAGE.md` was pasted at a point where it still
advertised the **Evacuate** button removed in 0.24.1, and mentioned nothing from
0.25–0.32. Corrected in `dfdcaa0`; the page needs re-pasting.

**AMP note:** the `automation` account cannot stop an instance
(`Core.AppManagement.StopApplication` denied), so `factorio_mod_updater push`
fails at the power step. Use `push --no-power --no-enable` and restart from the
AMP UI by hand. That path also **deletes older E-Tech zips server-side**, which
is safe on Linux while running but means the restart is one-way.

---

## What shipped

**Loop guards and the loop itself.** The reported bug: miners fill a passive
provider outside, a requester chest outside is the outer end of a Factorissimo
chest connection, and the inner end is a passive provider inside the factory.
Factorissimo reads requester-outside as an *input* and runs the connection
inwards; the outlet saw a provider full of ore inside a factory and pulled it
straight back out. **Both mods behaving exactly as designed.** Fixed by skipping
the interior end of chest connections — the CHEST, not the item and not the
factory, so everything else in that factory still exports. Five opt-in guards
sit alongside it, and *serve the factories from their own stock first* is the
one that removes the loop rather than refusing to take part in it.

**Per-factory export rules.** Every factory gets a **Factory export filter**
built into it, auto-fitted, no crafting. Its own constant-combinator signal list
is the item list; E-Tech's panel beside it holds only the mode. Default is **No
restriction**; quality **always** binds (no toggle — every signal carries a
quality, which is the point for upcycling).

**Quality.** Filter slots are item-with-quality across outlet/inlet/sensor, plus
a **minimum quality to pull out** for recycler upcycling loops: feedstock tiers
stay in, the top tier leaves.

**Two real gameplay bugs, neither reported:**
- the inlet **laundered spoilage** — spec-based inserts re-created items with a
  fresh timer, so Gleba produce arrived perfect;
- under short supply the inlet filled each chest to its full deficit in list
  order, so factories at the end of a stable list got **nothing**, pass after
  pass, invisibly.

**Other:** fluid sensor; fluid loop guard; circuit-set filters; per-item flow
rates; grid filter/sort; ctrl-click take-all; alt-click to personal requests;
inlet shortfall alerts (map setting, 60 s grace); factories named from
`game.backer_names`; Factories tab with search, coordinates, overlay icons and
an **Enter** button.

---

## Decisions, and what was rejected

**Where the export rule lives — four attempts.** Do not reopen without reading
this.

1. Own device, placed beside the **door** → landed *in* the entrance; dead
   centre of a Mk4's wider one.
2. Own device, **searched** for a free tile near the pole → different spot in
   every factory.
3. Own device, **fixed tile, no collision box** → correct approach, but see the
   geometry bug below.
4. Hosted on Factorissimo's **overlay controller** → removed placement entirely,
   but the controller only exists once the interior display upgrade is
   researched, and anything in an *active* section of it is painted on the
   outside of the building. Rejected.

Final: **own device, fixed tile, no collision**, anchored on the *interior
bounds*. **Never re-propose searching for a free tile.**

**Geometry, measured — the pole is not in the room.** Factorissimo's layouts put
`inside_energy` (power pole and roboport) OUTSIDE the floor: `factory-1` has
`inside_size` 30, so the floor ends at ±15, and the pole sits at **y = 17**.
Every tier is the same shape. Anchoring on the pole put the device off the floor
in the dark beside the door, invisible in game. Now anchored two tiles in from
the door-side wall, three to the side of the opening.

**Also rejected:** hosting the rule on a chest.
`factory-requester-chest-<tier>` is a plain `container`, hidden, `selection_box
= nil` — unopenable, no filter slots, and it is Factorissimo's construction
buffer. A player's storage chest has one filter slot (not a list), there is no
answer to *which* chest, and relative GUIs anchor by prototype name, so the
panel would appear on every storage chest in the base.

**Naming.** Factory buildings cannot carry a real `backer_name` — the engine
supports it on labs, locomotives, radars, roboports and train stops only. The
backer *list* is readable (`game.backer_names`), so names are picked from it by
factory id: identical for every client, stable, nothing stored.

**Still deliberately not fixed:** `factory_names` is never pruned (audit 1.9).
Every prune strategy has to tell "factory is gone" from "no device can currently
see it", and nothing answers that — a factory on a surface with no outlet looks
identical to a deleted one. Cost is one string per manually renamed factory.

---

## Tooling added — this is where most of the session's bugs were

`tools/verify-runtime.ps1` + `tools/runtime-test/` **run the game** and assert
11 behaviours. `--create` builds a map where a test mod places a real
Factorissimo factory and the hub devices, `--benchmark` runs ticks, assertions
go through `log()` and are grepped out of the log. Everything the repo had
before this proved only that the mod LOADS.

`tools/lint-gui-names.py` reads `LuaGuiElement`'s real member list out of the
game's own `runtime-api.json` and fails on any GUI element named after one.
A pane named `tabs` shipped in 0.24.1 as a **non-recoverable crash on opening an
outlet** — the engine refuses the element outright.

`verify.ps1` now: reports which checks did NOT run (`VERIFY OK (every check
ran)` vs a list), and asserts `Loading mod E-Tech <version>` is in the log
rather than treating "no errors" as success — a disabled mod loads nothing and
logs nothing.

`build.ps1` now: writes to a temp name, verifies the archive opens and contains
`info.json`, then `File.Replace`s into place; never deletes the installed zip on
its way to failing; and says plainly when Factorio has the zip open.

All verify scripts use an isolated `write-data` via their own `config.ini`, so
they run while Factorio is open.

---

## Traps worth not rediscovering

- **`on_nth_tick(N)` fires at tick 0** (`0 % N == 0`). Three of them as a
  schedule all fire on the first tick.
- **`--benchmark` has no player**, so no GUI can ever be opened there. Nothing
  behind a window is testable; that gap is what `lint-gui-names.py` covers.
- **Remote factory tables are snapshots.** `connections` and
  `inside_overlay_controller` can be absent from a cached copy and read as "no
  rule". Re-ask when a cached copy comes back empty.
- **Asserting existence is not asserting correctness.** The harness found the
  export filter by searching the whole surface, so it passed for two versions
  while the device was being built outside the room. It now asserts the
  position.
- **A test that has only ever passed is indistinguishable from one wired to
  nothing.** Make it fail on purpose first. One assertion here "passed" before
  the simulation had started, because a loose string anchor put it in the
  world-builder instead of the assertion function.
- **luacheck caught four undefined-variable bugs** this session, every one from
  surgical edits to a 3,000-line file. Run it before believing an edit landed.

---

## Where to pick up

1. **Restart `factorio01`** to move the server onto 0.32.0, with players off.
2. **Re-paste `docs/PORTAL-PAGE.md`** to the mod portal, and upload 0.32.0.
3. Optional: clear the older `E-Tech_*.zip` from this PC's mods folder.
4. Untested by anyone: the **fluid sensor** and **circuit-set filters** have
   never been exercised in game — only headlessly and by inspection.
