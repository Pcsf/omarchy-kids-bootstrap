#!/usr/bin/env bash
# modules/17-tpm-unlock.sh -- unlock the encrypted disk with the TPM at boot,
# so the machine goes straight to the login screen (no disk passphrase).
#
# Omarchy boots with the legacy busybox initramfs (udev + encrypt hooks), so
# this uses Clevis: the LUKS volume gets an extra TPM2 keyslot (policy '{}',
# no PCR binding: Secure Boot is off on these machines, so PCR binding would
# add little and break on every firmware update) and a 'clevis' hook runs
# before 'encrypt'. The disk passphrase keeps working as the fallback: if
# the TPM unseal fails, the normal passphrase prompt appears.
#
# Trade-off: anyone who can power the machine reaches the login screen. Set
# TPM_UNLOCK=no in config/kids.conf to keep the passphrase prompt.
#
# Undo: sudo clevis luks unbind -d <luks-device> -s <slot>; remove 'clevis'
# from HOOKS (backup in /root/*.omarchy-kids.bak); sudo mkinitcpio -P.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Print the disk (e.g. /dev/nvme0n1p2) behind the root dm-crypt device.
luks_device() {
    lsblk -nrpo NAME,TYPE,PKNAME 2>/dev/null | awk '$2=="crypt" && $3!="" {print $3; exit}'
}

# Print the mkinitcpio config file whose HOOKS line carries the legacy 'encrypt' hook.
hooks_file_with_encrypt() {
    local f
    for f in /etc/mkinitcpio.conf.d/*.conf /etc/mkinitcpio.conf; do
        [ -f "$f" ] || continue
        if grep -qE '^HOOKS=.*[ (]encrypt[ )]' "$f"; then
            printf '%s\n' "$f"
            return 0
        fi
    done
    return 1
}

module_main() {
    load_config
    require_parent

    step "TPM disk unlock (TPM_UNLOCK=$TPM_UNLOCK)"
    if [ "$TPM_UNLOCK" = "no" ]; then
        note "disabled in config/kids.conf; the disk passphrase is asked at every boot."
        return 0
    fi

    local dev hooks
    dev="$(luks_device)"
    if [ -z "$dev" ]; then
        warn "no dm-crypt root device found; skipping TPM unlock."
        return 0
    fi
    if [ ! -e /dev/tpmrm0 ]; then
        warn "no TPM found (/dev/tpmrm0). Enable fTPM/PTT in the BIOS; skipping."
        return 0
    fi
    note "LUKS device: $dev"

    if grep -rqsE '^HOOKS=.*[ (]clevis[ )]' /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d 2>/dev/null; then
        hooks=""    # already added by an earlier run
    elif ! hooks="$(hooks_file_with_encrypt)"; then
        warn "no mkinitcpio HOOKS line with the 'encrypt' hook (a systemd-based initramfs?); skipping."
        return 0
    fi

    step "Packages (clevis, tpm2-tools, mkinitcpio-clevis-hook)"
    local p
    for p in clevis tpm2-tools tpm2-tss; do
        have_pkg "$p" || pkg_install "$p"
    done
    if ! have_pkg mkinitcpio-clevis-hook; then
        aur_install mkinitcpio-clevis-hook
        if [ "$DRY_RUN" -eq 0 ] && ! have_pkg mkinitcpio-clevis-hook; then
            warn "mkinitcpio-clevis-hook did not install; skipping TPM unlock (nothing was changed)."
            return 0
        fi
    fi

    step "Binding the TPM to $dev (asks for the current disk passphrase)"
    if [ "$DRY_RUN" -eq 0 ] && sudo clevis luks list -d "$dev" 2>/dev/null | grep -q tpm2; then
        note "a TPM2 keyslot is already bound."
    else
        run sudo clevis luks bind -d "$dev" tpm2 '{}'
    fi

    if [ -n "$hooks" ]; then
        step "Adding the clevis hook before 'encrypt' in $hooks"
        as_root cp -n "$hooks" "/root/$(basename "$hooks").omarchy-kids.bak"
        as_root sed -i -E 's/(^HOOKS=.*[ (])encrypt([ )])/\1clevis encrypt\2/' "$hooks"
    fi

    step "Rebuilding the initramfs / boot image"
    as_root mkinitcpio -P

    if [ "$DRY_RUN" -eq 0 ]; then
        local img found=0
        for img in /boot/EFI/Linux/*.efi /boot/initramfs-linux.img; do
            sudo test -f "$img" || continue
            if sudo lsinitcpio "$img" 2>/dev/null | grep -qiE 'clevis'; then
                found=1
                note "clevis is inside $img"
                break
            fi
        done
        [ "$found" -eq 1 ] || warn "could not confirm clevis in the boot image; the passphrase prompt stays as the fallback."
        note "Reboot to test: the disk should unlock without a passphrase."
    fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    module_main "$@"
fi
