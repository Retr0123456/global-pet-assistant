# Global Pet Assistant structured kitty plugin integration.

[[ -o interactive ]] || return 0
[[ "${GPA_KITTY_PLUGIN:-1}" == "0" ]] && return 0
[[ -n "${KITTY_WINDOW_ID:-}" ]] || return 0
[[ -n "${__GPA_KITTY_PLUGIN_LOADED:-}" ]] && return 0
typeset -g __GPA_KITTY_PLUGIN_LOADED=1

autoload -Uz add-zsh-hook
zmodload zsh/datetime 2>/dev/null || true

: "${GPA_KITTY_PLUGIN_EMITTER:=$HOME/.config/kitty/global-pet-assistant/global_pet_assistant.py}"
: "${GPA_TERMINAL_PLUGIN_ENDPOINT:=http://127.0.0.1:17321/terminal-plugin/events}"
: "${GPA_KITTY_PLUGIN_TIMEOUT:=0.8}"
: "${GPA_KITTY_PLUGIN_EMIT_COMMAND_STARTED:=0}"
: "${GPA_KITTY_CONTROL_ENDPOINT:=${KITTY_LISTEN_ON:-}}"

typeset -g __gpa_kitty_plugin_command=""
typeset -gF __gpa_kitty_plugin_start=0
typeset -g __gpa_kitty_plugin_agent_provider=""

__gpa_kitty_plugin_ignored() {
  local normalized="${1#"${1%%[![:space:]]*}"}"
  normalized="${normalized%"${normalized##*[![:space:]]}"}"
  normalized="${normalized%%[;&|]*}"
  normalized="${normalized#"${normalized%%[![:space:]]*}"}"
  normalized="${normalized%"${normalized##*[![:space:]]}"}"
  case "$normalized" in
    ""|cd|cd\ *|ls|ls\ *|pwd|clear|history|history\ *|jobs|fg|bg) return 0 ;;
    "git status"|"git status "*|"git diff"|"git diff "*|"git log"|"git log "*|"git branch"|"git branch "*) return 0 ;;
  esac
  return 1
}

__gpa_kitty_plugin_agent_provider_for_command() {
  local command="$1"
  local -a words
  words=("${(@z)command}")

  local word
  for word in "${words[@]}"; do
    case "$word" in
      env|command|exec|noglob|time) continue ;;
      *=*) continue ;;
      codex|*/codex|cdx|*/cdx)
        echo codex
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  done
  return 1
}

__gpa_kitty_plugin_emit() {
  emulate -L zsh
  setopt no_unset

  local kind="" command="" exit_code="" duration_ms="" provider_hint=""
  while (( $# > 0 )); do
    case "$1" in
      --kind) kind="${2:-}"; shift 2 ;;
      --command) command="${2:-}"; shift 2 ;;
      --exit-code) exit_code="${2:-}"; shift 2 ;;
      --duration-ms) duration_ms="${2:-}"; shift 2 ;;
      --provider-hint) provider_hint="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -n "$kind" ]] || return 0
  (( $+commands[curl] )) || return 0

  local token="${GPA_TOKEN:-}"
  if [[ -z "$token" && -r "${GPA_TOKEN_FILE:-$HOME/.global-pet-assistant/token}" ]]; then
    token="$(< "${GPA_TOKEN_FILE:-$HOME/.global-pet-assistant/token}")"
  fi
  token="${token//$'\r'/}"
  token="${token//$'\n'/}"
  [[ -n "$token" ]] || return 0

  local session_id="kitty-${KITTY_WINDOW_ID:-$TTY}"
  local control_endpoint="${KITTY_LISTEN_ON:-$GPA_KITTY_CONTROL_ENDPOINT}"
  local terminal="{\"kind\":\"kitty\",\"sessionId\":$(__gpa_kitty_plugin_json "$session_id")"
  [[ -n "${KITTY_WINDOW_ID:-}" ]] && terminal+=",\"windowId\":$(__gpa_kitty_plugin_json "$KITTY_WINDOW_ID")"
  [[ -n "${KITTY_TAB_ID:-}" ]] && terminal+=",\"tabId\":$(__gpa_kitty_plugin_json "$KITTY_TAB_ID")"
  [[ -n "${PWD:-}" ]] && terminal+=",\"cwd\":$(__gpa_kitty_plugin_json "$PWD")"
  [[ -n "$command" ]] && terminal+=",\"command\":$(__gpa_kitty_plugin_json "$command")"
  [[ -n "$control_endpoint" ]] && terminal+=",\"controlEndpoint\":$(__gpa_kitty_plugin_json "$control_endpoint")"
  terminal+="}"

  local payload="{\"schemaVersion\":1,\"kind\":$(__gpa_kitty_plugin_json "$kind"),\"terminal\":$terminal,\"occurredAt\":${EPOCHREALTIME:-0}"
  [[ -n "$command" ]] && payload+=",\"command\":$(__gpa_kitty_plugin_json "$command")"
  [[ -n "$exit_code" ]] && payload+=",\"exitCode\":$exit_code"
  [[ -n "$duration_ms" ]] && payload+=",\"durationMs\":$duration_ms"
  [[ -n "$provider_hint" ]] && payload+=",\"providerHint\":$(__gpa_kitty_plugin_json "$provider_hint")"
  payload+="}"

  curl -fsS \
    --max-time "$GPA_KITTY_PLUGIN_TIMEOUT" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    --data-binary "$payload" \
    "$GPA_TERMINAL_PLUGIN_ENDPOINT" >/dev/null 2>&1 || true
}

__gpa_kitty_plugin_json() {
  emulate -L zsh
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  print -rn -- "\"$value\""
}

__gpa_kitty_plugin_preexec() {
  __gpa_kitty_plugin_command="$1"
  __gpa_kitty_plugin_start=$EPOCHREALTIME
  __gpa_kitty_plugin_agent_provider="$(__gpa_kitty_plugin_agent_provider_for_command "$1")"
  if [[ -n "$__gpa_kitty_plugin_agent_provider" ]]; then
    __gpa_kitty_plugin_emit --kind agent-observed --provider-hint "$__gpa_kitty_plugin_agent_provider" --command "$1"
  fi
  __gpa_kitty_plugin_ignored "$1" && return 0
  [[ "$GPA_KITTY_PLUGIN_EMIT_COMMAND_STARTED" == "1" ]] && __gpa_kitty_plugin_emit --kind command-started --command "$1"
}

__gpa_kitty_plugin_precmd() {
  local exit_status=$?
  local command="$__gpa_kitty_plugin_command"
  local provider="$__gpa_kitty_plugin_agent_provider"
  local -F start=$__gpa_kitty_plugin_start
  __gpa_kitty_plugin_command=""
  __gpa_kitty_plugin_agent_provider=""
  __gpa_kitty_plugin_start=0

  [[ -n "$command" ]] || return 0
  if [[ -n "$provider" ]]; then
    __gpa_kitty_plugin_emit \
      --kind agent-observed \
      --provider-hint "$provider" \
      --command "$command" \
      --exit-code "$exit_status"
  fi
  __gpa_kitty_plugin_ignored "$command" && return 0

  local duration_ms=0
  if (( start > 0 )); then
    duration_ms=$(( int((EPOCHREALTIME - start) * 1000) ))
  fi
  __gpa_kitty_plugin_emit \
    --kind command-completed \
    --command "$command" \
    --exit-code "$exit_status" \
    --duration-ms "$duration_ms"
}

gpa-codex() {
  __gpa_kitty_plugin_emit --kind agent-observed --provider-hint codex --command "codex $*"
  codex "$@"
  local exit_status=$?
  __gpa_kitty_plugin_emit \
    --kind agent-observed \
    --provider-hint codex \
    --command "codex $*" \
    --exit-code "$exit_status"
  return "$exit_status"
}

add-zsh-hook preexec __gpa_kitty_plugin_preexec
add-zsh-hook precmd __gpa_kitty_plugin_precmd
