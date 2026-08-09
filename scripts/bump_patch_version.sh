#!/bin/bash

# ============================================================================
# Bump the patch version in pubspec.yaml on every commit.
#
# `version: X.Y.Z+B` -> `version: X.Y.(Z+1)+B`. The +build suffix is left
# alone: CI replaces it with the commit count, so it is not ours to manage.
#
# Wired as a pre-commit hook so each commit ships its own bump. That keeps the
# release-apk workflow's clean `vX.Y.Z` tag moving with HEAD instead of
# sitting on whatever version was last hand-edited, which is what left the AUR
# package advertising a tag 8 commits behind.
#
# Deliberately NOT bumping minor: minor/major are the "how much broke" signal.
# Auto-incrementing them on every commit throws that signal away and reaches
# absurd numbers within a year.
# ============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
PUBSPEC=""

usage() {
    echo "Usage: $SCRIPT_NAME [--pubspec PATH]"
    echo "Options:"
    echo "  --pubspec PATH   pubspec.yaml to bump (default: repo root's)"
    echo "  -h, --help       Show this help"
    exit 0
}

# Bumping while a rebase/merge/amend is replaying commits would inflate the
# version once per replayed commit, so skip those states entirely.
in_replay_state() {
    local git_dir
    git_dir="$(git rev-parse --git-dir)"
    [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" \
       || -f "$git_dir/MERGE_HEAD" || -f "$git_dir/CHERRY_PICK_HEAD" ]]
}

# Only bump when something other than pubspec.yaml is staged. A commit that
# only touches the version (or only docs the hook itself rewrote) must not
# trigger another bump, or `git commit --amend` would climb a version per
# amend.
has_non_pubspec_changes() {
    local staged
    staged="$(git diff --cached --name-only)"
    [[ -n "$(grep -v -e '^$' -e 'pubspec\.yaml$' <<<"$staged")" ]]
}

main() {
    if [[ -z "$PUBSPEC" ]]; then
        PUBSPEC="$(git rev-parse --show-toplevel)/pubspec.yaml"
    fi

    if [[ ! -f "$PUBSPEC" ]]; then
        echo "Error: no pubspec.yaml at $PUBSPEC" >&2
        exit 1
    fi

    if in_replay_state; then
        echo "bump-version: rebase/merge in progress; leaving version alone"
        exit 0
    fi

    if ! has_non_pubspec_changes; then
        echo "bump-version: nothing staged but the version itself; not bumping"
        exit 0
    fi

    local raw semver build major minor patch next committed rel_path
    raw="$(sed -nE 's/^version:[[:space:]]*(.*)$/\1/p' "$PUBSPEC" | head -1)"
    if [[ -z "$raw" ]]; then
        echo "Error: no 'version:' line in $PUBSPEC" >&2
        exit 1
    fi

    # Bump relative to the LAST COMMITTED version, not the working-tree one.
    # Otherwise re-running the hook over the same staged change (a hook that
    # failed, got fixed, and was retried) climbs a patch per attempt instead
    # of per commit.
    rel_path="${PUBSPEC#"$(git rev-parse --show-toplevel)/"}"
    committed="$(git show "HEAD:$rel_path" 2>/dev/null \
        | sed -nE 's/^version:[[:space:]]*(.*)$/\1/p' | head -1 || true)"
    [[ -n "$committed" ]] && raw="$committed"

    semver="${raw%%+*}"
    build=""
    [[ "$raw" == *+* ]] && build="+${raw#*+}"

    if [[ ! "$semver" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "Error: version '$raw' is not X.Y.Z[+B]" >&2
        exit 1
    fi
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"

    next="$major.$minor.$((patch + 1))"
    sed -i -E "s/^version:[[:space:]]*.*$/version: $next$build/" "$PUBSPEC"
    git add "$PUBSPEC"
    echo "bump-version: $semver -> $next"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --pubspec)
            PUBSPEC="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

main "$@"
