#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build

swift run GlobalPetAssistant &
APP_PID=$!
BIG_PAYLOAD=""
BIG_RESPONSE=""
INVALID_STATE_RESPONSE=""
trap 'kill "$APP_PID" >/dev/null 2>&1 || true; rm -f "$BIG_PAYLOAD" "$BIG_RESPONSE" "$INVALID_STATE_RESPONSE"' EXIT

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
