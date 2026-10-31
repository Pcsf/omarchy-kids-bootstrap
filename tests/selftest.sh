#!/usr/bin/env bash
# tests/selftest.sh -- repo self-test, no root and no system changes:
# syntax, shellcheck when available, config parsing, policy rendering,
# and a planted negative for every check whose pass condition is "nothing found".
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT DRY_RUN=1
cd "$REPO_ROOT"
fail=0
ok()   { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }

# 1. Every script parses.
for f in bootstrap.sh lib/common.sh modules/*.sh child/*.sh system/sbin/* system/bin/* tests/*.sh; do
    bash -n "$f" && ok "syntax $f" || bad "syntax $f"
done

# 2. shellcheck, when installed.
if command -v shellcheck >/dev/null; then
    if shellcheck -x -S warning bootstrap.sh lib/common.sh modules/*.sh child/*.sh system/sbin/* system/bin/* tests/*.sh; then
        ok "shellcheck clean"
    else
        bad "shellcheck reported warnings"
    fi
else
    printf 'SKIP  shellcheck not installed\n'
fi

# 3. Config loads and the kid/parent split holds.
# shellcheck source=../lib/common.sh
source lib/common.sh
load_config
[ -n "$KID_USER" ] && ok "config: KID_USER=$KID_USER" || bad "config: KID_USER empty"

# 4. List parsing drops comments and blanks (positive and planted cases).
tmp="$(mktemp)"
printf '# comment\n\n  a  # trailing\nb\n' >"$tmp"
got="$(list_entries "$tmp" | tr '\n' ',')"
[ "$got" = "a,b," ] && ok "list_entries parses comments/whitespace" || bad "list_entries gave '$got'"
rm -f "$tmp"

# 5. The browser policy renders as valid JSON with a non-empty allowlist and
#    keeps the blocklist.
# shellcheck source=../modules/35-browser-policy.sh
source modules/35-browser-policy.sh
policy="$(render_policy)"
n="$(jq '.URLAllowlist | length' <<<"$policy")"
[ "$n" -gt 0 ] && ok "policy: $n allowlist entries" || bad "policy: empty allowlist"
[ "$(jq -r '.URLBlocklist[0]' <<<"$policy")" = "*" ] && ok "policy: URLBlocklist is *" || bad "policy: blocklist lost"
[ "$(jq -r '.DnsOverHttpsMode' <<<"$policy")" = "off" ] && ok "policy: DoH off" || bad "policy: DoH not off"

# 6. Every web app host is allowlisted (the webapps module warns; here it fails).
allowlisted() {
    local host="$1" e
    while IFS= read -r e; do
        e="${e#.}"; e="${e%%/*}"
        [[ $host == "$e" || $host == *".$e" ]] && return 0
    done < <(jq -r '.URLAllowlist[]' <<<"$policy")
    return 1
}
while IFS= read -r entry; do
    IFS='|' read -r name url _ <<<"$entry"
    host="${url#*://}"; host="${host%%/*}"; host="${host#www.}"
    allowlisted "$host" && ok "webapp '$name' host $host allowlisted" || bad "webapp '$name' host $host NOT allowlisted"
done < <(list_entries config/webapps.txt)
allowlisted "evil.example" && bad "(planted) evil.example passed the allowlist" || ok "(planted) evil.example rejected by the allowlist"

# 7. Planted negative: a malformed site must be rejected, proving the filter runs.
tmpdir="$(mktemp -d)"
mkdir -p "$tmpdir/config" "$tmpdir/system"
cp system/chromium-policy-base.json "$tmpdir/system/"
printf 'good.example\nbad entry with spaces\n' >"$tmpdir/config/allowed-sites.txt"
planted="$(REPO_ROOT="$tmpdir" render_policy 2>/dev/null | jq -r '.URLAllowlist | length')"
[ "$planted" = "1" ] && ok "policy: malformed entry rejected (planted)" || bad "policy: planted malformed entry not rejected ($planted)"
rm -rf "$tmpdir"

# 8. Non-ASCII guard on what this repo writes (docs, configs, scripts), with a
#    planted positive so an empty result means something.
if grep -rnP '[^\x00-\x7F]' --exclude-dir=.git . >/dev/null; then
    bad "non-ASCII characters present:"; grep -rnP '[^\x00-\x7F]' --exclude-dir=.git . | head -5
else
    ok "ASCII only"
fi
printf 'caf\xc3\xa9\n' | grep -qP '[^\x00-\x7F]' && ok "ASCII guard detects a planted UTF-8 byte" || bad "ASCII guard is blind"

# 9. The orchestrator's module map points at existing files.
# shellcheck disable=SC2016
missing="$(grep -oE '\[[a-z-]+\]="[0-9]+-[a-z-]+\.sh"' bootstrap.sh | sed 's/.*="\(.*\)"/\1/' | while read -r f; do [ -f "modules/$f" ] || echo "$f"; done)"
[ -z "$missing" ] && ok "all modules in bootstrap.sh exist" || bad "missing modules: $missing"

[ "$fail" -eq 0 ] && { echo; echo "selftest: all passed"; } || { echo; echo "selftest: FAILURES"; exit 1; }
