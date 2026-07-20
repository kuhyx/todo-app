#!/bin/bash
# Builds the todo Flutter app and installs it as an Arch Linux package via pacman.
# Run from anywhere — uses the directory of this script as the repo root.
# Requires: flutter, base-devel (provides makepkg), sudo for pacman.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The desktop app is a Flutter *web* build served by a small local wrapper.
# Flutter's Linux embedder only reaches ~20fps at 4K on this hardware, while
# the same Dart code in Chrome sustains ~144fps — see
# docs/desktop-performance-findings.md for the measurements.
WEB_DIR="$SCRIPT_DIR/build/web"
WRAPPER_BUNDLE="$SCRIPT_DIR/build/cli/bundle"
WORK_DIR="$(mktemp -d)"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# Parse version from pubspec.yaml (strip build number: 1.0.0+1 → 1.0.0)
PKGVER="$(grep '^version:' "$SCRIPT_DIR/pubspec.yaml" | sed 's/^version:[[:space:]]*//' | sed 's/+.*//')"

echo "==> Building todo $PKGVER (Flutter web release)..."
cd "$SCRIPT_DIR"
flutter build web --release

echo "==> Compiling the desktop wrapper..."
# AOT-compiled so the installed package needs no Dart SDK at run time.
# `dart build cli`, not `dart compile exe`: the package pulls in dependencies
# with native build hooks (sqlite3, objective_c), which `dart compile` refuses
# to handle even though the wrapper itself uses none of them.
rm -rf "$SCRIPT_DIR/build/cli"
dart build cli -o "$SCRIPT_DIR/build/cli"

echo "==> Generating PKGBUILD..."
# pkgname is 'todo-flutter', NOT 'todo': the AUR already ships an unrelated
# package literally named 'todo' (a todo.txt CLI). Sharing the name made pacman
# treat them as one package — `yay -Sua` kept trying to "upgrade" this app to
# the AUR tool. conflicts/replaces let a clean upgrade supersede any stray
# 'todo' still installed under the old name.
cat > "$WORK_DIR/PKGBUILD" <<EOF
pkgname=todo-flutter
pkgver=$PKGVER
pkgrel=1
pkgdesc='Offline-first notes app'
arch=('x86_64')
url='https://github.com/kuhyx/todo-app'
license=('custom')
# No hard browser dependency. A Chrome-family browser renders the UI, but
# naming one as a dependency is wrong here: makepkg installs it, and this
# system has a policy that immediately removes 'chromium' again, which then
# fails dependency resolution. The wrapper discovers whatever browser is
# actually present (including Thorium) and reports clearly if none is.
depends=()
optdepends=('chromium: renders the app window'
            'google-chrome: renders the app window')
conflicts=('todo')
replaces=('todo')
# Flutter release binaries are already stripped/AOT-compiled with no
# extractable DWARF debug info, so a split -debug package is pointless here
# and gdb-add-index just fails noisily on every binary. Skip it, overriding
# the system-wide 'debug' OPTIONS setting.
# !strip is load-bearing: the wrapper is a Dart AOT executable with its snapshot
# embedded in the ELF, and stripping it discards that snapshot. The stripped
# binary still runs but is just the bare Dart VM, which prints a usage message
# instead of starting the app.
options=('!strip' '!debug')

package() {
    # Preserve the bundle's bin/ + lib/ layout: the executable loads its
    # native libraries from ../lib, and resolves the web assets from ../web.
    install -dm755 "\$pkgdir/opt/todo"
    cp -r "$WRAPPER_BUNDLE/bin" "\$pkgdir/opt/todo/bin"
    cp -r "$WRAPPER_BUNDLE/lib" "\$pkgdir/opt/todo/lib"
    chmod 755 "\$pkgdir/opt/todo/bin/todo_desktop"

    install -dm755 "\$pkgdir/opt/todo/web"
    cp -r "$WEB_DIR/." "\$pkgdir/opt/todo/web/"

    install -dm755 "\$pkgdir/usr/bin"
    cat > "\$pkgdir/usr/bin/todo" <<'WRAPPER'
#!/bin/bash
exec /opt/todo/bin/todo_desktop "\$@"
WRAPPER
    chmod 755 "\$pkgdir/usr/bin/todo"
}
EOF

# Remove any package still installed under the old 'todo' name (this app's
# prior builds, or the unrelated AUR 'todo' CLI). Both own /usr/bin/todo and
# would cause a file conflict when todo-flutter installs. -Rdd skips dep checks
# so an installed todo-debug can't block removal.
for stale in todo todo-debug; do
    if pacman -Qq "$stale" &>/dev/null; then
        echo "==> Removing stale '$stale' package (name-collision cleanup)..."
        sudo pacman -Rdd --noconfirm "$stale"
    fi
done

echo "==> Installing package via makepkg..."
cd "$WORK_DIR"
makepkg -sif --noconfirm

# Remove stale wrappers that shadow /usr/bin/todo from the package.
# ~/.local/bin and /usr/local/bin both precede /usr/bin in PATH.
if [[ -f "$HOME/.local/bin/todo" ]]; then
    echo "==> Removing old ~/.local/bin/todo..."
    rm "$HOME/.local/bin/todo"
fi
if [[ -f "/usr/local/bin/todo" ]]; then
    echo "==> Removing old /usr/local/bin/todo (requires sudo)..."
    sudo rm "/usr/local/bin/todo"
fi

echo "==> Done. 'todo' now runs version $PKGVER installed via pacman."
