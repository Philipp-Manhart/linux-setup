#!/usr/bin/env bash

if [[ -n "${FEDORA_DEV_CONFIG_LOADED:-}" ]]; then
  return 0
fi
readonly FEDORA_DEV_CONFIG_LOADED=1

readonly FEDORA_DEV_DEFAULT_PROFILE="full"
readonly FEDORA_DEV_PROFILES=(minimal web data full)

FEDORA_DEV_ROOT="${FEDORA_DEV_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
FEDORA_DEV_CONFIG_FILE="${FEDORA_DEV_CONFIG_FILE:-$FEDORA_DEV_ROOT/machine.toml}"

fedora_dev_expand_path() {
  local value="$1"
  case "$value" in
    ~/*) printf '%s/%s\n' "$HOME" "${value#~/}" ;;
    ~)   printf '%s\n' "$HOME" ;;
    *)   printf '%s\n' "$value" ;;
  esac
}

fedora_dev_config_value() {
  local section="$1" key="$2" fallback="${3:-}"
  [[ -r "$FEDORA_DEV_CONFIG_FILE" ]] || { printf '%s\n' "$fallback"; return 0; }

  awk -v wanted_section="$section" -v wanted_key="$key" -v fallback="$fallback" '
    function trim(value) { gsub(/^[ \t]+|[ \t]+$/, "", value); return value }
    function unquote(value) {
      value = trim(value)
      if (value ~ /^".*"$/ || value ~ /^'"'"'.*'"'"'$/) return substr(value, 2, length(value) - 2)
      return value
    }
    /^[ \t]*#/ { next }
    /^[ \t]*\[/ {
      section = $0
      sub(/^[ \t]*\[/, "", section)
      sub(/\].*$/, "", section)
      next
    }
    section == wanted_section {
      line = $0
      sub(/[ \t]*#.*/, "", line)
      split(line, parts, "=")
      if (trim(parts[1]) == wanted_key) {
        value = line
        sub(/^[^=]*=/, "", value)
        print unquote(value)
        found = 1
        exit
      }
    }
    END { if (!found) print fallback }
  ' "$FEDORA_DEV_CONFIG_FILE"
}

fedora_dev_config_list() {
  local section="$1" key="$2"
  local value
  value="$(fedora_dev_config_value "$section" "$key" '')"
  value="${value#[}"
  value="${value%]}"
  printf '%s\n' "$value" | tr ',' '\n' | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//; /^[[:space:]]*$/d'
}

fedora_dev_config_copy_if_missing() {
  local destination="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/dev-machine/machine.toml}"
  [[ -r "$FEDORA_DEV_CONFIG_FILE" ]] || return 0
  [[ -e "$destination" ]] && return 0
  mkdir -p "$(dirname -- "$destination")"
  cp -- "$FEDORA_DEV_CONFIG_FILE" "$destination"
}

fedora_dev_profile_valid() {
  local requested="$1"
  local profile
  for profile in "${FEDORA_DEV_PROFILES[@]}"; do
    [[ "$requested" == "$profile" ]] && return 0
  done
  return 1
}

fedora_dev_profile_description() {
  case "$1" in
    minimal) printf '%s\n' 'Shell, Git, build tools, mise and diagnostics' ;;
    web)     printf '%s\n' 'Minimal plus Node.js, pnpm, Bun and web tooling' ;;
    data)    printf '%s\n' 'Minimal plus Python, uv, PostgreSQL and data tooling' ;;
    full)    printf '%s\n' 'Complete workstation: web, data, Docker, VS Code and Codex' ;;
    *)       return 1 ;;
  esac
}

fedora_dev_print_profiles() {
  local profile
  for profile in "${FEDORA_DEV_PROFILES[@]}"; do
    printf '%-8s %s\n' "$profile" "$(fedora_dev_profile_description "$profile")"
  done
}
