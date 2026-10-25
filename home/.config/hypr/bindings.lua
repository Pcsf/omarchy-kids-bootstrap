-- Learning-first shortcuts for the child (omarchy-kids-bootstrap).
-- SUPER + SHIFT + letter opens one of the six activities. These keys are free
-- because hyprland.lua sets omarchy_preinstalled_bindings = false.
-- Web apps are the launchers installed by config/webapps.txt.

o.bind("SUPER + SHIFT + C", "Code (Thonny)", { launch = "thonny" })
o.bind("SUPER + SHIFT + S", "School (GCompris)", { launch = "gcompris-qt" })
o.bind("SUPER + SHIFT + D", "Draw (Krita)", { launch = "krita" })
o.bind("SUPER + SHIFT + O", "Objects in 3D (Tinkercad)", { webapp = "https://www.tinkercad.com/dashboard" })
o.bind("SUPER + SHIFT + E", "Explore (Stellarium)", { launch = "stellarium" })
o.bind("SUPER + SHIFT + G", "Games (Luanti)", { launch = "luanti" })
o.bind("SUPER + SHIFT + A", "Scratch", { webapp = "https://scratch.mit.edu/projects/editor/" })
