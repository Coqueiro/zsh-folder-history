# shellcheck shell=zsh

if [[ -n ${__zsh_folder_history_loaded:-} ]]; then
  return 0
fi
typeset -g __zsh_folder_history_loaded=1

autoload -U add-zsh-hook
zmodload zsh/datetime 2>/dev/null || true

: ${ZSH_FOLDER_HISTORY_FILE:=${XDG_STATE_HOME:-$HOME/.local/state}/zsh-folder-history/directories}
: ${ZSH_FOLDER_HISTORY_MAX_DIRS:=500}
: ${ZSH_FOLDER_HISTORY_MAX_COMMANDS:=1000}
: ${ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR:=$ZSH_FOLDER_HISTORY_MAX_COMMANDS}
: ${ZSH_FOLDER_HISTORY_COMMANDS_FILE:=${ZSH_FOLDER_HISTORY_FILE:h}/commands.tsv}
: ${ZSH_FOLDER_HISTORY_BINDKEY:=^H}
: ${ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY:=alt-enter}
: ${ZSH_FOLDER_HISTORY_ENABLE_ALIASES:=0}

typeset -ga _zfh_dirs=()
typeset -gA _zfh_commands=()
typeset -gi _zfh_internal_cd=0
typeset -gi _zfh_widget_registered=0
typeset -gi _zfh_lock_fd=-1
typeset -gi _zfh_widget_active=0
typeset -gi _zfh_record_seq=0
typeset -g _zfh_lock_backend=''
typeset -g _zfh_lock_dir=''
typeset -g _zfh_last_selected_command=''

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

_zfh_history_limit() {
  emulate -L zsh

  local -i limit=$1
  shift

  local item
  local -A seen=()
  local -a ordered=("$@")
  local -a result=()

  ordered=("${(On)ordered}")

  for item in "${ordered[@]}"; do
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

_zfh_trim_command_records() {
  emulate -L zsh

  local -i limit=$1
  shift

  local record
  local -A seen=()
  local -a sorted=("${(On)@}")
  local -a result=()

  for record in "${sorted[@]}"; do
    [[ -n $record ]] || continue
    [[ -n ${seen[$record]-} ]] && continue
    seen[$record]=1
    result+=("$record")
    if (( limit > 0 && ${#result[@]} >= limit )); then
      break
    fi
  done

  print -rl -- "${result[@]}"
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

_zfh_now_epoch() {
  emulate -L zsh

  if [[ -n ${EPOCHSECONDS-} ]]; then
    print -r -- "$EPOCHSECONDS"
    return 0
  fi

  command date +%s
}

_zfh_now_sortkey() {
  emulate -L zsh

  local epoch realtime seconds microseconds
  local -i seconds_num microseconds_num pid_num seq_num

  epoch="$(_zfh_now_epoch)"
  realtime=${EPOCHREALTIME-}
  (( _zfh_record_seq++ ))

  if [[ -n $realtime && $realtime == *.* ]]; then
    seconds=${realtime%%.*}
    microseconds=${realtime#*.}
    microseconds=${microseconds[1,6]}
    microseconds=${(r:6::0:)microseconds}
  else
    seconds=$epoch
    microseconds=000000
  fi

  seconds_num=$((10#$seconds))
  microseconds_num=$((10#$microseconds))
  pid_num=$((10#$$))
  seq_num=$((10#$_zfh_record_seq))

  command printf '%010d%06d%06d%06d\n' "$seconds_num" "$microseconds_num" "$pid_num" "$seq_num"
}

_zfh_format_timestamp() {
  emulate -L zsh

  local epoch=$1
  local formatted=''

  if whence -w strftime >/dev/null 2>&1; then
    strftime -s formatted '%Y-%m-%d %H:%M:%S' "$epoch"
    print -r -- "$formatted"
    return 0
  fi

  if formatted=$(command date -r "$epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null); then
    print -r -- "$formatted"
    return 0
  fi

  if formatted=$(command date -d "@$epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null); then
    print -r -- "$formatted"
    return 0
  fi

  print -r -- "$epoch"
}

_zfh_ensure_file() {
  emulate -L zsh

  local target_file=$1
  command mkdir -p -- "${target_file:h}" || return 1
  [[ -f $target_file ]] || : >| "$target_file"
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

  _zfh_ensure_file "$ZSH_FOLDER_HISTORY_FILE"
  _zfh_ensure_file "$ZSH_FOLDER_HISTORY_COMMANDS_FILE"
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

_zfh_commands_lock_file() {
  emulate -L zsh
  print -r -- "${ZSH_FOLDER_HISTORY_COMMANDS_FILE}.lockfile"
}

_zfh_fzf_preview_command() {
  emulate -L zsh
  print -r -- "sh -c '[ -f \"\$1\" ] && cat -- \"\$1\"' sh {2}"
}

_zfh_make_command_record() {
  emulate -L zsh

  local sortkey=$1
  local epoch=$2
  local command_text=$3
  command printf '%s\t%s\t%s\n' "$sortkey" "$epoch" "$command_text"
}

_zfh_command_record_sortkey() {
  emulate -L zsh

  local record=$1
  print -r -- "${record%%$'\t'*}"
}

_zfh_command_record_epoch() {
  emulate -L zsh

  local record=$1
  local rest="${record#*$'\t'}"
  local epoch="${rest%%$'\t'*}"
  print -r -- "$epoch"
}

_zfh_command_record_text() {
  emulate -L zsh

  local record=$1
  local rest="${record#*$'\t'}"
  print -r -- "${rest#*$'\t'}"
}

_zfh_format_command_record() {
  emulate -L zsh

  local record=$1
  local epoch command_text

  epoch="$(_zfh_command_record_epoch "$record")"
  command_text="$(_zfh_command_record_text "$record")"
  print -r -- "[$(_zfh_format_timestamp "$epoch")] $command_text"
}

_zfh_write_command_preview() {
  emulate -L zsh

  local dir="${1:A}"
  local record=$2
  local epoch command_text

  epoch="$(_zfh_command_record_epoch "$record")"
  command_text="$(_zfh_command_record_text "$record")"

  cat <<EOF
Directory: $dir
Timestamp: $(_zfh_format_timestamp "$epoch")

$command_text
EOF
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

_zfh_add_command_record() {
  emulate -L zsh

  local dir="${1:A}"
  local record=$2
  local existing
  local -a merged=()

  [[ -n $dir ]] || return 0
  [[ -n $record ]] || return 0

  existing="${_zfh_commands[$dir]-}"
  merged=("$record" "${(@f)existing}")
  merged=("${(@f)$(_zfh_trim_command_records "$ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR" "${merged[@]}")}")
  _zfh_commands[$dir]="$(_zfh_join_lines "${merged[@]}")"
}

_zfh_load_commands() {
  emulate -L zsh

  local dir sortkey epoch command_text record current

  _zfh_ensure_state_file || return 1
  [[ -r $ZSH_FOLDER_HISTORY_COMMANDS_FILE ]] || return 0

  _zfh_commands=()

  while IFS=$'\t' read -r dir sortkey epoch command_text; do
    [[ -n $dir && -n $sortkey && -n $epoch && -n $command_text ]] || continue
    record="${sortkey}"$'\t'"${epoch}"$'\t'"${command_text}"
    current="${_zfh_commands[$dir]-}"
    if [[ -n $current ]]; then
      _zfh_commands[$dir]+=$'\n'"$record"
    else
      _zfh_commands[$dir]="$record"
    fi
  done < "$ZSH_FOLDER_HISTORY_COMMANDS_FILE"

  for dir in "${(@ok)_zfh_commands}"; do
    _zfh_commands[$dir]="$(_zfh_join_lines "${(@f)$(_zfh_trim_command_records "$ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR" "${(@f)_zfh_commands[$dir]}")}")"
  done
}

_zfh_refresh_commands() {
  emulate -L zsh
  _zfh_load_commands
}

_zfh_save_commands() {
  emulate -L zsh

  local lock_file temp_file exit_code dir existing record
  local -A memory_commands=()
  local -a merged=()

  _zfh_ensure_state_file || return 1
  memory_commands=("${(@kv)_zfh_commands}")
  lock_file="$(_zfh_commands_lock_file)"
  _zfh_acquire_lock "$lock_file" || return 1
  _zfh_load_commands

  for dir in "${(@ok)memory_commands}"; do
    merged=("${(@f)memory_commands[$dir]}" "${(@f)_zfh_commands[$dir]}")
    merged=("${(@f)$(_zfh_trim_command_records "$ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR" "${merged[@]}")}")
    _zfh_commands[$dir]="$(_zfh_join_lines "${merged[@]}")"
  done

  temp_file=$(command mktemp "${ZSH_FOLDER_HISTORY_COMMANDS_FILE}.tmp.XXXXXX") || {
    _zfh_release_lock
    return 1
  }

  {
    for dir in "${(@ok)_zfh_commands}"; do
      existing="${_zfh_commands[$dir]-}"
      [[ -n $existing ]] || continue
      for record in "${(@f)existing}"; do
        print -r -- "$dir"$'\t'"$record"
      done
    done
  } >| "$temp_file"
  exit_code=$?

  if (( exit_code == 0 )); then
    command mv -f -- "$temp_file" "$ZSH_FOLDER_HISTORY_COMMANDS_FILE"
    exit_code=$?
  fi

  [[ -f $temp_file ]] && command rm -f -- "$temp_file"
  _zfh_release_lock
  return $exit_code
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
  local sortkey epoch record

  [[ -d $dir ]] || return 0
  command_text="$(_zfh_normalize_command "$command_text")"
  [[ -n ${command_text//[[:space:]]/} ]] || return 0
  _zfh_is_ignored_command "$command_text" && return 0

  sortkey="$(_zfh_now_sortkey)"
  epoch="$(_zfh_now_epoch)"
  record="$(_zfh_make_command_record "$sortkey" "$epoch" "$command_text")"
  record="${record%$'\n'}"
  _zfh_add_command_record "$dir" "$record"
  _zfh_save_commands
}

_zfh_print_commands_for_dir() {
  emulate -L zsh

  local dir="${1:A}"
  local commands="${_zfh_commands[$dir]-}"
  local record

  if [[ -z $commands ]]; then
    print -r -- 'No commands recorded for this directory.'
    return 0
  fi

  for record in "${(@f)commands}"; do
    _zfh_format_command_record "$record"
  done
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

_zfh_build_command_picker_input() {
  emulate -L zsh

  local dir="${1:A}"
  local temp_dir=$2
  local commands="${_zfh_commands[$dir]-}"
  local record preview_file display command_text
  local -i index=0

  for record in "${(@f)commands}"; do
    (( index++ ))
    preview_file="$temp_dir/$index"
    _zfh_write_command_preview "$dir" "$record" >| "$preview_file"
    display="$(_zfh_format_command_record "$record")"
    command_text="$(_zfh_command_record_text "$record")"
    printf '%s\t%s\t%s\n' "$display" "$preview_file" "$command_text"
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
  local temp_dir output key selection selected_dir selected_command
  local exit_code

  command -v fzf >/dev/null 2>&1 || {
    print -u2 -- 'zfh: fzf is required'
    return 1
  }

  _zfh_last_selected_command=''
  _zfh_add_dir "$PWD"
  _zfh_refresh_dirs
  _zfh_refresh_commands
  temp_dir=$(command mktemp -d "${TMPDIR:-/tmp}/zsh-folder-history.XXXXXX") || return 1

  while true; do
    output="$(_zfh_build_picker_input "$temp_dir" | fzf \
      --delimiter=$'\t' \
      --with-nth=1 \
      --expect="$ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY" \
      --prompt='folder-history> ' \
      --header="$ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY: browse commands for highlighted folder" \
      --preview="$(_zfh_fzf_preview_command)" \
      --preview-window='right,60%,wrap' \
      --query "$query")"
    exit_code=$?

    (( exit_code == 0 )) || {
      command rm -rf -- "$temp_dir"
      return $exit_code
    }

    key="${output%%$'\n'*}"
    selection="${output#*$'\n'}"
    selected_dir="${selection%%$'\t'*}"

    if [[ "$key" == "$ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY" ]]; then
      [[ -n $selected_dir ]] || continue
      selected_command="$(zfh_command_pick "$selected_dir")"
      exit_code=$?
      (( exit_code == 0 )) || {
        command rm -rf -- "$temp_dir"
        return $exit_code
      }
      _zfh_last_selected_command="$selected_command"
      command rm -rf -- "$temp_dir"
      if (( !_zfh_widget_active )) && [[ -n $selected_command ]]; then
        print -r -- "$selected_command"
      fi
      return 0
    fi

    break
  done

  command rm -rf -- "$temp_dir"

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

zfh_command_pick() {
  emulate -L zsh
  setopt localoptions pipefail no_aliases

  local dir="${1:-$PWD}"
  shift
  local query="$*"
  local temp_dir selection selected_command commands
  local exit_code

  command -v fzf >/dev/null 2>&1 || {
    print -u2 -- 'zfh: fzf is required'
    return 1
  }

  dir="${dir:A}"
  _zfh_refresh_commands
  commands="${_zfh_commands[$dir]-}"

  if [[ -z $commands ]]; then
    print -u2 -- "zfh: no commands recorded for $dir"
    return 1
  fi

  temp_dir=$(command mktemp -d "${TMPDIR:-/tmp}/zsh-folder-history-commands.XXXXXX") || return 1
  selection="$(_zfh_build_command_picker_input "$dir" "$temp_dir" | fzf \
    --delimiter=$'\t' \
    --with-nth=1 \
    --prompt='command-history> ' \
    --header='enter: print selected command | preview: full command' \
    --preview="$(_zfh_fzf_preview_command)" \
    --preview-window='right,60%,wrap' \
    --query "$query")"
  exit_code=$?

  command rm -rf -- "$temp_dir"
  (( exit_code == 0 )) || return $exit_code

  selected_command="${selection##*$'\t'}"
  _zfh_last_selected_command="$selected_command"
  print -r -- "$selected_command"
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

  _zfh_widget_active=1
  zfh_pick
  exit_code=$?
  _zfh_widget_active=0

  if [[ -n $_zfh_last_selected_command ]]; then
    BUFFER=$_zfh_last_selected_command
    CURSOR=${#BUFFER}
  else
    BUFFER=$original_buffer
    CURSOR=$original_cursor
  fi

  zle reset-prompt
  return $exit_code
}

zfh_bindkey() {
  emulate -L zsh

  local key="${1:-$ZSH_FOLDER_HISTORY_BINDKEY}"
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
  zfh command-pick [dir] [query]
  zfh bindkey [key]
  zfh help

Notes:
  - Commands are timestamped and persisted across shell sessions.
  - Per-folder command history limit defaults to 1000 entries.
  - Folder picker header advertises the key that opens command search.
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
      _zfh_refresh_commands
      _zfh_print_commands_for_dir "${1:-$PWD}"
      ;;
    (command-pick)
      shift
      zfh_command_pick "$@"
      ;;
    (bindkey)
      shift
      zfh_bindkey "${1:-$ZSH_FOLDER_HISTORY_BINDKEY}"
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
