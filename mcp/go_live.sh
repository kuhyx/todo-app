#!/bin/bash
# One command that takes the todo MCP server live. Idempotent; rerun any time.
#
#   mcp/go_live.sh               # seed, token, install, publish, verify, cloud token
#   mcp/go_live.sh --verify-only # only step 5 (live MCP calls + 401 check)
#   mcp/go_live.sh --dry-run     # print the plan, change nothing
#   mcp/go_live.sh --new-cloud-token  # rotate the cloud token even if one exists
#
# Needs: python3, dart/flutter (install.sh), docker (Caddy), xclip, curl, ss.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly PORT=8735
readonly LOCAL_URL="http://127.0.0.1:${PORT}/mcp"
readonly PUBLIC_URL="https://todo.kuhy.duckdns.org/mcp"
readonly CONFIG_DIR="${HOME}/.config/todo-mcp"
readonly CRED_FILE="${CONFIG_DIR}/firebase_auth.json"
readonly TOKENS="${CONFIG_DIR}/tokens"
# Not under todo-mcp/: publish_caddy_site.sh would treat ~/.config/todo-mcp/token
# as an edge bearer gate and break the cloud token.
readonly CLIENT_TOKEN="${HOME}/.config/todo-mcp-client/token"
readonly ZSHENV="${HOME}/.zshenv"
# shellcheck disable=SC2016  # the line is written literally; zsh expands it later
readonly ZSHENV_LINE='export TODO_MCP_TOKEN="$(cat ~/.config/todo-mcp-client/token)"'
readonly SEED_DIR="${HOME}/src/utils/crdt-sync"
readonly SECRET_FILE="${HOME}/.config/crdt-sync/oauth_client_secret"
readonly CLIENT_ID="845446124781-prdoherj0v64vc6egvvcp3l0693khaur.apps.googleusercontent.com"
readonly PUBLISH="${HOME}/src/testsAndMisc/linux_configuration/features/publish_caddy_site.sh"
readonly VERIFY="${ROOT}/mcp/verify_mcp.py"

DRY_RUN=0
VERIFY_ONLY=0
NEW_CLOUD=0

say() { echo "[$1] $2"; }
die() { echo "FAIL: $*" >&2; exit 1; }
has_hash() { [[ -f "$TOKENS" ]] && awk -v e="$1" '$2 == e {f=1} END {exit !f}' "$TOKENS"; }

step_seed() {
    if [[ -f "$CRED_FILE" ]]; then say 1/6 "seed: credentials exist, skipped"; return; fi
    if ((DRY_RUN)); then say 1/6 "seed: would run seed_session --app todo-mcp (consent tap)"; return; fi
    [[ -f "$SECRET_FILE" ]] || die "no $SECRET_FILE; run ~/src/utils/crdt-sync/tool/refresh_oauth_secret.sh --app todo-mcp"
    say 1/6 "seed: sign in with Google when the browser opens"
    (cd "$SEED_DIR" && python3 -m tool.seed_session --client-id "$CLIENT_ID" \
        --client-secret "$(<"$SECRET_FILE")" --app todo-mcp) \
        || die "seed_session failed; rerun with -v or: tool/refresh_oauth_secret.sh --app todo-mcp"
    [[ -f "$CRED_FILE" ]] || die "seed ran but $CRED_FILE is missing"
    say 1/6 "seed: done"
}

step_token() {
    if has_hash pc && [[ -s "$CLIENT_TOKEN" ]]; then
        say 2/6 "pc token: exists, skipped"
    elif ((DRY_RUN)); then
        say 2/6 "pc token: would mint, store 0600 at $CLIENT_TOKEN"
    else
        # A hash without the raw token is unusable; minting replaces the pc line.
        umask 077
        mkdir -p "$(dirname "$CLIENT_TOKEN")"
        "${ROOT}/mcp/mint_token.sh" pc >"$CLIENT_TOKEN"
        chmod 600 "$CLIENT_TOKEN"
        say 2/6 "pc token: minted"
    fi
    if grep -qxF "$ZSHENV_LINE" "$ZSHENV" 2>/dev/null; then
        say 2/6 "zshenv: TODO_MCP_TOKEN line present"
    elif ((DRY_RUN)); then
        say 2/6 "zshenv: would append the TODO_MCP_TOKEN export"
    else
        printf '%s\n' "$ZSHENV_LINE" >>"$ZSHENV"
        say 2/6 "zshenv: appended (new shells and sessions only)"
    fi
}

wait_listen() {
    local _
    for _ in $(seq 1 60); do
        if ss -ltnH "sport = :${PORT}" | grep -q .; then return 0; fi
        sleep 1
    done
    return 1
}

step_install() {
    if ((DRY_RUN)); then
        say 3/6 "install: would run mcp/install.sh, enable --now todo-mcp.service, wait for :${PORT}"
        return
    fi
    say 3/6 "install: building (dart compile, can take a minute)"
    "${ROOT}/mcp/install.sh" >/dev/null
    systemctl --user enable --now todo-mcp.service 2>/dev/null
    wait_listen || die "nothing listens on :${PORT}; see: journalctl --user -u todo-mcp -n 30"
    say 3/6 "install: unit active, :${PORT} listening"
}

step_publish() {
    if ((DRY_RUN)); then
        if [[ -x "$PUBLISH" || -f "$PUBLISH" ]]; then
            say 4/6 "publish: would run publish_caddy_site.sh todo ${PORT}"
        else
            say 4/6 "publish: WOULD FAIL, $PUBLISH is missing"
        fi
        return
    fi
    [[ -f "$PUBLISH" ]] || die "missing $PUBLISH (untracked in testsAndMisc; restore it)"
    bash "$PUBLISH" todo "$PORT" >/dev/null
    say 4/6 "publish: https://todo.kuhy.duckdns.org -> 127.0.0.1:${PORT}"
}

verify_one() {
    local url="$1" wait="$2"
    python3 "$VERIFY" "$url" --token-file "$CLIENT_TOKEN" --wait "$wait"
    python3 "$VERIFY" "$url" --expect-401 --wait "$wait"
}

step_verify() {
    if ((DRY_RUN)); then
        say 5/6 "verify: would initialize + list_tasks and expect 401 without a token on $LOCAL_URL and $PUBLIC_URL"
        return
    fi
    [[ -s "$CLIENT_TOKEN" ]] || die "no client token at $CLIENT_TOKEN; run without --verify-only"
    local out
    out="$(verify_one "$LOCAL_URL" 20)" || die "local MCP check failed (journalctl --user -u todo-mcp -n 30)"
    say 5/6 "verify local: ${out//$'\n'/, }"
    # First public hit can wait on a fresh certificate (HTTP-01), so allow 60 s.
    out="$(verify_one "$PUBLIC_URL" 60)" || die "public MCP check failed (docker logs gitea-caddy --tail 30)"
    say 5/6 "verify public: ${out//$'\n'/, }"
}

step_cloud() {
    if has_hash cloud && ((! NEW_CLOUD)); then
        say 6/6 "cloud token: exists (rerun with --new-cloud-token to rotate)"
        return
    fi
    if ((DRY_RUN)); then
        say 6/6 "cloud token: would mint, copy to clipboard (manual: paste as cloud secret TODO_MCP_TOKEN)"
        return
    fi
    command -v xclip >/dev/null && [[ -n "${DISPLAY:-}" ]] || die "xclip or DISPLAY missing; cloud token not minted"
    "${ROOT}/mcp/mint_token.sh" cloud | xclip -selection clipboard -in
    say 6/6 "MANUAL: cloud token is on the clipboard; paste it as the cloud environment secret TODO_MCP_TOKEN"
}

main() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=1 ;;
            --verify-only) VERIFY_ONLY=1 ;;
            --new-cloud-token) NEW_CLOUD=1 ;;
            *) die "unknown option: $arg" ;;
        esac
    done
    if ((VERIFY_ONLY)); then step_verify; return; fi
    step_seed
    step_token
    step_install
    step_publish
    step_verify
    step_cloud
}

main "$@"
