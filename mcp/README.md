# todo backlog MCP server

A small, standalone, **read-only** [MCP](https://modelcontextprotocol.io)
server that lets Claude Code (and its subagents) query the todo app's backlog.

The todo app is Dart/Flutter and stores notes in a `sqlite_crdt` database that
must never be touched from outside the app (CRDT writes corrupt cross-device
merge). Instead, this server reads the app's exported `BACKLOG.md` — the
canonical NotesMarkdown snapshot written by **Settings → "Export notes"**.

## Staleness note

`BACKLOG.md` is a *manual* export, so it can be out of date. Every tool result
includes the file's modification time (`mtime`) so you can judge freshness. If
the file is missing, tools return `backlog_found: false` with a message telling
you to export it from the app — they never crash.

## Tools (all read-only)

- `list_backlog(priority: str | None = None, status: str | None = None, limit: int = 100)`
  — notes, optionally filtered by `priority` (`low`/`medium`/`high`) and/or
  `status` (`todo`/`inProgress`/`done`/`abandoned`), plus `total`, `returned`,
  and `mtime`.
- `get_note(note_id: str)` — one note by id, or `found: false`.
- `backlog_stats()` — counts `by_status` and `by_priority`, `total`, and `mtime`.

Nothing here writes to the database or to `BACKLOG.md`.

## Setup

```bash
mcp/scripts/setup_mcp.sh
```

This creates `~/.venvs/todo-mcp`, installs this package (which pulls in the
`mcp` SDK), and verifies the imports. The server is registered via the
repo-root `.mcp.json`; restart Claude Code in this repo and approve the project
MCP server prompt. Override the backlog location with `TODO_BACKLOG_PATH`
(defaults to `~/todo/BACKLOG.md`).

## Development

```bash
~/.venvs/todo-mcp/bin/pip install -e mcp pytest pytest-cov ruff mypy
~/.venvs/todo-mcp/bin/python -m pytest mcp/todo_mcp/tests \
    --cov=todo_mcp --cov-branch --cov-report=term-missing --cov-fail-under=100
```
