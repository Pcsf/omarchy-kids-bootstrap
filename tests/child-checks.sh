#!/usr/bin/env bash
# tests/child-checks.sh -- run AS THE CHILD (log in as the child, open a
# terminal, run this from a copy outside the parent's home, e.g.
#   sudo install -m 755 tests/child-checks.sh /usr/local/bin/omarchy-kids-child-checks
# then as the child: omarchy-kids-child-checks <parent-username>).
# Every line is a restriction that must hold from the child's point of view.
set -uo pipefail
parent="${1:?usage: $0 <parent-username>}"
fail=0
pass() { printf 'PASS  %s\n' "$*"; }
failed() { printf 'FAIL  %s\n' "$*"; fail=1; }
must_fail() { local msg="$1"; shift; if "$@" >/dev/null 2>&1; then failed "$msg"; else pass "$msg"; fi; }
must_pass() { local msg="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$msg"; else failed "$msg"; fi; }

echo "I am $(id)"
[ "$(id -u)" -ne 0 ] || { echo "run this as the child, not root"; exit 1; }

must_fail "sudo without a password" sudo -n true
must_fail "reading the parent's home" ls "/home/$parent"
must_fail "writing to /etc" touch /etc/omarchy-kids-child-test
must_fail "editing the browser policy" bash -c 'echo x >> /etc/chromium/policies/managed/omarchy-kids.json'
must_fail "editing the DNS config" bash -c 'echo x >> /etc/systemd/resolved.conf.d/50-omarchy-kids-nextdns.conf'
must_fail "stopping timekpr" systemctl stop timekpr.service
must_fail "changing time limits" timekpra --getuserlist
must_fail "running brave" bash -c 'command -v brave && brave --version'
must_fail "running nmcli" nmcli general status
must_fail "becoming the parent with su" bash -c "echo | su -c true $parent"
must_fail "plain DNS to 1.1.1.1" timeout 3 bash -c 'exec 3<>/dev/tcp/1.1.1.1/53'
must_pass "(planted) chromium is still runnable" test -x /usr/bin/chromium
must_pass "(planted) my own home is writable" touch "$HOME/.omarchy-kids-check"
rm -f "$HOME/.omarchy-kids-check"
if command -v resolvectl >/dev/null; then
    must_pass "DNS over TLS is on" bash -c 'resolvectl status | grep -q "+DNSOverTLS"'
fi
probe="$(curl -fsS --max-time 10 https://test.nextdns.io 2>/dev/null || true)"
[ -n "$probe" ] && echo "      nextdns: $probe"

echo
if [ "$fail" -eq 0 ]; then echo "child checks: all passed"; else echo "child checks: FAILURES above"; exit 1; fi
