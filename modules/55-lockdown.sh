#!/usr/bin/env bash
# modules/55-lockdown.sh -- second-layer restrictions for the child account:
# - file ACLs deny the child the browsers and network tools in
#   config/blocked-commands.txt; a pacman hook re-applies them after every
#   transaction, because a package upgrade replaces the file and its ACL;
# - su is limited to wheel (pam_wheel), so the child cannot become another
#   user even with a guessed password.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

HELPER=/usr/local/sbin/omarchy-kids-lockdown
HOOK=/etc/pacman.d/hooks/90-omarchy-kids-lockdown.hook

install_helper() {
    step "Installing the ACL helper and pacman hook"
    install_root_file system/sbin/omarchy-kids-lockdown "$HELPER" 755
    install_root_file config/blocked-commands.txt "$KIDS_ETC/blocked-commands.txt"
    install_root_file system/pacman-hooks/90-omarchy-kids-lockdown.hook "$HOOK"
}

apply_acls() {
    step "Applying ACLs for $KID_USER"
    as_root "$HELPER"
}

restrict_su() {
    step "Limiting su to wheel"
    local f
    for f in /etc/pam.d/su /etc/pam.d/su-l; do
        [ -f "$f" ] || continue
        if grep -qE '^auth\s+required\s+pam_wheel\.so use_uid' "$f"; then
            note "$f already restricted"
        else
            as_root sed -i 's/^#\(auth\s\+required\s\+pam_wheel\.so use_uid\)/\1/' "$f"
        fi
    done
}

module_main() {
    load_config
    require_parent
    if [ "$LOCKDOWN_ENABLED" != "1" ]; then
        step "Lockdown disabled in config/kids.conf"
        return 0
    fi
    install_helper
    apply_acls
    restrict_su
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
