"""Read-only MCP server package for the ``todo`` Flutter app's backlog.

The ``todo`` app is Dart/Flutter and stores notes in a ``sqlite_crdt`` database
that must never be touched from here (CRDT writes corrupt cross-device merge).
Instead, this package reads the app's exported ``BACKLOG.md`` file — the
canonical, human-exportable "NotesMarkdown" snapshot — and exposes it to MCP
clients (Claude Code and its subagents) as a handful of read-only tools.

See :mod:`todo_mcp._backlog` for the parser and :mod:`todo_mcp._mcp` for the
FastMCP stdio server.
"""

from __future__ import annotations

__all__ = ["__version__"]

__version__ = "1.0.0"
