#!/usr/bin/env bash
# modules/65-ssh-admin.sh -- remote administration: sshd for the parent only,
# key-based once a key is authorized, reachable from the LAN subnet.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

DROPIN=/etc/ssh/sshd_config.d/20-omarchy-kids-admin.conf

module_main() {
    load_config
    require_parent

    step "OpenSSH server"
    have_pkg openssh || pkg_install openssh
    as_root systemctl enable --now sshd.service

    local keys="$HOME/.ssh/authorized_keys" passwordless=no
    case "$SSH_PASSWORDLESS" in
        yes) passwordless=yes ;;
        no) passwordless=no ;;
        *) [ -s "$keys" ] && passwordless=yes ;;
    esac
    if [ "$passwordless" = "no" ]; then
        warn "no authorized key for $PARENT_USER; password logins stay on."
        warn "add one (ssh-copy-id from your laptop) and re-run --only ssh-admin."
    fi

    step "sshd drop-in: $DROPIN"
    install_root_stdin "$DROPIN" <<CONF
# Installed by omarchy-kids-bootstrap (ssh-admin module).
AllowUsers $PARENT_USER
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication $([ "$passwordless" = yes ] && echo no || echo yes)
KbdInteractiveAuthentication $([ "$passwordless" = yes ] && echo no || echo yes)
X11Forwarding no
CONF

    if [ "$DRY_RUN" -eq 0 ]; then
        if ! sudo sshd -t; then
            sudo rm -f "$DROPIN"
            die "sshd rejected the drop-in; removed it, service untouched"
        fi
        if ! sudo sshd -T | grep -qi "^allowusers $PARENT_USER"; then
            warn "AllowUsers did not take effect (an earlier config sets it); check: sudo sshd -T | grep -i allowusers"
        fi
        sudo systemctl reload sshd.service
    fi

    if have_cmd ufw; then
        step "Firewall: SSH from ${LAN_CIDR:-anywhere} (rate limited)"
        if [ -n "$LAN_CIDR" ]; then
            as_root ufw limit from "$LAN_CIDR" to any port 22 proto tcp comment "omarchy-kids: parent ssh"
            # Omarchy's own setup opens 22 to everyone; narrow it when present.
            run_shell "sudo ufw status | grep -q '^22/tcp.*LIMIT.*Anywhere' && sudo ufw delete limit 22/tcp || true"
        else
            as_root ufw limit 22/tcp comment "omarchy-kids: parent ssh"
        fi
        as_root ufw reload
    fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
