#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_HOOK="$ROOT_DIR/examples/hooks/kitty-command-flash.zsh"
HOOK_DIR="$HOME/.global-pet-assistant/hooks"
INSTALLED_HOOK="$HOOK_DIR/kitty-command-flash.zsh"
INSTALLED_ENV="$HOOK_DIR/kitty-command-flash.env.zsh"
ZSHRC="$HOME/.zshrc"
MARKER_BEGIN="# >>> global-pet-assistant kitty command flash >>>"
MARKER_END="# <<< global-pet-assistant kitty command flash <<<"

mkdir -p "$HOOK_DIR"
cp "$SOURCE_HOOK" "$INSTALLED_HOOK"
printf 'GPA_KITTY_COMMAND_FLASH_PETCTL=%q\n' "swift run --package-path $ROOT_DIR petctl" > "$INSTALLED_ENV"

if [[ ! -f "$ZSHRC" ]]; then
  touch "$ZSHRC"
fi

if grep -Fq "$MARKER_BEGIN" "$ZSHRC"; then
  echo "kitty command flash hook is already configured in $ZSHRC"
else
  {
    printf '\n%s\n' "$MARKER_BEGIN"
    printf 'if [[ -r "$HOME/.global-pet-assistant/hooks/kitty-command-flash.zsh" ]]; then\n'
    printf '  source "$HOME/.global-pet-assistant/hooks/kitty-command-flash.zsh"\n'
    printf 'fi\n'
    printf '%s\n' "$MARKER_END"
  } >> "$ZSHRC"
  echo "Added kitty command flash hook to $ZSHRC"
fi

echo "Installed $INSTALLED_HOOK"
echo "Installed $INSTALLED_ENV"
echo "Open a new kitty tab/window, or run: source ~/.zshrc"
