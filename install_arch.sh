#!/bin/bash
# Builds the todo Flutter app and installs it as an Arch Linux package via pacman.
# Run from anywhere — uses the directory of this script as the repo root.
# Requires: flutter, base-devel (provides makepkg), sudo for pacman.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$SCRIPT_DIR/build/linux/x64/release/bundle"
WORK_DIR="$(mktemp -d)"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# Parse version from pubspec.yaml (strip build number: 1.0.0+1 → 1.0.0)
PKGVER="$(grep '^version:' "$SCRIPT_DIR/pubspec.yaml" | sed 's/^version:[[:space:]]*//' | sed 's/+.*//')"

echo "==> Building todo $PKGVER (Flutter release)..."
cd "$SCRIPT_DIR"
flutter build linux --release

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
depends=('gtk3')
conflicts=('todo')
replaces=('todo')

package() {
    install -dm755 "\$pkgdir/opt/todo"
    cp -r "$BUNDLE_DIR/." "\$pkgdir/opt/todo/"
    chmod 755 "\$pkgdir/opt/todo/todo"

    install -dm755 "\$pkgdir/usr/bin"
    cat > "\$pkgdir/usr/bin/todo" <<'WRAPPER'
#!/bin/bash
exec /opt/todo/todo "\$@"
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
