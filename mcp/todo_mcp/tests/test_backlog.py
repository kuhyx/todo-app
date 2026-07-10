"""Tests for the NotesMarkdown backlog parser in ``_backlog``."""

from __future__ import annotations

import uuid

from todo_mcp._backlog import Note, parse_backlog

HEADER = "<!-- todo-backlog v1 -->\n\n"


def _marker(**attrs: str) -> str:
    pairs = " ".join(f'{k}="{v}"' for k, v in attrs.items())
    return f"<!-- @note {pairs} -->"


class TestParseBacklog:
    def test_empty_document_has_no_notes(self) -> None:
        assert parse_backlog("") == []

    def test_header_only_has_no_notes(self) -> None:
        assert parse_backlog(HEADER) == []

    def test_parses_a_single_note_with_heading_title(self) -> None:
        doc = (
            HEADER
            + _marker(
                id="abc",
                priority="high",
                status="inProgress",
            )
            + "\n# Set up my own mail\n\nbody text here\n"
        )
        notes = parse_backlog(doc)
        assert len(notes) == 1
        note = notes[0]
        assert note == Note(
            id="abc",
            title="Set up my own mail",
            body="# Set up my own mail\n\nbody text here",
            priority="high",
            status="inProgress",
        )

    def test_plain_first_line_becomes_title_verbatim(self) -> None:
        doc = _marker(id="x", priority="low", status="todo") + "\nInfakt api + mcp\n"
        (note,) = parse_backlog(doc)
        assert note.title == "Infakt api + mcp"

    def test_multiple_notes_split_on_markers(self) -> None:
        doc = (
            HEADER
            + _marker(id="1", priority="low", status="todo")
            + "\nfirst\n\n"
            + _marker(id="2", priority="medium", status="done")
            + "\nsecond\n"
        )
        notes = parse_backlog(doc)
        assert [n.id for n in notes] == ["1", "2"]
        assert notes[0].body == "first"
        assert notes[1].body == "second"

    def test_missing_id_gets_fresh_uuid(self) -> None:
        doc = _marker(priority="low", status="todo") + "\nno id here\n"
        (note,) = parse_backlog(doc)
        # A valid UUID string was minted for the absent id.
        assert uuid.UUID(note.id)

    def test_blank_id_gets_fresh_uuid(self) -> None:
        doc = _marker(id="", priority="low", status="todo") + "\nblank id\n"
        (note,) = parse_backlog(doc)
        assert uuid.UUID(note.id)

    def test_unknown_priority_and_status_fall_back_to_defaults(self) -> None:
        doc = _marker(id="z", priority="urgent", status="waiting") + "\nx\n"
        (note,) = parse_backlog(doc)
        assert note.priority == "medium"
        assert note.status == "todo"

    def test_absent_priority_and_status_fall_back_to_defaults(self) -> None:
        doc = _marker(id="z") + "\nx\n"
        (note,) = parse_backlog(doc)
        assert note.priority == "medium"
        assert note.status == "todo"

    def test_empty_body_yields_empty_title(self) -> None:
        # Two adjacent markers => the first note's body is empty.
        doc = (
            _marker(id="1", priority="low", status="todo")
            + "\n"
            + _marker(id="2", priority="low", status="todo")
            + "\nsecond\n"
        )
        notes = parse_backlog(doc)
        assert notes[0].body == ""
        assert notes[0].title == ""
