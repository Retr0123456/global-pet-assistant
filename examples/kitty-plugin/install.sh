#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${GPA_KITTY_PLUGIN_DIR:-$HOME/.config/kitty/global-pet-assistant}"
ZSHRC="${GPA_KITTY_PLUGIN_ZSHRC:-$HOME/.zshrc}"
MARKER_BEGIN="# >>> global-pet-assistant kitty plugin >>>"
MARKER_END="# <<< global-pet-assistant kitty plugin <<<"

mkdir -p "$INSTALL_DIR"
install -m 0755 "$SCRIPT_DIR/global_pet_assistant.py" "$INSTALL_DIR/global_pet_assistant.py"
install -m 0644 "$SCRIPT_DIR/shell-integration.zsh" "$INSTALL_DIR/shell-integration.zsh"

echo "Installed Global Pet Assistant kitty plugin to $INSTALL_DIR"

if [[ "${GPA_KITTY_PLUGIN_INSTALL_ZSHRC:-1}" == "0" ]]; then
  echo "Skipped zsh configuration because GPA_KITTY_PLUGIN_INSTALL_ZSHRC=0"
  echo "Enable it manually with:"
  echo "source \"$INSTALL_DIR/shell-integration.zsh\""
  exit 0
fi

if [[ ! -f "$ZSHRC" ]]; then
  touch "$ZSHRC"
fi

SOURCE_LINE="source \"$INSTALL_DIR/shell-integration.zsh\""

if grep -Fq "$MARKER_BEGIN" "$ZSHRC"; then
  echo "Kitty plugin is already configured in $ZSHRC"
else
  {
    printf '\n%s\n' "$MARKER_BEGIN"
    printf 'if [[ -n "${KITTY_WINDOW_ID:-}" && -r %q ]]; then\n' "$INSTALL_DIR/shell-integration.zsh"
    printf '  %s\n' "$SOURCE_LINE"
    printf 'fi\n'
    printf '%s\n' "$MARKER_END"
  } >> "$ZSHRC"
  echo "Added kitty plugin configuration to $ZSHRC"
fi

echo "Open a new kitty tab/window, or run: source \"$ZSHRC\""
