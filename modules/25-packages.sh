#!/usr/bin/env bash
# modules/25-packages.sh -- install the learning, creative and play applications.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

install_list() {
    local cfg="$1" installer="$2" label="$3"
    step "Installing $label"
    local pkgs=() entry
    while IFS= read -r entry; do
        if have_pkg "$entry"; then
            note "$entry already installed."
        else
            pkgs+=("$entry")
        fi
    done < <(list_entries "$REPO_ROOT/$cfg")
    if [ "${#pkgs[@]}" -gt 0 ]; then
        note "Installing: ${pkgs[*]}"
        if [ "$installer" = aur_install ]; then
            # One at a time: a stale AUR package must not block the others.
            local p
            for p in "${pkgs[@]}"; do
                "$installer" "$p" || warn "AUR package '$p' failed to install; continuing."
            done
        else
            "$installer" "${pkgs[@]}"
        fi
    else
        note "nothing to install."
    fi
}

# Thonny from PyPI via uv, system-wide, so the child account can run it.
# The AUR package is often broken (its build pins an old uv_build).
install_thonny() {
    step "Installing Thonny (uv, system-wide)"
    if have_cmd thonny; then
        note "thonny already installed."
        return 0
    fi
    have_cmd uv || pkg_install uv
    run_shell "sudo UV_TOOL_DIR=/opt/thonny UV_TOOL_BIN_DIR=/usr/local/bin uv tool install thonny"
    install_root_stdin /usr/local/share/applications/thonny.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Thonny
Comment=Python IDE for beginners
Exec=/usr/local/bin/thonny
Icon=applications-development
Terminal=false
Categories=Development;IDE;
DESKTOP
}

module_main() {
    load_config
    require_parent
    require_omarchy_or_warn
    install_list config/packages.txt pkg_install "repository packages (config/packages.txt)"
    install_thonny
    install_list config/aur-packages.txt aur_install "AUR packages (config/aur-packages.txt)"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
