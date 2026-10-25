#!/usr/bin/env bash
# bootstrap.sh -- turn a fresh Omarchy install into a parent-managed kids workstation.
# Run as the parent (wheel) account. With no flags, runs every module in order.
# Use --dry-run to preview; nothing needs sudo in that mode.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT
MODULES_DIR="$REPO_ROOT/modules"

MODULE_ORDER=(preflight login child-account packages webapps browser-policy dns screen-time desktop lockdown backup ssh-admin snapshot)
declare -A MODULE_FILE=(
    [preflight]="10-preflight.sh"
    [login]="15-login.sh"
    [child-account]="20-child-account.sh"
    [packages]="25-packages.sh"
    [webapps]="30-webapps.sh"
    [browser-policy]="35-browser-policy.sh"
    [dns]="40-dns.sh"
    [screen-time]="45-screen-time.sh"
    [desktop]="50-desktop.sh"
    [lockdown]="55-lockdown.sh"
    [backup]="60-backup.sh"
    [ssh-admin]="65-ssh-admin.sh"
    [snapshot]="70-snapshot.sh"
)

DRY_RUN=0
ONLY=""
SKIP=""

usage() {
    cat <<USAGE
Usage: ./bootstrap.sh [options]

With no options, runs all modules in order: ${MODULE_ORDER[*]}.

Options:
  --only m1,m2     Run only these modules (comma-separated).
  --skip m1,m2     Run all modules except these.
  --dry-run        Print planned actions without changing anything.
  -h, --help       Show this help.

Modules: ${MODULE_ORDER[*]}
USAGE
}

in_csv() { case ",$1," in *",$2,"*) return 0 ;; *) return 1 ;; esac; }

validate_names() {
    local csv="$1" name _names
    IFS=',' read -ra _names <<<"$csv"
    for name in "${_names[@]}"; do
        [ -n "$name" ] || continue
        if [ -z "${MODULE_FILE[$name]:-}" ]; then
            echo "Unknown module: $name" >&2
            echo "Valid modules: ${MODULE_ORDER[*]}" >&2
            exit 1
        fi
    done
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --only) shift; ONLY="${1:-}" ;;
        --only=*) ONLY="${1#*=}" ;;
        --skip) shift; SKIP="${1:-}" ;;
        --skip=*) SKIP="${1#*=}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done
export DRY_RUN

[ -n "$ONLY" ] && validate_names "$ONLY"
[ -n "$SKIP" ] && validate_names "$SKIP"

selected() {
    local m="$1"
    if [ -n "$ONLY" ]; then in_csv "$ONLY" "$m"; return; fi
    if [ -n "$SKIP" ] && in_csv "$SKIP" "$m"; then return 1; fi
    return 0
}

# One sudo prompt up front; the modules then run privileged steps as they come.
if [ "$DRY_RUN" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
    sudo -v
fi

for m in "${MODULE_ORDER[@]}"; do
    if selected "$m"; then
        printf '\n######## module: %s ########\n' "$m"
        DRY_RUN="$DRY_RUN" REPO_ROOT="$REPO_ROOT" bash "$MODULES_DIR/${MODULE_FILE[$m]}"
    fi
done

printf '\n==> bootstrap complete (dry-run=%s)\n' "$DRY_RUN"
if [ "$DRY_RUN" -eq 0 ]; then
    printf '    Next: run tests/acceptance.sh as the parent, then tests/child-checks.sh as %s.\n' "${KID_USER:-the child}"
fi
