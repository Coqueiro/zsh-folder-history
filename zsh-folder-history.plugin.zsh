# shellcheck shell=zsh

if [[ -n ${__zsh_folder_history_loaded:-} ]]; then
  return 0
fi
typeset -g __zsh_folder_history_loaded=1

autoload -U add-zsh-hook

: ${ZSH_FOLDER_HISTORY_FILE:=${XDG_STATE_HOME:-$HOME/.local/state}/zsh-folder-history/directories}
: ${ZSH_FOLDER_HISTORY_MAX_DIRS:=500}
: ${ZSH_FOLDER_HISTORY_MAX_COMMANDS:=50}
: ${ZSH_FOLDER_HISTORY_ENABLE_ALIASES:=0}

typeset -ga _zfh_dirs=()
typeset -gA _zfh_commands=()
typeset -gi _zfh_internal_cd=0
typeset -gi _zfh_widget_registered=0
typeset -gi _zfh_lock_fd=-1
typeset -g _zfh_lock_backend=''
typeset -g _zfh_lock_dir=''

_zfh_dedupe_limit() {
  emulate -L zsh

  local -i limit=$1
  shift

  local item
  local -A seen=()
  local -a result=()

  for item in "$@"; do
    [[ -n $item ]] || continue
    [[ -n ${seen[$item]-} ]] && continue
    seen[$item]=1
    result+=("$item")
    if (( limit > 0 && ${#result[@]} >= limit )); then
      break
    fi
  done

  print -rl -- "${result[@]}"
}

_zfh_join_lines() {
  emulate -L zsh
  local IFS=$'\n'
  print -r -- "$*"
}

_zfh_filter_existing_dirs() {
  emulate -L zsh

  local dir
  local -a existing=()

  for dir in "$@"; do
    [[ -d $dir ]] || continue
    existing+=("${dir:A}")
  done

  _zfh_dedupe_limit "$ZSH_FOLDER_HISTORY_MAX_DIRS" "${existing[@]}"
}

_zfh_normalize_command() {
  emulate -L zsh

  local command_text=$1
  command_text=${command_text//$'\r'/ }
  command_text=${command_text//$'\n'/ ' ↩ '}
  command_text=${command_text//$'\t'/ ' '}
  print -r -- "$command_text"
}

_zfh_is_ignored_command() {
  emulate -L zsh

  local command_text=$1

  case "$command_text" in
    (zfh|zfh\ *|folder-history|folder-history\ *|zsh-folder-history|zsh-folder-history\ *)
      return 0
      ;;
  esac

  return 1
}

_zfh_ensure_state_file() {
  emulate -L zsh

  command mkdir -p -- "${ZSH_FOLDER_HISTORY_FILE:h}" || return 1
  [[ -f $ZSH_FOLDER_HISTORY_FILE ]] || : >| "$ZSH_FOLDER_HISTORY_FILE"
}

_zfh_read_state_dirs() {
  emulate -L zsh

  local -a loaded=()

  _zfh_ensure_state_file || return 1

  if [[ -r $ZSH_FOLDER_HISTORY_FILE ]]; then
    loaded=("${(@f)$(<"$ZSH_FOLDER_HISTORY_FILE")}")
  fi

  _zfh_filter_existing_dirs "${loaded[@]}"
}

_zfh_lock_file() {
  emulate -L zsh
  print -r -- "${ZSH_FOLDER_HISTORY_FILE}.lockfile"
}

_zfh_refresh_dirs() {
  emulate -L zsh

  local -a disk_dirs=()
  disk_dirs=("${(@f)$(_zfh_read_state_dirs)}")
  _zfh_dirs=("${(@f)$(_zfh_filter_existing_dirs "${_zfh_dirs[@]}" "${disk_dirs[@]}")}")
}

_zfh_acquire_lock() {
  emulate -L zsh

  local lock_file=$1
  local lock_dir="${lock_file}.dir"
  local pid_file="${lock_dir}/pid"
  local owner_pid
  local -i attempts=100

  _zfh_lock_backend=''
  _zfh_lock_dir=''

  if zmodload -F zsh/system b:zsystem 2>/dev/null; then
    [[ -f $lock_file ]] || : >| "$lock_file"
    if zsystem flock -t 5 -f _zfh_lock_fd "$lock_file"; then
      _zfh_lock_backend='zsystem'
      return 0
    fi
    print -u2 -- 'zfh: failed to acquire state lock'
    return 1
  fi

  while (( attempts > 0 )); do
    if [[ -r $pid_file ]]; then
      owner_pid=$(<"$pid_file")
      if [[ -n $owner_pid ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
        command rm -rf -- "$lock_dir"
      fi
    fi

    if command mkdir -- "$lock_dir" 2>/dev/null; then
      print -r -- "$$" >| "$pid_file"
      _zfh_lock_backend='mkdir'
      _zfh_lock_dir="$lock_dir"
      return 0
    fi

    sleep 0.05
    (( attempts-- ))
  done

  print -u2 -- "zfh: failed to acquire state lock"
  return 1
}

_zfh_release_lock() {
  emulate -L zsh

  case "$_zfh_lock_backend" in
    (zsystem)
      if (( _zfh_lock_fd >= 0 )); then
        zsystem flock -u "$_zfh_lock_fd" 2>/dev/null
        _zfh_lock_fd=-1
      fi
      ;;
    (mkdir)
      [[ -n $_zfh_lock_dir ]] && command rm -rf -- "$_zfh_lock_dir"
      ;;
  esac

  _zfh_lock_backend=''
  _zfh_lock_dir=''
}

_zfh_load_dirs() {
  emulate -L zsh
  _zfh_dirs=("${(@f)$(_zfh_read_state_dirs)}")
}

_zfh_save_dirs() {
  emulate -L zsh

  local lock_file
  local temp_file exit_code
  local -a disk_dirs=()

  _zfh_ensure_state_file || return 1
  lock_file="$(_zfh_lock_file)"
  _zfh_acquire_lock "$lock_file" || return 1

  disk_dirs=("${(@f)$(_zfh_read_state_dirs)}")
  _zfh_dirs=("${(@f)$(_zfh_filter_existing_dirs "${_zfh_dirs[@]}" "${disk_dirs[@]}")}")

  temp_file=$(command mktemp "${ZSH_FOLDER_HISTORY_FILE}.tmp.XXXXXX") || {
    _zfh_release_lock
    return 1
  }

  if (( ${#_zfh_dirs[@]} == 0 )); then
    : >| "$temp_file"
  else
    print -rl -- "${_zfh_dirs[@]}" >| "$temp_file"
  fi

  exit_code=$?
  if (( exit_code == 0 )); then
    command mv -f -- "$temp_file" "$ZSH_FOLDER_HISTORY_FILE"
    exit_code=$?
  fi

  [[ -f $temp_file ]] && command rm -f -- "$temp_file"
  _zfh_release_lock
  return $exit_code
}

_zfh_add_dir() {
  emulate -L zsh

  local dir="${1:A}"
  [[ -n $dir && -d $dir ]] || return 0

  _zfh_dirs=("${(@f)$(_zfh_dedupe_limit "$ZSH_FOLDER_HISTORY_MAX_DIRS" "$dir" "${_zfh_dirs[@]}")}")
  _zfh_save_dirs
}

_zfh_record_command() {
  emulate -L zsh

  local dir="${1:A}"
  local command_text="$2"
  local existing
  local -a merged=()

  [[ -d $dir ]] || return 0
  command_text="$(_zfh_normalize_command "$command_text")"
  [[ -n ${command_text//[[:space:]]/} ]] || return 0
  _zfh_is_ignored_command "$command_text" && return 0

  existing="${_zfh_commands[$dir]-}"
  merged=("${(@f)$(_zfh_dedupe_limit "$ZSH_FOLDER_HISTORY_MAX_COMMANDS" "$command_text" "${(@f)existing}")}")
  _zfh_commands[$dir]="$(_zfh_join_lines "${merged[@]}")"
}

_zfh_print_commands_for_dir() {
  emulate -L zsh

  local dir="${1:A}"
  local commands="${_zfh_commands[$dir]-}"

  if [[ -z $commands ]]; then
    print -r -- 'No commands recorded for this directory in the current shell session.'
    return 0
  fi

  print -rl -- "${(@f)commands}"
}

_zfh_build_picker_input() {
  emulate -L zsh

  local temp_dir=$1
  local dir preview_file
  local -i index=0

  for dir in "${_zfh_dirs[@]}"; do
    (( index++ ))
    preview_file="$temp_dir/$index"
    _zfh_print_commands_for_dir "$dir" >| "$preview_file"
    printf '%s\t%s\n' "$dir" "$preview_file"
  done
}

_zfh_preexec() {
  emulate -L zsh

  local command_text="${1:-$3}"

  (( _zfh_internal_cd )) && return 0
  _zfh_record_command "$PWD" "$command_text"
}

_zfh_chpwd() {
  emulate -L zsh
  (( _zfh_internal_cd )) && return 0

  _zfh_add_dir "$PWD"
}

zfh_pick() {
  emulate -L zsh
  setopt localoptions pipefail no_aliases

  local query="$*"
  local temp_dir selection selected_dir
  local exit_code

  command -v fzf >/dev/null 2>&1 || {
    print -u2 -- 'zfh: fzf is required'
    return 1
  }

  _zfh_add_dir "$PWD"
  _zfh_refresh_dirs
  temp_dir=$(command mktemp -d "${TMPDIR:-/tmp}/zsh-folder-history.XXXXXX") || return 1

  selection="$(_zfh_build_picker_input "$temp_dir" | fzf \
    --delimiter=$'\t' \
    --with-nth=1 \
    --prompt='folder-history> ' \
    --preview='[[ -f {2} ]] && cat {2}' \
    --preview-window='right,60%,wrap' \
    --query "$query")"
  exit_code=$?

  command rm -rf -- "$temp_dir"

  (( exit_code == 0 )) || return $exit_code

  selected_dir="${selection%%$'\t'*}"
  [[ -n $selected_dir ]] || return 0

  _zfh_internal_cd=1
  builtin cd -- "$selected_dir"
  exit_code=$?
  _zfh_internal_cd=0

  if (( exit_code == 0 )); then
    _zfh_add_dir "$PWD"
  fi

  return $exit_code
}

_zfh_register_widget() {
  emulate -L zsh

  [[ -o interactive ]] || {
    print -u2 -- 'zfh: widget support requires an interactive zsh shell'
    return 1
  }

  (( _zfh_widget_registered )) && return 0
  zle -N zfh_widget
  _zfh_widget_registered=1
}

zfh_widget() {
  emulate -L zsh

  local original_buffer=$BUFFER
  local original_cursor=$CURSOR
  local exit_code

  BUFFER=''
  CURSOR=0
  zle -I

  zfh_pick
  exit_code=$?

  BUFFER=$original_buffer
  CURSOR=$original_cursor
  zle reset-prompt
  return $exit_code
}

zfh_bindkey() {
  emulate -L zsh

  local key="${1:-^H}"
  _zfh_register_widget || return 1
  bindkey "$key" zfh_widget
}

zfh_help() {
  cat <<'EOF'
zfh - zsh folder history picker

Usage:
  zfh
  zfh pick [query]
  zfh list
  zfh commands [dir]
  zfh bindkey [key]
  zfh help

Notes:
  - Commands are shown as recent unique commands for the current shell session.
  - Source this plugin from your shell config; it cannot cd when executed as a script.
EOF
}

zfh() {
  emulate -L zsh

  local subcommand=${1:-pick}

  case "$subcommand" in
    (pick)
      shift
      zfh_pick "$*"
      ;;
    (list)
      _zfh_refresh_dirs
      print -rl -- "${_zfh_dirs[@]}"
      ;;
    (commands)
      shift
      _zfh_print_commands_for_dir "${1:-$PWD}"
      ;;
    (bindkey)
      shift
      zfh_bindkey "${1:-^H}"
      ;;
    (help|-h|--help)
      zfh_help
      ;;
    (*)
      print -u2 -- "zfh: unknown subcommand: $subcommand"
      zfh_help >&2
      return 1
      ;;
  esac
}

zfh_unload() {
  emulate -L zsh
  add-zsh-hook -d preexec _zfh_preexec 2>/dev/null
  add-zsh-hook -d chpwd _zfh_chpwd 2>/dev/null
  unalias folder-history 2>/dev/null
  unalias zsh-folder-history 2>/dev/null
  unset __zsh_folder_history_loaded
}

if (( ZSH_FOLDER_HISTORY_ENABLE_ALIASES )); then
  alias folder-history='zfh'
  alias zsh-folder-history='zfh'
fi

if [[ -o interactive ]]; then
  _zfh_load_dirs
  _zfh_add_dir "$PWD"
  add-zsh-hook preexec _zfh_preexec
  add-zsh-hook chpwd _zfh_chpwd
fi
