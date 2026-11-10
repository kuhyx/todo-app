/// Usage text printed by `--help` and after a usage error.
const kUsage = r'''
Usage: dart run bin/todo_note.dart [options]

Adds a note to the todo app headlessly: pulls from Firebase RTDB, writes an
ordinary CRDT change as this install's own node, pushes, and prints the id.
A note with --repo is a repo task; one without is a plain idea.

  --text <markdown>     note text (first line = title); default: read stdin
  --priority <p>        low|medium|high (default medium)
  --status <s>          todo|in_progress|done|abandoned (default todo);
                        with --list/--search: show only that status
  --repo <owner/name>   repo task's repository, e.g. kuhyx/todo;
                        with --list/--search: show only that repo's tasks
  --done-check <cmd>    shell command, run from the repo root, exit 0 = done
  --new-note            with --repo: own note, not the shared one (an exact
                        title in another separate note merges into it)
  --by <who>            claude|kuhy
  --list                pull, then print live notes, one per line:
                        8-char id, status, priority, repo (- for none), title
  --search <q>          as --list, only notes whose text or repo contains q
  --get <id>            pull, then print one note in full (exit 1 if absent)
  --delete <id>         pull, tombstone the note, push
  --set-status <id> <s> pull, change the note's status (as --status), push
  --set-text <id>       pull, replace the note's whole text with --text (or
                        stdin; first line = title), keep its other fields, push
  --close <id> --evidence <s>
                        pull, set status done + evidence (commit sha + done
                        check exit code), push; refused without --evidence
  --backfill-created-by [--dry-run]
                        pull, set created_by (claude|kuhy) on every note that
                        has none, push; --dry-run prints the plan only
  --data-dir <dir>      local log + node id (default
                        $XDG_DATA_HOME/todo-cli or ~/.local/share/todo-cli)
  -h, --help            this text

<id> is a full id or a unique prefix of at least 8 characters.
--list, --search and --get never push.
Exit codes: 0 ok, 1 sync/auth failure or note not found, 2 bad arguments.''';
