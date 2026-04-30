#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_DIR=${SCRIPT_DIR:h}
PLUGIN_FILE="$REPO_DIR/zsh-folder-history.plugin.zsh"
export ZFH_PLUGIN_FILE="$PLUGIN_FILE"

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

assert_eq() {
  local expected=$1
  local actual=$2
  local message=$3
  [[ "$expected" == "$actual" ]] || fail "$message (expected: $expected, got: $actual)"
}

assert_contains() {
  local haystack=$1
  local needle=$2
  local message=$3
  [[ "$haystack" == *"$needle"* ]] || fail "$message (missing: $needle)"
}

TEST_DIR="$ZFH_TEST_ROOT/plugin"
mkdir -p "$TEST_DIR/state" "$TEST_DIR/home"

FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"
cat >| "$FAKE_BIN/fzf" <<'EOF'
#!/bin/sh
if [ -n "$FAKE_FZF_LOG_FILE" ]; then
  printf '%s\n' "$*" >> "$FAKE_FZF_LOG_FILE"
fi

if [ -n "$FAKE_FZF_OUTPUTS_DIR" ]; then
  counter_file="$FAKE_FZF_OUTPUTS_DIR/.counter"
  if [ -f "$counter_file" ]; then
    count=$(cat "$counter_file")
  else
    count=0
  fi
  count=$((count + 1))
  printf '%s' "$count" > "$counter_file"

  out_file="$FAKE_FZF_OUTPUTS_DIR/$count.out"
  rc_file="$FAKE_FZF_OUTPUTS_DIR/$count.rc"

  [ -f "$out_file" ] && cat "$out_file"
  if [ -f "$rc_file" ]; then
    exit "$(cat "$rc_file")"
  fi
  exit 0
fi

cat "$FAKE_FZF_OUTPUT_FILE"
EOF
chmod +x "$FAKE_BIN/fzf"

export HOME="$TEST_DIR/home"
export XDG_STATE_HOME="$TEST_DIR/state"
export ZSH_FOLDER_HISTORY_FILE="$XDG_STATE_HOME/zfh/directories"
export ZSH_FOLDER_HISTORY_COMMANDS_DIR="$XDG_STATE_HOME/zfh/commands"
export ZSH_FOLDER_HISTORY_AUTO_BIND=1
export ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK=1
export ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR=2
export PATH="$FAKE_BIN:$PATH"

TEST_WORKDIR="$TEST_DIR/work"
mkdir -p "$TEST_WORKDIR"
export TEST_WORKDIR

setopt interactivecomments

zsh -fi <<'EOF'
source "$ZFH_PLUGIN_FILE"
[[ -f $ZSH_FOLDER_HISTORY_FILE ]] || exit 11
[[ -d $ZSH_FOLDER_HISTORY_COMMANDS_DIR ]] || exit 12
[[ "$(bindkey '^H')" == *'zfh_widget'* ]] || exit 15
[[ "$(bindkey '^[j')" == *'zfh_command_widget'* ]] || exit 16
EOF

test_exit_code=$?
[[ $test_exit_code -eq 0 ]] || fail "interactive plugin smoke test failed with status $test_exit_code"

[[ -f $ZSH_FOLDER_HISTORY_FILE ]] || fail 'directory state file not created'
[[ -d $ZSH_FOLDER_HISTORY_COMMANDS_DIR ]] || fail 'command state directory not created'

dir_a="$TEST_DIR/dir-a"
dir_b="$TEST_DIR/dir-b"
mkdir -p "$dir_a" "$dir_b"
dir_a="${dir_a:A}"
dir_b="${dir_b:A}"
printf '%s\n%s\n%s\n' "$dir_a" "$dir_b" "$dir_a" >| "$ZSH_FOLDER_HISTORY_FILE"

zsh -f <<'EOF'
source "$ZFH_PLUGIN_FILE"
zfh list >/dev/null
EOF

dir_file_after=$(<"$ZSH_FOLDER_HISTORY_FILE")
dir_line_count_after=$(wc -l < "$ZSH_FOLDER_HISTORY_FILE" | tr -d ' ')
assert_eq "2" "$dir_line_count_after" 'directory history compaction should keep unique directories only'
assert_contains "$dir_file_after" "$dir_a" 'directory history should keep first directory after compaction'
assert_contains "$dir_file_after" "$dir_b" 'directory history should keep second directory after compaction'

zsh -f <<'EOF'
source "$ZFH_PLUGIN_FILE"
_zfh_record_command "$TEST_WORKDIR" 'echo hello'
_zfh_record_command "$TEST_WORKDIR" 'echo world'
EOF

command_file=$(zsh -f <<'EOF'
source "$ZFH_PLUGIN_FILE"
_zfh_command_file_for_dir "$TEST_WORKDIR"
print -r -- "$REPLY"
EOF
)

[[ -f "$command_file" ]] || fail 'per-dir command file should exist for the target directory'

selected_dir="$TEST_DIR/selected dir"
mkdir -p "$selected_dir"
selected_dir="${selected_dir:A}"
export FAKE_FZF_OUTPUT_FILE="$TEST_DIR/fzf-output"
printf '\n%s\n' "$selected_dir" >| "$FAKE_FZF_OUTPUT_FILE"

pick_state=$(zsh -f <<'EOF'
source "$ZFH_PLUGIN_FILE"
cd "$HOME"
zfh_pick >/dev/null
print -r -- "PWD=$PWD"
print -r -- "DIR=$_zfh_last_selected_dir"
EOF
)

assert_contains "$pick_state" "PWD=$selected_dir" 'zfh_pick should cd into selected directory'
assert_contains "$pick_state" "DIR=$selected_dir" 'zfh_pick should record selected directory for widget flow'

widget_like_state=$(zsh -f <<'EOF'
source "$ZFH_PLUGIN_FILE"
cd "$HOME"
_zfh_widget_active=1
zfh_pick >/dev/null
print -r -- "PWD=$PWD"
print -r -- "DIR=$_zfh_last_selected_dir"
print -r -- "CMD=$_zfh_last_selected_command"
EOF
)

assert_contains "$widget_like_state" "PWD=$selected_dir" 'widget-like folder picks should still change directory'
assert_contains "$widget_like_state" "DIR=$selected_dir" 'widget-like folder picks should keep selected directory'
assert_contains "$widget_like_state" "CMD=" 'widget-like folder picks should not inject a command when selecting a folder'

widget_buffer_state=$(zsh -fi <<'EOF'
source "$ZFH_PLUGIN_FILE"
BUFFER='ls ~'
CURSOR=3
LBUFFER=${BUFFER[1,CURSOR]}
RBUFFER=${BUFFER[CURSOR+1,-1]}

zle() {
  case "$1" in
    (-I)
      return 0
      ;;
    (accept-line)
      BUFFER=''
      CURSOR=0
      _zfh_restore_pending_buffer
      return 0
      ;;
    (reset-prompt)
      return 0
      ;;
    (*)
      return 0
      ;;
  esac
}

cd "$HOME"
zfh_widget
print -r -- "PWD=$PWD"
print -r -- "BUFFER=$BUFFER"
print -r -- "CURSOR=$CURSOR"
print -r -- "STACK=$(fc -ln -1)"
EOF
)

assert_contains "$widget_buffer_state" "PWD=$selected_dir" 'zfh_widget should still change directory when buffer is non-empty'
assert_contains "$widget_buffer_state" 'BUFFER=ls ~' 'zfh_widget should restore the original buffer text'
assert_contains "$widget_buffer_state" 'CURSOR=3' 'zfh_widget should restore the original cursor position'

restore_dir_a="$TEST_DIR/restore-a"
restore_dir_b="$TEST_DIR/restore-b"
restore_dir_c="$TEST_DIR/restore-c"
mkdir -p "$restore_dir_a" "$restore_dir_b" "$restore_dir_c"
restore_dir_a="${restore_dir_a:A}"
restore_dir_b="${restore_dir_b:A}"
restore_dir_c="${restore_dir_c:A}"
export restore_dir_b
printf '%s\n%s\n%s\n' "$restore_dir_a" "$restore_dir_b" "$restore_dir_c" >| "$ZSH_FOLDER_HISTORY_FILE"

zsh -f <<'EOF'
source "$ZFH_PLUGIN_FILE"
_zfh_record_command "$restore_dir_b" 'echo restore'
EOF

export FAKE_FZF_OUTPUTS_DIR="$TEST_DIR/fzf-seq"
mkdir -p "$FAKE_FZF_OUTPUTS_DIR"
export FAKE_FZF_LOG_FILE="$TEST_DIR/fzf-seq.log"
: >| "$FAKE_FZF_LOG_FILE"

printf 'alt-j\n%s\n' "$restore_dir_b" >| "$FAKE_FZF_OUTPUTS_DIR/1.out"
printf '0' >| "$FAKE_FZF_OUTPUTS_DIR/1.rc"
: >| "$FAKE_FZF_OUTPUTS_DIR/2.out"
printf '130' >| "$FAKE_FZF_OUTPUTS_DIR/2.rc"
printf '%s\n' "$restore_dir_b" >| "$FAKE_FZF_OUTPUTS_DIR/3.out"
printf '0' >| "$FAKE_FZF_OUTPUTS_DIR/3.rc"

restore_state=$(zsh -f <<'EOF'
source "$ZFH_PLUGIN_FILE"
_zfh_refresh_dirs
cd "$HOME"
zfh_pick >/dev/null
print -r -- "PWD=$PWD"
EOF
)

assert_contains "$restore_state" "PWD=$restore_dir_b" 'Esc from command picker should return to folder picker and keep selection usable'

fzf_log=$(<"$FAKE_FZF_LOG_FILE")
assert_contains "$fzf_log" 'load:pos(3)' 'folder picker should reopen at the previous folder index after Esc from command picker'
assert_contains "$fzf_log" '.preview.zsh {}' 'folder picker preview should use generated minimal preview script'

unset FAKE_FZF_OUTPUTS_DIR
unset FAKE_FZF_LOG_FILE

raw_file=$(<"$command_file")
assert_contains "$raw_file" $'echo hello' 'per-dir commands file should contain first command'
assert_contains "$raw_file" $'echo world' 'per-dir commands file should contain second command'

line_count_before=$(wc -l < "$command_file" | tr -d ' ')
[[ "$line_count_before" -ge 2 ]] || fail 'append-only commands file should contain appended records'

reloaded_output=$(zsh -f <<'EOF'
source "$ZFH_PLUGIN_FILE"
print -r -- "$(zfh commands "$TEST_WORKDIR")"
EOF
)
assert_contains "$reloaded_output" 'echo hello' 'reloaded commands should include first command'
assert_contains "$reloaded_output" 'echo world' 'reloaded commands should include second command'

line_count_after=$(wc -l < "$command_file" | tr -d ' ')
assert_eq "$line_count_before" "$line_count_after" 'append-only command file should not be compacted'

zsh -f <<'EOF'
source "$ZFH_PLUGIN_FILE"
_zfh_record_command "$TEST_WORKDIR" 'echo third'
print -r -- "$(zfh commands "$TEST_WORKDIR")"
EOF

trimmed_output=$(zsh -f <<'EOF'
source "$ZFH_PLUGIN_FILE"
print -r -- "$(zfh commands "$TEST_WORKDIR")"
EOF
)
[[ "$trimmed_output" == *'echo third'* ]] || fail 'trimmed output should include newest command'
[[ "$trimmed_output" == *'echo world'* ]] || fail 'trimmed output should include second newest command'
[[ "$trimmed_output" != *'echo hello'* ]] || fail 'trimmed output should drop oldest command beyond per-dir cap'
