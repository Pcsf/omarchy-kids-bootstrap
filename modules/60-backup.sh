#!/usr/bin/env bash
# modules/60-backup.sh -- daily restic backup of the child's work to a
# separate destination (external disk or NAS mount), run by a system timer.
# The repository password is created by the parent outside git.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

instructions() {
    step "Backups not configured"
    note "1. Mount the backup disk or NAS share (e.g. /mnt/backup) and set RESTIC_REPO in config/kids.conf."
    note "2. Create the password file (never in git):"
    note "     sudo install -d -m 700 $KIDS_ETC"
    note "     (umask 077; openssl rand -base64 32 | sudo tee $RESTIC_PASSWORD_FILE >/dev/null)"
    note "   and keep a copy of it in the family password manager: without it the backup is unreadable."
    note "3. Re-run: ./bootstrap.sh --only backup"
}

module_main() {
    load_config
    require_parent
    if [ -z "$RESTIC_REPO" ]; then instructions; return 0; fi
    if [ "$DRY_RUN" -eq 0 ] && ! sudo test -s "$RESTIC_PASSWORD_FILE"; then
        warn "missing $RESTIC_PASSWORD_FILE"
        instructions
        return 0
    fi

    have_pkg restic || pkg_install restic

    step "Installing the backup job"
    install_root_file system/sbin/omarchy-kids-backup /usr/local/sbin/omarchy-kids-backup 755
    install_root_file config/backup-paths.txt "$KIDS_ETC/backup-paths.txt"
    install_root_stdin "$KIDS_ETC/backup.env" 600 <<ENV
# Written by omarchy-kids-bootstrap (backup module).
RESTIC_REPOSITORY=$RESTIC_REPO
RESTIC_PASSWORD_FILE=$RESTIC_PASSWORD_FILE
KID_USER=$KID_USER
ENV
    install_root_file system/systemd/omarchy-kids-backup.service /etc/systemd/system/omarchy-kids-backup.service
    install_root_stdin /etc/systemd/system/omarchy-kids-backup.timer <<UNIT
[Unit]
Description=Daily omarchy-kids restic backup

[Timer]
OnCalendar=$BACKUP_ONCALENDAR
Persistent=true
RandomizedDelaySec=10m

[Install]
WantedBy=timers.target
UNIT
    as_root systemctl daemon-reload
    as_root systemctl enable --now omarchy-kids-backup.timer

    step "Initializing the repository if needed, then a first backup"
    as_root /usr/local/sbin/omarchy-kids-backup
    note "Restore guide: docs/operations.org"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
