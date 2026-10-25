#!/usr/bin/env bash
# modules/15-login.sh -- require a password at the login screen; set the hostname.
#
# Omarchy's installer writes /etc/sddm.conf.d/autologin.conf for the owner.
# On a shared machine the login screen must ask who is sitting down, so the
# file is renamed (SDDM reads only *.conf) and an override with an empty
# Autologin user is installed on top, in case a future Omarchy step writes
# the autologin file again.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

SDDM_DIR=/etc/sddm.conf.d
OVERRIDE="$SDDM_DIR/99-omarchy-kids-login.conf"

disable_autologin() {
    step "Disabling SDDM autologin"
    local f
    for f in "$SDDM_DIR"/*.conf; do
        [ -f "$f" ] || continue
        [ "$f" = "$OVERRIDE" ] && continue
        if grep -qsE '^\s*\[Autologin\]' "$f" && grep -qsE '^\s*User\s*=\s*\S' "$f"; then
            note "autologin user found in $f"
            as_root mv "$f" "$f.disabled-by-omarchy-kids"
        fi
    done

    install_root_stdin "$OVERRIDE" <<CONF
# Installed by omarchy-kids-bootstrap (login module).
# A shared family machine always asks who is logging in.
[Autologin]
User=
Session=

[Users]
RememberLastUser=true
CONF

    # getty on tty1 could also auto-login; Omarchy does not ship that, so a
    # drop-in doing it is somebody's manual change worth flagging.
    if grep -rqs -- '--autologin' /etc/systemd/system/getty@tty1.service.d 2>/dev/null; then
        warn "getty@tty1 has an --autologin drop-in; remove it by hand (sudo systemctl revert getty@tty1)"
    else
        note "tty1 getty: no autologin"
    fi
}

set_hostname() {
    [ -n "$KIDS_HOSTNAME" ] || return 0
    step "Hostname"
    local current
    current="$(hostnamectl --static 2>/dev/null || cat /etc/hostname 2>/dev/null || true)"
    if [ "$current" = "$KIDS_HOSTNAME" ]; then
        note "already $KIDS_HOSTNAME"
    else
        as_root hostnamectl set-hostname "$KIDS_HOSTNAME"
    fi
}

verify() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    step "Verifying"
    if grep -hsE '^\s*User\s*=\s*\S' "$SDDM_DIR"/*.conf 2>/dev/null | grep -q .; then
        die "an SDDM *.conf still names an autologin user; inspect $SDDM_DIR"
    fi
    note "no SDDM autologin user remains; the change is complete after the next reboot"
}

module_main() {
    load_config
    require_parent
    disable_autologin
    set_hostname
    verify
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
