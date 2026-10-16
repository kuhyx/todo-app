# todo

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Headless note CLI

`bin/todo_note.dart` adds, lists, reads and deletes notes from the PC without
the app, as one more sync node (own `node_id` and CRDT log under
`$XDG_DATA_HOME/todo-cli`, or `~/.local/share/todo-cli`). It needs the desktop
Firebase session at `~/.config/todo/firebase_auth.json` (seed it with
`python3 ~/src/utils/crdt-sync/tool/seed_session.py --app todo`).

```sh
dart run bin/todo_note.dart --text "Title

body" --priority high --status in_progress     # prints the new note id
echo "Title" | dart run bin/todo_note.dart     # text from stdin
dart run bin/todo_note.dart --list             # id, priority, status, title
dart run bin/todo_note.dart --get <id>         # full note
dart run bin/todo_note.dart --delete <id>
```

`--list` and `--get` never push; `--data-dir <dir>` selects a throwaway node.
Exit codes: 0 ok, 1 sync/auth failure or note not found, 2 bad arguments.
All logic is in `lib/cli/` (tested in `test/cli/`); `--help` lists every flag.
