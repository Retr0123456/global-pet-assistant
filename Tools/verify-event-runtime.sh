#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
LOG_DIR="$HOME/.global-pet-assistant/logs"
BUILD_LOG="$LOG_DIR/local-build-latest.log"
EXAMPLE_REPO_URL="https://github.com/example/global-pet-assistant"
SWIFT_BUILD_FLAGS="${SWIFT_BUILD_FLAGS:-}"

swift build ${SWIFT_BUILD_FLAGS}

swift run GlobalPetAssistant &
APP_PID=$!
BIG_PAYLOAD=""
BIG_RESPONSE=""
INVALID_STATE_RESPONSE=""
RATE_LIMIT_RESPONSE=""
CODEX_RESPONSE=""
INVALID_URL_RESPONSE=""
INVALID_FOLDER_RESPONSE=""
UNKNOWN_ACTION_RESPONSE=""
UNKNOWN_NOTIFY_RESPONSE=""
FILE_ACTION_RESPONSE=""
APP_ACTION_RESPONSE=""
trap 'kill "$APP_PID" >/dev/null 2>&1 || true; rm -f "$BIG_PAYLOAD" "$BIG_RESPONSE" "$INVALID_STATE_RESPONSE" "$RATE_LIMIT_RESPONSE" "$CODEX_RESPONSE" "$INVALID_URL_RESPONSE" "$INVALID_FOLDER_RESPONSE" "$UNKNOWN_ACTION_RESPONSE" "$UNKNOWN_NOTIFY_RESPONSE" "$FILE_ACTION_RESPONSE" "$APP_ACTION_RESPONSE"' EXIT

sleep 2

echo "healthz: app is reachable"
curl -fsS http://127.0.0.1:17321/healthz
echo

echo "petctl: invalid state rejected locally"
INVALID_STATE_RESPONSE="$(mktemp "${TMPDIR:-/tmp}/gpa-invalid-state.XXXXXX.out")"
if swift run petctl state invalid-state --timeout 1 >"$INVALID_STATE_RESPONSE" 2>&1; then
  echo "Expected petctl to reject invalid state"
  cat "$INVALID_STATE_RESPONSE"
  exit 1
fi

BIG_PAYLOAD="$(mktemp "${TMPDIR:-/tmp}/gpa-big-event.XXXXXX.json")"
BIG_RESPONSE="$(mktemp "${TMPDIR:-/tmp}/gpa-big-response.XXXXXX.json")"
perl -e 'print "{\"source\":\"manual\",\"type\":\"too.large\",\"message\":\"" . ("x" x 17000) . "\"}"' > "$BIG_PAYLOAD"
STATUS="$(curl -sS -o "$BIG_RESPONSE" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  --data-binary "@$BIG_PAYLOAD" \
  http://127.0.0.1:17321/events)"
if [[ "$STATUS" != "413" ]]; then
  echo "Expected oversized body to return HTTP 413, got $STATUS"
  cat "$BIG_RESPONSE"
  exit 1
fi
echo "body size limit: oversized event rejected with HTTP 413"

echo "rate limit: noisy default source eventually returns HTTP 429"
RATE_LIMIT_RESPONSE="$(mktemp "${TMPDIR:-/tmp}/gpa-rate-limit.XXXXXX.json")"
RATE_LIMIT_HIT=0
for _ in {1..25}; do
  STATUS="$(curl -sS -o "$RATE_LIMIT_RESPONSE" -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -d '{"source":"spam-test","type":"task.tick","level":"running","ttlMs":1000}' \
    http://127.0.0.1:17321/events)"
  if [[ "$STATUS" == "429" ]]; then
    RATE_LIMIT_HIT=1
    break
  fi
done
if [[ "$RATE_LIMIT_HIT" != "1" ]]; then
  echo "Expected spam-test burst to hit HTTP 429"
  cat "$RATE_LIMIT_RESPONSE"
  exit 1
fi
grep -q '"error":"rate_limited"' "$RATE_LIMIT_RESPONSE"
grep -q '"retryAfterMs":' "$RATE_LIMIT_RESPONSE"
echo "rate limit: HTTP 429 includes rate_limited and retryAfterMs"

echo "rate limit: clear remains accepted for a rate-limited source"
swift run petctl clear --source spam-test --timeout 5 >/dev/null

echo "action validation: allowed GitHub URL is accepted"
CODEX_RESPONSE="$(mktemp "${TMPDIR:-/tmp}/gpa-codex-action.XXXXXX.json")"
STATUS="$(curl -sS -o "$CODEX_RESPONSE" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d "{\"source\":\"codex-cli\",\"type\":\"task.completed\",\"level\":\"success\",\"title\":\"Open repo\",\"action\":{\"type\":\"open_url\",\"url\":\"$EXAMPLE_REPO_URL\"},\"ttlMs\":1000}" \
  http://127.0.0.1:17321/events)"
if [[ "$STATUS" != "202" ]]; then
  echo "Expected valid GitHub action URL to return HTTP 202, got $STATUS"
  cat "$CODEX_RESPONSE"
  exit 1
fi

echo "action allowlist: unknown source without action is accepted"
UNKNOWN_NOTIFY_RESPONSE="$(mktemp "${TMPDIR:-/tmp}/gpa-unknown-notify.XXXXXX.json")"
STATUS="$(curl -sS -o "$UNKNOWN_NOTIFY_RESPONSE" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d '{"source":"unknown-tool","type":"task.completed","level":"success","title":"Unknown source notification","ttlMs":1000}' \
  http://127.0.0.1:17321/events)"
if [[ "$STATUS" != "202" ]]; then
  echo "Expected unknown source without action to return HTTP 202, got $STATUS"
  cat "$UNKNOWN_NOTIFY_RESPONSE"
  exit 1
fi

echo "action allowlist: unknown source with action is rejected"
UNKNOWN_ACTION_RESPONSE="$(mktemp "${TMPDIR:-/tmp}/gpa-unknown-action.XXXXXX.json")"
STATUS="$(curl -sS -o "$UNKNOWN_ACTION_RESPONSE" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d "{\"source\":\"unknown-tool\",\"type\":\"task.completed\",\"level\":\"success\",\"title\":\"Unknown source action\",\"action\":{\"type\":\"open_url\",\"url\":\"$EXAMPLE_REPO_URL\"},\"ttlMs\":1000}" \
  http://127.0.0.1:17321/events)"
if [[ "$STATUS" != "403" ]]; then
  echo "Expected unknown source action to return HTTP 403, got $STATUS"
  cat "$UNKNOWN_ACTION_RESPONSE"
  exit 1
fi
grep -q '"error":"action_not_allowed"' "$UNKNOWN_ACTION_RESPONSE"

echo "action validation: petctl accepts an allowed project folder action"
swift run petctl notify \
  --source local-build \
  --level warning \
  --title "Open project folder" \
  --action-folder "$ROOT_DIR" \
  --ttl-ms 1000 \
  --timeout 5 >/dev/null

echo "action validation: petctl accepts an allowed build log file action"
mkdir -p "$LOG_DIR"
echo "example build failure" > "$BUILD_LOG"
swift run petctl notify \
  --source local-build \
  --level danger \
  --title "Open build log" \
  --action-file "$BUILD_LOG" \
  --ttl-ms 1000 \
  --timeout 5 >/dev/null

echo "action validation: allowed app bundle action is accepted"
APP_ACTION_RESPONSE="$(mktemp "${TMPDIR:-/tmp}/gpa-app-action.XXXXXX.json")"
STATUS="$(curl -sS -o "$APP_ACTION_RESPONSE" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d '{"source":"codex-cli","type":"task.completed","level":"success","title":"Open Codex","action":{"type":"open_app","bundleId":"com.openai.codex"},"ttlMs":1000}' \
  http://127.0.0.1:17321/events)"
if [[ "$STATUS" != "202" ]]; then
  echo "Expected valid app bundle action to return HTTP 202, got $STATUS"
  cat "$APP_ACTION_RESPONSE"
  exit 1
fi

echo "action validation: disallowed URL is rejected"
INVALID_URL_RESPONSE="$(mktemp "${TMPDIR:-/tmp}/gpa-invalid-url.XXXXXX.json")"
STATUS="$(curl -sS -o "$INVALID_URL_RESPONSE" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d '{"source":"codex-cli","type":"task.completed","level":"success","action":{"type":"open_url","url":"ftp://example.com/file"}}' \
  http://127.0.0.1:17321/events)"
if [[ "$STATUS" != "400" ]]; then
  echo "Expected invalid action URL to return HTTP 400, got $STATUS"
  cat "$INVALID_URL_RESPONSE"
  exit 1
fi

echo "action validation: non-directory folder action is rejected"
INVALID_FOLDER_RESPONSE="$(mktemp "${TMPDIR:-/tmp}/gpa-invalid-folder.XXXXXX.json")"
STATUS="$(curl -sS -o "$INVALID_FOLDER_RESPONSE" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d "{\"source\":\"local-build\",\"type\":\"task.completed\",\"level\":\"success\",\"action\":{\"type\":\"open_folder\",\"path\":\"$ROOT_DIR/Package.swift\"}}" \
  http://127.0.0.1:17321/events)"
if [[ "$STATUS" != "400" ]]; then
  echo "Expected invalid action folder to return HTTP 400, got $STATUS"
  cat "$INVALID_FOLDER_RESPONSE"
  exit 1
fi

echo "hook example: Codex running event"
examples/hooks/codex-task.sh running >/dev/null

echo "petctl: clear setup events before manual row checks"
swift run petctl clear --timeout 5 >/dev/null

echo "curl: level running -> running row"
curl -sS \
  -H 'Content-Type: application/json' \
  -d '{"source":"manual","type":"task.started","level":"running","title":"Running","message":"Manual running state"}' \
  http://127.0.0.1:17321/events
echo
sleep 2

echo "petctl: notify success -> review row"
swift run petctl notify --level success --title "Manual success" --message "Review row should play"
sleep 2

echo "petctl: notify warning -> waiting row"
swift run petctl notify --level warning --title "Manual warning" --message "Waiting row should play"
sleep 2

echo "curl: level danger -> failed row"
curl -sS \
  -H 'Content-Type: application/json' \
  -d '{"source":"manual","type":"task.failed","level":"danger","title":"Danger","message":"Failed row should play"}' \
  http://127.0.0.1:17321/events
echo
sleep 2

echo "petctl: clear high-priority failure before direct state checks"
swift run petctl clear --timeout 5 >/dev/null

echo "petctl: direct state running"
swift run petctl state running --message "Direct running state"
sleep 2

echo "petctl: direct state running-right"
swift run petctl state running-right --message "Direct running-right state"
sleep 2

echo "petctl: direct state running-left"
swift run petctl state running-left --message "Direct running-left state"
sleep 2

echo "petctl: direct state waving"
swift run petctl state waving --message "Direct waving state"
sleep 2

echo "petctl: direct state jumping"
swift run petctl state jumping --message "Direct jumping state"
sleep 2

echo "petctl: direct state waiting"
swift run petctl state waiting --message "Direct waiting state"
sleep 2

echo "petctl: direct state failed"
swift run petctl state failed --message "Direct failed state"
sleep 2

echo "petctl: direct state review"
swift run petctl state review --message "Direct review state"
sleep 2

echo "petctl: clear -> idle row"
swift run petctl clear --timeout 5

echo "Manual verification complete. Confirm the pet played all atlas rows: idle, running-right, running-left, waving, jumping, failed, waiting, running, and review."
