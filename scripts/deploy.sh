#!/bin/bash

# ============================================================================
# Deploy todo everywhere it runs, then prove each one is live.
#
#   scripts/deploy.sh                 # all targets: mcp desktop phone
#   scripts/deploy.sh mcp desktop     # only the named targets
#
# Targets (each has its own health check; any failure makes the exit non-zero,
# but the remaining targets still deploy so one unplugged phone does not leave
# the desktop on old code):
#   mcp      frozen binary + todo-mcp.service (mcp/install.sh), restart, then a
#            real initialize + list_tasks against :8735 (mcp/verify_mcp.py).
#   desktop  web build + pacman package todo-flutter (install_arch.sh); health
#            = installed package and bundled web version.json match pubspec.
#   phone    release APK via phone_deploy.sh (adb install -r only; it has no
#            uninstall / pm clear path); health = versionName on the Pixel
#            matches pubspec and the app process is running.
#
# Idempotent: desktop and phone skip the build when the installed version
# already equals pubspec's (every commit bumps the patch version, so an equal
# version means equal code); the MCP binary is cheap and always rebuilt.
#
# Nothing live runs from ~/src/todo (the MCP is a frozen binary, the desktop
# app lives in /opt/todo), so this deploys the checkout it sits in and never
# pulls kuhy's working tree.
# ============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT
readonly SERIAL="${ADB_SERIAL:-23181JEGR08034}"
readonly APP_ID="dev.kuhy.todo"
readonly MCP_UNIT="todo-mcp.service"
readonly MCP_URL="http://127.0.0.1:8735/mcp"
readonly MCP_TOKEN="${HOME}/.config/todo-mcp-client/token"
readonly PHONE_DEPLOY="${HOME}/.claude/scripts/phone_deploy.sh"
readonly CAPPED="${HOME}/.claude/scripts/capped.sh"
readonly WEB_VERSION_JSON="/opt/todo/web/version.json"
readonly KEY_PROPS="$ROOT/android/key.properties"
readonly SHARED_KEY_PROPS="${HOME}/.android/release/key.properties"

# systemd units and Ship do not source ~/.zshenv; phone_deploy needs the SDK
# for its apksigner check.
export ANDROID_HOME="${ANDROID_HOME:-${HOME}/sdk/foss-android-sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"

FAILED=()

say() { echo "[deploy:$1] $2"; }
fail() {
    echo "[deploy:$1] FAIL: $2" >&2
    FAILED+=("$1")
}

# pubspec `version: 1.0.77+1` -> `1.0.77` (the +build part is CI's).
pubspec_version() {
    sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "$ROOT/pubspec.yaml"
}

# Builds run under the shared resource cap when it exists on this machine.
heavy() {
    if [[ -x "$CAPPED" ]]; then
        CAP_MEM=4G CAP_CPU_PCT=20 "$CAPPED" "$@"
    else
        "$@"
    fi
}

mcp_pid() { systemctl --user show -p MainPID --value "$MCP_UNIT" 2>/dev/null || echo 0; }

deploy_mcp() {
    local old_pid new_pid out
    old_pid="$(mcp_pid)"
    heavy "$ROOT/mcp/install.sh" || { fail mcp "mcp/install.sh failed"; return; }
    # install.sh only restarts a running unit; make sure it is enabled + up.
    systemctl --user enable --now "$MCP_UNIT" >/dev/null 2>&1 ||
        { fail mcp "cannot start $MCP_UNIT"; return; }
    systemctl --user is-active --quiet "$MCP_UNIT" ||
        { fail mcp "$MCP_UNIT not active"; return; }
    new_pid="$(mcp_pid)"
    if [[ "$new_pid" == 0 || "$new_pid" == "$old_pid" ]]; then
        fail mcp "$MCP_UNIT was not restarted (pid $old_pid -> $new_pid)"
        return
    fi
    [[ -s "$MCP_TOKEN" ]] || { fail mcp "no client token at $MCP_TOKEN"; return; }
    out="$(python3 "$ROOT/mcp/verify_mcp.py" "$MCP_URL" \
        --token-file "$MCP_TOKEN" --wait 20 2>&1)" ||
        { fail mcp "live check: $out"; return; }
    say mcp "ok: pid $new_pid, ${out//$'\n'/, }"
}

desktop_versions_match() {
    local want="$1" pkg web
    pkg="$(pacman -Q todo-flutter 2>/dev/null | awk '{print $2}')"
    web="$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' "$WEB_VERSION_JSON" 2>/dev/null)"
    [[ "${pkg%-*}" == "$want" && "$web" == "$want" ]]
}

deploy_desktop() {
    local want
    want="$(pubspec_version)"
    if desktop_versions_match "$want"; then
        say desktop "ok: todo-flutter $want already installed"
        return
    fi
    sudo -n true 2>/dev/null ||
        { fail desktop "sudo needs a password; run: ! $ROOT/install_arch.sh"; return; }
    heavy "$ROOT/install_arch.sh" || { fail desktop "install_arch.sh failed"; return; }
    if desktop_versions_match "$want"; then
        say desktop "ok: todo-flutter $want installed"
    else
        fail desktop "installed version is not $want ($(pacman -Q todo-flutter 2>&1))"
    fi
}

phone_version() {
    adb -s "$SERIAL" shell dumpsys package "$APP_ID" 2>/dev/null |
        sed -n 's/^[[:space:]]*versionName=\([^[:space:]]*\).*/\1/p' | head -n 1
}

phone_health() {
    local want="$1" got
    got="$(phone_version)"
    [[ "$got" == "$want" ]] || { fail phone "versionName on phone is '$got', want $want"; return; }
    adb -s "$SERIAL" shell pidof "$APP_ID" >/dev/null 2>&1 ||
        adb -s "$SERIAL" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
    sleep 2
    adb -s "$SERIAL" shell pidof "$APP_ID" >/dev/null 2>&1 ||
        { fail phone "$APP_ID is installed but not running"; return; }
    say phone "ok: $APP_ID $want running on $SERIAL"
}

deploy_phone() {
    local want rc=0
    want="$(pubspec_version)"
    if [[ "$(adb -s "$SERIAL" get-state 2>/dev/null)" != device ]]; then
        fail phone "phone unreachable: $SERIAL not attached (plug it in, enable USB debugging)"
        return
    fi
    if [[ "$(phone_version)" == "$want" ]]; then
        say phone "already at $want, skipping build"
    else
        # A fresh checkout has no (gitignored) key.properties; without it the
        # build signs with the debug key and cannot install over a CI build.
        [[ -f "$KEY_PROPS" || ! -f "$SHARED_KEY_PROPS" ]] ||
            install -m 600 "$SHARED_KEY_PROPS" "$KEY_PROPS"
        # Outside a Claude session each phone_lease call would name its own
        # pid as owner, so phone_deploy's launch step blocked on the lease its
        # own install step took (exit 35). One owner for the whole run.
        PHONE_LEASE_OWNER="${PHONE_LEASE_OWNER:-deploy:$$}" ADB_SERIAL="$SERIAL" \
            heavy "$PHONE_DEPLOY" "$ROOT" --release || rc=$?
        ((rc == 0)) || { fail phone "phone_deploy.sh exited $rc (see its exit-code table)"; return; }
    fi
    phone_health "$want"
}

main() {
    local targets=("$@") t
    ((${#targets[@]})) || targets=(mcp desktop phone)
    for t in "${targets[@]}"; do
        case "$t" in
            mcp | desktop | phone) "deploy_$t" ;;
            *) echo "usage: $0 [mcp] [desktop] [phone]" >&2; exit 2 ;;
        esac
    done
    if ((${#FAILED[@]})); then
        echo "[deploy] FAILED: ${FAILED[*]}" >&2
        exit 1
    fi
    echo "[deploy] all healthy: ${targets[*]} at $(pubspec_version)"
}

main "$@"
