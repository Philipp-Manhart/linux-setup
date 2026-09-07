#!/usr/bin/env bash
set -Eeuo pipefail

# COSMIC currently shares the XDG-facing portion of this setup. Keep this
# module separate so COSMIC-specific settings can be added without changing
# the common or GNOME modules.
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$config_home/dev-machine/desktop/cosmic"
printf '%s\n' 'managed-by-linux-setup' > "$config_home/dev-machine/desktop/cosmic/README"
