#!/usr/bin/env bash
# tests/acceptance.sh -- run AS THE PARENT after bootstrap.sh: checks the
# security properties the plan requires. Every check prints PASS or FAIL;
# the exit code is non-zero when anything fails. Needs sudo for a few reads.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT DRY_RUN=1
# shellcheck source=../lib/common.sh
source "$REPO_ROOT/lib/common.sh"
load_config
fail=0
pass() { printf 'PASS  %s\n' "$*"; }
failed() { printf 'FAIL  %s\n' "$*"; fail=1; }
check() { local msg="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$msg"; else failed "$msg"; fi; }
kid_home_dir="$(kid_home)"
parent_home="$(getent passwd "$PARENT_USER" | cut -d: -f6)"

echo "== accounts =="
check "child $KID_USER exists" id "$KID_USER"
if id -nG "$KID_USER" 2>/dev/null | tr ' ' '\n' | grep -qxE 'wheel|sudo|docker|adm|root'; then
    failed "child is in a privileged group: $(id -nG "$KID_USER")"
else
    pass "child is in no privileged group ($(id -nG "$KID_USER" 2>/dev/null))"
fi
if sudo -l -U "$KID_USER" 2>/dev/null | grep -qE '\(ALL|may run the following'; then
    failed "sudo grants $KID_USER something: $(sudo -l -U "$KID_USER" | tail -3 | tr '\n' ' ')"
else
    pass "sudo grants $KID_USER nothing"
fi
check "parent home $parent_home is mode 700" test "$(stat -c '%a' "$parent_home")" = "700"
check "child home is not world-writable" test "$(stat -c '%a' "$kid_home_dir" | cut -c3)" != "7"
# Planted negative: the privileged-group test must fire for the parent.
id -nG "$PARENT_USER" | tr ' ' '\n' | grep -qx wheel && pass "(planted) group check detects wheel on $PARENT_USER" || failed "(planted) group check cannot see wheel"

echo "== login =="
if grep -hsE '^\s*User\s*=\s*\S' /etc/sddm.conf.d/*.conf 2>/dev/null | grep -q .; then
    failed "an SDDM conf still names an autologin user"
else
    pass "no SDDM autologin user"
fi
check "login override installed" test -f /etc/sddm.conf.d/99-omarchy-kids-login.conf
check "no getty autologin on tty1" bash -c '! grep -rqs -- --autologin /etc/systemd/system/getty@tty1.service.d'

echo "== browser policy =="
pol=/etc/chromium/policies/managed/omarchy-kids.json
check "policy file present" test -f "$pol"
check "policy root-owned 644" test "$(stat -c '%U:%a' "$pol" 2>/dev/null)" = "root:644"
check "policy blocks everything by default" test "$(jq -r '.URLBlocklist[0]' "$pol" 2>/dev/null)" = "*"
check "policy allowlist non-empty" test "$(jq '.URLAllowlist | length' "$pol" 2>/dev/null)" -gt 0
check "child cannot write the policy" bash -c "! sudo -u $KID_USER test -w $pol"
check "policy dir not writable by child" bash -c "! sudo -u $KID_USER test -w /etc/chromium/policies/managed"

echo "== dns =="
if [ -n "$NEXTDNS_PROFILE_ID" ]; then
    check "resolved drop-in present" test -f /etc/systemd/resolved.conf.d/50-omarchy-kids-nextdns.conf
    check "resolved reports DNSOverTLS" bash -c "resolvectl status | grep -q '+DNSOverTLS'"
    probe="$(curl -fsS --max-time 10 https://test.nextdns.io 2>/dev/null || true)"
    if grep -q "\"profile\": *\"$NEXTDNS_PROFILE_ID\"" <<<"$probe"; then
        pass "test.nextdns.io served by profile $NEXTDNS_PROFILE_ID"
    else
        failed "test.nextdns.io did not report profile $NEXTDNS_PROFILE_ID: ${probe:-no answer}"
    fi
    check "ufw denies plain DNS out" bash -c "sudo ufw status | grep -q 'omarchy-kids: no plain DNS'"
    # Plain DNS to a public resolver must fail (dig may be ACL-denied; use resolvectl/bash tcp).
    if timeout 3 bash -c 'exec 3<>/dev/tcp/1.1.1.1/53' 2>/dev/null; then
        failed "plain DNS to 1.1.1.1:53 is reachable"
    else
        pass "plain DNS to 1.1.1.1:53 is blocked"
    fi
else
    echo "SKIP  dns (NEXTDNS_PROFILE_ID empty)"
fi

echo "== screen time =="
check "timekpr.service active" systemctl is-active timekpr.service
check "tty sessions counted" grep -qE '^TIMEKPR_SESSION_TYPES_CTRL = .*tty' /etc/timekpr/timekpr.conf
if sudo timekpra --getuserinfo "$KID_USER" 2>/dev/null | grep -q .; then
    pass "timekpr has a configuration for $KID_USER"
    sudo timekpra --getuserinfo "$KID_USER" | grep -E 'LIMITS_PER_WEEKDAYS|ALLOWED_HOURS_1|LOCKOUT|PLAYTIME_ENABLED' | sed 's/^/      /'
else
    failed "timekpr has no configuration for $KID_USER"
fi
check "child cannot stop timekpr" bash -c "! sudo -u $KID_USER systemctl stop timekpr.service"
check "child cannot run timekpra" bash -c "! sudo -u $KID_USER timekpra --getuserlist"

echo "== lockdown =="
if [ "$LOCKDOWN_ENABLED" = "1" ]; then
    check "pacman hook installed" test -f /etc/pacman.d/hooks/90-omarchy-kids-lockdown.hook
    check "su limited to wheel" grep -qE '^auth\s+required\s+pam_wheel\.so use_uid' /etc/pam.d/su
    n=0; d=0
    while IFS= read -r p; do
        [ -f "$p" ] || continue
        n=$((n + 1))
        getfacl -p "$p" 2>/dev/null | grep -qx "user:$KID_USER:---" && d=$((d + 1))
    done < <(list_entries "$REPO_ROOT/config/blocked-commands.txt")
    [ "$n" -eq "$d" ] && pass "ACL denies $d/$n present blocked commands" || failed "ACL missing on $((n - d)) of $n blocked commands"
    check "(planted) ACL check sees the child can run chromium" bash -c "sudo -u $KID_USER test -x /usr/bin/chromium"
else
    echo "SKIP  lockdown disabled"
fi

echo "== backup =="
if [ -n "$RESTIC_REPO" ]; then
    check "backup timer enabled" systemctl is-enabled omarchy-kids-backup.timer
    check "password file root-only" test "$(sudo stat -c '%U:%a' "$RESTIC_PASSWORD_FILE" 2>/dev/null)" = "root:600"
    check "repository readable" sudo bash -c "set -a; . $KIDS_ETC/backup.env; restic snapshots --latest 1"
    check "child cannot read the password" bash -c "! sudo -u $KID_USER test -r $RESTIC_PASSWORD_FILE"
else
    echo "SKIP  backup (RESTIC_REPO empty)"
fi

echo "== ssh =="
if systemctl is-active sshd >/dev/null 2>&1; then
    eff="$(sudo sshd -T 2>/dev/null)"
    grep -qi "^allowusers $PARENT_USER" <<<"$eff" && pass "sshd AllowUsers $PARENT_USER" || failed "sshd AllowUsers not $PARENT_USER"
    grep -qi "^permitrootlogin no" <<<"$eff" && pass "sshd PermitRootLogin no" || failed "sshd PermitRootLogin not no"
    if grep -qi "^passwordauthentication no" <<<"$eff"; then pass "sshd passwords off"; else failed "sshd still accepts passwords (authorize a key, re-run --only ssh-admin)"; fi
else
    echo "SKIP  sshd not active"
fi

echo "== snapshots =="
if command -v snapper >/dev/null && [ -f /etc/snapper/configs/root ]; then
    check "a labelled bootstrap snapshot exists" bash -c "sudo snapper -c root list | grep -q 'omarchy-kids'"
else
    echo "SKIP  snapper not configured"
fi

echo
if [ "$fail" -eq 0 ]; then echo "acceptance: all passed"; else echo "acceptance: FAILURES above"; exit 1; fi
