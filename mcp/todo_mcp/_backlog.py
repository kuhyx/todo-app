"""Parser for the ``todo`` app's exported ``BACKLOG.md`` (NotesMarkdown) file.

This is a faithful Python re-implementation of the Dart exporter/parser in
``todo/lib/sync/notes_markdown.dart``. The exported document is valid Markdown:
a one-line header (``<!-- todo-backlog v1 -->``) followed by, per note, an HTML
comment metadata marker::

    <!-- @note id="..." priority="medium" status="todo" created="..." updated="..." -->

whose body (everything up to the next marker, trimmed) is the note's Markdown.

The functions here are pure and side-effect free so they can be unit-tested in
isolation; the MCP layer (:mod:`todo_mcp._mcp`) handles file I/O and staleness.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
import uuid

# Priority/status vocabularies mirror the Dart ``Priority``/``Status`` enums,
# which are serialised by their ``.name`` (e.g. ``priority="medium"``). Unknown
# or missing values fall back to the same defaults the Dart parser uses, so a
# hand-edited file never yields an invalid note.
_PRIORITIES = ("low", "medium", "high")
_STATUSES = ("todo", "inProgress", "done", "abandoned")
_DEFAULT_PRIORITY = "medium"
_DEFAULT_STATUS = "todo"

# Matches a per-note metadata marker at the start of a line (multi-line mode).
# The body is everything between one marker and the next (or end of file).
_MARKER_PATTERN = re.compile(r"^<!--\s*@note\s+(.*?)\s*-->[ \t]*$", re.MULTILINE)

# Matches ``key="value"`` attribute pairs inside a marker.
_ATTR_PATTERN = re.compile(r'(\w+)="([^"]*)"')


@dataclass(frozen=True)
class Note:
    """A single parsed backlog note.

    Attributes:
        id: Stable UUID from the marker, or a freshly minted one when the
            source marker had no (or a blank) ``id``.
        title: Human-readable title derived from the body's first line.
        body: The note's Markdown body, verbatim but trimmed.
        priority: One of ``low`` / ``medium`` / ``high``.
        status: One of ``todo`` / ``inProgress`` / ``done`` / ``abandoned``.
    """

    id: str
    title: str
    body: str
    priority: str
    status: str


def _parse_attrs(raw: str) -> dict[str, str]:
    """Extract ``key="value"`` pairs from a marker's attribute string.

    Args:
        raw: The captured text between ``@note`` and the closing ``-->``.

    Returns:
        A mapping of attribute name to its (possibly empty) string value.
    """
    return {m.group(1): m.group(2) for m in _ATTR_PATTERN.finditer(raw)}


def _normalize(value: str | None, allowed: tuple[str, ...], fallback: str) -> str:
    """Return ``value`` if it is a recognised token, else ``fallback``.

    Mirrors the Dart parser's tolerant enum resolution: a missing (``None``) or
    unknown value degrades to the enum's default rather than raising.

    Args:
        value: The raw attribute value, or ``None`` if the marker omitted it.
        allowed: The permitted tokens for this field.
        fallback: The default token to use when ``value`` is unrecognised.

    Returns:
        A valid token drawn from ``allowed``.
    """
    return value if value in allowed else fallback


def _derive_title(body: str) -> str:
    """Derive a display title from a note's (already-trimmed) body.

    Uses the first line, stripping any leading Markdown heading hashes so a
    ``# Set up my own mail`` heading becomes ``Set up my own mail``. An empty
    body yields an empty title.

    Args:
        body: The trimmed Markdown body of the note.

    Returns:
        The derived title, or an empty string for an empty body.
    """
    if not body:
        return ""
    return body.splitlines()[0].lstrip("#").strip()


def parse_backlog(text: str) -> list[Note]:
    """Parse an exported ``BACKLOG.md`` document into typed notes.

    Tolerant by design (matching the Dart parser): a missing/blank ``id`` is
    replaced with a fresh UUID, and unknown/missing ``priority``/``status``
    values fall back to their defaults, so a partially hand-edited file never
    raises. The header line and any content before the first marker are ignored.

    Args:
        text: The full contents of an exported NotesMarkdown document.

    Returns:
        The notes in document order (empty if there are no ``@note`` markers).
    """
    markers = list(_MARKER_PATTERN.finditer(text))
    notes: list[Note] = []
    for i, marker in enumerate(markers):
        attrs = _parse_attrs(marker.group(1))
        body_start = marker.end()
        body_end = markers[i + 1].start() if i + 1 < len(markers) else len(text)
        body = text[body_start:body_end].strip()

        raw_id = attrs.get("id", "")
        note_id = raw_id or str(uuid.uuid4())
        notes.append(
            Note(
                id=note_id,
                title=_derive_title(body),
                body=body,
                priority=_normalize(
                    attrs.get("priority"), _PRIORITIES, _DEFAULT_PRIORITY
                ),
                status=_normalize(attrs.get("status"), _STATUSES, _DEFAULT_STATUS),
            )
        )
    return notes
