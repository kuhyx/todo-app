# CLAUDE.md — todo

Offline-first, CRDT-synced notes app. Flutter, targets **Android + web**.

The **desktop app is the web build**, served by a small local wrapper
(`bin/todo_desktop.dart`) and shown in a Chrome `--app` window. Flutter's Linux
embedder was removed: it manages only ~20fps at 4K while the same Dart code in
Chrome sustains ~144fps. See `docs/desktop-performance-findings.md` for the
measurements. Do not re-add `linux/` — `flutter create --platforms linux` would
silently bring the slow path back.
Capture an idea instantly (persisted on every keystroke), browse/filter notes,
and sync peer-to-peer through a GitHub repo used as dumb storage.

- Package name: `todo` (Dart SDK `^3.12.2`).
- Git remote: `origin` → `github.com/kuhyx/todo-app`.
- The note **content** also syncs to a separate private repo `kuhyx/syncs`
  (under `todo-sync/`) via the in-app GitHub sync (changeset files); that is
  data, not this codebase.

## Git workflow (repo-specific — overrides global rules)

- **Never open pull requests. Always commit and work directly on `main` and
  `git push` to `origin/main`.** Do not create feature branches for normal work.
- End commit messages with the standard
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.

## Commands

- Run tests + coverage: `flutter test --coverage` (suite runs in 1–2min; keep it
  quick — see Testing below).
- Coverage summary: `lcov --list coverage/lcov.info`.
- Static analysis: `flutter analyze` (must be clean before committing).
- Format: `dart format lib/ test/`.
- Run the desktop app: `./run.sh` (builds the web bundle, starts the wrapper,
  opens Chrome). Mobile: `flutter run` with a connected Android device.
- The wrapper serves on a **fixed** port 8730 with a **fixed** Chrome profile
  dir. Both must stay fixed: the GitHub token (`localStorage`) and the notes
  (IndexedDB) are keyed by origin and live in that profile, so changing either
  silently logs you out and hides your notes. Because the port cannot move,
  `lib/desktop/port_guard.dart` decides what to do when it is already taken:
  reap a wrapper with no window attached (so an upgrade can't leave you on old
  code), join one that still has a window, and refuse to touch anything else.
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
  - `sync_service.dart`: each device owns one file
    `todo-sync/changesets/<nodeId>.json`
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

`lib/data/note_template.dart` is the **single source of truth** — the stepper,
the editor and the tests are all template-driven, so changing that list changes
every surface. A new note pre-fills a title line plus
`what / where / must / done / verify / read first`.

The set was cut from twelve sections to seven in 2026-07 after auditing 514 real
sessions (`docs/llm-design-spec-audit.md`): `estimate`, `ask`, `nice`, `tech`,
`never` and `depends` were measurably never read, and `verify` was added because
"test it yourself, on the phone" was the single most repeated correction in the
corpus. Do not re-add a section without evidence that it gets used.

`NoteTemplate.retiredLabels` lists the dropped headings. `parse()` reports any
note containing one as **non-conforming** so it opens in the raw editor — without
that, the stepper would fold a retired section into its neighbour on the next
save. `tool/migrate_backlog.dart` converts an old export (Settings → Export →
migrate → Settings → Import).

## Testing

- **The suite must stay quick and fully green.** It is currently **313 tests at
  100% line coverage** (2005 lines), running well under a minute on this
  machine. Don't regress either.
  (The "~5s" figure this file used to quote had drifted well before the port
  guard was added; measure before quoting a new one.)
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
- **Every file is at most 250 lines**, source and prose alike. Enforced by a
  pre-commit hook (`scripts/check_file_length.sh`, delegating to the shared
  gate in `~/utils`) and by `.github/workflows/file-length.yml`, so it fails
  the commit rather than being a note anyone can ignore. Install the hook on
  a fresh clone with `scripts/install_hooks.sh`. There is deliberately no
  baseline and no allowlist — split the file instead. Exemptions (generated,
  vendored, data files) live with the checker so the gate and the survey
  cannot disagree.
- Where a split would otherwise break callers, keep the original path as a
  barrel that re-exports the parts (`note_template.dart`,
  `firebase_backend.dart`, `note_repository.dart` all do this). Where a
  widget and its private `State` must stay one library, use `part` files
  (`note_editor_*.dart`, `capture_screen_*.dart`).

## Flutter/Dart AI rules

Upstream's Flutter/Dart guidance used to be pasted in below this line, which
made 85% of this always-loaded file a document nobody edits. It now lives in
`docs/`, linked rather than inlined so the part loaded on every turn stays
about *this repo*:

- [Language, style and architecture](docs/flutter-rules-language.md)
- [State, routing and data](docs/flutter-rules-state-and-data.md)
- [Code generation, testing, theming and assets](docs/flutter-rules-testing-and-assets.md)
- [UI: theming, layout and overlays](docs/flutter-rules-ui.md)
- [Colour, type, documentation and accessibility](docs/flutter-rules-design.md)

Sourced from [flutter/flutter docs/rules/rules.md](https://github.com/flutter/flutter/blob/main/docs/rules/rules.md)
via `~/.claude/CLAUDE.md`'s Flutter AI tooling setup. Re-fetch periodically.
