#!/usr/bin/env bash
# modules/40-dns.sh -- filtered DNS on the machine itself: systemd-resolved
# speaks DNS-over-TLS to the NextDNS profile, NetworkManager stops taking the
# router's resolvers, and ufw refuses plain DNS and DoT to anyone else.
#
# This is the device-side layer. The router/NextDNS side (a child network or
# per-device policy) is still the recommendation: a device-side rule protects
# this install, a router rule protects the child.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

NEXTDNS_V4=(45.90.28.0 45.90.30.0)
NEXTDNS_V6=(2a07:a8c0:: 2a07:a8c1::)
RESOLVED_DROPIN=/etc/systemd/resolved.conf.d/50-omarchy-kids-nextdns.conf
NM_DROPIN=/etc/NetworkManager/conf.d/50-omarchy-kids-dns.conf

configure_resolved() {
    step "systemd-resolved: DNS-over-TLS to NextDNS profile $NEXTDNS_PROFILE_ID"
    local host="$NEXTDNS_PROFILE_ID.dns.nextdns.io" servers=() ip
    for ip in "${NEXTDNS_V4[@]}" "${NEXTDNS_V6[@]}"; do servers+=("$ip#$host"); done
    install_root_stdin "$RESOLVED_DROPIN" <<CONF
# Installed by omarchy-kids-bootstrap (dns module).
# Domains=~. makes these global servers win over per-link ones from DHCP.
[Resolve]
DNS=${servers[*]}
DNSOverTLS=yes
Domains=~.
DNSSEC=no
CONF
    as_root systemctl restart systemd-resolved
}

configure_networkmanager() {
    step "NetworkManager: ignore DHCP-provided DNS"
    install_root_stdin "$NM_DROPIN" <<CONF
# Installed by omarchy-kids-bootstrap (dns module).
[main]
dns=systemd-resolved
CONF
    # Connection profiles keep their own DNS flags; switch them off one by one.
    local name
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        note "connection '$name': ignore auto DNS"
        as_root nmcli connection modify "$name" ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes
    done < <(nmcli -t -g NAME connection show 2>/dev/null | grep -v '^lo$' || true)
    as_root systemctl reload NetworkManager
}

configure_firewall() {
    have_cmd ufw || { warn "ufw not installed; skipping egress rules"; return 0; }
    step "ufw: DoT only to NextDNS, no plain DNS"
    local ip
    for ip in "${NEXTDNS_V4[@]}" "${NEXTDNS_V6[@]}"; do
        as_root ufw allow out to "$ip" port 853 proto tcp comment "omarchy-kids: NextDNS DoT"
    done
    as_root ufw deny out to any port 853 comment "omarchy-kids: no other DoT"
    as_root ufw deny out to any port 53 comment "omarchy-kids: no plain DNS"
    as_root ufw reload
}

verify() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    step "Verifying"
    if resolvectl status 2>/dev/null | grep -q "+DNSOverTLS"; then
        note "resolved reports +DNSOverTLS"
    else
        warn "resolved does not report +DNSOverTLS; check: resolvectl status"
    fi
    # test.nextdns.io answers with the profile that served the request.
    local probe
    if probe="$(curl -fsS --max-time 10 https://test.nextdns.io 2>/dev/null)"; then
        note "test.nextdns.io: $probe"
        grep -q "\"profile\": *\"$NEXTDNS_PROFILE_ID\"" <<<"$probe" || warn "probe did not report profile $NEXTDNS_PROFILE_ID"
    else
        warn "could not reach test.nextdns.io (offline, or DNS not working yet)"
    fi
}

module_main() {
    load_config
    require_parent
    if [ -z "$NEXTDNS_PROFILE_ID" ]; then
        step "DNS filtering not configured"
        note "1. Create a profile at https://my.nextdns.io (parental control, SafeSearch, blocklists)."
        note "2. Put its ID in config/kids.conf as NEXTDNS_PROFILE_ID."
        note "3. Re-run: ./bootstrap.sh --only dns"
        note "Also assign this machine's MAC a child policy on the router where possible."
        return 0
    fi
    [[ $NEXTDNS_PROFILE_ID =~ ^[a-z0-9]{4,12}$ ]] || die "NEXTDNS_PROFILE_ID looks wrong: $NEXTDNS_PROFILE_ID"
    configure_resolved
    configure_networkmanager
    configure_firewall
    verify
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
