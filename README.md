# zsh-folder-history

Standalone zsh folder picker with `fzf` previews of commands used in each folder.

## Goals

- no hard dependency on `dirhistory`
- no prompt/plugin-specific coupling
- callable as a normal command first
- keybinding/widget can be added later

## Current behavior

- Tracks visited directories with native zsh hooks.
- Persists directory history across shell sessions.
- Persists timestamped commands per directory across shell sessions.
- Commands keep the most recent entries per directory.
- Command writes are append-only during command execution; compaction happens on shell load.
- Opens an `fzf` picker and `cd`s into the selected directory.
- Shows session commands for the highlighted directory in the preview pane.
- Lets you open a second `fzf` picker to search commands inside the highlighted directory.

## Requirements

- zsh
- `fzf`

## Install

### Plain zsh

Clone the repo and source the plugin file from your zsh config:

```zsh
source /path/to/zsh-folder-history/zsh-folder-history.plugin.zsh
```

### Oh My Zsh

Clone into your custom plugins directory:

```zsh
git clone https://github.com/<you>/zsh-folder-history.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-folder-history
```

Then source it from `~/.zshrc` or add it through your plugin bootstrap:

```zsh
source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-folder-history/zsh-folder-history.plugin.zsh
```

### Antidote

Add the repo to your bundle file, then load as usual:

```txt
<you>/zsh-folder-history
```

### Antigen

```zsh
antigen bundle <you>/zsh-folder-history
```

### Zinit

```zsh
zinit light <you>/zsh-folder-history
```

### Zplug

```zsh
zplug "<you>/zsh-folder-history"
```

Aliases are still opt-in. The default shell bindings are enabled on load:

- `Ctrl-H`: folder picker
- `Ctrl-K`: command picker
- inside folder picker, `Ctrl-K`: command picker for the highlighted directory

To disable default binding setup:

```zsh
export ZSH_FOLDER_HISTORY_AUTO_BIND=0
```

## Usage

Quick test without touching `~/.zshrc`:

```zsh
~/Github/zsh-folder-history/bin/zfh
~/Github/zsh-folder-history/bin/zfh list
~/Github/zsh-folder-history/bin/zfh commands ~/Github
~/Github/zsh-folder-history/bin/zfh command-pick ~/Github
```

Notes for the wrapper:

- It sources the plugin and runs `zfh` in that shell process.
- It is good for `list`, `commands`, and basic picker testing.
- It is also good for `command-pick`, because that command prints the selected command.
- Because it runs as a standalone process, any `cd` done there cannot change your parent shell directory.

For real shell integration later, source the plugin from `~/.zshrc` and call `zfh` from the interactive shell.

For live testing with hooks + Ctrl-H/Ctrl-K, a temporary file was also created:

```zsh
source ~/.zshrc.zfh
```

That test file:

- sources the plugin into your current interactive shell
- enables the optional aliases
- enables auto-bind for both widgets
- uses a separate state file: `~/.local/state/zsh-folder-history-test/directories`
- uses a separate commands file: `~/.local/state/zsh-folder-history-test/commands.tsv`

To remove the hooks from the current shell session after testing:

```zsh
zfh_unload
```

Once sourced, usage is:

```zsh
zfh
zfh list
zfh commands
zfh commands ~/Github
zfh command-pick ~/Github
zfh bindkey '^H'
zfh bind-command-key '^K'
```

### Commands

- `zfh` or `zfh pick [query]`: open picker and `cd` to selection
- `zfh list`: print tracked directories
- `zfh commands [dir]`: print persisted timestamped commands for a directory
- `zfh command-pick [dir] [query]`: search commands for one directory and print the selected command
- `zfh bindkey [key]`: register the zle widget and bind a key (default: `^H`)
- `zfh bind-command-key [key]`: register the command picker widget and bind a key (default: `^K`)
- `zfh help`: print help

Shortcut summary:

- `Ctrl-H`: open folder picker
- `Ctrl-K`: open command picker directly
- with `ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK=1`, inside folder picker `Ctrl-K`: open command picker for highlighted directory

Run `zfh --help` to see the same instructions from the shell.

Inside the command picker, the main list shows timestamp + truncated command line, and the preview shows the full command.

If you also want aliases:

```zsh
export ZSH_FOLDER_HISTORY_ENABLE_ALIASES=1
source ~/Github/zsh-folder-history/zsh-folder-history.plugin.zsh
```

## Configuration

Set variables before sourcing the plugin:

```zsh
export ZSH_FOLDER_HISTORY_FILE="$HOME/.local/state/zsh-folder-history/directories"
export ZSH_FOLDER_HISTORY_COMMANDS_FILE="$HOME/.local/state/zsh-folder-history/commands.tsv"
export ZSH_FOLDER_HISTORY_MAX_DIRS=500
export ZSH_FOLDER_HISTORY_MAX_COMMANDS=1000
export ZSH_FOLDER_HISTORY_ENABLE_ALIASES=1
export ZSH_FOLDER_HISTORY_AUTO_BIND=1
export ZSH_FOLDER_HISTORY_AUTO_BIND_FOLDER=1
export ZSH_FOLDER_HISTORY_AUTO_BIND_COMMAND=1
export ZSH_FOLDER_HISTORY_BINDKEY='^H'
export ZSH_FOLDER_HISTORY_COMMAND_BINDKEY='^K'
export ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK=1
export ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY='ctrl-k'
```

### Environment variables

- `ZSH_FOLDER_HISTORY_FILE`: path for persisted directory history
- `ZSH_FOLDER_HISTORY_COMMANDS_FILE`: path for persisted command history
- `ZSH_FOLDER_HISTORY_MAX_DIRS`: max persisted directories
- `ZSH_FOLDER_HISTORY_MAX_COMMANDS`: base max command-history size
- `ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR`: max persisted commands per directory
- `ZSH_FOLDER_HISTORY_AUTO_BIND`: enable/disable default widget binding on load
- `ZSH_FOLDER_HISTORY_AUTO_BIND_FOLDER`: enable/disable automatic folder-widget binding
- `ZSH_FOLDER_HISTORY_AUTO_BIND_COMMAND`: enable/disable automatic command-widget binding
- `ZSH_FOLDER_HISTORY_COMPACT_ON_LOAD`: compact persisted command history when the plugin loads
- `ZSH_FOLDER_HISTORY_BINDKEY`: key for folder picker binding
- `ZSH_FOLDER_HISTORY_COMMAND_BINDKEY`: key for command picker binding
- `ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK`: enable/disable command search from inside folder picker
- `ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY`: key used inside folder picker to open command search
- `ZSH_FOLDER_HISTORY_ENABLE_ALIASES`: enable/disable aliases like `folder-history`

Defaults:

- `ZSH_FOLDER_HISTORY_FILE`: `${XDG_STATE_HOME:-$HOME/.local/state}/zsh-folder-history/directories`
- `ZSH_FOLDER_HISTORY_COMMANDS_FILE`: `${ZSH_FOLDER_HISTORY_FILE:h}/commands.tsv`
- `ZSH_FOLDER_HISTORY_MAX_DIRS`: `500`
- `ZSH_FOLDER_HISTORY_MAX_COMMANDS`: `1000`
- `ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR`: `1000`
- `ZSH_FOLDER_HISTORY_COMPACT_ON_LOAD`: `1`
- `ZSH_FOLDER_HISTORY_AUTO_BIND`: `1`
- `ZSH_FOLDER_HISTORY_AUTO_BIND_FOLDER`: `1`
- `ZSH_FOLDER_HISTORY_AUTO_BIND_COMMAND`: `1`
- `ZSH_FOLDER_HISTORY_ENABLE_ALIASES`: `0`
- `ZSH_FOLDER_HISTORY_BINDKEY`: `^H`
- `ZSH_FOLDER_HISTORY_COMMAND_BINDKEY`: `^K`
- `ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK`: `1`
- `ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY`: `ctrl-k`

## Tests

Run the lightweight zsh test suite:

```zsh
zsh tests/run.zsh
```

## Roadmap

- improve picker actions beyond plain `cd`
- add automated tests
