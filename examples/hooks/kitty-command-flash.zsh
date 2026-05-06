# Global Pet Assistant flash notifications for manual commands in kitty.
# Source this file from interactive zsh sessions. It is intentionally quiet
# outside kitty and can be disabled with GPA_KITTY_COMMAND_FLASH=0.

[[ -o interactive ]] || return 0
[[ -n "${KITTY_WINDOW_ID:-}" ]] || return 0
[[ "${GPA_KITTY_COMMAND_FLASH:-1}" != "0" ]] || return 0

autoload -Uz add-zsh-hook
zmodload zsh/datetime 2>/dev/null || return 0

if [[ -r "$HOME/.global-pet-assistant/hooks/kitty-command-flash.env.zsh" ]]; then
  source "$HOME/.global-pet-assistant/hooks/kitty-command-flash.env.zsh"
fi

: "${GPA_KITTY_COMMAND_FLASH_MIN_SUCCESS_MS:=5000}"
: "${GPA_KITTY_COMMAND_FLASH_SOURCE:=kitty-command}"
if [[ -z "${GPA_KITTY_COMMAND_FLASH_PETCTL:-}" ]]; then
  if (( $+commands[petctl] )); then
    GPA_KITTY_COMMAND_FLASH_PETCTL="petctl"
  else
    __gpa_kitty_hook_path="${(%):-%x}"
    __gpa_kitty_hook_dir="${__gpa_kitty_hook_path:A:h}"
    __gpa_kitty_repo_root="${__gpa_kitty_hook_dir:h:h}"
    if [[ -f "$__gpa_kitty_repo_root/Package.swift" ]]; then
      GPA_KITTY_COMMAND_FLASH_PETCTL="swift run --package-path ${__gpa_kitty_repo_root:q} petctl"
    else
      GPA_KITTY_COMMAND_FLASH_PETCTL="swift run petctl"
    fi
  fi
fi

typeset -g __gpa_kitty_command=""
typeset -gF __gpa_kitty_command_start=0

__gpa_kitty_command_is_ignored() {
  local command="${1#"${1%%[![:space:]]*}"}"
  command="${command%"${command##*[![:space:]]}"}"
  command="${command%%[;&|]*}"
  command="${command#"${command%%[![:space:]]*}"}"
  command="${command%"${command##*[![:space:]]}"}"

  [[ -z "$command" ]] && return 0
  [[ "$command" == "cd" || "$command" == cd\ * ]] && return 0
  [[ "$command" == "pwd" ]] && return 0
  [[ "$command" == "clear" ]] && return 0
  [[ "$command" == "history" || "$command" == history\ * ]] && return 0
  [[ "$command" == "ls" || "$command" == ls\ * ]] && return 0
  [[ "$command" == "ll" || "$command" == "la" || "$command" == "l" ]] && return 0
  [[ "$command" == "git status" || "$command" == "git status "* ]] && return 0
  [[ "$command" == "git diff" || "$command" == "git diff "* ]] && return 0
  [[ "$command" == "git log" || "$command" == "git log "* ]] && return 0
  [[ "$command" == "git branch" || "$command" == "git branch "* ]] && return 0
  [[ "$command" == "fg" || "$command" == "bg" || "$command" == "jobs" ]] && return 0

  return 1
}

__gpa_kitty_command_label() {
  local command="${1//$'\n'/ }"
  command="${command#"${command%%[![:space:]]*}"}"
  command="${command%"${command##*[![:space:]]}"}"
  if (( ${#command} > 80 )); then
    command="${command[1,79]}…"
  fi
  print -r -- "$command"
}

__gpa_kitty_command_flash() {
  setopt local_options no_bg_nice

  local level="$1"
  local message="$2"

  local -a petctl_command
  petctl_command=(${(z)GPA_KITTY_COMMAND_FLASH_PETCTL})
  "${petctl_command[@]}" flash \
    --source "$GPA_KITTY_COMMAND_FLASH_SOURCE:${KITTY_WINDOW_ID}" \
    --level "$level" \
    --message "$message" \
    --timeout 0.4 >/dev/null 2>&1 &
}

__gpa_kitty_command_preexec() {
  __gpa_kitty_command="$1"
  __gpa_kitty_command_start=$EPOCHREALTIME
}

__gpa_kitty_command_precmd() {
  local exit_status=$?
  local command="$__gpa_kitty_command"
  local -F start=$__gpa_kitty_command_start

  __gpa_kitty_command=""
  __gpa_kitty_command_start=0

  [[ -n "$command" ]] || return 0
  [[ "${GPA_KITTY_COMMAND_FLASH:-1}" != "0" ]] || return 0
  __gpa_kitty_command_is_ignored "$command" && return 0

  local -F elapsed=0
  elapsed=$(( EPOCHREALTIME - start ))
  local -i elapsed_ms
  elapsed_ms=$(( elapsed * 1000 ))
  local label="$(__gpa_kitty_command_label "$command")"

  if (( exit_status != 0 )); then
    __gpa_kitty_command_flash danger "$label failed (${exit_status})"
  elif (( elapsed_ms >= GPA_KITTY_COMMAND_FLASH_MIN_SUCCESS_MS )); then
    __gpa_kitty_command_flash success "$label passed"
  fi
}

add-zsh-hook preexec __gpa_kitty_command_preexec
add-zsh-hook precmd __gpa_kitty_command_precmd
