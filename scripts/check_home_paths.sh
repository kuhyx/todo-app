#!/bin/bash

# ============================================================================
# Fail if code builds a ~/<name> path that ~ is not allowed to contain.
#
# Thin delegate to the shared gate in ~/src/utils, which owns the eleven
# allowed root entries and the exclusion list. Copying that logic here is what
# lets one repo's idea of the layout drift from every other repo's -- so this
# script only locates the shared checker and forwards its arguments.
#
# Why it exists: the 2026-09-11 reorganisation's rewriter matched *literal*
# /home/kuhy/<name> strings, so a path assembled at run time was invisible to
# it. The todo desktop wrapper went on exporting to a dead ~/todo for a day
# while its MCP read ~/src/todo, and every backlog read in between was stale.
#
# Usage:
#   scripts/check_home_paths.sh <file> [<file> ...]   # pre-commit passes these
#   scripts/check_home_paths.sh --all [<root>]        # whole tree, default cwd
# ============================================================================

set -euo pipefail

readonly SHARED_GATE="${UTILS_ROOT:-$HOME/src/utils}/scripts/check_home_paths.sh"

main() {
    if [[ ! -x "$SHARED_GATE" ]]; then
        echo "Error: shared gate not found at $SHARED_GATE" >&2
        echo "Clone kuhyx/utils to ~/src/utils, or set UTILS_ROOT." >&2
        exit 1
    fi
    exec "$SHARED_GATE" "$@"
}

main "$@"
