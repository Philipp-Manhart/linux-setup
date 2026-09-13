# Fedora 44 Development Machine

An opinionated bootstrap for a **clean Fedora 44 workstation** focused on Python, TypeScript/JavaScript, Go, Rust, PostgreSQL, Docker, VS Code, and OpenAI Codex.

Current release: `0.1.0`.

The goal is to keep the machine **simple, reproducible, fast, and organized**. Each layer has one clear responsibility, and development state is kept out of the visible home-directory root wherever practical.

The desired machine state lives in [`machine.toml`](machine.toml). The CLI
reads its runtime versions, project paths, VS Code profiles/extensions,
desktop mode, PostgreSQL policy, and optional skills repository from that
file.

---

## Quick start

Download the project, make the CLI executable, then run it as your **normal user**:

```bash
cd ~/Code/linux-setup
chmod +x linux-setup lib/install.sh
./linux-setup install
```

Do **not** run the CLI or installer with `sudo`. They ask for `sudo` only where system-level changes are required.

The CLI is intentionally small and delegates the installation work to
`lib/install.sh`:

```bash
./linux-setup help
./linux-setup profiles
./linux-setup plan --profile full
./linux-setup install --dry-run --profile web
./linux-setup doctor
./linux-setup diff
./linux-setup apply
./linux-setup auth github
./linux-setup auth codex
./linux-setup ssh configure
./linux-setup skills sync
./linux-setup firmware
./linux-setup security check
./linux-setup info
./linux-setup update-self
./linux-setup update
./linux-setup postgres up
./linux-setup postgres status
```

After installation, the same maintenance commands are also available directly
as `dev-doctor`, `dev-update`, `linux-setup`, and `pgdev` from `~/.local/bin`.

Available profiles are currently being migrated into the modular installer.
The `minimal`, `web`, and `data` profiles can be inspected with `plan`; the
existing full installer remains the only profile that performs installation
until each module has been migrated and tested.

When it finishes:

1. Log out of Fedora and log back in once.
2. Your login shell will now be **Fish**.
3. If needed, set your terminal font to **JetBrainsMono Nerd Font**.
4. Run:

```fish
dev-doctor
```

PostgreSQL is deliberately **not started by the installer**. Start it only when you need it:

```fish
pgdev up
```

> **Fresh-machine assumption:** this installer is designed for a clean Fedora machine. It does not back up old dotfiles, migrate shell history, migrate Conda environments, or preserve old development-manager state.

## Reconciliation commands

`apply` reruns the installer against `machine.toml`; it is safe to rerun after
editing the desired versions or extensions. `diff` reports missing, outdated,
and misconfigured items without changing the machine. `doctor` performs the
deeper checks, including Docker group membership, the login shell, the Code
bookmark, VS Code profiles/extensions, Codex reachability, GitHub auth, the
PostgreSQL stopped-by-default policy, mise resolution, and Python's uv origin.

The requested setup deliberately does not automate Brave/default-browser
configuration, project templates, GitHub repository creation, default
applications, laptop hardware policy, snapshots, or a second dry-run mode.
The existing `install --dry-run` planner remains available.

## Authentication, firmware, security, and inventory

Run `linux-setup auth github` to configure an Ed25519 key, GitHub's SSH Git
protocol, and `gh`'s Git credential integration. It launches browser OAuth if
needed and never writes tokens into this repository. `linux-setup auth codex`
checks the Codex login and starts its interactive login only when needed.

`linux-setup ssh configure` writes a small managed block to `~/.ssh/config`
without replacing unrelated host entries. `linux-setup firmware` refreshes
fwupd metadata and lists updates; it never flashes firmware. `linux-setup
security check` is read-only and reports Secure Boot, firewall, SELinux, disk
encryption, SSH key permissions, Docker's privileged group warning, and pending
updates. `linux-setup info` prints a compact hardware, desktop, firmware, Docker,
and runtime inventory.

## Desktop modules

Desktop integration is separated into:

```text
desktop/common
desktop/gnome
desktop/cosmic
```

Common integration uses XDG paths. GNOME adds the `~/Code` Files bookmark;
COSMIC has its own module so later COSMIC-specific settings do not leak into
the common or GNOME paths. Use `linux-setup desktop apply` to reapply the
detected module.

## Git-synced Codex skills

`~/Code/skills` is the editable Git checkout for your reusable skills. Every
directory beneath it that contains `SKILL.md` is symlinked into Codex's active
skills directory, `~/.local/share/codex/skills`. This supports your existing
`published/` and `unpublished/` folders without flattening the source checkout.

The repository and checkout location are configured in `[skills]` in
`machine.toml`. Clone the configured GitHub repository into that location on a
new machine, then run:

```bash
linux-setup skills sync
```

```fish
cd ~/Code/skills
git add .
git commit -m "Describe the skill change"
git push
linux-setup skills sync
```

`skills sync` uses `git pull --ff-only` when the checkout is clean and never
resets or overwrites uncommitted skill edits. It then refreshes the symlinks, so
newly created skills become available to Codex. If a pre-existing, non-symlink
Codex skill has the same name, it is preserved as `<skill>.before-linux-setup`
before the managed symlink is made.

---

# Architecture

```text
Fedora 44
│
├── DNF / system packages
│   ├── Fish
│   ├── Git + Git LFS + GitHub CLI
│   ├── compilers/build tools
│   ├── useful CLI utilities
│   ├── Docker Engine + Compose + Buildx
│   └── Visual Studio Code
│
├── mise
│   ├── Node.js 24
│   ├── pnpm 12
│   ├── Bun
│   ├── Go 1.27
│   ├── Rust stable (via rustup)
│   ├── uv
│   ├── Starship
│   ├── zoxide
│   └── LazyDocker
│
├── uv
│   └── Python 3.14
│
├── Docker
│   └── PostgreSQL 18 (stopped unless explicitly started)
│
├── VS Code
│   ├── Web Development
│   └── Python & Data
│
├── Codex
│   ├── CLI
│   ├── VS Code extension
│   └── ~/.local/share/codex/skills → ~/Code/skills
│
└── ~/Code
    └── all source repositories/projects
```

The ownership model is deliberate:

- **DNF** manages software that belongs to Fedora itself.
- **Fish** is your interactive/default login shell.
- **mise** manages developer runtimes and CLI tool versions.
- **uv** manages Python versions, virtual environments, and Python project dependencies.
- **pnpm** is the default package manager for Node/TypeScript projects.
- **Bun** is available when a project explicitly uses Bun.
- **Docker Compose** runs stateful local infrastructure such as PostgreSQL.
- **LazyDocker** provides an interactive Docker/container UI.
- **VS Code profiles** keep web and Python/data extensions separated.

The setup intentionally avoids overlapping managers such as nvm, fnm, asdf, pyenv, Conda, and Homebrew.

---

# Project location

All projects live under:

```text
~/Code
```

Examples:

```text
~/Code/web-app
~/Code/data-project
~/Code/api
~/Code/experiments
```

The installer exposes this location as:

```text
DEV_HOME=~/Code
```

## GNOME Files bookmark

The installer also adds `~/Code` to the **GNOME Files (Nautilus) sidebar** as a bookmark named **Code**.

GNOME/GTK stores user folder bookmarks in:

```text
~/.config/gtk-3.0/bookmarks
```

The installer adds this entry only when the URI is not already bookmarked:

```text
file:///home/<user>/Code Code
```

This is idempotent, so rerunning the installer does not create duplicate Code bookmarks and it does not overwrite other bookmarks you add yourself.

You can also add it manually in GNOME Files by opening `~/Code` and choosing **Add to Bookmarks** from the location/path menu, or by dragging the folder into the sidebar's bookmark area.

---

# Clean home-directory design

The setup follows the XDG Base Directory layout wherever practical.

```text
~
├── Code/                         projects
├── .config/
│   ├── fish/                    Fish configuration/functions
│   ├── dev-machine/             local machine service configuration
│   ├── docker/                  Docker CLI configuration
│   ├── environment.d/           GUI/session environment
│   ├── git/                     Git defaults/ignore
│   ├── mise/                    mise configuration
│   ├── npm/                     npm configuration
│   └── starship.toml            prompt configuration
├── .local/
│   ├── bin/                     user executables/helpers
│   ├── share/                   persistent application/tool data
│   └── state/                   persistent state/history
└── .cache/                      disposable caches
```

Important paths:

| Purpose | Location |
|---|---|
| Config | `~/.config` |
| Tool/application data | `~/.local/share` |
| Persistent state | `~/.local/state` |
| Caches | `~/.cache` |
| User commands | `~/.local/bin` |
| Projects | `~/Code` |
| Editable skills repository | `~/Code/skills` |
| Active Codex skills | `~/.local/share/codex/skills` |
| Codex data | `~/.local/share/codex` |
| Go workspace data | `~/.local/share/go` |

---

# Fedora packages

The script updates Fedora first:

```bash
sudo dnf upgrade --refresh -y
```

Before updating, it configures DNF to use up to 10 parallel downloads and to
assume confirmation for non-interactive package operations:

```ini
max_parallel_downloads=10
defaultyes=True
```

It then installs the OS-level foundation.

## Core tools

```text
git
git-lfs
gh
curl
wget
unzip
zip
tar
xz
jq
```

## CLI utilities

```text
ripgrep
fd-find
fzf
bat
```

These provide modern equivalents for common search/navigation tasks and are also useful to coding agents.

## Build toolchain

```text
gcc
gcc-c++
make
cmake
pkgconf-pkg-config
openssl-devel
libffi-devel
```

These cover common native build requirements for Python and JavaScript dependencies.

## Shell/font support

```text
fish
util-linux-user
fontconfig
```

Fish becomes your default login shell after installation.

---

# Fish shell

Fish is installed through Fedora/DNF because the login shell belongs to the operating-system layer.

The installer changes your login shell to the installed Fish binary using the user account configuration. The change takes effect after you log out and back in.

Check it with:

```fish
echo $SHELL
fish --version
```

Expected login shell:

```text
/usr/bin/fish
```

## Fish configuration

The configuration stays under XDG paths:

```text
~/.config/fish/config.fish
~/.config/fish/conf.d/10-dev-machine.fish
~/.config/fish/functions/
```

There is no need for this development setup to put its own `.bashrc` or `.bash_profile` in your home-directory root.

## Fish integrations

Interactive Fish initializes:

```text
mise
Starship
zoxide
```

All three are configured natively for Fish.

## Abbreviations

Fish abbreviations are used instead of a large alias collection:

```text
cls   → clear
c     → code .
ll    → ls -lah --color=auto
la    → ls -A --color=auto
g     → git
ga    → git add
gs    → git status
gl    → git log --oneline --graph --decorate --all
gp    → git push
gc    → git commit
```

Unlike aliases, Fish abbreviations expand visibly while you type, so you can always see the actual command being executed.

## Helper functions

Create and enter a directory:

```fish
mkcd my-project
```

Open the current repository with the Web Development profile:

```fish
code-web
```

Open it with Python & Data:

```fish
code-data
```

Or pass a path:

```fish
code-web ~/Code/web-app
code-data ~/Code/analysis
```

---

# mise

mise is the central development-tool/version manager.

Global defaults installed by the script:

| Tool | Default |
|---|---|
| Node.js | 24 |
| pnpm | 12 |
| Bun | latest |
| Go | 1.27 |
| Rust | stable |
| uv | latest |
| Starship | latest |
| zoxide | latest |
| LazyDocker | latest |

These are **machine defaults**. Projects should still pin their own requirements when appropriate.

Example layout when skills are configured:

```fish
cd ~/Code/web-app
mise use node@24 pnpm@12
```

A project can then commit its `mise.toml` so another machine can reproduce its tool versions.

Useful commands:

```fish
mise ls
mise current
mise install
mise upgrade
mise doctor
```

## Rust

Rust is installed by mise's native `rust` backend, which manages the Rust
toolchain through `rustup`; the installer does not also install Rust from DNF
or the standalone rustup script. The global channel is `stable`, while Cargo
and rustup data live under `~/.local/share/cargo` and `~/.local/share/rustup`.
Executables installed with `cargo install` are available through Cargo's XDG
`bin` directory, which the installer adds to `PATH`.

For a project, pin the required toolchain in its committed `mise.toml`. When a
project already has `rust-toolchain.toml`, enable mise's Rust idiomatic-version
file support instead of declaring a competing Rust version in `mise.toml`:

```fish
mise settings add idiomatic_version_file_enable_tools rust
mise install
```

---

# Python + uv

mise installs **uv**, but uv owns Python itself.

```text
mise
  └── uv
       └── Python 3.14
```

The installer runs the equivalent of:

```bash
uv python install 3.14 --default
uv python pin --global 3.14
```

Fedora's own system Python is not modified.

## New Python project

```fish
cd ~/Code
mkdir analysis
cd analysis
uv init
uv add pandas polars
code-data .
```

Typical project files:

```text
pyproject.toml
uv.lock
.python-version
.venv/
```

Run Python or project commands through uv:

```fish
uv run python
uv run pytest
```

The setup deliberately does **not** install Conda, Poetry, pyenv, or Jupyter tooling globally.

---

# Node.js, pnpm, TypeScript and Bun

The global web-development defaults are:

```text
Node.js 24
pnpm 12
Bun latest
```

For normal TypeScript/JavaScript projects, use Node + pnpm:

```fish
cd ~/Code
mkdir web-app
cd web-app
mise use node@24 pnpm@12
pnpm init
pnpm add -D typescript
code-web .
```

Use Bun only in repositories that intentionally use Bun. Avoid mixing pnpm and Bun lockfiles in the same project.

---

# Go

Go 1.27 is installed through mise.

```fish
go version
go build
go test ./...
```

Go data is kept out of a visible `~/go` directory:

```text
GOPATH     ~/.local/share/go
GOBIN      ~/.local/bin
GOMODCACHE ~/.cache/go/mod
GOCACHE    ~/.cache/go/build
```

The **Go VS Code extension is intentionally not installed** at this stage.

---

# Starship prompt

Starship provides a compact **single-line Fish prompt**.

Configuration:

```text
~/.config/starship.toml
```

The directory uses the real path in a blue Powerline capsule. Directory names are not replaced by icons.

Example layout when skills are configured:

```text
 ~/Code/my-project  main +2 !1 Python 3.14 ❯
```

At home:

```text
 ~  ❯
```

Displayed context can include:

- path
- Git branch
- compact Git status
- Python version
- Node version
- Bun version
- Go version
- command duration for slower commands

Git status notation includes:

```text
+2    staged files
!1    modified files
?1    untracked files
⇡2    commits ahead
⇣1    commits behind
✘1    deleted files
```

The final prompt arrow is blue for both successful and failed commands so the prompt stays visually consistent.

---

# JetBrainsMono Nerd Font

The installer downloads JetBrainsMono Nerd Font to:

```text
~/.local/share/fonts/JetBrainsMonoNerdFont
```

It refreshes the font cache, but it does **not** change your terminal emulator's settings.

If the Powerline separators do not render correctly, select a **JetBrainsMono Nerd Font** variant in your terminal settings.

Ghostty is not configured by this script.

---

# zoxide

zoxide provides smart directory navigation without replacing normal `cd`.

Normal Fish navigation stays unchanged:

```fish
cd ~/Code/my-project
```

After zoxide learns your commonly visited directories:

```fish
z project
z web-app
```

---

# Docker

The setup installs native Docker Engine rather than Docker Desktop.

Packages:

```text
docker-ce
docker-ce-cli
containerd.io
docker-buildx-plugin
docker-compose-plugin
```

Docker itself is enabled at boot:

```text
Docker daemon: running as a system service
PostgreSQL container: stopped unless you explicitly start it
```

This gives you Docker immediately when you need it, while not consuming PostgreSQL resources all day.

Your user is added to the `docker` group. After the required logout/login, Docker works without `sudo`:

```fish
docker ps
docker compose ps
```

> The Docker group grants powerful access to the host. This is the convenient standard setup for a personal development machine, but it should be treated as privileged access.

## Common Docker commands

```fish
docker ps
docker ps -a
docker images
docker logs <container>
docker stats
docker stop <container>
docker start <container>
docker rm <container>
```

---

# LazyDocker

LazyDocker is installed through mise and provides a terminal UI for Docker.

Start it with:

```fish
lazydocker
```

It provides interactive views for:

- containers
- Compose services
- images
- volumes
- logs
- stats
- start/stop/restart actions
- container commands/shell access

This is the main interactive Docker manager in the setup.

---

# PostgreSQL 18

PostgreSQL is not installed directly on Fedora. It is configured as a small Docker Compose service using:

```text
postgres:18
```

Configuration:

```text
~/.config/dev-machine/postgres/
├── .env
└── compose.yaml
```

## Important: PostgreSQL is off by default

The installer **does not start PostgreSQL**.

The Compose service also uses:

```yaml
restart: "no"
```

Therefore PostgreSQL will **not automatically start after a reboot**, even though Docker Engine itself starts with Fedora.

Start PostgreSQL only when you need it:

```fish
pgdev up
```

When finished:

```fish
pgdev down
```

You can also stop it while retaining the existing container:

```fish
pgdev stop
```

## Local development connection

```text
Host:     127.0.0.1
Port:     5432
Database: dev
Username: dev
Password: dev
```

URL:

```text
postgresql://dev:dev@127.0.0.1:5432/dev
```

It binds only to `127.0.0.1`, so it is not deliberately exposed to your LAN.

Database data lives in a Docker named volume and survives normal container recreation.

## `pgdev` helper

The installer creates:

```text
~/.local/bin/pgdev
```

Commands:

```fish
pgdev up        # start PostgreSQL
pgdev down      # stop and remove the container, keep volume
pgdev stop      # stop the container
pgdev restart   # restart it
pgdev pull      # pull current postgres:18 image
pgdev logs      # follow logs
pgdev status    # show Compose status
pgdev psql      # open psql inside the container
pgdev url       # print connection URL
pgdev reset     # delete/recreate the development database volume
```

`pgdev reset` is destructive and requires you to type `RESET` before it proceeds.

---

# Visual Studio Code

VS Code is installed from Microsoft's native Fedora RPM repository rather than Flatpak.

This avoids unnecessary sandbox friction with local development tools, Docker, SSH, mise, uv, and Codex.

The setup creates two profiles.

## Web Development

Installed extensions:

```text
Codex – OpenAI's coding agent
Atom One Dark Theme
mise integration
ESLint
Prettier
```

VS Code already contains built-in TypeScript, JavaScript, JSON, HTML and CSS language support.

Open with:

```fish
code-web ~/Code/web-app
```

## Python & Data

Installed extensions:

```text
Codex – OpenAI's coding agent
Atom One Dark Theme
mise integration
Python
Pylance
debugpy
Python Environments
Ruff
Even Better TOML
Rainbow CSV
PDF Viewer
DBCode
```

No Jupyter extension is installed.

DBCode is the database client inside this profile and can be used for PostgreSQL, SQLite, DuckDB and other supported databases.

Open with:

```fish
code-data ~/Code/analysis
```

## Codex in all profiles

Codex is installed in:

```text
Default
Web Development
Python & Data
```

So it remains available even if you accidentally open normal VS Code without choosing one of the named profiles.

## Shared appearance in every profile

The installer also installs the **Atom One Dark Theme** in the Default, Web Development, and Python & Data profiles and keeps these appearance settings application-wide:

```json
{
  "workbench.colorTheme": "Atom One Dark",
  "workbench.browser.showInTitleBar": false,
  "workbench.browser.openLocalhostLinks": false,
  "workbench.browser.enableChatTools": false,
  "window.commandCenter": false,
  "chat.titleBar.openInAgentsWindow.enabled": false,
  "workbench.activityBar.compact": true,
  "workbench.layoutControl.enabled": false,
  "preview.defaultBrowserPreviewType": "external",
  "window.titleBarStyle": "custom",
  "window.controlsStyle": "hidden",
  "window.density.layout": "compact"
}
```

VS Code's `workbench.settings.applyToAllProfiles` mechanism is used so these visual preferences stay synchronized across the Default profile and both development profiles, while language/tool-specific settings remain profile-scoped. Localhost links open in the external browser, the browser title-bar entry is hidden, and chat agents cannot open the integrated browser. VS Code still allows the integrated browser to be opened explicitly from its command palette.

The same keyboard map is written to Default, Web Development, and Python & Data. It uses scan-code bindings for `Ctrl` + the physical backquote/backslash keys, which keeps those shortcuts in the same place on a German layout. `Ctrl+T` toggles the terminal; `Ctrl+Shift+T` creates a terminal; `Ctrl+D` duplicates the current editor line; and `Ctrl+F` is sent to Fish while a terminal is focused, so it accepts Fish's autosuggestion instead of opening VS Code's terminal find UI. Press `Tab` for Fish's normal completion list.

## Go editor tooling

Go itself is installed, but the Go VS Code extension is intentionally omitted for now.

---

# Codex CLI and Skills

The Codex CLI is installed through npm, whose global prefix is redirected under XDG-managed user data.

Codex data:

```text
~/.local/share/codex
```

Editable skills checkout:

```text
~/Code/skills
```

Codex reads symlinks from:

```text
~/.local/share/codex/skills/
└── <skill-name>/
    └── SKILL.md
```

For a new reusable skill, create and test it in the Git checkout:

```fish
cd ~/Code/skills
mkdir -p unpublished/my-skill
code unpublished/my-skill/SKILL.md
linux-setup skills sync
```

Commit and push the change from `~/Code/skills` when you are ready to share it
with GitHub; the symlink makes it immediately available to local Codex after
`linux-setup skills sync`.

---

# Git defaults

The installer keeps Git identity personal and does not set your name, email, or signing keys.

It writes conservative defaults under:

```text
~/.config/git/config
```

including:

```text
default branch = main
fetch prune = true
push autoSetupRemote = true
rerere = true
```

Global ignore patterns live under:

```text
~/.config/git/ignore
```

---

# `dev-doctor`

Run:

```fish
dev-doctor
```

It reports versions/status for:

```text
Fedora
Git
GitHub CLI
Fish
mise
Python
uv
Node
pnpm
Bun
Go
Docker
Docker Compose
LazyDocker
Starship
zoxide
VS Code
Codex
```

It also prints important paths, your login shell, PostgreSQL URL, and PostgreSQL status.

A stopped PostgreSQL service is a **normal healthy state** in this setup.

---

# `dev-update`

Run:

```fish
dev-update
```

It updates:

```text
Fedora packages
mise-managed tools
uv-managed Python
Codex CLI
PostgreSQL 18 Docker image
```

Because Starship, LazyDocker, zoxide, Bun, uv, etc. are managed by mise, `mise upgrade` covers most user-space development tooling in one place.

Updating the PostgreSQL image does not start PostgreSQL.

---

# Typical workflows

## Web project

```fish
cd ~/Code
mkdir web-app
cd web-app
mise use node@24 pnpm@12
pnpm init
pnpm add -D typescript
code-web .
```

## Python project

```fish
cd ~/Code
mkdir analytics
cd analytics
uv init
uv add pandas polars duckdb
code-data .
```

## Work with PostgreSQL

```fish
pgdev up
pgdev status
pgdev psql
```

When done:

```fish
pgdev down
```

## Manage containers visually

```fish
lazydocker
```

## Navigate quickly

```fish
z analytics
```

---

# What is intentionally not installed

```text
Conda / Miniconda
Jupyter / Jupyter VS Code extension
Poetry
pyenv
nvm
fnm
asdf
Homebrew
Docker Desktop
Beekeeper Studio
DBeaver
pgAdmin
SQLTools
Go VS Code extension
tmux
Ghostty configuration
system-installed PostgreSQL
```

The objective is a focused workstation, not the maximum possible number of tools.

---

# First-login checklist

## 1. Log out and back in

This activates:

- Fish as the login shell
- Docker group membership
- graphical-session environment variables
- the clean PATH for GUI-launched VS Code

## 2. Confirm Fish

```fish
echo $SHELL
fish --version
```

## 3. Verify the whole workstation

```fish
dev-doctor
```

## 4. Check Docker

```fish
docker ps
lazydocker
```

## 5. PostgreSQL should initially be stopped

```fish
pgdev status
```

When you actually need it:

```fish
pgdev up
pgdev url
pgdev psql
```

And when you are finished:

```fish
pgdev down
```

## 6. Open VS Code

```fish
code-web ~/Code
code-data ~/Code
```

## 7. Set the terminal font

Choose a **JetBrainsMono Nerd Font** variant if the Powerline separators do not render correctly.

## 8. Authenticate personal services as needed

```fish
gh auth login
codex
```

---

# Maintenance philosophy

The final workstation follows five rules:

1. **The OS stays boring.** Fedora/DNF manages system software only.
2. **Tool versions are explicit.** mise manages developer runtimes and utilities; projects can pin versions.
3. **Python has one modern workflow.** uv manages Python and Python projects.
4. **Infrastructure is on demand.** Docker is available, but PostgreSQL remains stopped until explicitly started.
5. **Editor environments stay focused.** VS Code profiles separate web development from Python/data/database work.

That keeps the machine easy to reason about, reproduce, update, and troubleshoot.
