#!/bin/sh
# Exports Linux + Windows builds (PCK embedded) and creates the release archives in dist/.
set -e
cd "$(dirname "$0")/.."
GODOT=${GODOT:-$HOME/.local/share/godot/godot}
rm -rf build dist && mkdir -p build/linux build/windows dist
"$GODOT" --headless --path . --export-release "Linux" build/linux/MishmeretLayla.x86_64
"$GODOT" --headless --path . --export-release "Windows" build/windows/MishmeretLayla.exe
# Linux: executable (+x), icon, .desktop and the menu-entry installer
P=build/pkg-linux/MishmeretLayla
mkdir -p "$P"
cp build/linux/MishmeretLayla.x86_64 "$P/"
chmod +x "$P/MishmeretLayla.x86_64"
cp icon.png "$P/icon.png"
cp packaging/mishmeret-layla.desktop packaging/install-desktop-entry.sh "$P/"
chmod +x "$P/install-desktop-entry.sh"
cp README.md CREDITS.md "$P/"
tar -C "$P" -czf dist/MishmeretLayla-linux.tar.gz .
# Windows
W=build/pkg-windows/MishmeretLayla
mkdir -p "$W"
cp build/windows/MishmeretLayla.exe README.md CREDITS.md "$W/"
(cd build/pkg-windows && zip -qr ../../dist/MishmeretLayla-windows.zip MishmeretLayla)
ls -la dist
