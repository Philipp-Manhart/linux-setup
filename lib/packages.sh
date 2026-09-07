#!/usr/bin/env bash

configure_dnf() {
  local setting value
  for setting in max_parallel_downloads defaultyes; do
    if [[ "$setting" == max_parallel_downloads ]]; then
      value=10
    else
      value=True
    fi

    if sudo grep -Eq "^[[:space:]]*${setting}[[:space:]]*=" /etc/dnf/dnf.conf; then
      sudo sed -i -E "s|^[[:space:]]*${setting}[[:space:]]*=.*|${setting}=${value}|" /etc/dnf/dnf.conf
    else
      printf '%s=%s\n' "$setting" "$value" | sudo tee -a /etc/dnf/dnf.conf >/dev/null
    fi
  done
}

install_base_packages() {
  log "Updating Fedora and installing base development packages"
  sudo -v
  configure_dnf
  sudo dnf upgrade --refresh -y
  sudo dnf install -y \
    dnf5-plugins git git-lfs gh curl wget unzip zip tar xz jq ripgrep fd-find \
    fzf bat fish util-linux-user gcc gcc-c++ make cmake pkgconf-pkg-config \
    openssl-devel libffi-devel fontconfig

  git lfs install --skip-repo >/dev/null
  ok "Fedora updated and base development packages installed"
}
