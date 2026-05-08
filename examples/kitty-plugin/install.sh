#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${GPA_KITTY_PLUGIN_DIR:-$HOME/.config/kitty/global-pet-assistant}"

mkdir -p "$INSTALL_DIR"
install -m 0755 "$SCRIPT_DIR/global_pet_assistant.py" "$INSTALL_DIR/global_pet_assistant.py"
install -m 0644 "$SCRIPT_DIR/shell-integration.zsh" "$INSTALL_DIR/shell-integration.zsh"

echo "Installed Global Pet Assistant kitty plugin to $INSTALL_DIR"
echo "Enable it in a kitty zsh session with:"
echo "source \"$INSTALL_DIR/shell-integration.zsh\""
