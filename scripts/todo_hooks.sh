#!/bin/bash
# Shim: forward to the shared todo git hooks in ~/src/utils (silent if absent).
set -euo pipefail

readonly SHARED="${UTILS_ROOT:-$HOME/src/utils}/scripts/todo_hooks.sh"

main() {
    [[ -f "$SHARED" ]] || exit 0
    exec bash "$SHARED" "$@"
}

main "$@"
