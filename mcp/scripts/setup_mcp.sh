#!/bin/bash

# ============================================================================
# Set up the dedicated virtualenv that hosts the todo backlog MCP server.
# Claude Code spawns this interpreter (see the repo-root .mcp.json) to run
# `python -m todo_mcp._mcp` over stdio.
#
# The MCP SDK (`mcp`) and the `todo_mcp` package live ONLY in this venv — the
# todo app itself is Dart/Flutter and has no Python, so this is fully separate.
# Both `mcp` and `todo_mcp` must be importable by this one interpreter or the
# MCP server fails to start silently.
#
# Idempotent: safe to re-run to pick up dependency changes.
# ============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PKG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly VENV_DIR="${HOME}/.venvs/todo-mcp"

main() {
    echo "== Setting up MCP venv at ${VENV_DIR} =="

    if [[ ! -d "${VENV_DIR}" ]]; then
        python3 -m venv "${VENV_DIR}"
    fi

    "${VENV_DIR}/bin/pip" install --quiet --upgrade pip
    "${VENV_DIR}/bin/pip" install --quiet -e "${PKG_DIR}"

    echo "== Verifying imports =="
    "${VENV_DIR}/bin/python" -c \
        "import mcp, todo_mcp; print('mcp + todo_mcp import OK')"

    echo
    echo "Done. The server is registered via $(cd "${PKG_DIR}/.." && pwd)/.mcp.json"
    echo "Restart Claude Code in this repo and approve the project MCP server prompt."
}

main "$@"
