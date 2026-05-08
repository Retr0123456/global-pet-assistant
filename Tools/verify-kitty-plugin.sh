#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/kitty"

echo "kitty plugin: shell syntax"
bash -n "$PLUGIN_DIR/install.sh"
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$PLUGIN_DIR/shell-integration.zsh"
else
  echo "zsh not found; skipped zsh syntax check"
fi

echo "kitty plugin: python emitter syntax"
python3 - "$PLUGIN_DIR/global_pet_assistant.py" <<'PY'
import ast
import sys
from pathlib import Path

path = Path(sys.argv[1])
ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
PY

tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

echo "kitty plugin: clean HOME install"
HOME="$tmp_home" \
  GPA_KITTY_PLUGIN_SKIP_PREFLIGHT=1 \
  "$PLUGIN_DIR/install.sh" >/tmp/global-pet-assistant-kitty-install.log

installed_dir="$tmp_home/.config/kitty/global-pet-assistant"
test -x "$installed_dir/global_pet_assistant.py"
test -r "$installed_dir/shell-integration.zsh"
test -r "$installed_dir/env.zsh"
test -r "$installed_dir/kitty.conf"
grep -Fq "global-pet-assistant kitty plugin" "$tmp_home/.zshrc"
grep -Fq "global-pet-assistant kitty remote control" "$tmp_home/.config/kitty/kitty.conf"
grep -Fq "allow_remote_control yes" "$installed_dir/kitty.conf"
grep -Fq "listen_on unix:" "$installed_dir/kitty.conf"

echo "kitty plugin: idempotent reinstall"
HOME="$tmp_home" \
  GPA_KITTY_PLUGIN_SKIP_PREFLIGHT=1 \
  "$PLUGIN_DIR/install.sh" >/tmp/global-pet-assistant-kitty-reinstall.log

zsh_blocks="$(grep -Fc "global-pet-assistant kitty plugin" "$tmp_home/.zshrc")"
kitty_blocks="$(grep -Fc "global-pet-assistant kitty remote control" "$tmp_home/.config/kitty/kitty.conf")"
if [[ "$zsh_blocks" != "2" ]]; then
  echo "Expected one zsh managed block, found marker count $zsh_blocks" >&2
  exit 1
fi
if [[ "$kitty_blocks" != "2" ]]; then
  echo "Expected one kitty managed block, found marker count $kitty_blocks" >&2
  exit 1
fi

echo "kitty plugin verified"
