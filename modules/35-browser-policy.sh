#!/usr/bin/env bash
# modules/35-browser-policy.sh -- mandatory Chromium-family policy: allowlist only.
#
# The policy file is generated from config/allowed-sites.txt on top of
# system/chromium-policy-base.json and installed root-owned into every policy
# directory Omarchy itself manages (Chromium, Chrome, Edge, Brave). Chromium
# policies are machine-wide: they bind the parent too when the parent browses
# on this machine. The lockdown module keeps the child out of other browsers.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

POLICY_DIRS=(
    /etc/chromium/policies/managed
    /etc/opt/chrome/policies/managed
    /etc/opt/edge/policies/managed
    /etc/brave/policies/managed
)
POLICY_NAME=omarchy-kids.json

# Build the JSON on stdout. Used by the module and by tests/selftest.sh.
render_policy() {
    local base="$REPO_ROOT/system/chromium-policy-base.json"
    local sites="$REPO_ROOT/config/allowed-sites.txt"
    local entry allow=()
    while IFS= read -r entry; do
        if [[ $entry == chrome://* ]] || valid_domain "$entry"; then
            allow+=("$entry")
        else
            warn "allowed-sites.txt: skipping malformed entry '$entry'"
        fi
    done < <(list_entries "$sites")
    [ "${#allow[@]}" -gt 0 ] || die "allowed-sites.txt has no entries; refusing to install an empty allowlist"
    printf '%s\n' "${allow[@]}" | jq -R . | jq -s --slurpfile base "$base" '$base[0] + {URLAllowlist: .}'
}

module_main() {
    load_config
    require_parent
    have_cmd jq || die "jq is required (Omarchy ships it)"

    step "Rendering the browser policy from config/allowed-sites.txt"
    local tmp
    tmp="$(mktemp)"
    render_policy >"$tmp"
    note "$(jq '.URLAllowlist | length' "$tmp") allowed URL patterns"

    local dir
    for dir in "${POLICY_DIRS[@]}"; do
        step "Installing $dir/$POLICY_NAME"
        # Omarchy's browser-policy helper insists on root-owned 755 parents; keep that shape.
        as_root install -d -m 755 -o root -g root "$(dirname "$dir")" "$dir"
        as_root install -m 644 -o root -g root -T "$tmp" "$dir/$POLICY_NAME"
    done
    rm -f "$tmp"

    # Firefox reads a different format; when it is installed the lockdown module
    # denies it to the child, and this stub keeps its policy directory root-owned.
    if have_pkg firefox; then
        step "Firefox is installed"
        warn "Firefox has no allowlist here; config/blocked-commands.txt denies it to $KID_USER"
    fi

    note "Verify in the child's browser: chrome://policy must list URLBlocklist and URLAllowlist as mandatory."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
