#!/bin/bash

# ============================================================================
# Fail if any markdown file breaks the shared naming convention.
#
# Thin delegate to the shared gate in ~/utils, which owns the four namespaces
# (README / CLAUDE* / DOCS* / TODO*), the "REMOVE ME AFTER FINISH" marker rule
# and the exemption list. Copying that logic here is what lets one repo's idea
# of a valid name drift from every other repo's -- so this script only locates
# the shared checker and forwards its arguments.
#
# Usage:
#   scripts/check_md_naming.sh <file> [<file> ...]   # pre-commit passes these
#   scripts/check_md_naming.sh --all                 # whole tree, from cwd
# ============================================================================

set -euo pipefail

readonly SHARED_GATE="${UTILS_ROOT:-$HOME/utils}/scripts/check_md_naming.sh"

main() {
    if [[ ! -x "$SHARED_GATE" ]]; then
        echo "Error: shared markdown-naming gate not found at $SHARED_GATE" >&2
        echo "       Clone github.com/kuhyx/utils to ~/utils, or set" >&2
        echo "       UTILS_ROOT to where it lives." >&2
        exit 1
    fi

    exec bash "$SHARED_GATE" "$@"
}

main "$@"
