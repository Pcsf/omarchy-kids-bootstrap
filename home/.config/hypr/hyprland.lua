-- Hyprland config for the child's account (omarchy-kids-bootstrap).
-- Same structure as Omarchy's /etc/skel copy, with the preinstalled-app
-- bindings switched off so bindings.lua can give those keys to learning apps.

dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

omarchy_preinstalled_bindings = false

require("default.hypr.omarchy")

require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

require("default.hypr.toggles")
