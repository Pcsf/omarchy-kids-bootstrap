# lib/common.sh -- shared helpers for omarchy-kids-bootstrap modules.
# Sourced by every module and by bootstrap.sh. Not meant to be executed directly.
# shellcheck shell=bash

set -euo pipefail

: "${DRY_RUN:=0}"

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export REPO_ROOT

# System-side state written by the modules (never inside a user's home, so root
# tools can read it when no user session is up).
KIDS_ETC=/etc/omarchy-kids
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
export KIDS_ETC OMARCHY_PATH

step() { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '    [warn] %s\n' "$*" >&2; }
die()  { printf '    [error] %s\n' "$*" >&2; exit 1; }

# Run a command, or print it under --dry-run.
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '    [dry-run]'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# Run a shell snippet (pipes, redirections), or print it under --dry-run.
run_shell() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '    [dry-run] %s\n' "$*"
    else
        bash -c "$*"
    fi
}

as_root() { run sudo "$@"; }

# Write stdin to a root-owned file (mode 644 unless given) through sudo.
# Prints the content under --dry-run so the plan stays reviewable.
install_root_stdin() {
    local dst="$1" mode="${2:-644}"
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '    [dry-run] install -m %s -o root -g root %s <<EOF\n' "$mode" "$dst"
        sed 's/^/    | /'
        printf '    EOF\n'
    else
        sudo install -D -m "$mode" -o root -g root /dev/stdin "$dst"
    fi
}

# Copy a repo file to a root-owned destination.
install_root_file() {
    local src="$1" dst="$2" mode="${3:-644}"
    [ -f "$REPO_ROOT/$src" ] || die "missing $src"
    as_root install -D -m "$mode" -o root -g root "$REPO_ROOT/$src" "$dst"
}

# Trim whitespace after stripping a trailing comment.
strip_line() {
    local s="${1%%#*}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Print the uncommented, trimmed entries of a config list file, one per line.
list_entries() {
    local cfg="$1" line entry
    [ -f "$cfg" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        entry="$(strip_line "$line")"
        [ -n "$entry" ] && printf '%s\n' "$entry"
    done <"$cfg"
}

have_pkg() { pacman -Qi "$1" >/dev/null 2>&1; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

pkg_install() {
    [ "$#" -gt 0 ] || return 0
    if have_cmd omarchy-pkg-add; then
        run omarchy-pkg-add "$@"
    else
        as_root pacman -S --needed --noconfirm "$@"
    fi
}

aur_install() {
    [ "$#" -gt 0 ] || return 0
    if have_cmd omarchy-pkg-aur-add; then
        run omarchy-pkg-aur-add "$@"
    elif have_cmd yay; then
        run yay -S --needed --noconfirm "$@"
    else
        warn "no AUR helper found; cannot install: $*"
    fi
}

# ---------------------------------------------------------------------------
# Kids configuration
# ---------------------------------------------------------------------------

load_config() {
    local cfg="$REPO_ROOT/config/kids.conf"
    if [ ! -f "$cfg" ]; then
        # A dry-run may preview with the example; a real run needs the real file.
        [ "$DRY_RUN" -eq 1 ] || die "missing config/kids.conf (cp config/kids.conf.example config/kids.conf)"
        warn "config/kids.conf missing; previewing with config/kids.conf.example"
        cfg="$REPO_ROOT/config/kids.conf.example"
    fi
    # shellcheck source=../config/kids.conf.example
    source "$cfg"
    : "${KID_USER:?KID_USER must be set in config/kids.conf}"
    : "${KID_FULL_NAME:=$KID_USER}"
    : "${KID_THEME:=tokyo-night}"
    : "${PARENT_USER:=${SUDO_USER:-$USER}}"
    : "${KIDS_HOSTNAME:=}"
    : "${KIDS_LOGIN_THEME:=omarchy-kids}"
    : "${TPM_UNLOCK:=auto}"
    : "${NEXTDNS_PROFILE_ID:=}"
    : "${LAN_CIDR:=}"
    : "${SSH_PASSWORDLESS:=auto}"
    : "${TIME_LIMITS:=2h;2h;2h;2h;2h;3h;3h}"
    : "${ALLOWED_HOURS_WEEKDAY:=7;8;9;10;11;12;13;14;15;16;17;18;19}"
    : "${ALLOWED_HOURS_WEEKEND:=8;9;10;11;12;13;14;15;16;17;18;19;20}"
    : "${LOCKOUT_TYPE:=terminate}"
    : "${PLAYTIME_ENABLED:=1}"
    : "${PLAYTIME_LIMITS:=1h;1h;1h;1h;1h;1h30m;1h30m}"
    : "${PLAYTIME_ACTIVITIES:=luanti[Luanti];prismlauncher[Minecraft launcher];java[Minecraft]}"
    : "${LOCKDOWN_ENABLED:=1}"
    : "${RESTIC_REPO:=}"
    : "${RESTIC_PASSWORD_FILE:=$KIDS_ETC/restic.password}"
    : "${BACKUP_ONCALENDAR:=*-*-* 19:00:00}"
    [ "$KID_USER" != "$PARENT_USER" ] || die "KID_USER and PARENT_USER are the same account ($KID_USER)"
    [ "$KID_USER" != "root" ] || die "KID_USER cannot be root"
    export KID_USER KID_FULL_NAME KID_THEME PARENT_USER
}

# The modules run as the parent (the wheel account), never as root: $HOME and
# the repo belong to the parent, and sudo is used per privileged step.
require_parent() {
    [ "$(id -u)" -ne 0 ] || die "run bootstrap.sh as the parent account, not as root"
    if ! id -nG | tr ' ' '\n' | grep -qx wheel; then
        die "$(id -un) is not in wheel; the parent account needs sudo"
    fi
}

require_omarchy_or_warn() {
    if [ -d "$OMARCHY_PATH" ] || have_cmd omarchy-pkg-add; then
        return 0
    fi
    warn "Omarchy not detected at $OMARCHY_PATH; proceeding with plain pacman/yay."
}

kid_exists() { id "$KID_USER" >/dev/null 2>&1; }

kid_home() {
    if kid_exists; then
        getent passwd "$KID_USER" | cut -d: -f6
    else
        printf '/home/%s' "$KID_USER"
    fi
}

# Run a repo script as the child. The repo lives in the parent's home (mode
# 700), so the child cannot read it: the script is fed on stdin instead. The
# environment is the minimum Omarchy's own user scripts expect.
as_kid_script() {
    local script="$1"; shift
    [ -f "$REPO_ROOT/$script" ] || die "missing $script"
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '    [dry-run] sudo -u %s -H bash -s -- %s < %s\n' "$KID_USER" "$*" "$script"
        return 0
    fi
    kid_exists || die "user $KID_USER does not exist; run the child-account module first"
    sudo -u "$KID_USER" -H \
        env -i HOME="$(kid_home)" USER="$KID_USER" LOGNAME="$KID_USER" \
            SHELL=/bin/bash TERM="${TERM:-dumb}" LANG="${LANG:-C.UTF-8}" \
            OMARCHY_PATH="$OMARCHY_PATH" KIDS_ETC="$KIDS_ETC" KID_THEME="$KID_THEME" \
            PATH="$OMARCHY_PATH/bin:/usr/local/bin:/usr/bin:/bin" \
        bash -s -- "$@" <"$REPO_ROOT/$script"
}

# Copy a repo file into the child's home, owned by the child.
install_kid_file() {
    local src="$1" rel="$2" mode="${3:-644}"
    [ -f "$REPO_ROOT/$src" ] || die "missing $src"
    as_root install -D -m "$mode" -o "$KID_USER" -g "$KID_USER" "$REPO_ROOT/$src" "$(kid_home)/$rel"
}

# True when the string is a syntactically plausible hostname label list.
valid_domain() { [[ $1 =~ ^\.?([A-Za-z0-9*-]+\.)*[A-Za-z0-9-]+(/.*)?$ ]]; }
