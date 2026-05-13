#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(basename "$SCRIPT_DIR")" == "Tools" && "$(basename "$(dirname "$SCRIPT_DIR")")" == "Resources" ]]; then
  RESOURCE_ROOT="$(dirname "$SCRIPT_DIR")"
else
  RESOURCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

BUNDLED_PETCTL="$RESOURCE_ROOT/bin/petctl"

if [[ ! -x "$BUNDLED_PETCTL" ]]; then
  if command -v swift >/dev/null 2>&1 && [[ -f "$RESOURCE_ROOT/Package.swift" ]]; then
    BUNDLED_PETCTL=(swift run --package-path "$RESOURCE_ROOT" petctl)
  else
    echo "Could not find bundled petctl at $BUNDLED_PETCTL" >&2
    echo "Install GlobalPetAssistant.app or run this script from the source checkout." >&2
    exit 1
  fi
fi

echo "Global Pet Assistant integration setup"
echo "Resources: $RESOURCE_ROOT"
echo

if [[ "$(declare -p BUNDLED_PETCTL 2>/dev/null)" == declare\ -a* ]]; then
  GPA_RESOURCE_ROOT="$RESOURCE_ROOT" "${BUNDLED_PETCTL[@]}" install "$@"
else
  GPA_RESOURCE_ROOT="$RESOURCE_ROOT" "$BUNDLED_PETCTL" install "$@"
fi
