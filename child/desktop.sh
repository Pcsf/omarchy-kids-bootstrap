#!/usr/bin/env bash
# child/desktop.sh "<desktop ids>" -- runs AS THE CHILD: hide launchers, trim the bar.
set -euo pipefail
: "${OMARCHY_PATH:=/usr/share/omarchy}"
export OMARCHY_PATH PATH="$OMARCHY_PATH/bin:$PATH"
apps_dir="$HOME/.local/share/applications"
mkdir -p "$apps_dir"

for id in ${1:-}; do
    # A local entry with the same id overrides the system one; an existing
    # Omarchy-generated file is left alone and just gets NoDisplay.
    f="$apps_dir/$id"
    if [ -f "$f" ]; then
        grep -q '^NoDisplay=true' "$f" || printf 'NoDisplay=true\n' >>"$f"
    else
        printf '[Desktop Entry]\nType=Application\nName=%s\nNoDisplay=true\nHidden=true\n' "${id%.desktop}" >"$f"
    fi
done
update-desktop-database "$apps_dir" 2>/dev/null || true
echo "    hidden ${1:+$(wc -w <<<"$1")} launcher ids"

# The bar: no update prompt (the parent updates over SSH) and no agents widget.
shell_json="$HOME/.config/omarchy/shell.json"
if [ -f "$shell_json" ] && command -v jq >/dev/null; then
    tmp="$(mktemp)"
    jq 'walk(if type == "array" then map(select((type == "object" and (.id == "omarchy.system-update" or .id == "omarchy.agents")) | not)) else . end)' \
        "$shell_json" >"$tmp" && mv "$tmp" "$shell_json"
    echo "    bar: removed system-update and agents widgets"
fi
