#!/usr/bin/env bash
set -Eeuo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
projects="${DEV_HOME:-$HOME/Code}"
bookmark_dir="$config_home/gtk-3.0"
bookmark_file="$bookmark_dir/bookmarks"
bookmark_uri="file://$projects"
mkdir -p "$bookmark_dir"
touch "$bookmark_file"
if ! awk -v uri="$bookmark_uri" '$1 == uri { found=1 } END { exit !found }' "$bookmark_file"; then
  printf '%s %s\n' "$bookmark_uri" Code >> "$bookmark_file"
fi
