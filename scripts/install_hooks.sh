#!/bin/bash

# ============================================================================
# Install this repo's git hooks.
#
# .git/hooks/ is not tracked, so a fresh clone has no hooks. Run this once
# after cloning.
#
# This repo used to write a hand-rolled .git/hooks/pre-commit here. It moved
# to the pre-commit framework when the 250-line file-length gate was added:
# three checks in one hand-written hook is the point where "just a plain
# script" stops paying for itself, and pre-commit already solves passing only
# the staged files to each check. The checks themselves are unchanged and
# still live in scripts/ -- see .pre-commit-config.yaml.
# ============================================================================

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
readonly REPO_ROOT
readonly HOOK="$REPO_ROOT/.git/hooks/pre-commit"
readonly LEGACY_MARKER='bump_patch_version.sh'

# The old hand-written hook has to go before pre-commit will install over it;
# pre-commit refuses to clobber a foreign hook, and leaving it would run the
# version bump twice per commit.
remove_legacy_hook() {
    if [[ -e "$HOOK" ]] && grep -q "$LEGACY_MARKER" "$HOOK" \
        && ! grep -q 'pre-commit' "$HOOK"; then
        rm -f "$HOOK"
        echo "Removed the legacy hand-written pre-commit hook."
    fi
}

ensure_pre_commit() {
    if command -v pre-commit >/dev/null 2>&1; then
        return
    fi
    echo "Installing pre-commit..."
    if command -v pipx >/dev/null 2>&1; then
        pipx install pre-commit
    else
        python3 -m pip install --user pre-commit
    fi
}

main() {
    ensure_pre_commit
    remove_legacy_hook
    pre-commit install
    echo "Installed pre-commit hooks: $HOOK"
}

main "$@"
