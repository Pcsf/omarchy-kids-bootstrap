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
# Sorts after Omarchy's own 99-omarchy-login.conf, so it wins (last file wins).
OVERRIDE="$SDDM_DIR/zz-omarchy-kids-login.conf"
OLD_OVERRIDE="$SDDM_DIR/99-omarchy-kids-login.conf"

# Omarchy's login theme logs in only the last user and has no picker, so the
# child could never choose their account. "omarchy-kids" is a copy of it
# (same images) with a Left/Right user picker; see config/sddm/Main.qml.
install_login_theme() {
    case "$KIDS_LOGIN_THEME" in
        omarchy-kids) ;;
        *) return 0 ;;
    esac
    local src=/usr/share/sddm/themes/omarchy dst=/usr/share/sddm/themes/omarchy-kids
    step "Installing SDDM theme omarchy-kids (user picker)"
    if [ ! -d "$src" ] && [ "$DRY_RUN" -eq 0 ]; then
        warn "$src not found; keeping the default login theme."
        KIDS_LOGIN_THEME=omarchy
        return 0
    fi
    as_root rm -rf "$dst"
    as_root cp -a "$src" "$dst"
    install_root_file config/sddm/Main.qml "$dst/Main.qml"
}

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

    [ -f "$OLD_OVERRIDE" ] && as_root rm -f "$OLD_OVERRIDE"

    install_login_theme
    local theme_conf=""
    if [ -n "$KIDS_LOGIN_THEME" ]; then
        theme_conf="[Theme]
Current=$KIDS_LOGIN_THEME
"
    fi
    install_root_stdin "$OVERRIDE" <<CONF
# Installed by omarchy-kids-bootstrap (login module).
# A shared family machine always asks who is logging in.
[Autologin]
User=
Session=

[Users]
RememberLastUser=true

$theme_conf
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
