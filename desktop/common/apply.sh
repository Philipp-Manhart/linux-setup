#!/usr/bin/env bash
set -Eeuo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$config_home/dev-machine/desktop/common" "$data_home/dev-machine"
printf '%s\n' 'managed-by-linux-setup' > "$config_home/dev-machine/desktop/common/README"
