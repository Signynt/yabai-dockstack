#!/bin/sh
# Pin / unpin the focused window on top of other windows (yabai sub-layer).
# Needs yabai's scripting addition: without it the sub-layer change fails and
# nothing else is touched. Pinning a tiled window also floats it; unpinning
# re-tiles only a window that pinning floated.

win=$(yabai -m query --windows --window) || exit 0
id=$(printf '%s' "$win" | jq -r '.id')
marker="${TMPDIR:-/tmp}/yabai-dockstack-pin-floated-$id"

if [ "$(printf '%s' "$win" | jq -r '."sub-layer"')" = "above" ]; then
  yabai -m window --sub-layer normal || exit 1
  if [ -f "$marker" ]; then
    rm -f "$marker"
    yabai -m window --toggle float
  fi
else
  yabai -m window --sub-layer above || exit 1
  if [ "$(printf '%s' "$win" | jq -r '."is-floating"')" = "false" ]; then
    yabai -m window --toggle float && touch "$marker"
  fi
fi
