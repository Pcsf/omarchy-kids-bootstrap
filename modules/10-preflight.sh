#!/usr/bin/env bash
# modules/10-preflight.sh -- report the machine state the other modules rely on.
# Read-only: it never changes anything, with or without --dry-run.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

module_main() {
    load_config
    require_parent
    require_omarchy_or_warn

    step "Omarchy"
    if [ -r /etc/os-release ]; then
        note "$(grep -E '^(PRETTY_NAME|BUILD_ID)=' /etc/os-release | tr '\n' ' ')"
    fi
    have_cmd omarchy-provision-user && note "per-user provisioning: omarchy-provision-user present"
    [ -d /etc/skel/.config/hypr ] && note "/etc/skel carries the Omarchy Hyprland config (new users get it)"

    step "Accounts"
    note "parent: $PARENT_USER (groups: $(id -nG "$PARENT_USER" | tr ' ' ','))"
    if kid_exists; then
        note "child:  $KID_USER exists (groups: $(id -nG "$KID_USER" | tr ' ' ','))"
    else
        note "child:  $KID_USER does not exist yet (child-account module creates it)"
    fi
    note "parent home mode: $(stat -c '%a %U' "$(getent passwd "$PARENT_USER" | cut -d: -f6)")"

    step "Disk"
    note "root fs: $(findmnt -no FSTYPE,SOURCE /)"
    if lsblk -no TYPE | grep -q crypt; then
        note "LUKS: a dm-crypt device is present"
    else
        warn "LUKS: no dm-crypt device found; the plan assumes full-disk encryption"
    fi
    if have_cmd snapper && [ -f /etc/snapper/configs/root ]; then
        note "snapper: root config present (snapshot module will use it)"
    else
        warn "snapper: no root config; snapshots skipped (configure with Omarchy's install/config/snapper.sh)"
    fi

    step "Login manager"
    if grep -qsE '^\s*User\s*=\s*\S' /etc/sddm.conf.d/*.conf 2>/dev/null; then
        warn "SDDM autologin is configured (login module disables it)"
    else
        note "SDDM autologin: not configured"
    fi

    step "Network"
    note "NetworkManager: $(systemctl is-active NetworkManager 2>/dev/null || true), systemd-resolved: $(systemctl is-active systemd-resolved 2>/dev/null || true), ufw: $(systemctl is-active ufw 2>/dev/null || true)"
    if [ -z "$NEXTDNS_PROFILE_ID" ]; then
        warn "NEXTDNS_PROFILE_ID is empty; the dns module will only print instructions"
    fi

    step "Config summary"
    note "hostname: ${KIDS_HOSTNAME:-(unchanged)}  theme: $KID_THEME  lockdown: $LOCKDOWN_ENABLED"
    note "time limits Mon..Sun: $TIME_LIMITS  lockout: $LOCKOUT_TYPE  playtime: $PLAYTIME_ENABLED ($PLAYTIME_LIMITS)"
    note "restic repo: ${RESTIC_REPO:-(unset, backup module prints instructions)}"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
