#!/bin/bash

# ============================================================================
# Install the todo launcher icon and .desktop entry for the Linux desktop.
#
# Flutter's GTK runner has no icon of its own: my_application.cc calls
# gtk_window_set_icon_name("todo"), which resolves through the hicolor icon
# theme. This script is what puts the icon into that theme, plus a .desktop
# entry so the app appears in application menus.
#
# Icon PNGs are pre-rendered and committed under linux/icons/, so this script
# needs no image tooling at run time. Regenerate them with:
#   PYTHONPATH=~/testsAndMisc python3 -m python_pkg.app_icons \
#       generate --app todo --linux-out linux/icons
# ============================================================================

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LINUX_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$LINUX_DIR")"
readonly SCRIPT_NAME LINUX_DIR REPO_DIR
readonly ICON_NAME="todo"
readonly BINARY_NAME="todo"
# GTK derives WM_CLASS from the GApplication id in linux/CMakeLists.txt,
# not from the binary name; verified with xprop on the running window.
readonly WM_CLASS="dev.kuhy.todo"
readonly ICON_SRC_DIR="$LINUX_DIR/icons"
readonly ICON_THEME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
readonly DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
readonly BUNDLE_BIN="$REPO_DIR/build/linux/x64/release/bundle/$BINARY_NAME"

usage() {
    echo "Usage: $SCRIPT_NAME"
    echo "Installs the todo icon into the hicolor theme and writes a .desktop entry."
    exit 0
}

validate_requirements() {
    if [[ ! -d "$ICON_SRC_DIR" ]]; then
        echo "Error: $ICON_SRC_DIR is missing; regenerate the icons first" >&2
        exit 1
    fi
}

ensure_theme_index() {
    # A user-local hicolor tree created from scratch has no index.theme, and
    # without it gtk-update-icon-cache refuses to build a cache ("No theme
    # index file"). Seed it from the system theme when one is available.
    local system_index="/usr/share/icons/hicolor/index.theme"
    if [[ ! -f "$ICON_THEME_DIR/index.theme" && -f "$system_index" ]]; then
        install -Dm644 "$system_index" "$ICON_THEME_DIR/index.theme"
    fi
}

install_icons() {
    local size_dir size icon
    for size_dir in "$ICON_SRC_DIR"/*/; do
        size="$(basename "$size_dir")"
        icon="$size_dir$ICON_NAME.png"
        [[ -f "$icon" ]] || continue
        install -Dm644 "$icon" \
            "$ICON_THEME_DIR/${size}x${size}/apps/$ICON_NAME.png"
    done
    # Refresh the theme cache so GTK picks the icon up without a re-login.
    # Harmless if the tool is absent: the icon still resolves, just slower.
    if command -v gtk-update-icon-cache >/dev/null; then
        gtk-update-icon-cache --quiet --force "$ICON_THEME_DIR" || true
    fi
}

install_desktop_entry() {
    mkdir -p "$DESKTOP_DIR"
    # StartupWMClass must match the window's actual WM class, or the taskbar
    # shows a generic icon for the running window even though the launcher
    # entry itself looks right.
    cat > "$DESKTOP_DIR/$ICON_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=todo
Comment=Offline-first, CRDT-synced notes
Exec=$BUNDLE_BIN
Icon=$ICON_NAME
Terminal=false
Categories=Utility;TextEditor;
StartupWMClass=$WM_CLASS
EOF
    if command -v update-desktop-database >/dev/null; then
        update-desktop-database "$DESKTOP_DIR" || true
    fi
}

main() {
    validate_requirements
    ensure_theme_index
    install_icons
    install_desktop_entry
    echo "Installed $ICON_NAME icon into $ICON_THEME_DIR"
    echo "Installed $DESKTOP_DIR/$ICON_NAME.desktop"
    if [[ ! -x "$BUNDLE_BIN" ]]; then
        echo "Note: $BUNDLE_BIN does not exist yet."
        echo "      Run 'flutter build linux --release' to make the entry launchable."
    fi
}

while [[ $# -gt 0 ]]; do
    case $1 in
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
