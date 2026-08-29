"""Read-only MCP server exposing the ``todo`` app's exported backlog.

Run via the dedicated venv that has ``mcp`` and ``todo_mcp`` installed::

    ~/.venvs/todo-mcp/bin/python -m todo_mcp._mcp

(see ``mcp/scripts/setup_mcp.sh`` and the repo-root ``.mcp.json``).

Safety invariants (do not break when adding tools):
  * **READ-ONLY.** Every tool only *reads* ``BACKLOG.md``. Nothing here writes
    to the file, and nothing ever touches the app's ``sqlite_crdt`` database
    (CRDT writes corrupt cross-device merge). There is no write tool.
  * **stdout is the JSON-RPC channel.** This module must never write to stdout;
    all logging is routed to STDERR below.
  * **No secret ever leaves.** The backlog holds only user-authored note text;
    there are no credentials to expose, and no config/token is ever read.

Because ``BACKLOG.md`` is a *manual* export (the app writes it from Settings →
"Export notes"), it may be stale. Every result therefore includes the file's
modification time (``mtime``) so a client can judge freshness, and a missing
file yields a graceful "please export it" message rather than an error.
"""

from __future__ import annotations

from datetime import UTC, datetime
import logging
import os
from pathlib import Path
import sys
from typing import Any

from mcp.server.mcpserver import MCPServer

from todo_mcp._backlog import Note, parse_backlog

# Log to STDERR only — STDOUT carries the MCP JSON-RPC protocol frames, so a
# single stray stdout write would corrupt the stream and kill the session.
logging.basicConfig(
    level=logging.INFO,
    stream=sys.stderr,
    format="%(asctime)s [%(levelname)s] todo-mcp: %(message)s",
)
logger = logging.getLogger(__name__)

# mcp 2.x renamed FastMCP to MCPServer; the decorator and run() API are
# unchanged, so only the import and the constructor moved.
mcp = MCPServer("todo")

_DEFAULT_LIST_LIMIT = 100


def _backlog_path() -> Path:
    """Resolve the ``BACKLOG.md`` path (env override, else the default).

    Returns:
        ``$TODO_BACKLOG_PATH`` when set, otherwise ``~/todo/BACKLOG.md``.
    """
    override = os.environ.get("TODO_BACKLOG_PATH")
    if override:
        return Path(override)
    return Path.home() / "todo" / "BACKLOG.md"


def _missing_message() -> str:
    """Return the user-facing hint shown when the backlog file is absent."""
    return (
        f"BACKLOG.md not found at {_backlog_path()}. Export it from the todo "
        "app (Settings -> Export notes), then try again."
    )


def _load_backlog() -> tuple[bool, list[Note], str | None]:
    """Load and parse the backlog, reporting existence and file mtime.

    Returns:
        A ``(found, notes, mtime)`` triple. When the file is absent ``found``
        is ``False`` and ``notes``/``mtime`` are empty; otherwise ``mtime`` is
        the file's UTC modification time as an ISO-8601 string.
    """
    path = _backlog_path()
    try:
        stat = path.stat()
    except OSError:
        return False, [], None
    mtime = datetime.fromtimestamp(stat.st_mtime, tz=UTC).isoformat()
    notes = parse_backlog(path.read_text(encoding="utf-8"))
    return True, notes, mtime


def _note_to_dict(note: Note) -> dict[str, str]:
    """Project a :class:`Note` into a JSON-serialisable dict for a tool result.

    Args:
        note: The parsed note to serialise.

    Returns:
        The note's fields as a plain string-keyed dict.
    """
    return {
        "id": note.id,
        "title": note.title,
        "priority": note.priority,
        "status": note.status,
        "body": note.body,
    }


@mcp.tool()
def list_backlog(
    priority: str | None = None,
    status: str | None = None,
    limit: int = _DEFAULT_LIST_LIMIT,
) -> dict[str, Any]:
    """List backlog notes, optionally filtered by priority and/or status.

    Args:
        priority: If given, keep only notes with this priority
            (``low`` / ``medium`` / ``high``).
        status: If given, keep only notes with this status
            (``todo`` / ``inProgress`` / ``done`` / ``abandoned``).
        limit: Maximum number of notes to return (non-positive returns none).

    Returns:
        A dict with the matching ``notes`` (capped at ``limit``), the total
        match count, the number returned, and the backlog file ``mtime``. If
        the file is missing, ``backlog_found`` is ``False`` and a ``note`` field
        explains how to export it.
    """
    found, notes, mtime = _load_backlog()
    if not found:
        return {"backlog_found": False, "note": _missing_message()}
    matches = [
        n
        for n in notes
        if (priority is None or n.priority == priority)
        and (status is None or n.status == status)
    ]
    capped = matches[: max(0, limit)]
    return {
        "backlog_found": True,
        "mtime": mtime,
        "total": len(matches),
        "returned": len(capped),
        "notes": [_note_to_dict(n) for n in capped],
    }


@mcp.tool()
def get_note(note_id: str) -> dict[str, Any]:
    """Fetch a single backlog note by its id.

    Args:
        note_id: The note's UUID (the ``id`` from its marker).

    Returns:
        A dict with ``found`` and, on a hit, the ``note`` plus the backlog
        ``mtime``. If the file is missing, ``backlog_found`` is ``False`` and a
        ``note`` field explains how to export it.
    """
    found, notes, mtime = _load_backlog()
    if not found:
        return {"backlog_found": False, "found": False, "note": _missing_message()}
    for note in notes:
        if note.id == note_id:
            return {
                "backlog_found": True,
                "found": True,
                "mtime": mtime,
                "note": _note_to_dict(note),
            }
    return {
        "backlog_found": True,
        "found": False,
        "mtime": mtime,
        "note_id": note_id,
    }


@mcp.tool()
def backlog_stats() -> dict[str, Any]:
    """Summarise the backlog: note counts by status and by priority.

    Returns:
        A dict with the ``total`` note count, ``by_status`` and ``by_priority``
        count maps, and the backlog ``mtime``. If the file is missing,
        ``backlog_found`` is ``False`` and a ``note`` field explains how to
        export it.
    """
    found, notes, mtime = _load_backlog()
    if not found:
        return {"backlog_found": False, "note": _missing_message()}
    by_status: dict[str, int] = {}
    by_priority: dict[str, int] = {}
    for note in notes:
        by_status[note.status] = by_status.get(note.status, 0) + 1
        by_priority[note.priority] = by_priority.get(note.priority, 0) + 1
    return {
        "backlog_found": True,
        "mtime": mtime,
        "total": len(notes),
        "by_status": by_status,
        "by_priority": by_priority,
    }


def main() -> None:
    """Run the MCP server over stdio (STDOUT = JSON-RPC, STDERR = logs)."""
    logger.info("Starting todo MCP server (python=%s)", sys.executable)
    mcp.run()  # pragma: no cover


if __name__ == "__main__":
    main()
