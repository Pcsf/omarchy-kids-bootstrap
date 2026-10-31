#!/usr/bin/env bash
# modules/45-screen-time.sh -- Timekpr-nExT: daily quota, allowed hours and a
# PlayTime quota for games, enforced by the system daemon through logind.
#
# Timekpr counts x11/wayland/mir sessions and EXCLUDES tty by default, which
# would make Ctrl+Alt+F3 a free terminal. The server config is changed to
# count tty sessions too. PlayTime is switched on globally (per-user PlayTime
# is ignored otherwise), and a user service pauses the quota while the
# child's screen is locked (Hyprland does not report the lock to logind).
# The quota state lives in /var/lib/timekpr and survives logout, relogin and
# reboot.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

TK_CONF=/etc/timekpr/timekpr.conf

install_timekpr() {
    step "Installing timekpr-next (AUR)"
    if have_pkg timekpr-next; then
        note "already installed."
    else
        aur_install timekpr-next
    fi
    as_root systemctl enable --now timekpr.service
}

count_tty_sessions() {
    step "Counting tty sessions as screen time"
    if [ "$DRY_RUN" -eq 0 ] && [ ! -f "$TK_CONF" ]; then
        die "$TK_CONF missing; did the package install?"
    fi
    if [ "$DRY_RUN" -eq 0 ] && grep -qE '^TIMEKPR_SESSION_TYPES_CTRL = .*tty' "$TK_CONF"; then
        note "already counted."
        return 0
    fi
    as_root sed -i \
        -e 's/^TIMEKPR_SESSION_TYPES_CTRL = .*/TIMEKPR_SESSION_TYPES_CTRL = x11;wayland;mir;tty/' \
        -e 's/^TIMEKPR_SESSION_TYPES_EXCL = .*/TIMEKPR_SESSION_TYPES_EXCL = unspecified/' \
        "$TK_CONF"
    as_root systemctl restart timekpr.service
}

# Per-user PlayTime is ignored (and reads back False) until PlayTime is
# switched on globally in timekpr.conf; timekpra has no option for that.
enable_playtime_globally() {
    [ "$PLAYTIME_ENABLED" = "1" ] || return 0
    step "Enabling PlayTime globally in $TK_CONF"
    if [ "$DRY_RUN" -eq 0 ] && grep -qE '^TIMEKPR_PLAYTIME_ENABLED = True' "$TK_CONF"; then
        note "already enabled."
        return 0
    fi
    as_root sed -i -e 's/^TIMEKPR_PLAYTIME_ENABLED = .*/TIMEKPR_PLAYTIME_ENABLED = True/' "$TK_CONF"
    as_root systemctl restart timekpr.service
}

# Hyprland's lock screen does not tell logind the session is locked, so
# Timekpr kept counting. A user service in the child's session sets the
# session's IdleHint/LockedHint while hyprlock runs.
install_lockhint() {
    step "Pausing screen time while the child's screen is locked"
    install_root_file system/bin/omarchy-kids-lockhint /usr/local/bin/omarchy-kids-lockhint 755
    install_root_stdin /etc/systemd/user/omarchy-kids-lockhint.service <<UNIT
# Installed by omarchy-kids-bootstrap (screen-time module).
[Unit]
Description=Tell logind when the screen is locked (Timekpr pauses)
ConditionUser=$KID_USER
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=/usr/local/bin/omarchy-kids-lockhint
Restart=always
RestartSec=5

[Install]
WantedBy=graphical-session.target
UNIT
    as_root systemctl --global enable omarchy-kids-lockhint.service
    # Apply an updated helper to a running child session right away.
    if [ "$DRY_RUN" -eq 0 ] && sudo systemctl --user -M "$KID_USER@" is-active --quiet omarchy-kids-lockhint.service 2>/dev/null; then
        sudo systemctl --user -M "$KID_USER@" daemon-reload || true
        sudo systemctl --user -M "$KID_USER@" restart omarchy-kids-lockhint.service || true
        note "restarted the helper in $KID_USER's running session"
    fi
}

tka() { as_root timekpra "$@"; }

configure_user() {
    step "Limits for $KID_USER"
    if [ "$DRY_RUN" -eq 0 ]; then
        # The daemon registers on the system bus a moment after it starts.
        local _
        for _ in 1 2 3 4 5; do
            sudo timekpra --getuserlist >/dev/null 2>&1 && break
            sleep 1
        done
    fi
    tka --setalloweddays "$KID_USER" "1;2;3;4;5;6;7"
    tka --settimelimits "$KID_USER" "$TIME_LIMITS"
    local d
    for d in 1 2 3 4 5; do tka --setallowedhours "$KID_USER" "$d" "$ALLOWED_HOURS_WEEKDAY"; done
    for d in 6 7;         do tka --setallowedhours "$KID_USER" "$d" "$ALLOWED_HOURS_WEEKEND"; done
    tka --setlockouttype "$KID_USER" "$LOCKOUT_TYPE"
    # Locked screen and idle time do not count.
    tka --settrackinactive "$KID_USER" false
    tka --sethidetrayicon "$KID_USER" false

    if [ "$PLAYTIME_ENABLED" = "1" ]; then
        step "PlayTime quota for games"
        tka --setplaytimealloweddays "$KID_USER" "1;2;3;4;5;6;7"
        tka --setplaytimelimits "$KID_USER" "$PLAYTIME_LIMITS"
        tka --setplaytimeactivities "$KID_USER" "$PLAYTIME_ACTIVITIES"
        # PlayTime counts inside the daily total, not on top of it.
        tka --setplaytimelimitoverride "$KID_USER" false
        # Needs TIMEKPR_PLAYTIME_ENABLED = True (enable_playtime_globally).
        # Note: on timekpr-next 0.5.x --getuserinfo keeps showing
        # PLAYTIME_ENABLED: False even while PlayTime is enforced; check
        # --getuserinfort (ACTUAL_PLAYTIME_LEFT_DAY falls while a game runs).
        tka --setplaytimeenabled "$KID_USER" true
    else
        tka --setplaytimeenabled "$KID_USER" false
    fi

    [ "$DRY_RUN" -eq 1 ] && return 0
    step "Effective configuration"
    sudo timekpra --getuserinfo "$KID_USER" | sed 's/^/    /'
}

module_main() {
    load_config
    require_parent
    install_timekpr
    count_tty_sessions
    enable_playtime_globally
    configure_user
    install_lockhint
    note "Parent tools: 'sudo timekpra --settimeleft $KID_USER + 30m' adds time today;"
    note "'sudo timekpra --getuserinfort $KID_USER' shows today's usage. GUI: timekpr-admin."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
