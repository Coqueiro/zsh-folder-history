#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_DIR=${SCRIPT_DIR:h}
PLUGIN_FILE="$REPO_DIR/zsh-folder-history.plugin.zsh"

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

export HOME="$TEST_DIR/home"
export XDG_STATE_HOME="$TEST_DIR/state"
export ZSH_FOLDER_HISTORY_FILE="$XDG_STATE_HOME/zfh/directories"
export ZSH_FOLDER_HISTORY_COMMANDS_FILE="$XDG_STATE_HOME/zfh/commands.tsv"
export ZSH_FOLDER_HISTORY_AUTO_BIND=1
export ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK=1

setopt interactivecomments
_zfh_test_zdotdir="$TEST_DIR/zdotdir"
mkdir -p "$_zfh_test_zdotdir"
export ZDOTDIR="$_zfh_test_zdotdir"

print -r -- "source $PLUGIN_FILE" >| "$ZDOTDIR/.zshrc"

zsh -fi <<'EOF'
[[ -f $ZSH_FOLDER_HISTORY_FILE ]] || exit 11
[[ -f $ZSH_FOLDER_HISTORY_COMMANDS_FILE ]] || exit 12
[[ "$(bindkey '^H')" == *'zfh_widget'* ]] || exit 15
[[ "$(bindkey '^K')" == *'zfh_command_widget'* ]] || exit 16
_zfh_record_command "$PWD" 'echo hello'
_zfh_record_command "$PWD" 'echo world'
commands_output=$(zfh commands "$PWD")
[[ "$commands_output" == *'echo hello'* ]] || exit 13
[[ "$commands_output" == *'echo world'* ]] || exit 14
EOF

status=$?
[[ $status -eq 0 ]] || fail "interactive plugin smoke test failed with status $status"

[[ -f $ZSH_FOLDER_HISTORY_FILE ]] || fail 'directory state file not created'
[[ -f $ZSH_FOLDER_HISTORY_COMMANDS_FILE ]] || fail 'command state file not created'

raw_file=$(<"$ZSH_FOLDER_HISTORY_COMMANDS_FILE")
assert_contains "$raw_file" $'echo hello' 'commands file should contain first command'
assert_contains "$raw_file" $'echo world' 'commands file should contain second command'

reloaded_output=$(zsh -fi <<'EOF'
print -r -- "$(zfh commands "$PWD")"
EOF
)
assert_contains "$reloaded_output" 'echo hello' 'reloaded commands should include first command'
assert_contains "$reloaded_output" 'echo world' 'reloaded commands should include second command'
