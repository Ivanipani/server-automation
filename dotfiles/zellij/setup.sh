#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
CONFIG_HOME="$HOME/.config/zellij"

check_dep() {
  if ! command -v "$1" &>/dev/null; then
    echo "WARNING: '$1' not found"
  fi
}

cmd_setup() {
  check_dep "zellij"

  echo "Creating symlinks..."
  mkdir -p "$CONFIG_HOME"
  ln -sf "$SCRIPT_DIR/config.kdl" "$CONFIG_HOME/config.kdl"

  rm -rf "$CONFIG_HOME/layouts"
  ln -sf "$SCRIPT_DIR/layouts" "$CONFIG_HOME/layouts"

  rm -rf "$CONFIG_HOME/plugins"
  ln -sf "$SCRIPT_DIR/plugins" "$CONFIG_HOME/plugins"

  echo "Done."
}

cmd_setup
