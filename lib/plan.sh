#!/usr/bin/env bash

fedora_dev_plan() {
  local profile="${1:-full}"
  fedora_dev_profile_valid "$profile" || {
    printf 'Unknown profile: %s\n' "$profile" >&2
    return 2
  }

  printf 'Installation plan: %s\n\n' "$profile"
  printf 'Profile: %s\n' "$(fedora_dev_profile_description "$profile")"
  printf 'Target:  Fedora workstation\n'
  printf 'Mode:    dry run (no changes will be made)\n\n'

  printf 'Planned components:\n'
  printf '  - Fedora base packages, Git, Fish and build tools\n'
  printf '  - mise-managed developer tools, including Rust stable\n'

  case "$profile" in
    web|full)
      printf '  - Node.js, pnpm, Bun and web development tooling\n'
      ;;
  esac
  case "$profile" in
    data|full)
      printf '  - Python, uv and PostgreSQL development service\n'
      ;;
  esac
  case "$profile" in
    full)
      printf '  - Docker Engine, VS Code, Codex and desktop integrations\n'
      ;;
  esac
}
