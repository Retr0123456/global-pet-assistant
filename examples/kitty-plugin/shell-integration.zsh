# Global Pet Assistant structured kitty plugin integration.

[[ "${GPA_KITTY_PLUGIN:-1}" == "0" ]] && return 0
[[ -n "${KITTY_WINDOW_ID:-}" ]] || return 0

autoload -Uz add-zsh-hook
zmodload zsh/datetime 2>/dev/null || true

: "${GPA_KITTY_PLUGIN_EMITTER:=$HOME/.config/kitty/global-pet-assistant/global_pet_assistant.py}"

typeset -g __gpa_kitty_plugin_command=""
typeset -gF __gpa_kitty_plugin_start=0
typeset -g __gpa_kitty_plugin_agent_provider=""

__gpa_kitty_plugin_ignored() {
  local normalized="${1#"${1%%[![:space:]]*}"}"
  normalized="${normalized%"${normalized##*[![:space:]]}"}"
  case "$normalized" in
    cd|ls|pwd|clear|history|jobs|"git status") return 0 ;;
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
  [[ -x "$GPA_KITTY_PLUGIN_EMITTER" ]] || return 0
  "$GPA_KITTY_PLUGIN_EMITTER" "$@" >/dev/null 2>&1 || true
}

__gpa_kitty_plugin_preexec() {
  __gpa_kitty_plugin_command="$1"
  __gpa_kitty_plugin_start=$EPOCHREALTIME
  __gpa_kitty_plugin_agent_provider="$(__gpa_kitty_plugin_agent_provider_for_command "$1")"
  if [[ -n "$__gpa_kitty_plugin_agent_provider" ]]; then
    __gpa_kitty_plugin_emit --kind agent-observed --provider-hint "$__gpa_kitty_plugin_agent_provider" --command "$1"
  fi
  __gpa_kitty_plugin_ignored "$1" && return 0
  __gpa_kitty_plugin_emit --kind command-started --command "$1"
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
