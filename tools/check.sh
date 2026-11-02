#!/bin/bash
cd "$(dirname "$0")/.."
for f in $(find scripts -name "*.gd"); do
  timeout 60 ~/.local/share/godot/godot --headless --path . --check-only --script $f 2>&1 | grep -A1 "SCRIPT ERROR" | grep -v "^--$" | paste -d' ' - -
done | grep -vE "Identifier not found: (Settings|Sfx)|Failed to compile depended" | sed 's/SCRIPT ERROR: //; s/ *at: GDScript::reload//' | sort -u
