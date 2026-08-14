#!/bin/bash

# ============================================================================
# Fail if any file in the commit exceeds the shared 250-line cap.
#
# Thin delegate to the shared gate in ~/utils, which owns the cap and the
# exemption list (generated / vendored / data files). Copying that logic here
# is what lets one repo's idea of "too long" drift from every other repo's --
# so this script only locates the shared checker and forwards its arguments.
#
# Usage:
#   scripts/check_file_length.sh <file> [<file> ...]   # pre-commit passes these
#   scripts/check_file_length.sh --all                 # whole tree, from cwd
# ============================================================================

set -euo pipefail

readonly SHARED_GATE="${UTILS_ROOT:-$HOME/utils}/scripts/check_file_length.sh"

main() {
    if [[ ! -x "$SHARED_GATE" ]]; then
        echo "Error: shared file-length gate not found at $SHARED_GATE" >&2
        echo "       Clone github.com/kuhyx/utils to ~/utils, or set" >&2
        echo "       UTILS_ROOT to where it lives." >&2
        exit 1
    fi

    exec bash "$SHARED_GATE" "$@"
}

main "$@"
