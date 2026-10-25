#!/usr/bin/env bash
# modules/70-snapshot.sh -- a snapper snapshot of the root subvolume, bootable
# from the Limine menu, labelled so it can be found later.
# Snapshots cover the system, not /home: the backup module covers the child's work.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

module_main() {
    load_config
    require_parent
    local desc="${1:-omarchy-kids bootstrap}"
    step "Snapshot: $desc"
    if ! have_cmd snapper || [ ! -f /etc/snapper/configs/root ]; then
        warn "snapper is not configured; skipping. Omarchy: sudo bash $OMARCHY_PATH/install/config/snapper.sh"
        return 0
    fi
    as_root snapper -c root create -c number -d "$desc"
    as_root snapper -c root cleanup number
    [ "$DRY_RUN" -eq 1 ] || sudo snapper -c root list | tail -3 | sed 's/^/    /'
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
