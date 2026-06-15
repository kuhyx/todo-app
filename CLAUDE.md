# CLAUDE.md — todo

Offline-first, CRDT-synced notes app. Flutter, targets **Android + Linux**.
Capture an idea instantly (persisted on every keystroke), browse/filter notes,
and sync peer-to-peer through a GitHub repo used as dumb storage.

- Package name: `todo` (Dart SDK `^3.12.2`).
- Git remote: `origin` → `github.com/kuhyx/todo-app`.
- The note **content** also syncs to a separate private repo `kuhyx/todo-sync`
  via the in-app GitHub sync (changeset files); that is data, not this codebase.

## Git workflow (repo-specific — overrides global rules)

- **Never open pull requests. Always commit and work directly on `main` and
  `git push` to `origin/main`.** Do not create feature branches for normal work.
- End commit messages with the standard
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

## Commands

- Run tests + coverage: `flutter test --coverage` (suite runs in ~5s; keep it
  that fast — see Testing below).
- Coverage summary: `lcov --list coverage/lcov.info`.
- Static analysis: `flutter analyze` (must be clean before committing).
- Format: `dart format lib/ test/`.
- Run the app: `flutter run` (Linux desktop or a connected Android device).
- Release APK: `flutter build apk --release` (signs with the debug key; debug
  builds are janky — always measure smoothness on a release build).
- Sync smoke test (hits real GitHub, needs a token): `dart run tool/sync_smoke.dart`.

## Architecture

Three layers under `lib/`, each single-purpose:

- `data/` — domain + local storage.
  - `note.dart`: `Note` model; `Priority` enum (low/medium/high, **default
    medium**, no "none"); `Status` enum (todo/inProgress/done/abandoned).
  - `note_repository.dart`: CRDT storage over `sqlite_crdt`. Schema is at
    **version 3** with `onCreate`/`onUpgrade` migrations (v1→v2 adds the
    `status` column; v2→v3 backfills legacy priority `0`→medium). Also defines
    `NoteFilter` (query / priorities / statuses / created+updated date ranges,
    AND-combined), `NoteSort`, `watchNotes`/`watchCount` streams, and
    `importNotes` (safe newer-wins merge by id).
- `sync/` — GitHub-as-storage sync.
  - `sync_service.dart`: each device owns one file `changesets/<nodeId>.json`
    holding its full CRDT changeset. No two devices write the same file ⇒ no
    git merge conflicts; convergence is the CRDT layer's job (pull every other
    device's changeset and `merge()`, which is commutative + idempotent).
  - `github_client.dart`: thin GitHub contents-API client (injectable
    `http.Client`). `github_device_auth.dart`: OAuth device flow to mint a
    token. `sync_settings.dart`: persisted owner/repo/token/clientId.
  - `notes_markdown.dart`: round-trippable single-file export/import format
    (HTML-comment `<!-- @note id=… priority=… status=… … -->` markers).
- `ui/` — screens, all take an injected `NoteRepository`.
  - `capture_screen.dart`: landing screen; always-focused text box pre-filled
    with the structured template; lazy note creation on first keystroke.
  - `notes_list_screen.dart`: list + search + sort + filter sheet + per-note
    sheet. **Default view hides Done/Abandoned and shows no filter badge**
    (looks unfiltered).
  - `settings_screen.dart`: GitHub connect/test, device-flow auth, and the
    Export/Import backup actions.
- `main.dart`: bootstrap only (`// coverage:ignore-file`) — wires platform DB
  paths and `runApp`.

### Note template (default content of every new note)

Every new note pre-fills this scaffold (matches the user's `<work_backlog>`
format): a title line plus `what / where / must / nice / out / done / depends /
estimate / refs` sections.

## Testing

- **The suite must stay fast (~5s) and fully green.** It is currently **101
  tests at 100% line coverage**. Don't regress either.
- Widget tests use `test/fake_note_repository.dart` — a `FakeNoteRepository`
  built on `StreamController`s, **not** a real DB. A real `sqlite_crdt` DB
  schedules timers that never drain under the widget tester's fake clock
  ("A Timer is still pending"); the fake avoids that.
- Pitfalls learned the hard way (keep following these):
  - **Avoid `pumpAndSettle` when a widget animates forever** — an autofocused
    `TextField`'s cursor blink never settles, and an open device-code dialog
    keeps a pending poll timer. Use explicit `pump(Duration)` there.
    `pumpAndSettle` is fine once nothing is animating (e.g. a route/dialog pop,
    or a dialog already showing a static error).
  - Inject fakes rather than touching the platform: `MockClient`
    (`package:http/testing.dart`) for HTTP; the `file_selector` and
    `url_launcher` **platform interfaces** (`MockPlatformInterfaceMixin`) for
    the picker/launcher; stub `SystemChannels.platform` for clipboard.
  - To exercise the configured sync path, pass a `MockClient` via
    `CaptureScreen(httpClient: …)` / `SettingsScreen(httpClient: …)` — the real
    `SyncService` then runs without network.
  - `getChangeset()` serialises HLCs as `String`; `merge()` needs `Hlc.parse`
    and fresh mutable maps (QueryRows are read-only) — see the changeset test.
- Use `// coverage:ignore-line` / `ignore-start`/`ignore-end` only for
  genuinely unreachable code (e.g. a private static-only constructor, or a
  mobile-only `Platform.isAndroid` branch that can't run on the Linux test
  host), with a one-line reason.

## Conventions

- Run `dart format` + `flutter analyze` (clean) before every commit.
- Comments explain intent/trade-offs, not syntax.
- Keep the app buttery-smooth and low on CPU/RAM — it's a quick-capture tool.
