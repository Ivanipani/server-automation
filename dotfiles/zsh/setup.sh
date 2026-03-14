#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"

check_dep() {
  if ! command -v "$1" &>/dev/null; then
    echo "WARNING: '$1' not found"
  fi
}

cmd_setup() {
  local os="$(uname -s)"
  local platform
  case "$os" in
    Darwin) platform="mac" ;;
    Linux)  platform="linux" ;;
    *)      echo "Unsupported OS: $os"; exit 1 ;;
  esac

  echo "Platform: $platform"
  echo "Checking dependencies..."

  # Shared dependencies
  for dep in nvim direnv just zellij starship fd fzf go git wget; do
    check_dep "$dep"
  done

  # Mac-only dependencies
  if [[ "$platform" == "mac" ]]; then
    for dep in cargo wezterm atuin bun; do
      check_dep "$dep"
    done
  fi

  echo "Creating symlinks..."
  ln -sf "$SCRIPT_DIR/$platform/config" "$HOME/.zshrc"
  ln -sf "$SCRIPT_DIR/starship.toml" "$HOME/.config/starship.toml"
  mkdir -p "$HOME/scripts"
  ln -sf "$SCRIPT_DIR/scripts/retry" "$HOME/scripts/retry"
  echo "Done."
}

cmd_setup
