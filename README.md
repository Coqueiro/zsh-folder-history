# zsh-folder-history

Standalone zsh folder picker with `fzf` previews of commands used in each folder during the current shell session.

## Goals

- no hard dependency on `dirhistory`
- no prompt/plugin-specific coupling
- callable as a normal command first
- keybinding/widget can be added later

## Current behavior

- Tracks visited directories with native zsh hooks.
- Persists directory history across shell sessions.
- Tracks commands per directory only for the current shell session.
- Commands are shown as recent unique commands, not a full shell history.
- Opens an `fzf` picker and `cd`s into the selected directory.
- Shows session commands for the highlighted directory in the preview pane.

## Requirements

- zsh
- `fzf`

## Install

Clone the repo and source the plugin file from your zsh config:

```zsh
source ~/Github/zsh-folder-history/zsh-folder-history.plugin.zsh
```

No keybinding is installed yet. No aliases are installed by default either.

## Usage

Quick test without touching `~/.zshrc`:

```zsh
~/Github/zsh-folder-history/bin/zfh
~/Github/zsh-folder-history/bin/zfh list
~/Github/zsh-folder-history/bin/zfh commands ~/Github
```

Notes for the wrapper:

- It sources the plugin and runs `zfh` in that shell process.
- It is good for `list`, `commands`, and basic picker testing.
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
- uses a separate state file: `~/.local/state/zsh-folder-history-test/directories`

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
zfh bindkey '^H'
```

### Commands

- `zfh` or `zfh pick [query]`: open picker and `cd` to selection
- `zfh list`: print tracked directories
- `zfh commands [dir]`: print current-session commands recorded for a directory
- `zfh bindkey [key]`: register the zle widget and bind a key (default: `^H`)
- `zfh help`: print help

If you also want aliases:

```zsh
export ZSH_FOLDER_HISTORY_ENABLE_ALIASES=1
source ~/Github/zsh-folder-history/zsh-folder-history.plugin.zsh
```

## Configuration

Set variables before sourcing the plugin:

```zsh
export ZSH_FOLDER_HISTORY_FILE="$HOME/.local/state/zsh-folder-history/directories"
export ZSH_FOLDER_HISTORY_MAX_DIRS=500
export ZSH_FOLDER_HISTORY_MAX_COMMANDS=50
export ZSH_FOLDER_HISTORY_ENABLE_ALIASES=1
```

Defaults:

- `ZSH_FOLDER_HISTORY_FILE`: `${XDG_STATE_HOME:-$HOME/.local/state}/zsh-folder-history/directories`
- `ZSH_FOLDER_HISTORY_MAX_DIRS`: `500`
- `ZSH_FOLDER_HISTORY_MAX_COMMANDS`: `50`
- `ZSH_FOLDER_HISTORY_ENABLE_ALIASES`: `0`

## Roadmap

- add an optional zle widget + keybinding helper
- improve picker actions beyond plain `cd`
- add automated tests
