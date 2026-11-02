#!/bin/sh
# Installs a menu entry for Mishmeret Layla for the current user only (no sudo).
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor/256x256/apps"
mkdir -p "$APPS" "$ICONS"
chmod +x "$DIR/MishmeretLayla.x86_64"
cp "$DIR/icon.png" "$ICONS/mishmeret-layla.png"
sed -e "s|^Exec=.*|Exec=\"$DIR/MishmeretLayla.x86_64\"|" -e "s|^Icon=.*|Icon=$ICONS/mishmeret-layla.png|" \
    -e "/^StartupWMClass/a Path=$DIR" "$DIR/mishmeret-layla.desktop" > "$APPS/mishmeret-layla.desktop"
chmod +x "$APPS/mishmeret-layla.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" >/dev/null 2>&1 || true
echo "Installed: $APPS/mishmeret-layla.desktop"
