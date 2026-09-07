#!/usr/bin/env bash
set -Eeuo pipefail

# Fedora development workstation installer
# Target: Fedora 44 / Fish (installer itself runs with Bash)
#
# Installs and configures:
#   - Git + GitHub CLI + common CLI/build utilities
#   - mise as the single toolchain/version manager
#   - Node.js 24 LTS, pnpm 12, Bun, Go 1.27, uv
#   - Python 3.14 managed by uv
#   - Fish as the default login shell
#   - Starship + zoxide + LazyDocker
#   - Docker Engine + Compose + Buildx
#   - LazyDocker terminal UI for Docker/container management
#   - PostgreSQL 18 in Docker
#   - Visual Studio Code (official Microsoft RPM repository)
#   - Two focused VS Code profiles: Web Development + Python & Data
#   - Codex VS Code extension in every profile; DBCode in Python & Data
#   - Codex CLI in an XDG-clean location
#   - Global Agent Skills directory for Codex at ~/.agents/skills
#   - ~/Code bookmark in GNOME Files (Nautilus)
#   - JetBrainsMono Nerd Font for Starship glyphs
#
# Home-directory policy:
#   Fish configuration lives under ~/.config/fish; no shell dotfiles are added
#   to the home-directory root. Tool data/config/cache/state is redirected into:
#     ~/.config
#     ~/.local/share
#     ~/.local/state
#     ~/.cache
#     ~/.local/bin
#   Source repos go in ~/Code.
#
# This script intentionally does NOT install/configure tmux or Ghostty.

readonly SCRIPT_NAME="$(basename "$0")"
readonly LIB_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
readonly REPO_ROOT="$(cd -- "$LIB_DIR/.." && pwd)"

# shellcheck source=config.sh
source "$LIB_DIR/config.sh"
# shellcheck source=commands.sh
source "$LIB_DIR/commands.sh"

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      cat <<EOF
Usage: $SCRIPT_NAME [options]

Options:
  -h, --help  Show this help.

PostgreSQL is configured but intentionally not started. Use: pgdev up
EOF
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# shellcheck source=packages.sh
source "$LIB_DIR/packages.sh"

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  die "Run this script as your normal user, not as root. It will use sudo when needed."
fi

if [[ ! -r /etc/os-release ]]; then
  die "Cannot identify the operating system."
fi
# shellcheck disable=SC1091
source /etc/os-release
if [[ ${ID:-} != "fedora" ]]; then
  die "This script targets Fedora. Detected: ${PRETTY_NAME:-unknown}."
fi
if [[ ${VERSION_ID:-} != "44" ]]; then
  warn "This was designed for Fedora 44. Detected Fedora ${VERSION_ID:-unknown}; continuing."
fi

# -----------------------------------------------------------------------------
# XDG layout
# -----------------------------------------------------------------------------
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

readonly DEV_CONFIG_DIR="$XDG_CONFIG_HOME/dev-machine"
readonly POSTGRES_DIR="$DEV_CONFIG_DIR/postgres"
readonly AGENT_SKILLS_DIR="$(fedora_dev_expand_path "$(fedora_dev_config_value paths agent_skills '~/.agents/skills')")"
readonly VSCODE_WEB_PROFILE="$(fedora_dev_config_value vscode web_profile 'Web Development')"
readonly VSCODE_DATA_PROFILE="$(fedora_dev_config_value vscode data_profile 'Python & Data')"
readonly NODE_VERSION="$(fedora_dev_config_value toolchain node 24)"
readonly PNPM_VERSION="$(fedora_dev_config_value toolchain pnpm 12)"
readonly BUN_VERSION="$(fedora_dev_config_value toolchain bun latest)"
readonly GO_VERSION="$(fedora_dev_config_value toolchain go 1.27)"
readonly UV_VERSION="$(fedora_dev_config_value toolchain uv latest)"
readonly PYTHON_VERSION="$(fedora_dev_config_value toolchain python 3.14)"
readonly POSTGRES_VERSION="$(fedora_dev_config_value toolchain postgres 18)"

mkdir -p \
  "$XDG_CONFIG_HOME" \
  "$XDG_DATA_HOME" \
  "$XDG_STATE_HOME" \
  "$XDG_CACHE_HOME" \
  "$XDG_BIN_HOME" \
  "$DEV_HOME" \
  "$AGENT_SKILLS_DIR"

log "Preparing the clean XDG home layout"

# Fresh-machine bootstrap: no history/state migration and no backup layer.
# New state is written directly to the standard XDG locations below.

mkdir -p \
  "$XDG_CONFIG_HOME/fish/conf.d" \
  "$XDG_CONFIG_HOME/fish/functions" \
  "$XDG_CONFIG_HOME/environment.d" \
  "$XDG_CONFIG_HOME/npm" \
  "$XDG_CONFIG_HOME/docker" \
  "$XDG_CONFIG_HOME/git" \
  "$XDG_DATA_HOME/go" \
  "$XDG_DATA_HOME/npm" \
  "$XDG_DATA_HOME/pnpm" \
  "$XDG_DATA_HOME/bun/install/global" \
  "$XDG_DATA_HOME/codex" \
  "$XDG_CACHE_HOME/go/build" \
  "$XDG_CACHE_HOME/go/mod" \
  "$XDG_CACHE_HOME/npm" \
  "$XDG_CACHE_HOME/bun/install" \
  "$XDG_CACHE_HOME/bun/runtime" \
  "$XDG_STATE_HOME/python" \
  "$XDG_STATE_HOME/node" \
  "$XDG_STATE_HOME/postgresql" \
  "$XDG_STATE_HOME/less" \
  "$DEV_CONFIG_DIR"

mkdir -p \
  "$XDG_DATA_HOME/dev-machine" \
  "$DEV_CONFIG_DIR/desktop/common" \
  "$DEV_CONFIG_DIR/desktop/gnome" \
  "$DEV_CONFIG_DIR/desktop/cosmic"

# The repository remains the development source; this copy makes the helper
# commands available after the checkout is no longer on PATH.
cp -- "$LIB_DIR/config.sh" "$XDG_DATA_HOME/dev-machine/config.sh"
cp -- "$LIB_DIR/commands.sh" "$XDG_DATA_HOME/dev-machine/commands.sh"
cp -- "$REPO_ROOT/machine.toml" "$XDG_DATA_HOME/dev-machine/machine.toml"
mkdir -p "$XDG_DATA_HOME/dev-machine/desktop/common" "$XDG_DATA_HOME/dev-machine/desktop/gnome" "$XDG_DATA_HOME/dev-machine/desktop/cosmic"
cp -- "$REPO_ROOT/desktop/common/apply.sh" "$XDG_DATA_HOME/dev-machine/desktop/common/apply.sh"
cp -- "$REPO_ROOT/desktop/gnome/apply.sh" "$XDG_DATA_HOME/dev-machine/desktop/gnome/apply.sh"
cp -- "$REPO_ROOT/desktop/cosmic/apply.sh" "$XDG_DATA_HOME/dev-machine/desktop/cosmic/apply.sh"
chmod +x "$XDG_DATA_HOME/dev-machine/desktop"/*/apply.sh
FEDORA_DEV_CONFIG_FILE="$XDG_DATA_HOME/dev-machine/machine.toml"
export FEDORA_DEV_ROOT="$XDG_DATA_HOME/dev-machine"

if [[ "$(fedora_dev_config_value features desktop_integration true)" == true ]]; then
  bash "$XDG_DATA_HOME/dev-machine/desktop/common/apply.sh"
  case "${XDG_CURRENT_DESKTOP,,}" in
    *gnome*) bash "$XDG_DATA_HOME/dev-machine/desktop/gnome/apply.sh" ;;
    *cosmic*) bash "$XDG_DATA_HOME/dev-machine/desktop/cosmic/apply.sh" ;;
  esac
fi

# -----------------------------------------------------------------------------
# GNOME Files (Nautilus) bookmark
# -----------------------------------------------------------------------------
log "Adding ~/Code to GNOME Files bookmarks"
GTK_BOOKMARK_DIR="$XDG_CONFIG_HOME/gtk-3.0"
GTK_BOOKMARK_FILE="$GTK_BOOKMARK_DIR/bookmarks"
CODE_BOOKMARK_URI="file://$DEV_HOME"

mkdir -p "$GTK_BOOKMARK_DIR"
touch "$GTK_BOOKMARK_FILE"

# Bookmark lines use a URI as the first field and may optionally have a label.
# Match by URI so rerunning the installer never adds a duplicate Code bookmark.
if ! awk -v uri="$CODE_BOOKMARK_URI" '$1 == uri { found=1 } END { exit !found }' "$GTK_BOOKMARK_FILE"; then
  printf '%s %s\n' "$CODE_BOOKMARK_URI" 'Code' >> "$GTK_BOOKMARK_FILE"
fi
ok "~/Code added to the GNOME Files sidebar bookmarks"

# Keep future CLI state out of $HOME.
cat > "$XDG_CONFIG_HOME/environment.d/10-dev-machine.conf" <<EOF
# managed-by-linux-setup
XDG_CONFIG_HOME=$XDG_CONFIG_HOME
XDG_DATA_HOME=$XDG_DATA_HOME
XDG_STATE_HOME=$XDG_STATE_HOME
XDG_CACHE_HOME=$XDG_CACHE_HOME
XDG_BIN_HOME=$XDG_BIN_HOME
DEV_HOME=$DEV_HOME

# Runtime/tool state
CODEX_HOME=$XDG_DATA_HOME/codex
DOCKER_CONFIG=$XDG_CONFIG_HOME/docker
STARSHIP_CONFIG=$XDG_CONFIG_HOME/starship.toml

# Go: no visible ~/go directory
GOPATH=$XDG_DATA_HOME/go
GOBIN=$XDG_BIN_HOME
GOMODCACHE=$XDG_CACHE_HOME/go/mod
GOCACHE=$XDG_CACHE_HOME/go/build

# npm/pnpm: no ~/.npm cache or ad-hoc global package folder
NPM_CONFIG_USERCONFIG=$XDG_CONFIG_HOME/npm/npmrc
NPM_CONFIG_CACHE=$XDG_CACHE_HOME/npm
NPM_CONFIG_PREFIX=$XDG_DATA_HOME/npm
PNPM_HOME=$XDG_DATA_HOME/pnpm

# Bun: mise owns the binary; XDG owns package/cache state
BUN_INSTALL_CACHE_DIR=$XDG_CACHE_HOME/bun/install
BUN_INSTALL_GLOBAL_DIR=$XDG_DATA_HOME/bun/install/global
BUN_INSTALL_BIN=$XDG_BIN_HOME
BUN_RUNTIME_TRANSPILER_CACHE_PATH=$XDG_CACHE_HOME/bun/runtime

# Histories/state
PYTHON_HISTORY=$XDG_STATE_HOME/python/history
NODE_REPL_HISTORY=$XDG_STATE_HOME/node/repl_history
PSQL_HISTORY=$XDG_STATE_HOME/postgresql/psql_history
LESSHISTFILE=$XDG_STATE_HOME/less/history

# GUI apps and shells can resolve user binaries and mise tools.
PATH=$XDG_BIN_HOME:$XDG_DATA_HOME/mise/shims:$XDG_DATA_HOME/pnpm:$XDG_DATA_HOME/npm/bin:\${PATH}
EOF

# Apply the same environment immediately to this bootstrap process.
set -a
# shellcheck disable=SC1090
source "$XDG_CONFIG_HOME/environment.d/10-dev-machine.conf"
set +a
export PATH

install_base_packages

# -----------------------------------------------------------------------------
# mise + managed toolchain
# -----------------------------------------------------------------------------
log "Installing mise and the managed development toolchain"
if ! command_exists mise; then
  tmp_mise="$(mktemp)"
  curl -fsSL https://mise.run -o "$tmp_mise"
  sh "$tmp_mise"
  rm -f "$tmp_mise"
fi
export PATH="$XDG_BIN_HOME:$PATH"
command_exists mise || die "mise was installed but is not available on PATH."

# Global defaults. Projects should still commit their own mise.toml when needed.
mise use -g \
  "node@$NODE_VERSION" \
  "pnpm@$PNPM_VERSION" \
  "bun@$BUN_VERSION" \
  "go@$GO_VERSION" \
  "uv@$UV_VERSION" \
  starship@latest \
  zoxide@latest \
  lazydocker@latest

# Make shims available to GUI-launched VS Code too.
mise reshim
ok "mise toolchain installed"

# -----------------------------------------------------------------------------
# Python: uv owns Python itself
# -----------------------------------------------------------------------------
log "Installing Python 3.14 with uv"
uv python install "$PYTHON_VERSION" --default
uv python pin --global "$PYTHON_VERSION"
ok "Python $PYTHON_VERSION is managed by uv (Fedora's system Python is untouched)"

# -----------------------------------------------------------------------------
# Codex CLI
# -----------------------------------------------------------------------------
log "Installing/updating the Codex CLI in the clean npm prefix"
# Official npm package, but its global prefix is redirected into ~/.local/share/npm.
npm install -g @openai/codex@latest
ok "Codex CLI installed; CODEX_HOME is $XDG_DATA_HOME/codex"

# -----------------------------------------------------------------------------
# Starship + Fish shell config
# -----------------------------------------------------------------------------
log "Installing JetBrainsMono Nerd Font and configuring Fish + Starship"
FONT_DIR="$XDG_DATA_HOME/fonts/JetBrainsMonoNerdFont"
if ! fc-match 'JetBrainsMono Nerd Font' 2>/dev/null | grep -i 'JetBrainsMono Nerd Font' >/dev/null; then
  tmp_font_dir="$(mktemp -d)"
  curl -fL --retry 3 \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz \
    -o "$tmp_font_dir/JetBrainsMono.tar.xz"
  rm -rf "$FONT_DIR"
  mkdir -p "$FONT_DIR"
  tar -xf "$tmp_font_dir/JetBrainsMono.tar.xz" -C "$FONT_DIR"
  rm -rf "$tmp_font_dir"
  fc-cache -f >/dev/null
fi

cat > "$XDG_CONFIG_HOME/starship.toml" <<'EOF'
# managed-by-linux-setup
# One-line prompt: blue Powerline directory capsule, compact Git/project context,
# real directory names (no path-to-icon substitutions), and a blue prompt arrow.

format = "$directory$git_branch$git_status$python$nodejs$bun$golang$cmd_duration$character"
add_newline = false

[directory]
style = "bold fg:#ffffff bg:#769ff0"
format = "[](fg:#769ff0)[ $path ]($style)[](fg:#769ff0) "
truncation_length = 5
truncation_symbol = "…/"
read_only = " read-only"

[git_branch]
symbol = ""
style = "bold #769ff0"
format = "[$branch]($style) "

[git_status]
style = "bold yellow"
format = "([$all_status$ahead_behind]($style) )"
conflicted = "=${count}"
ahead = "⇡${count}"
behind = "⇣${count}"
diverged = "⇕⇡${ahead_count}⇣${behind_count}"
up_to_date = ""
untracked = "?${count}"
stashed = "*${count}"
modified = "!${count}"
staged = "+${count}"
renamed = "»${count}"
deleted = "✘${count}"

[python]
symbol = "Python "
style = "bold yellow"
version_format = "${major}.${minor}"
format = "[$symbol$version]($style) "

[nodejs]
symbol = "Node "
style = "bold green"
version_format = "${major}.${minor}"
format = "[$symbol$version]($style) "

[bun]
symbol = "Bun "
style = "bold yellow"
version_format = "${major}.${minor}"
format = "[$symbol$version]($style) "

[golang]
symbol = "Go "
style = "bold cyan"
version_format = "${major}.${minor}"
format = "[$symbol$version]($style) "

[cmd_duration]
min_time = 1500
style = "dimmed white"
format = "[took $duration]($style) "

[character]
success_symbol = "[❯](bold #769ff0)"
error_symbol = "[❯](bold #769ff0)"
vimcmd_symbol = "[❮](bold #769ff0)"
EOF

# Fish gets a native XDG environment file; no ~/.bashrc or ~/.bash_profile is needed.
cat > "$XDG_CONFIG_HOME/fish/conf.d/10-dev-machine.fish" <<'EOF'
# managed-by-linux-setup
set -gx XDG_CONFIG_HOME "$HOME/.config"
set -gx XDG_DATA_HOME "$HOME/.local/share"
set -gx XDG_STATE_HOME "$HOME/.local/state"
set -gx XDG_CACHE_HOME "$HOME/.cache"
set -gx XDG_BIN_HOME "$HOME/.local/bin"
set -gx DEV_HOME "$HOME/Code"

set -gx CODEX_HOME "$XDG_DATA_HOME/codex"
set -gx DOCKER_CONFIG "$XDG_CONFIG_HOME/docker"
set -gx STARSHIP_CONFIG "$XDG_CONFIG_HOME/starship.toml"

set -gx GOPATH "$XDG_DATA_HOME/go"
set -gx GOBIN "$XDG_BIN_HOME"
set -gx GOMODCACHE "$XDG_CACHE_HOME/go/mod"
set -gx GOCACHE "$XDG_CACHE_HOME/go/build"

set -gx NPM_CONFIG_USERCONFIG "$XDG_CONFIG_HOME/npm/npmrc"
set -gx NPM_CONFIG_CACHE "$XDG_CACHE_HOME/npm"
set -gx NPM_CONFIG_PREFIX "$XDG_DATA_HOME/npm"
set -gx PNPM_HOME "$XDG_DATA_HOME/pnpm"

set -gx BUN_INSTALL_CACHE_DIR "$XDG_CACHE_HOME/bun/install"
set -gx BUN_INSTALL_GLOBAL_DIR "$XDG_DATA_HOME/bun/install/global"
set -gx BUN_INSTALL_BIN "$XDG_BIN_HOME"
set -gx BUN_RUNTIME_TRANSPILER_CACHE_PATH "$XDG_CACHE_HOME/bun/runtime"

set -gx PYTHON_HISTORY "$XDG_STATE_HOME/python/history"
set -gx NODE_REPL_HISTORY "$XDG_STATE_HOME/node/repl_history"
set -gx PSQL_HISTORY "$XDG_STATE_HOME/postgresql/psql_history"
set -gx LESSHISTFILE "$XDG_STATE_HOME/less/history"

fish_add_path -g "$XDG_BIN_HOME" "$XDG_DATA_HOME/mise/shims" "$XDG_DATA_HOME/pnpm" "$XDG_DATA_HOME/npm/bin"
EOF

cat > "$XDG_CONFIG_HOME/fish/config.fish" <<'EOF'
# managed-by-linux-setup

# Start directly at the prompt; suppress Fish's default welcome message.
set -g fish_greeting ""

if status is-interactive
    # mise owns tool versions and project environments.
    if type -q mise
        mise activate fish | source
    end

    # Fast, context-aware prompt.
    if type -q starship
        starship init fish | source
    end

    # Smarter navigation without replacing normal `cd`.
    if type -q zoxide
        zoxide init fish | source
    end

    # Small set of quality-of-life abbreviations.
    abbr --add cls clear
    abbr --add c 'code .'
    abbr --add ll 'ls -lah --color=auto'
    abbr --add la 'ls -A --color=auto'
    abbr --add g git
    abbr --add ga 'git add'
    abbr --add gs 'git status'
    abbr --add gl 'git log --oneline --graph --decorate --all'
    abbr --add gp 'git push'
    abbr --add gc 'git commit'
end
EOF

cat > "$XDG_CONFIG_HOME/fish/functions/mkcd.fish" <<'EOF'
# managed-by-linux-setup
function mkcd --description 'Create a directory and enter it'
    mkdir -p -- $argv[1]; and cd -- $argv[1]
end
EOF

cat > "$XDG_CONFIG_HOME/fish/functions/code-web.fish" <<'EOF'
# managed-by-linux-setup
function code-web --description 'Open VS Code with the Web Development profile'
    if test (count $argv) -eq 0
        command code --profile "Web Development" .
    else
        command code --profile "Web Development" $argv
    end
end
EOF

cat > "$XDG_CONFIG_HOME/fish/functions/code-data.fish" <<'EOF'
# managed-by-linux-setup
function code-data --description 'Open VS Code with the Python & Data profile'
    if test (count $argv) -eq 0
        command code --profile "Python & Data" .
    else
        command code --profile "Python & Data" $argv
    end
end
EOF

# Validate every generated Fish file before making Fish the login shell.
for fish_file in \
  "$XDG_CONFIG_HOME/fish/conf.d/10-dev-machine.fish" \
  "$XDG_CONFIG_HOME/fish/config.fish" \
  "$XDG_CONFIG_HOME/fish/functions/mkcd.fish" \
  "$XDG_CONFIG_HOME/fish/functions/code-web.fish" \
  "$XDG_CONFIG_HOME/fish/functions/code-data.fish"; do
  fish -n "$fish_file" || die "Generated invalid Fish configuration: $fish_file"
done

FISH_BIN="$(command -v fish)"
CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
if [[ "$CURRENT_SHELL" != "$FISH_BIN" ]]; then
  sudo usermod --shell "$FISH_BIN" "$USER"
fi
ok "Fish configured as the default login shell; Starship, mise and zoxide are Fish-native"

# -----------------------------------------------------------------------------
# Docker Engine
# -----------------------------------------------------------------------------
log "Installing Docker Engine, Compose and Buildx"
docker_conflicts=(
  docker
  docker-client
  docker-client-latest
  docker-common
  docker-latest
  docker-latest-logrotate
  docker-logrotate
  docker-selinux
  docker-engine-selinux
  docker-engine
  podman-docker
)
installed_conflicts=()
for pkg in "${docker_conflicts[@]}"; do
  rpm -q "$pkg" >/dev/null 2>&1 && installed_conflicts+=("$pkg")
done
if (( ${#installed_conflicts[@]} > 0 )); then
  sudo dnf remove -y "${installed_conflicts[@]}"
fi

if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
  sudo dnf config-manager addrepo \
    --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
fi

sudo dnf install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
ok "Docker installed and enabled"

# -----------------------------------------------------------------------------
# PostgreSQL local developer service
# -----------------------------------------------------------------------------
log "Configuring the local PostgreSQL developer service"
mkdir -p "$POSTGRES_DIR"

# Keep the local development database on the stable PostgreSQL 18 major line.
# The major tag automatically receives current PostgreSQL 18 patch releases.
POSTGRES_IMAGE="postgres:$POSTGRES_VERSION"

cat > "$POSTGRES_DIR/.env" <<EOF
# managed-by-linux-setup
POSTGRES_IMAGE=$POSTGRES_IMAGE
POSTGRES_USER=dev
POSTGRES_PASSWORD=dev
POSTGRES_DB=dev
POSTGRES_PORT=5432
EOF
chmod 600 "$POSTGRES_DIR/.env"

cat > "$POSTGRES_DIR/compose.yaml" <<'EOF'
# managed-by-linux-setup
services:
  postgres:
    image: ${POSTGRES_IMAGE}
    restart: "no"
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    ports:
      - "127.0.0.1:${POSTGRES_PORT}:5432"
    volumes:
      - postgres_data:/var/lib/postgresql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 5s
      retries: 12

volumes:
  postgres_data:
EOF

cat > "$XDG_BIN_HOME/pgdev" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DIR="$XDG_CONFIG_HOME/dev-machine/postgres"
COMPOSE=(docker compose --env-file "$DIR/.env" -f "$DIR/compose.yaml")

case "${1:-status}" in
  up)       "${COMPOSE[@]}" up -d ;;
  down)     "${COMPOSE[@]}" down ;;
  stop)     "${COMPOSE[@]}" stop ;;
  restart)  "${COMPOSE[@]}" restart ;;
  pull)     "${COMPOSE[@]}" pull ;;
  logs)     "${COMPOSE[@]}" logs -f postgres ;;
  status)   "${COMPOSE[@]}" ps ;;
  psql)     "${COMPOSE[@]}" exec postgres psql -U dev -d dev ;;
  url)      printf '%s\n' 'postgresql://dev:dev@127.0.0.1:5432/dev' ;;
  reset)
    printf 'This deletes the local PostgreSQL dev volume. Type RESET to continue: '
    read -r answer
    [[ "$answer" == "RESET" ]] || exit 1
    "${COMPOSE[@]}" down -v
    "${COMPOSE[@]}" up -d
    ;;
  *)
    printf 'Usage: pgdev {up|down|stop|restart|pull|logs|status|psql|url|reset}\n' >&2
    exit 2
    ;;
esac
EOF
chmod +x "$XDG_BIN_HOME/pgdev"

ok "PostgreSQL configured with image: $POSTGRES_IMAGE (stopped by default; use pgdev up)"

# -----------------------------------------------------------------------------
# Visual Studio Code official RPM
# -----------------------------------------------------------------------------
log "Installing Visual Studio Code from Microsoft's RPM repository"
if [[ ! -f /etc/yum.repos.d/vscode.repo ]]; then
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  printf '%s\n' \
    '[code]' \
    'name=Visual Studio Code' \
    'baseurl=https://packages.microsoft.com/yumrepos/vscode' \
    'enabled=1' \
    'autorefresh=1' \
    'type=rpm-md' \
    'gpgcheck=1' \
    'gpgkey=https://packages.microsoft.com/keys/microsoft.asc' \
    | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
fi
sudo dnf install -y code
ok "Visual Studio Code installed"

install_code_extension() {
  local profile="$1" extension="$2"
  if code --install-extension "$extension" --profile "$profile" --force >/dev/null 2>&1; then
    ok "VS Code [$profile]: $extension"
  else
    warn "Could not install VS Code extension $extension in profile '$profile' (continuing)."
  fi
}

ensure_code_profile() {
  local profile="$1"
  if code --list-extensions --profile "$profile" >/dev/null 2>&1; then
    return 0
  fi

  log "Creating VS Code profile: $profile"
  # VS Code creates a named profile when launched with --profile. There is no
  # separate non-GUI create-profile CLI, so a window may briefly/open during
  # the first bootstrap. Extension installation becomes fully scriptable after
  # the profile exists.
  code --profile "$profile" --new-window >/dev/null 2>&1 &

  local attempt
  for attempt in {1..20}; do
    if code --list-extensions --profile "$profile" >/dev/null 2>&1; then
      ok "VS Code profile created: $profile"
      return 0
    fi
    sleep 1
  done

  die "VS Code profile '$profile' could not be created automatically. Launch 'code --profile \"$profile\"' once, then rerun this installer."
}

log "Creating focused VS Code profiles"
ensure_code_profile "$VSCODE_WEB_PROFILE"
ensure_code_profile "$VSCODE_DATA_PROFILE"

# Codex and the shared theme should be present even if the Default profile is opened accidentally.
code --install-extension openai.chatgpt --force >/dev/null 2>&1 || \
  warn "Could not install Codex in the VS Code Default profile."
code --install-extension akamud.vscode-theme-onedark --force >/dev/null 2>&1 || \
  warn "Could not install Atom One Dark in the VS Code Default profile."

log "Installing Web Development profile extensions"
while IFS= read -r extension; do
  [[ -n "$extension" ]] || continue
  install_code_extension "$VSCODE_WEB_PROFILE" "$extension"
done < <(fedora_dev_config_list vscode web_extensions)

log "Installing Python & Data profile extensions"
while IFS= read -r extension; do
  [[ -n "$extension" ]] || continue
  install_code_extension "$VSCODE_DATA_PROFILE" "$extension"
done < <(fedora_dev_config_list vscode data_extensions)

ok "VS Code profiles configured: $VSCODE_WEB_PROFILE and $VSCODE_DATA_PROFILE"

# Keep the visual shell identical across Default + every named profile.
# VS Code supports marking individual settings as application-wide via
# workbench.settings.applyToAllProfiles, while language/tool settings remain
# profile-specific.
log "Applying shared VS Code appearance settings to all profiles"
VSCODE_USER_DIR="$XDG_CONFIG_HOME/Code/User"
VSCODE_SETTINGS="$VSCODE_USER_DIR/settings.json"
mkdir -p "$VSCODE_USER_DIR"

appearance_tmp="$(mktemp)"
cat > "$appearance_tmp" <<'EOF'
{
  "workbench.colorTheme": "Atom One Dark",
  "workbench.browser.showInTitleBar": false,
  "window.commandCenter": false,
  "chat.titleBar.openInAgentsWindow.enabled": false,
  "workbench.activityBar.compact": true,
  "workbench.layoutControl.enabled": false,
  "terminal.integrated.defaultProfile.linux": "fish",
  "files.autoSave": "afterDelay",
  "files.insertFinalNewline": true,
  "files.trimTrailingWhitespace": true,
  "workbench.startupEditor": "none",
  "git.confirmSync": true,
  "search.exclude": {
    "**/.git": true,
    "**/.venv": true,
    "**/node_modules": true,
    "**/dist": true,
    "**/build": true
  },
  "workbench.settings.applyToAllProfiles": [
    "workbench.colorCustomizations",
    "workbench.colorTheme",
    "workbench.browser.showInTitleBar",
    "window.commandCenter",
    "chat.titleBar.openInAgentsWindow.enabled",
    "workbench.activityBar.compact",
    "workbench.layoutControl.enabled",
    "terminal.integrated.defaultProfile.linux",
    "files.autoSave",
    "files.insertFinalNewline",
    "files.trimTrailingWhitespace",
    "workbench.startupEditor",
    "git.confirmSync",
    "search.exclude"
  ]
}
EOF

# Validate the fragment independently so a future installer edit cannot make
# an existing settings file look like the source of a generated JSON error.
if ! jq empty "$appearance_tmp" >/dev/null 2>&1; then
  rm -f "$appearance_tmp"
  die "The installer generated invalid VS Code appearance JSON."
fi

# On a clean machine settings.json does not yet exist. On reruns, merge our
# managed appearance keys into valid existing JSON instead of discarding other
# user settings. The file generated by this installer is standard JSON; VS Code
# JSONC comments/trailing commas are not accepted by jq and must be removed
# before rerunning this installer.
if [[ -s "$VSCODE_SETTINGS" ]]; then
  merged_tmp="$(mktemp)"
  if jq empty "$VSCODE_SETTINGS" >/dev/null 2>&1 && jq -s '
    .[0] as $old | .[1] as $managed |
    ($old * $managed) |
    .["workbench.settings.applyToAllProfiles"] =
      ((($old["workbench.settings.applyToAllProfiles"] // []) +
        ($managed["workbench.settings.applyToAllProfiles"] // [])) | unique)
  ' "$VSCODE_SETTINGS" "$appearance_tmp" > "$merged_tmp"; then
    mv "$merged_tmp" "$VSCODE_SETTINGS"
  else
    rm -f "$merged_tmp" "$appearance_tmp"
    die "Existing VS Code settings.json is not valid JSON. Fix it, then rerun the installer."
  fi
else
  mv "$appearance_tmp" "$VSCODE_SETTINGS"
  appearance_tmp=""
fi
[[ -z "${appearance_tmp:-}" ]] || rm -f "$appearance_tmp"
ok "VS Code appearance shared across Default, Web Development and Python & Data"

# Profile-scoped editor settings. Common workflow settings are application-wide
# in the Default profile above; language/tool settings stay with the profile
# that owns them. Profile IDs are resolved from VS Code metadata because they
# are not stable across machines.
profile_settings_dir="$VSCODE_USER_DIR/profiles"
profile_settings_path() {
  local profile_name="$1"
  local storage="$VSCODE_USER_DIR/globalStorage/storage.json"
  local location
  [[ -r "$storage" ]] || return 1
  location="$(jq -r --arg name "$profile_name" '.userDataProfiles[]? | select(.name == $name) | .location' "$storage" | head -n 1)"
  [[ -n "$location" && "$location" != null && "$location" != builtin/* ]] || return 1
  printf '%s/%s/settings.json\n' "$profile_settings_dir" "$location"
}

merge_profile_settings() {
  local settings_file="$1" managed_file="$2" profile_name="$3" merged_file
  mkdir -p "$(dirname -- "$settings_file")"
  merged_file="$(mktemp)"
  if [[ -s "$settings_file" ]]; then
    if jq empty "$settings_file" >/dev/null 2>&1 && jq -s '
      def deepmerge(a; b):
        if (a | type) == "object" and (b | type) == "object" then
          reduce (b | keys_unsorted[]) as $key
            (a; .[$key] = if has($key) then deepmerge(.[$key]; b[$key]) else b[$key] end)
        else b end;
      . as $documents | deepmerge($documents[0]; $documents[1])
    ' "$settings_file" "$managed_file" > "$merged_file"; then
      mv "$merged_file" "$settings_file"
    else
      rm -f "$merged_file"
      die "Existing VS Code settings for '$profile_name' are not valid JSON: $settings_file"
    fi
  else
    mv "$managed_file" "$settings_file"
  fi
}

profile_settings_tmp="$(mktemp -d)"
cat > "$profile_settings_tmp/web.json" <<'EOF'
{
  "[javascript][typescript][json][css][html]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.formatOnSave": true
  },
  "typescript.updateImportsOnFileMove.enabled": "prompt",
  "javascript.updateImportsOnFileMove.enabled": "prompt"
}
EOF
cat > "$profile_settings_tmp/data.json" <<'EOF'
{
  "python.defaultInterpreterPath": "${workspaceFolder}/.venv/bin/python",
  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.formatOnSave": true
  }
}
EOF

for profile_name in "$VSCODE_WEB_PROFILE" "$VSCODE_DATA_PROFILE"; do
  if profile_file="$(profile_settings_path "$profile_name")"; then
    if [[ "$profile_name" == "$VSCODE_WEB_PROFILE" ]]; then
      profile_fragment="$profile_settings_tmp/web.json"
    else
      profile_fragment="$profile_settings_tmp/data.json"
    fi
    merge_profile_settings "$profile_file" "$profile_fragment" "$profile_name"
    ok "VS Code profile settings configured: $profile_name"
  else
    warn "Could not locate VS Code profile metadata for '$profile_name'; profile settings were not changed."
  fi
done
rm -r -- "$profile_settings_tmp"

# -----------------------------------------------------------------------------
# Git defaults in XDG config (do not touch identity or existing ~/.gitconfig)
# -----------------------------------------------------------------------------
log "Writing conservative Git defaults"
GIT_XDG_CONFIG="$XDG_CONFIG_HOME/git/config"
if [[ ! -f "$GIT_XDG_CONFIG" ]]; then
  cat > "$GIT_XDG_CONFIG" <<'EOF'
# managed-by-linux-setup
[init]
    defaultBranch = main
[fetch]
    prune = true
[push]
    autoSetupRemote = true
[rerere]
    enabled = true
EOF
fi

cat > "$XDG_CONFIG_HOME/git/ignore" <<'EOF'
# managed-by-linux-setup
.DS_Store
Thumbs.db
*.swp
*~
EOF

# Synchronize optional public skills only when the repository is configured.
# A placeholder URL keeps a fresh checkout self-contained and non-failing.
SKILLS_REPOSITORY="$(fedora_dev_config_value skills repository '')"
if [[ -n "$SKILLS_REPOSITORY" && "$SKILLS_REPOSITORY" != *REPLACE_WITH_YOUR_GITHUB_USER* ]]; then
  fedora_dev_skills_sync || warn "Could not synchronize canonical skills; run 'linux-setup skills sync' when network access is available."
else
  warn "Optional skills repository is not configured; set [skills].repository in machine.toml to enable sync."
fi

# -----------------------------------------------------------------------------
# Maintenance + diagnostics helpers
# -----------------------------------------------------------------------------
cat > "$XDG_BIN_HOME/dev-update" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '\n==> Fedora packages\n'
sudo dnf upgrade --refresh -y
printf '\n==> mise-managed tools\n'
mise upgrade
mise reshim
printf '\n==> uv-managed Python\n'
uv python upgrade || true
printf '\n==> Codex CLI\n'
npm install -g @openai/codex@latest
printf '\n==> PostgreSQL image\n'
pgdev pull || true
printf '\nDone.\n'
EOF
chmod +x "$XDG_BIN_HOME/dev-update"

cat > "$XDG_BIN_HOME/dev-doctor" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
runtime="${XDG_DATA_HOME:-$HOME/.local/share}/dev-machine"
export FEDORA_DEV_ROOT="$runtime"
export FEDORA_DEV_CONFIG_FILE="$runtime/machine.toml"
# shellcheck source=/dev/null
source "$runtime/config.sh"
# shellcheck source=/dev/null
source "$runtime/commands.sh"
fedora_dev_doctor
EOF
chmod +x "$XDG_BIN_HOME/dev-doctor"

cat > "$XDG_BIN_HOME/linux-setup" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
runtime="${XDG_DATA_HOME:-$HOME/.local/share}/dev-machine"
export FEDORA_DEV_ROOT="$runtime"
export FEDORA_DEV_CONFIG_FILE="$runtime/machine.toml"
# shellcheck source=/dev/null
source "$runtime/config.sh"
# shellcheck source=/dev/null
source "$runtime/commands.sh"
case "${1:-help}" in
  doctor) fedora_dev_doctor ;;
  diff) fedora_dev_diff ;;
  info) fedora_dev_info ;;
  firmware) fedora_dev_firmware ;;
  security) [[ "${2:-}" == check ]] || { printf 'Usage: linux-setup security check\n' >&2; exit 2; }; fedora_dev_security_check ;;
  auth)
    [[ "${2:-}" == github ]] || { printf 'Use the repository CLI for auth codex and other commands.\n' >&2; exit 2; }
    fedora_dev_auth_github
    ;;
  *) printf 'Use linux-setup from the checkout for installation and management commands.\n' >&2; exit 2 ;;
esac
EOF
chmod +x "$XDG_BIN_HOME/linux-setup"

log "Installation complete"
printf '\nToolchain defaults:\n'
printf '  Python:     %s (uv)\n' "$PYTHON_VERSION"
printf '  Node.js:    %s (mise)\n' "$NODE_VERSION"
printf '  pnpm:       %s (mise)\n' "$PNPM_VERSION"
printf '  Bun:        %s (mise)\n' "$BUN_VERSION"
printf '  Go:         %s (mise)\n' "$GO_VERSION"
printf '  LazyDocker: latest (mise)\n'
printf '  PostgreSQL: %s (Docker)\n' "$POSTGRES_IMAGE"
printf '  Projects:   %s\n' "$DEV_HOME"

printf '\nUseful commands:\n'
printf '  dev-doctor       verify the whole development machine\n'
printf '  dev-update       update Fedora + mise + uv Python + Codex + Postgres image\n'
printf '  pgdev up         start PostgreSQL when you need it\n'
printf '  pgdev down       stop/remove the PostgreSQL container\n'
printf '  pgdev status     check PostgreSQL\n'
printf '  pgdev psql       open psql inside the PostgreSQL container\n'
printf '  pgdev url        print the local PostgreSQL connection URL\n'
printf '  z <name>         smart directory navigation via zoxide\n'
printf '  lazydocker       interactive Docker/container manager\n'
printf '  code-web [path]  open a project with the Web Development profile\n'
printf '  code-data [path] open a project with the Python & Data profile\n'
printf '  skills:          %s\n' "$AGENT_SKILLS_DIR"


printf '\nIMPORTANT:\n'
printf '  Log out of Fedora and log back in once. This activates Fish as your login shell,\n'
printf '  Docker group membership, and environment.d variables for GUI applications.\n'
printf '  PostgreSQL remains stopped until you explicitly run: pgdev up\n'
printf '  Then run: dev-doctor\n\n'
