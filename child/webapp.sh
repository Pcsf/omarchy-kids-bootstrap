#!/usr/bin/env bash
# child/webapp.sh <name> <url> [icon] -- runs AS THE CHILD: install one Omarchy web app.
set -euo pipefail
: "${OMARCHY_PATH:=/usr/share/omarchy}"
export OMARCHY_PATH PATH="$OMARCHY_PATH/bin:$PATH"
name="$1" url="$2" icon="${3:-}"
if [ -f "$HOME/.local/share/applications/$name.desktop" ]; then
    echo "    $name already installed"
    exit 0
fi
# An empty icon makes Omarchy fetch the site's own; when that fails offline,
# fall back to a generic icon so the launcher still appears.
if ! omarchy-webapp-install "$name" "$url" "$icon" "" ""; then
    echo "    icon fetch failed for $name; installing with a generic icon"
    omarchy-webapp-install "$name" "$url" "applications-education" "" ""
fi
echo "    installed web app: $name"
