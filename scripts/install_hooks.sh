#!/bin/bash

# ============================================================================
# Install this repo's git hooks.
#
# .git/hooks/ is not tracked, so a fresh clone has no hooks. Run this once
# after cloning.
#
# Two layers, deliberately:
#
#   1. pre-commit (the framework) runs the read-only gates in
#      .pre-commit-config.yaml -- the crdt_sync override check and the
#      250-line file-length cap.
#   2. A thin wrapper hook installed here runs pre-commit first and, only if
#      it passed, runs scripts/bump_patch_version.sh.
#
# The bump cannot live in .pre-commit-config.yaml. pre-commit stashes
# unstaged changes for the duration of its run and restores them with
# `git apply`; the bump rewrites pubspec.yaml inside that window, so an
# uncommitted edit anywhere near the `version:` line makes the restore
# conflict -- which aborts the commit and DROPS the developer's edit from the
# working tree. Running it after pre-commit has exited keeps the mutation
# outside the stash cycle, and gating it on pre-commit's exit status stops a
# rejected commit from leaving a stray bump staged for the next one.
# ============================================================================

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
readonly REPO_ROOT
readonly HOOK="$REPO_ROOT/.git/hooks/pre-commit"
readonly LEGACY_MARKER='bump_patch_version.sh'

# The old hand-written hook has to go before pre-commit will install over it;
# pre-commit refuses to clobber a foreign hook.
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

# Wraps pre-commit's own generated hook so the version bump runs after it,
# and only on success. pre-commit install --hook-type pre-commit writes the
# generated script; we move it aside and call it from ours.
install_wrapper() {
    local generated="$REPO_ROOT/.git/hooks/pre-commit.pre-commit-generated"
    mv "$HOOK" "$generated"
    cat > "$HOOK" <<'HOOK_BODY'
#!/bin/bash
# Installed by scripts/install_hooks.sh — see that file for why the version
# bump runs here rather than as a pre-commit hook.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
readonly ROOT

# The read-only gates. A non-zero exit here rejects the commit, and the bump
# below never runs, so a rejected attempt leaves no stray version change.
"$ROOT/.git/hooks/pre-commit.pre-commit-generated" "$@"

exec bash "$ROOT/scripts/bump_patch_version.sh"
HOOK_BODY
    chmod 755 "$HOOK"
}

main() {
    ensure_pre_commit
    remove_legacy_hook
    pre-commit install
    install_wrapper
    echo "Installed pre-commit hooks: $HOOK"
}

main "$@"
