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
cat "$FAKE_FZF_OUTPUT_FILE"
EOF
chmod +x "$FAKE_BIN/fzf"

export HOME="$TEST_DIR/home"
export XDG_STATE_HOME="$TEST_DIR/state"
export ZSH_FOLDER_HISTORY_FILE="$XDG_STATE_HOME/zfh/directories"
export ZSH_FOLDER_HISTORY_COMMANDS_FILE="$XDG_STATE_HOME/zfh/commands.tsv"
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
[[ -f $ZSH_FOLDER_HISTORY_COMMANDS_FILE ]] || exit 12
[[ "$(bindkey '^H')" == *'zfh_widget'* ]] || exit 15
[[ "$(bindkey '^K')" == *'zfh_command_widget'* ]] || exit 16
EOF

test_exit_code=$?
[[ $test_exit_code -eq 0 ]] || fail "interactive plugin smoke test failed with status $test_exit_code"

[[ -f $ZSH_FOLDER_HISTORY_FILE ]] || fail 'directory state file not created'
[[ -f $ZSH_FOLDER_HISTORY_COMMANDS_FILE ]] || fail 'command state file not created'

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

raw_file=$(<"$ZSH_FOLDER_HISTORY_COMMANDS_FILE")
assert_contains "$raw_file" $'echo hello' 'commands file should contain first command'
assert_contains "$raw_file" $'echo world' 'commands file should contain second command'

line_count_before=$(wc -l < "$ZSH_FOLDER_HISTORY_COMMANDS_FILE" | tr -d ' ')
[[ "$line_count_before" -ge 2 ]] || fail 'append-only commands file should contain appended records'

reloaded_output=$(zsh -f <<'EOF'
source "$ZFH_PLUGIN_FILE"
print -r -- "$(zfh commands "$TEST_WORKDIR")"
EOF
)
assert_contains "$reloaded_output" 'echo hello' 'reloaded commands should include first command'
assert_contains "$reloaded_output" 'echo world' 'reloaded commands should include second command'

line_count_after=$(wc -l < "$ZSH_FOLDER_HISTORY_COMMANDS_FILE" | tr -d ' ')
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
