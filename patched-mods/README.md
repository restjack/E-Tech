# patched-mods — locally patched mod builds

Authoritative copies of third-party mods we patched to run on the current
Factorio version (2.1.x) because the mod portal has no official update yet.
Each zip's version is bumped one patch above the portal release so any future
official update automatically supersedes it in the in-game updater.

- **`LOCAL-PATCHED-MODS.md`** — the manifest: every patched mod, its portal
  baseline, what was changed, and whether it can ever be swapped for an
  official release (some hold save data and must never be removed).
- The zips here mirror what is live in the game's mods folder. When a mod
  gets patched again, the new zip lands here and the old one is archived to
  `Projects\Factorio (ModUpdateCode)\mods-replaced\`.
- The 2.0→2.1 patch method and full API fix catalog live in
  `Projects\Factorio (ModUpdateCode)\README.md`.

Zips are not committed to git (see repo `.gitignore`) — they are other
authors' mods, kept here only for local bookkeeping via Nextcloud.
