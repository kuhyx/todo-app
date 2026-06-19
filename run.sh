#!/bin/bash
#
# run.sh — install missing Flutter + Linux-desktop build dependencies, then
# launch the todo app on Arch Linux or Ubuntu/Debian.
#
# Usage: ./run.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly AUR_FLUTTER_BIN_URL="https://aur.archlinux.org/flutter-bin.git"

BUILD_DIR=""
cleanup() {
    if [[ -n "${BUILD_DIR}" && -d "${BUILD_DIR}" ]]; then
        rm -rf "${BUILD_DIR}"
    fi
}
trap cleanup EXIT

log() { printf '==> %s\n' "$1"; }
err() { printf 'error: %s\n' "$1" >&2; }

# Echoes "arch" or "debian" depending on /etc/os-release; exits otherwise.
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        case "${ID:-}:${ID_LIKE:-}" in
            *arch*) echo "arch"; return ;;
            *debian*|*ubuntu*) echo "debian"; return ;;
        esac
    fi
    err "unsupported distro (expected Arch Linux or Ubuntu/Debian)"
    exit 1
}

require_non_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        err "run as a regular user with sudo access, not as root (makepkg/apt need that)"
        exit 1
    fi
}

# makepkg refuses to run as root, so flutter-bin is built directly from its
# AUR git repo rather than requiring an AUR helper (yay/paru) to be installed.
install_flutter_arch() {
    command -v flutter >/dev/null 2>&1 && return
    log "flutter not found; building flutter-bin from the AUR"
    sudo pacman -S --needed --noconfirm base-devel git
    BUILD_DIR="$(mktemp -d)"
    git clone --depth 1 "${AUR_FLUTTER_BIN_URL}" "${BUILD_DIR}/flutter-bin"
    (cd "${BUILD_DIR}/flutter-bin" && makepkg -si --noconfirm)
}

install_linux_desktop_deps_arch() {
    local -a pkgs=(clang cmake ninja pkgconf gtk3)
    local -a missing=()
    for pkg in "${pkgs[@]}"; do
        pacman -Qi "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
    done
    if ((${#missing[@]} > 0)); then
        log "installing missing build deps: ${missing[*]}"
        sudo pacman -S --needed --noconfirm "${missing[@]}"
    fi
}

# Prefers a real apt package if the user's mirrors happen to carry one;
# Ubuntu/Debian have none in the standard repos as of writing, so this
# normally falls back to cloning the upstream Flutter SDK.
install_flutter_debian() {
    command -v flutter >/dev/null 2>&1 && return
    log "flutter not found; checking apt for a flutter package"
    sudo apt-get update -qq
    if apt-cache show flutter >/dev/null 2>&1; then
        sudo apt-get install -y flutter
        return
    fi
    log "no apt package named 'flutter'; cloning the Flutter SDK instead"
    local install_dir="${HOME}/development/flutter"
    if [[ ! -d "${install_dir}" ]]; then
        sudo apt-get install -y git curl
        git clone --depth 1 -b stable https://github.com/flutter/flutter.git "${install_dir}"
    fi
    export PATH="${install_dir}/bin:${PATH}"
    log "flutter installed at ${install_dir}; add 'export PATH=\"${install_dir}/bin:\$PATH\"' to your shell rc to make this permanent"
}

install_linux_desktop_deps_debian() {
    local -a pkgs=(clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev)
    local -a missing=()
    for pkg in "${pkgs[@]}"; do
        dpkg -s "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
    done
    if ((${#missing[@]} > 0)); then
        log "installing missing build deps: ${missing[*]}"
        sudo apt-get update -qq
        sudo apt-get install -y "${missing[@]}"
    fi
}

main() {
    require_non_root
    local distro
    distro="$(detect_distro)"

    case "${distro}" in
        arch)
            install_flutter_arch
            install_linux_desktop_deps_arch
            ;;
        debian)
            install_flutter_debian
            install_linux_desktop_deps_debian
            ;;
    esac

    command -v flutter >/dev/null 2>&1 || { err "flutter still not on PATH after install"; exit 1; }

    cd "${SCRIPT_DIR}"
    flutter config --enable-linux-desktop >/dev/null
    log "fetching pub packages"
    flutter pub get
    log "launching the app"
    exec flutter run -d linux
}

main "$@"
