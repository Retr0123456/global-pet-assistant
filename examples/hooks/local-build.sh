#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PETCTL_COMMAND="${PETCTL:-swift run petctl}"
PET_SOURCE="${PET_SOURCE:-local-build}"
PET_DEDUPE_KEY="${PET_DEDUPE_KEY:-local-build:global-pet-assistant}"
PET_TTL_MS="${PET_TTL_MS:-30000}"
PET_LOG_PATH="${PET_LOG_PATH:-/Users/ryanchen/.global-pet-assistant/logs/local-build-latest.log}"

run_petctl() {
  ${PETCTL_COMMAND} "$@"
}

if [[ "$#" -gt 0 ]]; then
  BUILD_COMMAND=("$@")
else
  BUILD_COMMAND=(swift build)
fi

run_petctl state running \
  --source "$PET_SOURCE" \
  --message "${PET_MESSAGE:-Running ${BUILD_COMMAND[*]}}" \
  --ttl-ms "$PET_TTL_MS" \
  --dedupe-key "$PET_DEDUPE_KEY"

mkdir -p "$(dirname "$PET_LOG_PATH")"

if "${BUILD_COMMAND[@]}" >"$PET_LOG_PATH" 2>&1; then
  run_petctl notify \
    --source "$PET_SOURCE" \
    --level success \
    --title "${PET_TITLE:-Local build complete}" \
    --message "${PET_SUCCESS_MESSAGE:-${BUILD_COMMAND[*]} succeeded}" \
    --dedupe-key "$PET_DEDUPE_KEY" \
    --action-folder "${PET_ACTION_FOLDER:-/Users/ryanchen/codespace/global-pet-assistant}"
else
  run_petctl notify \
    --source "$PET_SOURCE" \
    --level danger \
    --title "${PET_TITLE:-Local build failed}" \
    --message "${PET_FAILURE_MESSAGE:-${BUILD_COMMAND[*]} failed. Click to open the latest log.}" \
    --dedupe-key "$PET_DEDUPE_KEY" \
    --action-file "$PET_LOG_PATH"
  exit 1
fi
