# Refactor TODO — enforce the 250-line file cap

> **This file is a ready-to-use prompt.** Paste it to Claude, or open this repo
> and say "do refactor_claude_todo". It is self-contained: everything needed to
> execute is below. Generated 2026-08-14 from a measured survey of every repo.

## Goal

Every file in this repo must be **at most 250 lines** — source, tests, and
prose (`.md`/`.txt`/`.rst`/`.tex`) alike — and must **stay** that way forever,
enforced by a gate that fails the commit, not by a note anyone can ignore.

Why: a file that cannot be read in one piece forces re-reads and partial edits,
which is the single largest avoidable cost in an LLM-assisted workflow. Aim by
churn, not size alone — refactoring pays where code is read and changed often
(Fowler, *refactoring economic benefit*).

## Scope in this repo

- **26 files** currently exceed 250 lines (of 128 eligible files).
- **13,166 lines** sit in violation; longest file is **1838 lines**.

Exempt (do NOT split these):
- generated files — `*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `**/l10n/generated/**`,
  anything with a `GENERATED` header
- markup — `.html`, `.css`, `.scss`
- data files — `.json`, `.yaml`, `.csv`, wordlists and other data-ish `.txt`
  (mean line length under 25 chars)

## Violations, highest ROI first

ROI = lines x commits in the last year. Work top-down; a long file nobody edits
has near-zero payoff and should not be first.

| lines | commits/yr | kind | file |
|------:|-----------:|:-----|:-----|
| 739 | 19 | code | `lib/ui/capture_screen.dart` |
| 660 | 17 | code | `test/capture_screen_test.dart` |
| 702 | 10 | code | `lib/ui/note_editor.dart` |
| 677 | 9 | code | `test/note_repository_test.dart` |
| 925 | 6 | prose | `CLAUDE.md` |
| 391 | 13 | code | `test/settings_screen_test.dart` |
| 698 | 7 | code | `lib/ui/notes_list_screen.dart` |
| 429 | 8 | code | `lib/data/note_repository.dart` |
| 502 | 6 | code | `test/note_editor_test.dart` |
| 356 | 7 | code | `test/sync_service_test.dart` |
| 402 | 5 | code | `test/wrapper_server_test.dart` |
| 370 | 5 | code | `lib/data/note_template.dart` |
| 253 | 7 | code | `bin/todo_desktop.dart` |
| 347 | 4 | code | `test/notes_list_screen_test.dart` |
| 336 | 4 | code | `lib/desktop/wrapper_server.dart` |

_(11 further files over 250 lines not listed — re-run the survey for the full set.)_

## How to split

- **Python** — extract cohesive helpers into sibling modules; keep the public
  API and imports stable.
- **Shell** — split into `lib/*.sh` sourced by a thin entry script. Keep
  `set -euo pipefail` in each.
- **Dart / TypeScript** — extract widgets/components into their own files.
- **Tests** — split by test-group into sibling files
  (`foo.test.ts` -> `foo.parsing.test.ts`, `foo.render.test.ts`). Coverage must
  not drop.
- **Docs** — split into topic files under `docs/` with an index. For an
  oversized `CLAUDE.md`, move detail into referenced docs so the
  always-loaded part shrinks.

**Do not** game the cap: no one-lining, no deleting tests, no moving code into
an exempt extension, no `# noqa`-style suppressions.

## Make it permanent (required — this is the point)

A refactor without a gate silently regrows. Before this task is done:

1. Wire the shared gate `~/utils/scripts/check_file_length.sh` into this repo's
   `.pre-commit-config.yaml` as a local hook. If the repo has no pre-commit
   config, add a minimal one.
2. The hook checks **files in the commit** (not the whole tree), so unrelated
   commits never break, and it **fails** — exit 1, not a warning.
3. No baseline file and no allowlist. Those are suppressions.
4. If this repo has CI (`.github/workflows`), add the same check there so it
   also fails on push.

## Done condition

- `bash ~/utils/scripts/check_file_length.sh --all` from this repo root exits 0.
- The repo's own test suite and coverage bar are still green.
- `pre-commit run --files <changed files>` passes.
- A deliberately over-250-line test file, staged, makes `git commit` **fail**.
- For a deployed daemon/app: the entry point still actually runs.

## Verify

Mobile is the primary platform: verify with an APK on the phone via the `phone-deploy` skill, not on desktop.
