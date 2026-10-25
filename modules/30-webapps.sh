#!/usr/bin/env bash
# modules/30-webapps.sh -- install Omarchy web-app launchers in the child's account.
# omarchy-webapp-install writes into $HOME, so it runs as the child.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# True when the host equals an allowlist entry or is a subdomain of one.
host_allowlisted() {
    local host="$1" e
    while IFS= read -r e; do
        e="${e#.}"; e="${e%%/*}"
        [[ $host == "$e" || $host == *".$e" ]] && return 0
    done < <(list_entries "$REPO_ROOT/config/allowed-sites.txt")
    return 1
}

module_main() {
    load_config
    require_parent
    step "Installing web apps for $KID_USER (config/webapps.txt)"
    local entry name url icon count=0
    while IFS= read -r entry; do
        IFS='|' read -r name url icon <<<"$entry"
        name="$(strip_line "$name")"; url="$(strip_line "$url")"; icon="$(strip_line "${icon:-}")"
        if [ -z "$name" ] || [ -z "$url" ]; then
            warn "invalid entry: $entry"
            continue
        fi
        local host="${url#*://}"; host="${host%%/*}"; host="${host#www.}"
        if ! host_allowlisted "$host"; then
            warn "$name: $host is not in allowed-sites.txt; the policy will block it"
        fi
        count=$((count + 1))
        as_kid_script child/webapp.sh "$name" "$url" "$icon"
    done < <(list_entries "$REPO_ROOT/config/webapps.txt")
    [ "$count" -gt 0 ] || note "nothing uncommented in webapps.txt."
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
