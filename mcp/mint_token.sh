#!/bin/bash
# Prints a new <env> token once; ~/.config/todo-mcp/tokens keeps only its sha256.

set -euo pipefail

readonly CONFIG_DIR="${HOME}/.config/todo-mcp"
readonly TOKENS="${CONFIG_DIR}/tokens"

main() {
    local env="${1:-}"
    if [[ ! "$env" =~ ^[a-z0-9_-]+$ ]]; then
        echo "usage: $(basename "$0") <env>   (e.g. pc, cloud)" >&2
        exit 2
    fi
    umask 077
    mkdir -p "$CONFIG_DIR"
    local token hash tmp
    token="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    hash="$(printf '%s' "$token" | sha256sum | cut -d' ' -f1)"
    tmp="$(mktemp "${TOKENS}.XXXXXX")"
    if [[ -f "$TOKENS" ]]; then
        awk -v env="$env" '$2 != env' "$TOKENS" >"$tmp"
    fi
    printf '%s %s\n' "$hash" "$env" >>"$tmp"
    mv "$tmp" "$TOKENS"
    echo "$token"
}

main "$@"
