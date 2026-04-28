# shellcheck shell=zsh

if [[ -n ${__zsh_folder_history_loaded:-} ]]; then
  return 0
fi
typeset -g __zsh_folder_history_loaded=1
typeset -g _zfh_plugin_file=${${(%):-%x}:A}

autoload -U add-zsh-hook
autoload -U add-zle-hook-widget 2>/dev/null || true
zmodload zsh/datetime 2>/dev/null || true

: ${ZSH_FOLDER_HISTORY_FILE:=${XDG_STATE_HOME:-$HOME/.local/state}/zsh-folder-history/directories}
: ${ZSH_FOLDER_HISTORY_MAX_DIRS:=500}
: ${ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR:=1000}
: ${ZSH_FOLDER_HISTORY_COMMANDS_DIR:=${ZSH_FOLDER_HISTORY_FILE:h}/commands}
: ${ZSH_FOLDER_HISTORY_AUTO_BIND:=1}
: ${ZSH_FOLDER_HISTORY_AUTO_BIND_FOLDER:=1}
: ${ZSH_FOLDER_HISTORY_AUTO_BIND_COMMAND:=1}
: ${ZSH_FOLDER_HISTORY_BINDKEY:=^H}
: ${ZSH_FOLDER_HISTORY_COMMAND_BINDKEY:=^[j}
: ${ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK:=1}
: ${ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY:=alt-j}
: ${ZSH_FOLDER_HISTORY_ENABLE_ALIASES:=0}

typeset -ga _zfh_dirs=()
typeset -gA _zfh_command_file_cache=()
typeset -gi _zfh_internal_cd=0
typeset -gi _zfh_folder_widget_registered=0
typeset -gi _zfh_command_widget_registered=0
typeset -gi _zfh_line_init_hook_registered=0
typeset -gi _zfh_lock_fd=-1
typeset -gi _zfh_widget_active=0
typeset -gi _zfh_record_seq=0
typeset -g _zfh_lock_backend=''
typeset -g _zfh_lock_dir=''
typeset -g _zfh_last_selected_command=''
typeset -g _zfh_last_selected_dir=''
typeset -g _zfh_pending_buffer=''
typeset -gi _zfh_pending_cursor=-1

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
  command_text=${command_text//$'\t'/ }
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
  command mkdir -p -- "$ZSH_FOLDER_HISTORY_COMMANDS_DIR" || return 1
}

_zfh_hash_dir_path() {
  emulate -L zsh

  local dir="${1:A}"
  local hash_value

  if zmodload zsh/md5 2>/dev/null; then
    hash_value=$(md5 -s "$dir" 2>/dev/null) || return 1
    hash_value=${hash_value##* = }
    hash_value=${hash_value##* }
    print -r -- "$hash_value"
    return 0
  fi

  hash_value=$(printf '%s\n' "$dir" | cksum | command cut -d' ' -f1) || return 1
  print -r -- "$hash_value"
}

_zfh_command_file_for_dir() {
  emulate -L zsh

  local dir="${1:A}"
  local hash_value

  if [[ -n ${_zfh_command_file_cache[$dir]-} ]]; then
    print -r -- "${_zfh_command_file_cache[$dir]}"
    return 0
  fi

  hash_value="$(_zfh_hash_dir_path "$dir")" || return 1
  _zfh_command_file_cache[$dir]="$ZSH_FOLDER_HISTORY_COMMANDS_DIR/$hash_value"
  print -r -- "${_zfh_command_file_cache[$dir]}"
}

_zfh_commands_lock_file_for_dir() {
  emulate -L zsh

  local dir="${1:A}"
  local command_file

  command_file="$(_zfh_command_file_for_dir "$dir")" || return 1
  print -r -- "${command_file}.lockfile"
}

_zfh_read_command_records_file() {
  emulate -L zsh

  local command_file=$1
  local sortkey epoch command_text record
  local -a records=()

  [[ -r $command_file ]] || return 0

  while IFS=$'\t' read -r sortkey epoch command_text; do
    [[ -n $sortkey && -n $epoch && -n $command_text ]] || continue
    record="${sortkey}"$'\t'"${epoch}"$'\t'"${command_text}"
    records+=("$record")
  done < "$command_file"

  _zfh_trim_command_records "$ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR" "${records[@]}"
}

_zfh_write_command_records_file() {
  emulate -L zsh

  local command_file=$1
  shift
  local temp_file exit_code
  local -a records=("$@")

  command mkdir -p -- "${command_file:h}" || return 1
  temp_file=$(command mktemp "${command_file}.tmp.XXXXXX") || return 1

  if (( ${#records[@]} == 0 )); then
    : >| "$temp_file"
  else
    print -rl -- "${records[@]}" >| "$temp_file"
  fi

  exit_code=$?
  if (( exit_code == 0 )); then
    command mv -f -- "$temp_file" "$command_file"
    exit_code=$?
  fi

  [[ -f $temp_file ]] && command rm -f -- "$temp_file"
  return $exit_code
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

_zfh_append_dir_record() {
  emulate -L zsh

  local dir="${1:A}"
  local lock_file

  _zfh_ensure_state_file || return 1
  lock_file="$(_zfh_lock_file)"
  _zfh_acquire_lock "$lock_file" || return 1
  print -r -- "$dir" >> "$ZSH_FOLDER_HISTORY_FILE"
  _zfh_release_lock
}

_zfh_append_command_record() {
  emulate -L zsh

  local dir="${1:A}"
  local record=$2
  local lock_file command_file

  _zfh_ensure_state_file || return 1
  command_file="$(_zfh_command_file_for_dir "$dir")" || return 1
  command mkdir -p -- "${command_file:h}" || return 1
  [[ -f $command_file ]] || : >| "$command_file"
  lock_file="$(_zfh_commands_lock_file_for_dir "$dir")" || return 1
  _zfh_acquire_lock "$lock_file" || return 1
  print -r -- "$record" >> "$command_file"
  _zfh_release_lock
}

_zfh_records_for_dir() {
  emulate -L zsh

  local target_dir="${1:A}"
  local command_file

  _zfh_ensure_state_file || return 1
  command_file="$(_zfh_command_file_for_dir "$target_dir")" || return 1
  _zfh_read_command_records_file "$command_file"
}

_zfh_trim_commands_for_dir() {
  emulate -L zsh

  local target_dir="${1:A}"
  local lock_file command_file exit_code
  local -a kept_records=()

  _zfh_ensure_state_file || return 1
  command_file="$(_zfh_command_file_for_dir "$target_dir")" || return 1
  lock_file="$(_zfh_commands_lock_file_for_dir "$target_dir")" || return 1
  _zfh_acquire_lock "$lock_file" || return 1

  kept_records=("${(@f)$(_zfh_read_command_records_file "$command_file")}")
  _zfh_write_command_records_file "$command_file" "${kept_records[@]}"
  exit_code=$?
  _zfh_release_lock
  return $exit_code
}

_zfh_fzf_dir_preview_command() {
  emulate -L zsh
  print -r -- "zsh -fc 'source \"\$1\"; shift; _zfh_print_commands_for_dir \"\$1\" 0' zsh ${_zfh_plugin_file:q} {}"
}

_zfh_fzf_command_preview_command() {
  emulate -L zsh
  print -r -- "zsh -fc 'source \"\$1\"; shift; _zfh_write_command_preview_fields \"\$1\" \"\$2\" \"\$3\"' zsh ${_zfh_plugin_file:q} {2} {3} {4}"
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

  _zfh_write_command_preview_fields "$dir" "$epoch" "$command_text"
}

_zfh_write_command_preview_fields() {
  emulate -L zsh

  local dir="${1:A}"
  local epoch=$2
  local command_text=$3

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

_zfh_compact_dirs() {
  emulate -L zsh

  local lock_file temp_file exit_code
  local -a compacted=()

  _zfh_ensure_state_file || return 1
  lock_file="$(_zfh_lock_file)"
  _zfh_acquire_lock "$lock_file" || return 1
  compacted=("${(@f)$(_zfh_read_state_dirs)}")

  temp_file=$(command mktemp "${ZSH_FOLDER_HISTORY_FILE}.tmp.XXXXXX") || {
    _zfh_release_lock
    return 1
  }

  if (( ${#compacted[@]} == 0 )); then
    : >| "$temp_file"
  else
    print -rl -- "${compacted[@]}" >| "$temp_file"
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
  _zfh_append_dir_record "$dir"
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
  _zfh_append_command_record "$dir" "$record"
}

_zfh_print_commands_for_dir() {
  emulate -L zsh

  local dir="${1:A}"
  local -i persist_trim=${2:-1}
  local commands
  local record

  (( persist_trim )) && _zfh_trim_commands_for_dir "$dir"
  commands="$(_zfh_records_for_dir "$dir")"

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

  print -rl -- "${_zfh_dirs[@]}"
}

_zfh_build_command_picker_input() {
  emulate -L zsh

  local dir="${1:A}"
  local commands=$2
  local record display command_text epoch

  for record in "${(@f)commands}"; do
    display="$(_zfh_format_command_record "$record")"
    epoch="$(_zfh_command_record_epoch "$record")"
    command_text="$(_zfh_normalize_command "$(_zfh_command_record_text "$record")")"
    printf '%s\t%s\t%s\t%s\n' "$display" "$dir" "$epoch" "$command_text"
  done
}

_zfh_preexec() {
  emulate -L zsh

  local command_text="$1"

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
  local output key selection selected_dir selected_command
  local exit_code
  local -a fzf_args=()

  command -v fzf >/dev/null 2>&1 || {
    print -u2 -- 'zfh: fzf is required'
    return 1
  }

  _zfh_last_selected_command=''
  _zfh_last_selected_dir=''
  _zfh_add_dir "$PWD"
  _zfh_refresh_dirs

  fzf_args=(
    --prompt='folder-history> '
    --preview="$(_zfh_fzf_dir_preview_command)"
    --preview-window='right,60%,wrap,nohidden'
    --query "$query"
  )

  if (( ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK )); then
    fzf_args+=(--expect="$ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY")
  fi

  while true; do
    output="$(_zfh_build_picker_input | fzf "${fzf_args[@]}")"
    exit_code=$?

    (( exit_code == 0 )) || return $exit_code

    if (( ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK )); then
      if [[ "$output" == *$'\n'* ]]; then
        key="${output%%$'\n'*}"
        selection="${output#*$'\n'}"
      else
        key=''
        selection="$output"
      fi
    else
      key=''
      selection="$output"
    fi

    selected_dir="$selection"

    if (( ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK )) && [[ "$key" == "$ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY" ]]; then
      [[ -n $selected_dir ]] || continue
      selected_command="$(zfh_command_pick "$selected_dir")"
      exit_code=$?
      (( exit_code == 0 )) || return $exit_code
      _zfh_last_selected_command="$selected_command"
      if (( !_zfh_widget_active )) && [[ -n $selected_command ]]; then
        print -r -- "$selected_command"
      fi
      return 0
    fi

    break
  done

  [[ -n $selected_dir ]] || return 0

  _zfh_internal_cd=1
  builtin cd -- "$selected_dir"
  exit_code=$?
  _zfh_internal_cd=0

  if (( exit_code == 0 )); then
    _zfh_add_dir "$PWD"
    _zfh_last_selected_dir="$PWD"
  fi

  return $exit_code
}

zfh_command_pick() {
  emulate -L zsh
  setopt localoptions pipefail no_aliases

  local dir="${1:-$PWD}"
  shift
  local query="$*"
  local selection selected_command commands
  local exit_code

  command -v fzf >/dev/null 2>&1 || {
    print -u2 -- 'zfh: fzf is required'
    return 1
  }

  _zfh_last_selected_command=''
  dir="${dir:A}"
  _zfh_trim_commands_for_dir "$dir"
  commands="$(_zfh_records_for_dir "$dir")"

  if [[ -z $commands ]]; then
    print -u2 -- "zfh: no commands recorded for $dir"
    return 1
  fi

  selection="$(_zfh_build_command_picker_input "$dir" "$commands" | fzf \
    --delimiter=$'\t' \
    --with-nth=1 \
    --prompt='command-history> ' \
    --preview="$(_zfh_fzf_command_preview_command)" \
    --preview-window='right,60%,wrap,nohidden' \
    --query "$query")"
  exit_code=$?

  (( exit_code == 0 )) || return $exit_code

  selected_command="${selection#*$'\t'}"
  selected_command="${selected_command#*$'\t'}"
  selected_command="${selected_command#*$'\t'}"
  _zfh_last_selected_command="$selected_command"
  print -r -- "$selected_command"
}

_zfh_register_widget() {
  emulate -L zsh

  [[ -o interactive ]] || {
    print -u2 -- 'zfh: widget support requires an interactive zsh shell'
    return 1
  }

  (( _zfh_folder_widget_registered )) || {
    zle -N zfh_widget
    _zfh_folder_widget_registered=1
  }

  (( _zfh_command_widget_registered )) || {
    zle -N zfh_command_widget
    _zfh_command_widget_registered=1
  }

  (( _zfh_line_init_hook_registered )) || {
    add-zle-hook-widget line-init _zfh_restore_pending_buffer 2>/dev/null || true
    _zfh_line_init_hook_registered=1
  }
}

_zfh_queue_buffer_restore() {
  emulate -L zsh

  _zfh_pending_buffer=$1
  _zfh_pending_cursor=$2
}

_zfh_restore_pending_buffer() {
  emulate -L zsh

  (( _zfh_pending_cursor >= 0 )) || return 0

  BUFFER=$_zfh_pending_buffer
  CURSOR=$_zfh_pending_cursor
  _zfh_pending_buffer=''
  _zfh_pending_cursor=-1
}

zfh_widget() {
  emulate -L zsh

  local original_buffer=$BUFFER
  local original_cursor=$CURSOR
  local had_original_buffer=0
  local exit_code

  [[ -n $original_buffer ]] && had_original_buffer=1

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
  elif (( exit_code == 0 )) && [[ -n $_zfh_last_selected_dir ]] && (( ! had_original_buffer )); then
    BUFFER=''
    CURSOR=0
    zle accept-line
    return 0
  elif (( exit_code == 0 )) && [[ -n $_zfh_last_selected_dir ]]; then
    _zfh_queue_buffer_restore "$original_buffer" "$original_cursor"
    BUFFER=''
    CURSOR=0
    zle accept-line
    return 0
  else
    BUFFER=$original_buffer
    CURSOR=$original_cursor
  fi

  zle reset-prompt
  return $exit_code
}

zfh_command_widget() {
  emulate -L zsh

  local original_buffer=$BUFFER
  local original_cursor=$CURSOR
  local exit_code

  BUFFER=''
  CURSOR=0
  zle -I

  _zfh_widget_active=1
  zfh_command_pick "$PWD"
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

zfh_bind_command_key() {
  emulate -L zsh

  local key="${1:-$ZSH_FOLDER_HISTORY_COMMAND_BINDKEY}"
  _zfh_register_widget || return 1
  bindkey "$key" zfh_command_widget
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
  zfh bind-command-key [key]
  zfh help

Notes:
  - Commands are timestamped and persisted across shell sessions.
  - Per-folder command history limit defaults to 1000 entries.
  - Default bindings: Ctrl-H opens folders and Alt-J opens command search.
  - Disable automatic binding with ZSH_FOLDER_HISTORY_AUTO_BIND=0.
  - Disable the folder widget with ZSH_FOLDER_HISTORY_AUTO_BIND_FOLDER=0.
  - Disable the command widget with ZSH_FOLDER_HISTORY_AUTO_BIND_COMMAND=0.
  - Inside the folder picker, alt-j opens command search by default.
  - Disable folder-picker command search with ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK=0.
  - Folder history appends on navigation and compacts when zfh folder-history commands run.
  - Command history appends on execution and trims only for the requested directory.
  - Preview panes are forced visible by default.
  - Environment variables:
      ZSH_FOLDER_HISTORY_FILE
      ZSH_FOLDER_HISTORY_COMMANDS_DIR
      ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR
      ZSH_FOLDER_HISTORY_MAX_DIRS
      ZSH_FOLDER_HISTORY_AUTO_BIND
      ZSH_FOLDER_HISTORY_AUTO_BIND_FOLDER
      ZSH_FOLDER_HISTORY_AUTO_BIND_COMMAND
      ZSH_FOLDER_HISTORY_BINDKEY
      ZSH_FOLDER_HISTORY_COMMAND_BINDKEY
      ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK
      ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY
      ZSH_FOLDER_HISTORY_ENABLE_ALIASES
  - Source this plugin from your shell config; it cannot cd when executed as a script.
EOF
}

zfh() {
  emulate -L zsh

  local subcommand=${1:-pick}

  case "$subcommand" in
    (pick)
      shift
      _zfh_compact_dirs
      zfh_pick "$*"
      ;;
    (list)
      _zfh_compact_dirs
      _zfh_refresh_dirs
      print -rl -- "${_zfh_dirs[@]}"
      ;;
    (commands)
      shift
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
    (bind-command-key)
      shift
      zfh_bind_command_key "${1:-$ZSH_FOLDER_HISTORY_COMMAND_BINDKEY}"
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
  add-zle-hook-widget -d line-init _zfh_restore_pending_buffer 2>/dev/null
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

  if (( ZSH_FOLDER_HISTORY_AUTO_BIND )); then
    (( ZSH_FOLDER_HISTORY_AUTO_BIND_FOLDER )) && zfh_bindkey "$ZSH_FOLDER_HISTORY_BINDKEY"
    (( ZSH_FOLDER_HISTORY_AUTO_BIND_COMMAND )) && zfh_bind_command_key "$ZSH_FOLDER_HISTORY_COMMAND_BINDKEY"
  fi
fi
