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
- Opens an `fzf` picker and `cd`s into the selected directory.
- Shows session commands for the highlighted directory in the preview pane.
- Lets you open a second `fzf` picker to search commands inside the highlighted directory.

## Requirements

- zsh
- `fzf`

## Install

Clone the repo and source the plugin file from your zsh config:

```zsh
source ~/Github/zsh-folder-history/zsh-folder-history.plugin.zsh
```

No aliases are installed by default. Keybinding setup is optional.

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

For live testing with hooks + Ctrl-H, a temporary file was also created:

```zsh
source ~/.zshrc.zfh
```

That test file:

- sources the plugin into your current interactive shell
- enables the optional aliases
- binds `Ctrl-H` to the picker via `zfh bindkey '^H'`
- binds `Ctrl-K` to the command picker via `zfh bind-command-key '^K'`
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

Inside the folder picker, press the key from `ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY` (default: `ctrl-k`) to open the command picker for the highlighted directory.

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
export ZSH_FOLDER_HISTORY_BINDKEY='^H'
export ZSH_FOLDER_HISTORY_COMMAND_BINDKEY='^K'
export ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY='ctrl-k'
```

Defaults:

- `ZSH_FOLDER_HISTORY_FILE`: `${XDG_STATE_HOME:-$HOME/.local/state}/zsh-folder-history/directories`
- `ZSH_FOLDER_HISTORY_COMMANDS_FILE`: `${ZSH_FOLDER_HISTORY_FILE:h}/commands.tsv`
- `ZSH_FOLDER_HISTORY_MAX_DIRS`: `500`
- `ZSH_FOLDER_HISTORY_MAX_COMMANDS`: `1000`
- `ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR`: `1000`
- `ZSH_FOLDER_HISTORY_ENABLE_ALIASES`: `0`
- `ZSH_FOLDER_HISTORY_BINDKEY`: `^H`
- `ZSH_FOLDER_HISTORY_COMMAND_BINDKEY`: `^K`
- `ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY`: `ctrl-k`

## Roadmap

- improve picker actions beyond plain `cd`
- add automated tests
