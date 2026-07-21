# patched-mods — locally patched mod builds

Authoritative copies of third-party mods we patched to run on the current
Factorio version (2.1.x) because the mod portal has no official update yet.
Each zip's version is bumped one patch above the portal release so any future
official update automatically supersedes it in the in-game updater.

**The folder is the distribution set** (restructured 2026-07-21): zips +
`install-mods.bat` + `README.txt` only, nothing else — so it can be shared
as-is (Nextcloud read-only link) with friends/family and the server. The
installer copies every zip into `%APPDATA%\Factorio\mods` (Steam default;
takes an alternate mods path as argument) and overwrites older copies.

Bookkeeping lives here in `docs/`:

- **`LOCAL-PATCHED-MODS.md`** — the manifest: every patched mod, its portal
  baseline, what was changed, and whether it can ever be swapped for an
  official release (some hold save data and must never be removed).
- The zips mirror what is live in the game's mods folder. When a mod gets
  patched again, the new zip lands in `patched-mods/` and the old one is
  archived to `Projects\Factorio (ModUpdateCode)\mods-replaced\`.
- The 2.0→2.1 patch method and full API fix catalog live in
  `Projects\Factorio (ModUpdateCode)\README.md`.
- Public patch definitions (find/replace + apply script, no mod code) live in
  the separate `Projects\factorio-mod-patches\` repo.

Zips are not committed to git (see repo `.gitignore`) — they are other
authors' mods, kept here only for local bookkeeping via Nextcloud.

**Multiplayer:** server and all clients need byte-identical zips. After any
patch lands in `patched-mods/`, upload the changed zip(s) to the server's
mods folder and have the group re-run `install-mods.bat`.
