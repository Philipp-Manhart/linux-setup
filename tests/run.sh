#!/usr/bin/env bash
# Integration and contract tests for the non-destructive linux-setup CLI paths.
# The installer itself intentionally touches Fedora and is therefore verified by
# syntax and generated-configuration contracts here, not executed in a test run.
set -uo pipefail

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/linux-setup-tests.XXXXXX")"

PASS=0
FAIL=0
EXPECT_OUTPUT=''

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  return 1
}

run_test() {
  local name="$1"
  shift
  if ( "$@" ); then
    printf 'ok - %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'not ok - %s\n' "$name" >&2
    FAIL=$((FAIL + 1))
  fi
}

expect_status() {
  local expected="$1"
  shift
  EXPECT_OUTPUT="$("$@" 2>&1)"
  local actual=$?
  [[ "$actual" == "$expected" ]] || {
    printf 'Expected exit %s, got %s. Output:\n%s\n' "$expected" "$actual" "$EXPECT_OUTPUT" >&2
    return 1
  }
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_file_contains() {
  local file="$1" needle="$2"
  [[ -f "$file" ]] || fail "missing file: $file"
  grep -Fq -- "$needle" "$file" || fail "expected $file to contain: $needle"
}

new_environment() {
  local name="$1"
  TEST_HOME="$TEST_ROOT/$name/home"
  TEST_CONFIG="$TEST_ROOT/$name/machine.toml"
  mkdir -p "$TEST_HOME"
}

write_config() {
  local projects="$1" codex_skills="$2" checkout="$3" repository="$4"
  mkdir -p "$(dirname -- "$TEST_CONFIG")"
  printf '%s\n' \
    '[machine]' \
    'expected_shell = "fish"' \
    'desktop = "auto"' \
    '[paths]' \
    "projects = \"$projects\"" \
    "codex_skills = \"$codex_skills\"" \
    '[toolchain]' \
    'node = "24"' \
    'pnpm = "12"' \
    'bun = "latest"' \
    'go = "1.27"' \
    'rust = "stable"' \
    'uv = "latest"' \
    '[vscode]' \
    'web_profile = "Web Development"' \
    'data_profile = "Python & Data"' \
    'web_extensions = ["web.one", "web.two"]' \
    'data_extensions = ["data.one"]' \
    '[skills]' \
    "checkout = \"$checkout\"" \
    "repository = \"$repository\"" \
    'branch = "main"' \
    'sync_mode = "symlink"' > "$TEST_CONFIG"
}

run_cli() {
  env -u DEV_HOME -u CODEX_SKILLS_DIR \
    HOME="$TEST_HOME" \
    XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" \
    XDG_STATE_HOME="$TEST_HOME/.local/state" \
    XDG_CACHE_HOME="$TEST_HOME/.cache" \
    XDG_BIN_HOME="$TEST_HOME/.local/bin" \
    FEDORA_DEV_CONFIG_FILE="$TEST_CONFIG" \
    "$REPO_ROOT/linux-setup" "$@"
}

test_cli_help_profiles_and_errors() {
  new_environment cli
  write_config '~/Code' '~/.local/share/codex/skills' '~/Code/skills' 'https://example.invalid/skills.git'

  expect_status 0 run_cli help || return
  assert_contains "$EXPECT_OUTPUT" 'Usage: linux-setup <command> [options]' || return
  assert_contains "$EXPECT_OUTPUT" 'skills sync' || return

  expect_status 0 run_cli version || return
  assert_contains "$EXPECT_OUTPUT" 'linux-setup 0.1.0' || return

  expect_status 0 run_cli profiles || return
  assert_contains "$EXPECT_OUTPUT" 'minimal' || return
  assert_contains "$EXPECT_OUTPUT" 'web' || return
  assert_contains "$EXPECT_OUTPUT" 'data' || return
  assert_contains "$EXPECT_OUTPUT" 'full' || return

  expect_status 2 run_cli plan --profile unknown || return
  assert_contains "$EXPECT_OUTPUT" 'Unknown profile' || return

  expect_status 2 run_cli does-not-exist || return
  assert_contains "$EXPECT_OUTPUT" 'unknown command' || return

  expect_status 1 run_cli install --profile web || return
  assert_contains "$EXPECT_OUTPUT" 'preview-only' || return

  expect_status 1 run_cli update || return
  assert_contains "$EXPECT_OUTPUT" 'not installed yet' || return

  expect_status 1 run_cli postgres status || return
  assert_contains "$EXPECT_OUTPUT" 'not installed yet' || return

  expect_status 1 run_cli auth nope || return
  assert_contains "$EXPECT_OUTPUT" 'Usage: linux-setup auth' || return

  expect_status 1 run_cli ssh nope || return
  assert_contains "$EXPECT_OUTPUT" 'Usage: linux-setup ssh configure' || return

  expect_status 1 run_cli skills nope || return
  assert_contains "$EXPECT_OUTPUT" 'Usage: linux-setup skills sync' || return

  expect_status 1 run_cli desktop nope || return
  assert_contains "$EXPECT_OUTPUT" 'Usage: linux-setup desktop {apply|wallpaper <image-file>}' || return

  expect_status 2 run_cli desktop wallpaper assets/wallpapers/missing.jpg || return
  assert_contains "$EXPECT_OUTPUT" 'Wallpaper image not found' || return

  expect_status 1 run_cli firmware extra || return
  assert_contains "$EXPECT_OUTPUT" 'firmware does not accept options' || return

  expect_status 1 run_cli security nope || return
  assert_contains "$EXPECT_OUTPUT" 'Usage: linux-setup security check' || return

  expect_status 1 run_cli info extra || return
  assert_contains "$EXPECT_OUTPUT" 'info does not accept options' || return
}

test_profile_plans_and_dry_runs() {
  new_environment plans
  write_config '~/Code' '~/.local/share/codex/skills' '~/Code/skills' 'https://example.invalid/skills.git'

  local profile
  for profile in minimal web data full; do
    expect_status 0 run_cli plan --profile "$profile" || return
    assert_contains "$EXPECT_OUTPUT" "Installation plan: $profile" || return
    assert_contains "$EXPECT_OUTPUT" 'Rust stable' || return
  done

  expect_status 0 run_cli plan --profile web || return
  assert_contains "$EXPECT_OUTPUT" 'Node.js, pnpm, Bun' || return
  [[ "$EXPECT_OUTPUT" != *'Python, uv and PostgreSQL'* ]] || fail 'web plan unexpectedly includes data tooling'

  expect_status 0 run_cli plan --profile data || return
  assert_contains "$EXPECT_OUTPUT" 'Python, uv and PostgreSQL' || return
  [[ "$EXPECT_OUTPUT" != *'Node.js, pnpm, Bun'* ]] || fail 'data plan unexpectedly includes web tooling'

  expect_status 0 run_cli install --dry-run --profile minimal || return
  assert_contains "$EXPECT_OUTPUT" 'Mode:    dry run' || return

  expect_status 1 run_cli install --dry-run --unexpected || return
  assert_contains "$EXPECT_OUTPUT" 'unknown install option' || return
}

test_config_helpers() {
  new_environment config
  write_config '~/Workspace' '~/.local/share/codex/skills' '~/Workspace/skills' 'https://example.invalid/skills.git'

  export HOME="$TEST_HOME" FEDORA_DEV_CONFIG_FILE="$TEST_CONFIG"
  unset FEDORA_DEV_CONFIG_LOADED
  # shellcheck source=../lib/config.sh
  source "$REPO_ROOT/lib/config.sh"

  [[ "$(fedora_dev_expand_path '~/Workspace')" == "$TEST_HOME/Workspace" ]] || fail 'tilde path was not expanded'
  [[ "$(fedora_dev_expand_path '~')" == "$TEST_HOME" ]] || fail 'home path was not expanded'
  [[ "$(fedora_dev_expand_path '/tmp/literal')" == '/tmp/literal' ]] || fail 'absolute path changed'
  [[ "$(fedora_dev_config_value toolchain rust)" == stable ]] || fail 'Rust config value missing'
  [[ "$(fedora_dev_config_value missing value fallback)" == fallback ]] || fail 'config fallback failed'
  [[ "$(fedora_dev_config_list vscode web_extensions)" == $'web.one\nweb.two' ]] || fail 'config list parsing failed'
  fedora_dev_profile_valid full || fail 'full profile rejected'
  ! fedora_dev_profile_valid invalid || fail 'invalid profile accepted'
  [[ "$(fedora_dev_profile_description data)" == *'Python'* ]] || fail 'data description incorrect'

  local copy="$TEST_HOME/copied/machine.toml"
  fedora_dev_config_copy_if_missing "$copy"
  cmp -s "$TEST_CONFIG" "$copy" || fail 'config copy differs'
  printf '%s\n' preserved > "$copy"
  fedora_dev_config_copy_if_missing "$copy"
  [[ "$(<"$copy")" == preserved ]] || fail 'existing config was overwritten'
}

seed_skills_remote() {
  local remote="$1" seed="$2"
  git init --bare --initial-branch=main "$remote" >/dev/null
  git init --initial-branch=main "$seed" >/dev/null
  git -C "$seed" config user.email tests@example.invalid
  git -C "$seed" config user.name 'linux-setup tests'
  mkdir -p "$seed/published/alpha" "$seed/unpublished/beta"
  printf '%s\n' '---' 'name: alpha' '---' > "$seed/published/alpha/SKILL.md"
  printf '%s\n' '---' 'name: beta' '---' > "$seed/unpublished/beta/SKILL.md"
  git -C "$seed" add .
  git -C "$seed" commit -m seed >/dev/null
  git -C "$seed" remote add origin "$remote"
  git -C "$seed" push -u origin main >/dev/null
}

test_skills_sync_clone_link_and_dirty_protection() {
  new_environment skills
  local remote="$TEST_ROOT/skills/remote.git" seed="$TEST_ROOT/skills/seed"
  local checkout="$TEST_ROOT/skills/checkout" active="$TEST_HOME/codex-skills"
  mkdir -p "$TEST_ROOT/skills" "$active/alpha"
  printf '%s\n' old > "$active/alpha/SKILL.md"
  seed_skills_remote "$remote" "$seed"
  write_config "$TEST_HOME/Code" "$active" "$checkout" "$remote"

  expect_status 0 run_cli skills sync || return
  assert_contains "$EXPECT_OUTPUT" 'Synced skill: alpha' || return
  assert_contains "$EXPECT_OUTPUT" 'Synced skill: beta' || return
  [[ -L "$active/alpha" ]] || fail 'alpha was not linked into Codex'
  [[ -L "$active/beta" ]] || fail 'nested beta was not linked into Codex'
  [[ -d "$active/alpha.before-linux-setup" ]] || fail 'existing Codex skill was not preserved'
  [[ "$(readlink -f "$active/alpha")" == "$checkout/published/alpha" ]] || fail 'alpha link targets the wrong skill'

  mkdir -p "$seed/published/gamma"
  printf '%s\n' '---' 'name: gamma' '---' > "$seed/published/gamma/SKILL.md"
  git -C "$seed" add .
  git -C "$seed" commit -m gamma >/dev/null
  git -C "$seed" push >/dev/null

  expect_status 0 run_cli skills sync || return
  [[ -L "$active/gamma" ]] || fail 'clean skills checkout did not fast-forward and link gamma'

  printf '%s\n' local-change >> "$checkout/published/alpha/SKILL.md"
  mkdir -p "$seed/published/delta"
  printf '%s\n' '---' 'name: delta' '---' > "$seed/published/delta/SKILL.md"
  git -C "$seed" add .
  git -C "$seed" commit -m delta >/dev/null
  git -C "$seed" push >/dev/null

  expect_status 0 run_cli skills sync || return
  assert_contains "$EXPECT_OUTPUT" 'local changes; preserving them' || return
  [[ ! -e "$active/delta" ]] || fail 'dirty skills checkout unexpectedly pulled remote changes'
  assert_file_contains "$checkout/published/alpha/SKILL.md" local-change
}

test_skills_sync_rejects_non_git_checkout() {
  new_environment non-git-skills
  local checkout="$TEST_ROOT/non-git-skills/checkout" active="$TEST_HOME/codex-skills"
  mkdir -p "$checkout/published/example"
  printf '%s\n' '---' 'name: example' '---' > "$checkout/published/example/SKILL.md"
  write_config "$TEST_HOME/Code" "$active" "$checkout" 'https://example.invalid/skills.git'

  expect_status 2 run_cli skills sync || return
  assert_contains "$EXPECT_OUTPUT" 'is not a Git checkout' || return
  [[ ! -e "$active/example" ]] || fail 'non-Git checkout changed Codex skills'
}

test_ssh_and_desktop_commands_are_idempotent() {
  new_environment desktop
  write_config "$TEST_HOME/Code" "$TEST_HOME/codex-skills" "$TEST_HOME/Code/skills" 'https://example.invalid/skills.git'

  expect_status 0 run_cli ssh configure || return
  expect_status 0 run_cli ssh configure || return
  local ssh_config="$TEST_HOME/.ssh/config"
  assert_file_contains "$ssh_config" 'Host github.com' || return
  [[ "$(grep -Fc '# BEGIN linux-setup managed GitHub defaults' "$ssh_config")" == 1 ]] || fail 'SSH block was duplicated'

  EXPECT_OUTPUT="$(env -u DEV_HOME -u CODEX_SKILLS_DIR XDG_CURRENT_DESKTOP=GNOME \
    HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_DATA_HOME="$TEST_HOME/.local/share" \
    XDG_STATE_HOME="$TEST_HOME/.local/state" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_BIN_HOME="$TEST_HOME/.local/bin" \
    FEDORA_DEV_CONFIG_FILE="$TEST_CONFIG" "$REPO_ROOT/linux-setup" desktop apply 2>&1)"
  assert_file_contains "$TEST_HOME/.config/dev-machine/desktop/common/README" managed-by-linux-setup || return
  assert_file_contains "$TEST_HOME/.config/gtk-3.0/bookmarks" "file://$TEST_HOME/Code Code" || return

  EXPECT_OUTPUT="$(env -u DEV_HOME -u CODEX_SKILLS_DIR XDG_CURRENT_DESKTOP=COSMIC \
    HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_DATA_HOME="$TEST_HOME/.local/share" \
    XDG_STATE_HOME="$TEST_HOME/.local/state" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_BIN_HOME="$TEST_HOME/.local/bin" \
    FEDORA_DEV_CONFIG_FILE="$TEST_CONFIG" "$REPO_ROOT/linux-setup" desktop apply 2>&1)"
  assert_file_contains "$TEST_HOME/.config/dev-machine/desktop/cosmic/README" managed-by-linux-setup

  local fake_bin="$TEST_ROOT/desktop/fake-bin" wallpaper="$TEST_ROOT/desktop/wallpaper.png" gsettings_log="$TEST_ROOT/desktop/gsettings.log"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "$GSETTINGS_LOG"' > "$fake_bin/gsettings"
  chmod +x "$fake_bin/gsettings"
  printf '%s\n' image > "$wallpaper"
  EXPECT_OUTPUT="$(env -u DEV_HOME -u CODEX_SKILLS_DIR \
    HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/.config" XDG_DATA_HOME="$TEST_HOME/.local/share" \
    XDG_STATE_HOME="$TEST_HOME/.local/state" XDG_CACHE_HOME="$TEST_HOME/.cache" XDG_BIN_HOME="$TEST_HOME/.local/bin" \
    FEDORA_DEV_CONFIG_FILE="$TEST_CONFIG" GSETTINGS_LOG="$gsettings_log" PATH="$fake_bin:$PATH" \
    "$REPO_ROOT/linux-setup" desktop wallpaper "$wallpaper" 2>&1)"
  assert_contains "$EXPECT_OUTPUT" 'GNOME wallpaper set from' || return
  assert_file_contains "$gsettings_log" 'org.gnome.desktop.background picture-uri file://' || return
  assert_file_contains "$gsettings_log" 'org.gnome.desktop.background picture-uri-dark file://'
}

test_generated_installer_contracts() {
  bash -n "$REPO_ROOT/linux-setup" "$REPO_ROOT/lib/"*.sh "$REPO_ROOT/desktop/"*/apply.sh || return

  local appearance="$TEST_ROOT/appearance.json" keybindings="$TEST_ROOT/keybindings.json"
  awk 'f { if ($0 == "EOF") exit; print } /^cat > "\$appearance_tmp"/ { f=1; next }' "$REPO_ROOT/lib/install.sh" > "$appearance"
  awk 'f { if ($0 == "EOF") exit; print } /^cat > "\$keybindings_tmp"/ { f=1; next }' "$REPO_ROOT/lib/install.sh" > "$keybindings"
  jq -e '
    .["workbench.colorTheme"] == "Atom One Dark" and
    .["workbench.browser.openLocalhostLinks"] == false and
    .["workbench.browser.enableChatTools"] == false and
    .["terminal.integrated.defaultProfile.linux"] == "fish" and
    .["git.autofetch"] == true and
    .["git.autofetchPeriod"] == 180 and
    (."workbench.settings.applyToAllProfiles" | index("git.autofetch")) and
    (."workbench.settings.applyToAllProfiles" | index("git.autofetchPeriod"))
  ' "$appearance" >/dev/null || fail 'shared VS Code settings contract failed'
  jq -e '
    any(.[]; .key == "ctrl+t" and .command == "workbench.action.terminal.toggleTerminal") and
    any(.[]; .key == "ctrl+shift+t" and .command == "workbench.action.terminal.new") and
    any(.[]; .key == "ctrl+f" and .command == "-workbench.action.terminal.focusFind")
  ' "$keybindings" >/dev/null || fail 'shared VS Code keybindings contract failed'
  grep -Fq '"rust@$RUST_VERSION"' "$REPO_ROOT/lib/install.sh" || fail 'Rust is not installed through mise'
  grep -Fq 'CARGO_HOME=$XDG_DATA_HOME/cargo' "$REPO_ROOT/lib/install.sh" || fail 'Cargo is not XDG-managed'
  [[ -d "$REPO_ROOT/assets/wallpapers" && -d "$REPO_ROOT/assets/icons" && -d "$REPO_ROOT/assets/images" ]] || fail 'asset directories are missing'
  assert_file_contains "$REPO_ROOT/assets/README.md" 'desktop wallpaper'
}

run_test 'CLI help, profiles, and guarded commands' test_cli_help_profiles_and_errors
run_test 'profile plans and install dry runs' test_profile_plans_and_dry_runs
run_test 'configuration helpers and path expansion' test_config_helpers
run_test 'skills clone, recursive links, and dirty-checkout protection' test_skills_sync_clone_link_and_dirty_protection
run_test 'skills sync rejects a non-Git checkout safely' test_skills_sync_rejects_non_git_checkout
run_test 'SSH and desktop commands are idempotent' test_ssh_and_desktop_commands_are_idempotent
run_test 'installer syntax and generated VS Code contracts' test_generated_installer_contracts

printf '\n%d passed; %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
