#!/usr/bin/env bash
# modules/50-desktop.sh -- the child's desktop: learning-first keybindings,
# hidden developer entries, a quieter bar, and the one sudo rule that lets the
# child's theme switch finish without asking for the parent's password.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

THEME_GRANT=/etc/sudoers.d/omarchy-kids-theme-browser
THEME_HELPER=/usr/bin/omarchy-theme-set-browser-policy

# omarchy-theme-set recolours the browsers by writing color.json into the
# root-owned policy directories through $THEME_HELPER. Without a NOPASSWD sudo
# entry for it the helper falls back to pkexec, and polkit asks a non-wheel user
# for an administrator's password. The helper accepts only six hex digits and
# writes a fixed JSON shape, so this grant cannot touch the allowlist policy.
render_theme_grant() {
    printf '%s ALL=(root) NOPASSWD: %s %s\n' "$KID_USER" "$THEME_HELPER" \
        '[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]'
}

install_theme_grant() {
    step "Letting $KID_USER's theme switch recolour the browser ($THEME_GRANT)"
    [ -x "$THEME_HELPER" ] || { warn "$THEME_HELPER not found; skipping"; return 0; }
    local rule
    rule="$(render_theme_grant)"
    visudo -cqf - <<<"$rule" || die "generated sudoers rule failed visudo"
    install_root_stdin "$THEME_GRANT" 440 <<<"$rule"
}

module_main() {
    load_config
    require_parent

    install_theme_grant

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
