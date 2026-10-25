#!/usr/bin/env bash
# modules/20-child-account.sh -- create the unprivileged child account and give
# it a working Omarchy desktop without Omarchy's developer extras.
#
# useradd -m copies /etc/skel, which on Omarchy 4 is the whole per-user
# config (Hyprland, shell bar, terminals). What skel cannot do is run with
# $HOME set: theme, keyring, user dirs. Omarchy does that in
# omarchy-provision-user, but that script also installs a dozen AI coding
# agents through mise and fetches Node, which a child's account does not
# need. child/provision.sh does the same essential steps by hand and marks
# Omarchy's own finalization done so first login does not redo it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

PRIVILEGED_GROUPS=(wheel sudo docker adm root libvirt kvm)

create_account() {
    step "Child account: $KID_USER"
    if kid_exists; then
        note "exists: $(id "$KID_USER")"
    else
        as_root useradd -m -s /bin/bash -c "$KID_FULL_NAME" "$KID_USER"
    fi

    local g
    for g in "${PRIVILEGED_GROUPS[@]}"; do
        if kid_exists && id -nG "$KID_USER" | tr ' ' '\n' | grep -qx "$g"; then
            warn "$KID_USER is in privileged group '$g'; removing"
            as_root gpasswd -d "$KID_USER" "$g"
        fi
    done

    if [ "$DRY_RUN" -eq 0 ]; then
        local status
        status="$(sudo passwd -S "$KID_USER" | awk '{print $2}')"
        if [ "$status" != "P" ]; then
            note "setting the child's password (status: $status)"
            sudo passwd "$KID_USER"
        else
            note "password already set"
        fi
    else
        note "[dry-run] would prompt for the child's password if none is set"
    fi
}

protect_parent_home() {
    step "Protecting the parent's home"
    local home
    home="$(getent passwd "$PARENT_USER" | cut -d: -f6)"
    if [ "$(stat -c '%a' "$home")" = "700" ]; then
        note "$home already 700"
    else
        as_root chmod 700 "$home"
    fi
}

create_project_dirs() {
    step "Child project directories"
    local home d
    home="$(kid_home)"
    for d in Documents Projects Pictures Designs Videos Downloads; do
        as_root install -d -m 755 -o "$KID_USER" -g "$KID_USER" "$home/$d"
    done
    as_root install -d -m 755 "$KIDS_ETC"
    # Settings the system-side helpers (lockdown hook, backup timer) read.
    install_root_stdin "$KIDS_ETC/kids.env" <<ENV
# Written by omarchy-kids-bootstrap; edit config/kids.conf and re-run instead.
KID_USER=$KID_USER
PARENT_USER=$PARENT_USER
ENV
}

provision_desktop() {
    step "Provisioning the child's Omarchy desktop (theme, keyring, user dirs)"
    as_kid_script child/provision.sh
}

module_main() {
    load_config
    require_parent
    create_account
    protect_parent_home
    create_project_dirs
    provision_desktop
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
