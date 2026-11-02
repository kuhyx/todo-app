#!/bin/bash
# Deploy: frozen binary + systemd --user unit; restarts the unit if running.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly BIN_DIR="${HOME}/.local/lib/todo-mcp"
readonly UNIT_DIR="${HOME}/.config/systemd/user"
readonly UNIT="todo-mcp.service"

main() {
    mkdir -p "$BIN_DIR" "$UNIT_DIR"
    (cd "$ROOT" && flutter pub get >/dev/null)
    (cd "$ROOT" && dart compile exe mcp/todo_mcp.dart -o "$BIN_DIR/todo_mcp.new")
    mv "$BIN_DIR/todo_mcp.new" "$BIN_DIR/todo_mcp"
    install -m 644 "$ROOT/mcp/$UNIT" "$UNIT_DIR/$UNIT"
    systemctl --user daemon-reload
    if systemctl --user is-active --quiet "$UNIT"; then
        systemctl --user restart "$UNIT"
        echo "restarted $UNIT"
    else
        echo "installed; start with: systemctl --user enable --now $UNIT"
    fi
}

main "$@"
