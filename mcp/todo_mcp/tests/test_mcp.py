"""Tests for the read-only MCP tools in ``_mcp``.

Tools are driven directly (``@mcp.tool()`` leaves the function callable). File
I/O is exercised for real against a temp ``BACKLOG.md`` pointed at via the
``TODO_BACKLOG_PATH`` env var, so ``_backlog_path``'s override branch runs on
every call; one test covers the default-path branch explicitly.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from todo_mcp import _mcp

_DOC = """<!-- todo-backlog v1 -->

<!-- @note id="n1" priority="high" status="todo" -->
# First task
alpha

<!-- @note id="n2" priority="low" status="done" -->
# Second task
beta

<!-- @note id="n3" priority="high" status="done" -->
# Third task
gamma
"""


@pytest.fixture
def backlog(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    path = tmp_path / "BACKLOG.md"
    path.write_text(_DOC, encoding="utf-8")
    monkeypatch.setenv("TODO_BACKLOG_PATH", str(path))
    return path


@pytest.fixture
def missing(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    path = tmp_path / "absent.md"
    monkeypatch.setenv("TODO_BACKLOG_PATH", str(path))
    return path


class TestBacklogPath:
    def test_default_path_when_env_unset(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.delenv("TODO_BACKLOG_PATH", raising=False)
        assert _mcp._backlog_path() == Path.home() / "todo" / "BACKLOG.md"


class TestListBacklog:
    def test_lists_all_notes_with_mtime(self, backlog: Path) -> None:
        out = _mcp.list_backlog()
        assert out["backlog_found"] is True
        assert out["total"] == 3
        assert out["returned"] == 3
        assert out["mtime"] is not None
        assert [n["id"] for n in out["notes"]] == ["n1", "n2", "n3"]

    def test_filter_by_priority(self, backlog: Path) -> None:
        out = _mcp.list_backlog(priority="high")
        assert [n["id"] for n in out["notes"]] == ["n1", "n3"]

    def test_filter_by_status(self, backlog: Path) -> None:
        out = _mcp.list_backlog(status="done")
        assert [n["id"] for n in out["notes"]] == ["n2", "n3"]

    def test_filter_by_priority_and_status(self, backlog: Path) -> None:
        out = _mcp.list_backlog(priority="high", status="done")
        assert [n["id"] for n in out["notes"]] == ["n3"]

    def test_limit_caps_results(self, backlog: Path) -> None:
        out = _mcp.list_backlog(limit=1)
        assert out["total"] == 3
        assert out["returned"] == 1

    def test_negative_limit_returns_none(self, backlog: Path) -> None:
        out = _mcp.list_backlog(limit=-3)
        assert out["returned"] == 0
        assert out["notes"] == []

    def test_missing_file_is_graceful(self, missing: Path) -> None:
        out = _mcp.list_backlog()
        assert out["backlog_found"] is False
        assert "Export it" in out["note"]


class TestGetNote:
    def test_found(self, backlog: Path) -> None:
        out = _mcp.get_note("n2")
        assert out["found"] is True
        assert out["note"]["title"] == "Second task"
        assert out["mtime"] is not None

    def test_not_found_in_present_file(self, backlog: Path) -> None:
        out = _mcp.get_note("nope")
        assert out["backlog_found"] is True
        assert out["found"] is False
        assert out["note_id"] == "nope"

    def test_missing_file_is_graceful(self, missing: Path) -> None:
        out = _mcp.get_note("n1")
        assert out["backlog_found"] is False
        assert out["found"] is False
        assert "Export it" in out["note"]


class TestBacklogStats:
    def test_counts_by_status_and_priority(self, backlog: Path) -> None:
        out = _mcp.backlog_stats()
        assert out["total"] == 3
        assert out["by_status"] == {"todo": 1, "done": 2}
        assert out["by_priority"] == {"high": 2, "low": 1}
        assert out["mtime"] is not None

    def test_missing_file_is_graceful(self, missing: Path) -> None:
        out = _mcp.backlog_stats()
        assert out["backlog_found"] is False
        assert "Export it" in out["note"]


def test_main_runs_stdio_server(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[tuple[()]] = []
    monkeypatch.setattr(_mcp.mcp, "run", lambda: calls.append(()))
    _mcp.main()
    assert calls == [()]
