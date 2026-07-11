# Migration: `sqlite_crdt` → shared `crdt_sync`

todo's note storage and sync were moved off `sqlite_crdt` onto the shared
[`crdt_sync`](https://github.com/kuhyx/utils/tree/main/crdt_sync_dart) library
(pinned tag `crdt_sync_dart-v0.3.0`), so every companion app now syncs through
one library.

## What changed

- **Storage:** `NoteRepository` is backed by `crdt_sync`'s `LogStore` (a
  `Log = Map<String, Record>` persisted as JSON). Each `Note` is stored *as* a
  `Record` (per-field last-writer-wins + a sticky tombstone), so the on-disk
  log **is** the sync wire format — no separate adapter. Filtering/sorting run
  in Dart over the in-memory log.
- **Sync:** `SyncService` pushes each device's `Log` to
  `todo-sync/notes/<nodeId>.json` in `kuhyx/syncs` (new dir; the old
  `changesets/` format is incompatible, so it's a clean cutover). It uses
  `crdt_sync`'s `GitHubClient` + `logToJson`/`logFromJson`.
- **Client:** todo's local `lib/sync/github_client.dart` was deleted; it now
  uses `crdt_sync`'s `GitHubClient` (which gained `canAccessRepo()` +
  `deleteFile()` in v0.3.0). `putFileText` self-resolves the file sha, so the
  old SHA-tracking is gone.

## The one-time on-device migration

`NoteRepository.open()` migrates a pre-existing `sqlite_crdt` DB into the log on
first launch, guarded by a persisted `crdt.migratedFromSqlite` flag. Verified
on-device: a real 27-note backlog (+5 tombstones) migrated intact.

`sqlite_crdt` is **retained as a dependency** only to read that legacy DB during
migration — the old `todo.db` is left untouched as a safety net. Remove the dep
in a later cleanup once every device is known-migrated.

## Surprises / non-obvious decisions

- **Seed HLCs from each note's `updatedAt`, not "now".** Two devices migrate
  independently; stamping migration-time "now" would let per-field LWW resolve
  a pre-cutover edit arbitrarily. Seeding from `updatedAt` keeps
  last-real-edit-wins across the cutover.
- **Reuse the legacy `sqlite_crdt` node id** (persisted in prefs) so a device
  keeps its `devices/<id>` identity and devices still converge.
- **`watchNotes`/`watchCount` seed in `onListen`**, not lazily in an `async*`
  body — otherwise a write between `listen()` and the first generator tick
  swallows the initial snapshot.
