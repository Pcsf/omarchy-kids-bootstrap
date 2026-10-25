#!/usr/bin/env bash
# child/provision.sh -- runs AS THE CHILD (fed on stdin by as_kid_script).
# The essential parts of omarchy-provision-user without the developer extras
# (mise, Node, AI agents, git identity, XCompose).
set -euo pipefail

: "${OMARCHY_PATH:=/usr/share/omarchy}"
: "${KID_THEME:=tokyo-night}"
export OMARCHY_PATH PATH="$OMARCHY_PATH/bin:$PATH"
state_dir="$HOME/.local/state/omarchy"
mkdir -p "$state_dir"

echo "    user dirs and bookmarks"
mkdir -p ~/Downloads ~/Pictures ~/Videos ~/Projects ~/Documents ~/Designs ~/.config/gtk-3.0
xdg-user-dirs-update --set TEMPLATES "$HOME"
xdg-user-dirs-update --set PUBLICSHARE "$HOME"
xdg-user-dirs-update --set DESKTOP "$HOME"
rmdir ~/Templates ~/Public ~/Desktop 2>/dev/null || true
touch ~/.config/gtk-3.0/bookmarks
for dir in Projects Documents Pictures Designs Downloads; do
    bookmark="file://$HOME/$dir $dir"
    grep -qxF "$bookmark" ~/.config/gtk-3.0/bookmarks || echo "$bookmark" >>~/.config/gtk-3.0/bookmarks
done

echo "    theme: $KID_THEME"
mkdir -p ~/.config/omarchy/themes
if [ ! -d "$OMARCHY_PATH/themes/$KID_THEME" ]; then
    echo "    theme $KID_THEME not found under $OMARCHY_PATH/themes; using tokyo-night" >&2
    KID_THEME=tokyo-night
fi
# Headless: no Hyprland session to notify, no browser-policy write (that one
# needs sudo, which this account does not have).
OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "$KID_THEME"
mkdir -p ~/.config/btop/themes
ln -snf "$state_dir/current/theme/btop.theme" ~/.config/btop/themes/current.theme

echo "    passwordless default keyring (Chromium stores nothing sensitive for a child)"
if [ -f "$OMARCHY_PATH/install/user/default-keyring.sh" ]; then
    bash "$OMARCHY_PATH/install/user/default-keyring.sh"
fi

echo "    default browser: chromium"
mkdir -p ~/.local/share/applications
env -u BROWSER XDG_CURRENT_DESKTOP= xdg-settings set default-web-browser chromium.desktop 2>/dev/null || true

echo "    marking Omarchy's own finalization and migrations as done"
mkdir -p "$state_dir/migrations" "$state_dir/done"
for migration in "$OMARCHY_PATH"/migrations/*.sh; do
    [ -f "$migration" ] && touch "$state_dir/migrations/$(basename "$migration")"
done
# finalize-user: skips omarchy-provision-user at first login (it would install
# the coding agents). The invitations are the first-login toasts for
# dictation, AI agent and fingerprint setup: not for this account.
for marker in finalize-user voxtype-install-invitation agent-setup-invitation fingerprint-setup-invitation; do
    touch "$state_dir/done/$marker"
done

update-desktop-database ~/.local/share/applications 2>/dev/null || true
echo "    child provisioning done"
