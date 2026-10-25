#!/usr/bin/env bash
# modules/50-desktop.sh -- the child's desktop: learning-first keybindings,
# hidden developer entries, a quieter bar. Interface only; no security here.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

module_main() {
    load_config
    require_parent

    step "Hyprland config for $KID_USER (home/.config/hypr)"
    install_kid_file home/.config/hypr/hyprland.lua .config/hypr/hyprland.lua
    install_kid_file home/.config/hypr/bindings.lua .config/hypr/bindings.lua

    step "Hiding developer launchers and trimming the bar"
    as_kid_script child/desktop.sh "$(list_entries "$REPO_ROOT/config/hidden-apps.txt" | tr '\n' ' ')"

    note "The child's Hyprland reloads on next login (or: hyprctl reload inside the child's session)."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
