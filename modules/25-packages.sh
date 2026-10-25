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
        "$installer" "${pkgs[@]}"
    else
        note "nothing to install."
    fi
}

module_main() {
    load_config
    require_parent
    require_omarchy_or_warn
    install_list config/packages.txt pkg_install "repository packages (config/packages.txt)"
    install_list config/aur-packages.txt aur_install "AUR packages (config/aur-packages.txt)"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
