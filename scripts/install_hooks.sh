#!/bin/bash

# ============================================================================
# Install this repo's git hooks.
#
# .git/hooks/ is not tracked, so a fresh clone has no hooks. Run this once
# after cloning. Unlike habit_stack and diet-guard, this repo does not use the
# pre-commit framework (its quality gate is CI), so the hook is a plain script.
# ============================================================================

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
readonly REPO_ROOT
readonly HOOK="$REPO_ROOT/.git/hooks/pre-commit"

main() {
    if [[ -e "$HOOK" ]] && ! grep -q 'bump_patch_version.sh' "$HOOK"; then
        echo "Error: $HOOK exists and is not ours; refusing to clobber it." >&2
        exit 1
    fi

    cat > "$HOOK" <<'HOOK_BODY'
#!/bin/bash
# Installed by scripts/install_hooks.sh — see that file.
set -euo pipefail
readonly ROOT="$(git rev-parse --show-toplevel)"
# Gate first: a local crdt_sync override left in place makes CI build a
# library this checkout has never tested against, silently and in both
# directions. Blocking the commit is the only thing that actually prevents it.
bash "$ROOT/scripts/check_no_crdt_sync_override.sh" "$ROOT/pubspec.yaml"
exec bash "$ROOT/scripts/bump_patch_version.sh"
HOOK_BODY

    chmod 755 "$HOOK"
    echo "Installed pre-commit hook: $HOOK"
}

main "$@"
