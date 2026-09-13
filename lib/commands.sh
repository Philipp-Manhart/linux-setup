#!/usr/bin/env bash

# Shared, read-mostly commands used by linux-setup and the installed helpers.

if [[ -z "${FEDORA_DEV_CONFIG_LOADED:-}" ]]; then
  # shellcheck source=config.sh
  source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/config.sh"
fi

fedora_dev_xdg_init() {
  export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
  export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
  export XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
  if [[ -z "${DEV_HOME:-}" ]]; then
    export DEV_HOME="$(fedora_dev_expand_path "$(fedora_dev_config_value paths projects '~/Code')")"
  else
    export DEV_HOME
  fi
  if [[ -z "${CODEX_SKILLS_DIR:-}" ]]; then
    export CODEX_SKILLS_DIR="$(fedora_dev_expand_path "$(fedora_dev_config_value paths codex_skills '~/.local/share/codex/skills')")"
  else
    export CODEX_SKILLS_DIR
  fi
}

fedora_dev_xdg_init

fedora_dev_have() { command -v "$1" >/dev/null 2>&1; }

fedora_dev_mark() {
  local label="$1" state="$2" detail="${3:-}"
  if [[ "$state" == ok ]]; then
    printf '%-28s ✓ %s\n' "$label" "$detail"
  else
    printf '%-28s ✗ %s\n' "$label" "$detail"
    FEDORA_DEV_CHECKS_FAILED=$((FEDORA_DEV_CHECKS_FAILED + 1))
  fi
}

fedora_dev_warn_mark() {
  printf '%-28s ! %s\n' "$1" "$2"
}

fedora_dev_login_shell() {
  getent passwd "${USER:-$(id -un)}" 2>/dev/null | cut -d: -f7
}

fedora_dev_code_profile_exists() {
  local profile="$1"
  fedora_dev_have code || return 1
  code --list-extensions --profile "$profile" >/dev/null 2>&1
}

fedora_dev_extension_installed() {
  local profile="$1" extension="$2"
  code --list-extensions --profile "$profile" 2>/dev/null | grep -Fxq "$extension"
}

fedora_dev_doctor() {
  local expected_shell web_profile data_profile extension
  local project_uri="file://$DEV_HOME"
  local bookmark_file="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/bookmarks"
  local postgres_dir="${XDG_CONFIG_HOME:-$HOME/.config}/dev-machine/postgres"
  local compose_file="$postgres_dir/compose.yaml"
  local postgres_running=0
  FEDORA_DEV_CHECKS_FAILED=0
  expected_shell="$(fedora_dev_config_value machine expected_shell fish)"
  web_profile="$(fedora_dev_config_value vscode web_profile 'Web Development')"
  data_profile="$(fedora_dev_config_value vscode data_profile 'Python & Data')"

  printf '\nDevelopment machine\n===================\n'
  printf 'Config: %s\n\n' "$FEDORA_DEV_CONFIG_FILE"

  fedora_dev_mark 'Machine config' ok "$FEDORA_DEV_CONFIG_FILE"
  if [[ -d "$DEV_HOME" ]]; then fedora_dev_mark '~/Code exists' ok "$DEV_HOME"; else fedora_dev_mark '~/Code exists' fail "missing: $DEV_HOME"; fi
  if [[ -r "$bookmark_file" ]] && grep -Fq -- "$project_uri" "$bookmark_file"; then
    fedora_dev_mark 'Code bookmark' ok 'GNOME/GTK bookmark present'
  else
    fedora_dev_mark 'Code bookmark' fail 'not present'
  fi

  if [[ "$(fedora_dev_login_shell)" == "$(command -v "$expected_shell" 2>/dev/null)" ]]; then
    fedora_dev_mark 'Fish default shell' ok "$(fedora_dev_login_shell)"
  else
    fedora_dev_mark 'Fish default shell' fail "expected $expected_shell"
  fi

  if id -nG "${USER:-$(id -un)}" 2>/dev/null | tr ' ' '\n' | grep -Fxq docker; then
    fedora_dev_mark 'Docker group membership' ok 'docker'
  else
    fedora_dev_mark 'Docker group membership' fail 'logout/login may be required'
  fi

  if fedora_dev_have code && fedora_dev_code_profile_exists "$web_profile"; then
    fedora_dev_mark 'VS Code profiles' ok "$web_profile"
  else
    fedora_dev_mark 'VS Code profiles' fail "$web_profile missing"
  fi
  if fedora_dev_have code && fedora_dev_code_profile_exists "$data_profile"; then
    fedora_dev_mark 'VS Code data profile' ok "$data_profile"
  else
    fedora_dev_mark 'VS Code data profile' fail "$data_profile missing"
  fi

  for profile_key in web_extensions data_extensions; do
    if [[ "$profile_key" == web_extensions ]]; then profile="$web_profile"; else profile="$data_profile"; fi
    while IFS= read -r extension; do
      [[ -n "$extension" ]] || continue
      if fedora_dev_have code && fedora_dev_extension_installed "$profile" "$extension"; then
        fedora_dev_mark "VS Code $extension" ok "$profile"
      else
        fedora_dev_mark "VS Code $extension" fail "$profile"
      fi
    done < <(fedora_dev_config_list vscode "$profile_key")
  done

  if fedora_dev_have codex; then fedora_dev_mark 'Codex reachable' ok "$(command -v codex)"; else fedora_dev_mark 'Codex reachable' fail 'codex not on PATH'; fi
  if fedora_dev_have gh && gh auth status >/dev/null 2>&1; then fedora_dev_mark 'GitHub auth' ok 'gh is authenticated'; else fedora_dev_mark 'GitHub auth' fail 'run: linux-setup auth github'; fi

  if fedora_dev_have docker && docker info >/dev/null 2>&1; then fedora_dev_mark 'Docker' ok 'daemon reachable'; else fedora_dev_mark 'Docker' fail 'daemon unavailable'; fi
  if fedora_dev_have mise && mise which node >/dev/null 2>&1 && mise which go >/dev/null 2>&1 && mise which cargo >/dev/null 2>&1; then
    fedora_dev_mark 'mise shims' ok 'node, go and Rust/Cargo resolve'
  else
    fedora_dev_mark 'mise shims' fail 'node/go/Rust do not resolve through mise'
  fi
  if fedora_dev_have python && fedora_dev_have uv; then
    local python_path uv_python
    python_path="$(command -v python)"
    uv_python="$(uv python find 2>/dev/null || true)"
    if [[ "$python_path" == *"/uv/python/"* ]] || [[ -n "$uv_python" && "$(readlink -f "$python_path" 2>/dev/null)" == "$(readlink -f "$uv_python" 2>/dev/null)" ]]; then
      fedora_dev_mark 'Python from uv' ok "$python_path"
    else
      fedora_dev_mark 'Python from uv' fail "python=$python_path uv=$uv_python"
    fi
  else
    fedora_dev_mark 'Python from uv' fail 'python or uv missing'
  fi

  if [[ -f "$compose_file" ]] && fedora_dev_have docker; then
    docker compose --env-file "$postgres_dir/.env" -f "$compose_file" ps --status running 2>/dev/null | grep -q postgres && postgres_running=1 || true
  fi
  if (( postgres_running == 0 )); then fedora_dev_mark 'PostgreSQL autostart' ok 'disabled/stopped'; else fedora_dev_mark 'PostgreSQL autostart' fail 'container is running'; fi

  printf '\nResult: '
  if (( FEDORA_DEV_CHECKS_FAILED == 0 )); then printf 'all checks passed\n'; return 0; fi
  printf '%d check(s) need attention\n' "$FEDORA_DEV_CHECKS_FAILED"
  return 1
}

fedora_dev_diff() {
  local expected_shell web_profile data_profile extension current desired
  local bookmark_file="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/bookmarks"
  local postgres_dir="${XDG_CONFIG_HOME:-$HOME/.config}/dev-machine/postgres"
  local compose_file="$postgres_dir/compose.yaml"
  local changes=0
  fedora_dev_xdg_init
  expected_shell="$(fedora_dev_config_value machine expected_shell fish)"
  web_profile="$(fedora_dev_config_value vscode web_profile 'Web Development')"
  data_profile="$(fedora_dev_config_value vscode data_profile 'Python & Data')"
  printf '\nDesired state diff\n==================\n'

  if [[ ! -d "$DEV_HOME" ]]; then printf 'Missing:\n  %s\n' "$DEV_HOME"; changes=$((changes + 1)); fi
  if [[ ! -r "$bookmark_file" ]] || ! grep -Fq -- "file://$DEV_HOME" "$bookmark_file"; then
    printf 'Missing:\n  Code Files bookmark\n'
    changes=$((changes + 1))
  fi
  if [[ "$(fedora_dev_login_shell)" != "$(command -v "$expected_shell" 2>/dev/null)" ]]; then
    printf 'Misconfigured:\n  login shell = %s\n  expected    = %s\n' "$(fedora_dev_login_shell)" "$expected_shell"
    changes=$((changes + 1))
  fi
  if ! id -nG "${USER:-$(id -un)}" 2>/dev/null | tr ' ' '\n' | grep -Fxq docker; then
    printf 'Misconfigured:\n  docker group membership is missing\n'
    changes=$((changes + 1))
  fi
  if ! fedora_dev_have gh || ! gh auth status >/dev/null 2>&1; then
    printf 'Missing:\n  GitHub authentication\n'
    changes=$((changes + 1))
  fi
  if [[ -f "$compose_file" ]] && docker compose --env-file "$postgres_dir/.env" -f "$compose_file" ps --status running 2>/dev/null | grep -q postgres; then
    printf 'Misconfigured:\n  PostgreSQL is running (expected stopped by default)\n'
    changes=$((changes + 1))
  fi
  for profile in "$web_profile" "$data_profile"; do
    if ! fedora_dev_code_profile_exists "$profile"; then printf 'Missing:\n  VS Code profile: %s\n' "$profile"; changes=$((changes + 1)); fi
  done
  for pair in "web_extensions:$web_profile" "data_extensions:$data_profile"; do
    local key="${pair%%:*}" profile="${pair#*:}"
    while IFS= read -r extension; do
      [[ -n "$extension" ]] || continue
      if ! fedora_dev_extension_installed "$profile" "$extension"; then
        printf 'Missing:\n  VS Code extension: %s (%s)\n' "$extension" "$profile"
        changes=$((changes + 1))
      fi
    done < <(fedora_dev_config_list vscode "$key")
  done
  for tool in node pnpm go rust uv; do
    desired="$(fedora_dev_config_value toolchain "$tool" '')"
    if fedora_dev_have mise; then current="$(mise current "$tool" 2>/dev/null | head -n 1 || true)"; else current='not installed'; fi
    if [[ -n "$desired" && "$desired" != latest && "$current" != *"$desired"* ]]; then
      printf 'Outdated or missing:\n  %s %s → %s\n' "$tool" "$current" "$desired"
      changes=$((changes + 1))
    fi
  done
  if (( changes == 0 )); then printf 'Machine matches the configured checks.\n'; else printf '\n%d difference(s) found.\n' "$changes"; fi
  return 0
}

fedora_dev_configure_ssh() {
  local ssh_dir="$HOME/.ssh" config="$HOME/.ssh/config" block_start='# BEGIN linux-setup managed GitHub defaults' block_end='# END linux-setup managed GitHub defaults'
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  touch "$config"
  chmod 600 "$config"
  if ! grep -Fq "$block_start" "$config"; then
    {
      printf '\n%s\n' "$block_start"
      printf '%s\n' 'Host github.com' '    AddKeysToAgent yes' '    IdentityFile ~/.ssh/id_ed25519'
      printf '%s\n' "$block_end"
    } >> "$config"
  fi
  printf 'SSH config ready: %s\n' "$config"
}

fedora_dev_auth_github() {
  fedora_dev_configure_ssh
  if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N '' -C "${USER:-dev}@$(hostname)"
  fi
  chmod 600 "$HOME/.ssh/id_ed25519"
  chmod 644 "$HOME/.ssh/id_ed25519.pub"
  if ! fedora_dev_have gh; then printf 'GitHub CLI (gh) is not installed. Run apply first.\n' >&2; return 1; fi
  if ! gh auth status >/dev/null 2>&1; then
    gh auth login --git-protocol ssh --web
  fi
  gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$(hostname)-$(date +%Y-%m-%d)" 2>/dev/null || true
  gh auth setup-git
  printf 'GitHub authentication and SSH Git access are configured.\n'
}

fedora_dev_auth_codex() {
  fedora_dev_have codex || { printf 'Codex CLI is not installed. Run apply first.\n' >&2; return 1; }
  if codex login status >/dev/null 2>&1; then
    printf 'Codex is authenticated.\n'
  else
    printf 'Starting the interactive Codex login...\n'
    codex login
  fi
}

fedora_dev_skills_sync() {
  local repo branch source_dir skill target mode existing_backup synced=0
  repo="$(fedora_dev_config_value skills repository '')"
  branch="$(fedora_dev_config_value skills branch main)"
  mode="$(fedora_dev_config_value skills sync_mode symlink)"
  [[ -n "$repo" && "$repo" != *REPLACE_WITH_YOUR_GITHUB_USER* ]] || {
    printf 'Set [skills].repository in machine.toml before syncing skills.\n' >&2
    return 2
  }
  source_dir="$(fedora_dev_expand_path "$(fedora_dev_config_value skills checkout "$DEV_HOME/skills")")"
  if [[ -e "$source_dir" ]]; then
    if ! git -C "$source_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      printf 'Skills checkout exists but is not a Git checkout: %s\n' "$source_dir" >&2
      printf 'Initialize it with the configured GitHub repository, then rerun: linux-setup skills sync\n' >&2
      return 2
    fi
    if [[ -z "$(git -C "$source_dir" status --porcelain)" ]]; then
      git -C "$source_dir" pull --ff-only origin "$branch"
    else
      printf 'Skills checkout has local changes; preserving them and skipping GitHub pull.\n'
    fi
  else
    mkdir -p "$(dirname -- "$source_dir")"
    git clone --branch "$branch" "$repo" "$source_dir"
  fi
  mkdir -p "$CODEX_SKILLS_DIR"
  while IFS= read -r -d '' skill; do
    skill="$(dirname -- "$skill")"
    target="$CODEX_SKILLS_DIR/$(basename "$skill")"
    if [[ "$mode" == symlink ]]; then
      if [[ -e "$target" && ! -L "$target" ]]; then
        existing_backup="${target}.before-linux-setup"
        if [[ -e "$existing_backup" || -L "$existing_backup" ]]; then
          printf 'Skipped skill with existing backup: %s\n' "$(basename "$skill")" >&2
          continue
        fi
        mv -- "$target" "$existing_backup"
        printf 'Preserved existing Codex skill: %s\n' "$existing_backup"
      fi
      ln -sfn "$skill" "$target"
    else
      printf 'Unsupported skills.sync_mode: %s\n' "$mode" >&2
      return 2
    fi
    printf 'Synced skill: %s\n' "$(basename "$skill")"
    synced=$((synced + 1))
  done < <(find "$source_dir" -type f -name SKILL.md -print0)
  if (( synced == 0 )); then
    printf 'No SKILL.md files found in %s\n' "$source_dir" >&2
    return 1
  fi
  printf 'Skills checkout: %s\nCodex skills:     %s\n' "$source_dir" "$CODEX_SKILLS_DIR"
}

fedora_dev_firmware() {
  fedora_dev_have fwupdmgr || { printf 'fwupdmgr is not installed.\n' >&2; return 1; }
  printf 'Refreshing firmware metadata...\n'
  sudo fwupdmgr refresh
  printf '\nAvailable firmware updates:\n'
  sudo fwupdmgr get-updates
  printf '\nNo firmware is flashed automatically.\n'
}

fedora_dev_security_check() {
  local encryption ssh_bad=0
  printf '\nSecurity baseline\n=================\n'
  if fedora_dev_have mokutil; then mokutil --sb-state 2>/dev/null | sed 's/^/Secure Boot: /'; else printf 'Secure Boot: unavailable (mokutil missing)\n'; fi
  if fedora_dev_have firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then printf 'Firewall: enabled\n'; else printf 'Firewall: check failed or not running\n'; fi
  if fedora_dev_have getenforce && [[ "$(getenforce 2>/dev/null)" == Enforcing ]]; then printf 'SELinux: enforcing\n'; else printf 'SELinux: not enforcing or unavailable\n'; fi
  encryption="$(lsblk -o TYPE 2>/dev/null | grep -Fx crypt | head -n 1 || true)"
  if [[ -n "$encryption" || -s /etc/crypttab ]]; then printf 'Disk encryption: detected\n'; else printf 'Disk encryption: not detected\n'; fi
  if fedora_dev_have ssh-keygen; then
    while IFS= read -r -d '' key; do
      [[ "$(stat -c '%a' "$key" 2>/dev/null)" == 600 ]] || ssh_bad=$((ssh_bad + 1))
    done < <(find "$HOME/.ssh" -maxdepth 1 -type f -name 'id_*' ! -name '*.pub' -print0 2>/dev/null)
  fi
  if (( ssh_bad == 0 )); then printf 'SSH private-key permissions: acceptable\n'; else printf 'SSH private-key permissions: %d key(s) need chmod 600\n' "$ssh_bad"; fi
  if fedora_dev_have docker && docker info >/dev/null 2>&1; then printf 'Docker: note that docker-group users have root-equivalent daemon access\n'; else printf 'Docker: daemon unavailable\n'; fi
  if fedora_dev_have dnf; then
    local update_status
    if dnf -q check-update >/dev/null 2>&1; then update_status=0; else update_status=$?; fi
    case "$update_status" in
      0) printf 'Automatic updates: no pending updates detected\n' ;;
      100) printf 'Automatic updates: pending updates exist\n' ;;
      *) printf 'Automatic updates: unable to determine\n' ;;
    esac
  fi
}

fedora_dev_info() {
  local os desktop
  os="unknown"
  [[ -r /etc/os-release ]] && os="$(. /etc/os-release; printf '%s' "$PRETTY_NAME")"
  desktop="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-unknown}}"
  printf '\nMachine inventory\n=================\n'
  printf '%-18s %s\n' 'Host' "$(hostname)" 'OS' "$os" 'Kernel' "$(uname -sr)" 'Desktop' "$desktop"
  printf '%-18s %s\n' 'CPU' "$(lscpu 2>/dev/null | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')" \
    'RAM' "$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')" \
    'GPU' "$(lspci 2>/dev/null | awk -F: '/VGA compatible controller|3D controller/ {gsub(/^[ \t]+/, "", $3); print $3; exit}')" \
    'SSD' "$(lsblk -dn -o NAME,SIZE,TYPE 2>/dev/null | awk '$3 == "disk" {print $1 " " $2}' | paste -sd ', ' -)"
  printf '%-18s %s\n' 'Firmware' "$(fwupdmgr get-devices 2>/dev/null | awk -F: '/Current version/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
  printf '%-18s %s\n' 'Display' "$(xrandr --current 2>/dev/null | awk '/ connected/ {print $1 " " $3; exit}')"
  printf '%-18s %s\n' 'Docker' "$(docker --version 2>/dev/null || printf 'not installed')"
  printf '%-18s %s\n' 'Development' "$(mise current 2>/dev/null | tr '\n' ';' || printf 'mise unavailable')"
}

fedora_dev_update_self() {
  local repo="$FEDORA_DEV_ROOT"
  local -a git_cmd
  if [[ -d "$repo/.git" || -f "$repo/.git" ]]; then
    git_cmd=(git -C "$repo")
  elif [[ -d "$repo/.linux-setup.git" ]]; then
    git_cmd=(git --git-dir="$repo/.linux-setup.git" --work-tree="$repo")
  else
    printf 'This checkout has no Git metadata; update it from its source repository.\n' >&2
    return 1
  fi
  "${git_cmd[@]}" pull --ff-only
  printf 'Updated linux-setup from %s\n' "$repo"
}

fedora_dev_desktop_apply() {
  local desktop="$(fedora_dev_config_value machine desktop auto)" desktop_root
  desktop_root="$FEDORA_DEV_ROOT/desktop"
  [[ "$desktop" == auto ]] && desktop="${XDG_CURRENT_DESKTOP,,}"
  case "$desktop" in
    *gnome*)
      printf 'Applying common + GNOME desktop integration.\n'
      [[ -x "$desktop_root/common/apply.sh" ]] && bash "$desktop_root/common/apply.sh"
      [[ -x "$desktop_root/gnome/apply.sh" ]] && bash "$desktop_root/gnome/apply.sh"
      ;;
    *cosmic*)
      printf 'Applying common + COSMIC desktop integration.\n'
      [[ -x "$desktop_root/common/apply.sh" ]] && bash "$desktop_root/common/apply.sh"
      [[ -x "$desktop_root/cosmic/apply.sh" ]] && bash "$desktop_root/cosmic/apply.sh"
      ;;
    *)
      printf 'Applying common desktop integration only (%s).\n' "${desktop:-unknown}"
      [[ -x "$desktop_root/common/apply.sh" ]] && bash "$desktop_root/common/apply.sh"
      ;;
  esac
}
