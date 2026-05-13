#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${GPA_RESOURCE_ROOT:-}" ]]; then
  RESOURCE_ROOT="$GPA_RESOURCE_ROOT"
else
  RESOURCE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

exec "$RESOURCE_ROOT/Tools/install-codex-hooks.sh"
