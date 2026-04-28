# zsh-folder-history

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Standalone zsh folder history with an `fzf` picker and per-directory command previews.

## Features

- Tracks visited directories with native zsh hooks.
- Persists directory history and timestamped per-directory command history across sessions.
- Opens a folder picker with `Ctrl-H` by default.
- Opens a command picker with `Ctrl-K` by default.
- Inside the folder picker, `Ctrl-K` opens the command picker for the highlighted directory.
- Uses XDG-friendly state files by default.

## Requirements

- zsh
- `fzf`

## Installation

### Plain zsh

Clone the repo and source the plugin from your `~/.zshrc`:

```zsh
source /path/to/zsh-folder-history/zsh-folder-history.plugin.zsh
```

### Oh My Zsh

```zsh
git clone https://github.com/Coqueiro/zsh-folder-history.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-folder-history
source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-folder-history/zsh-folder-history.plugin.zsh
```

The plugin uses a standard `*.plugin.zsh` layout, so other zsh plugin managers may also work, but the plain zsh and Oh My Zsh installs above are the only documented paths for now.

## Quick start

Once sourced, the default bindings are:

- `Ctrl-H`: folder picker
- `Ctrl-K`: command picker
- inside folder picker, `Ctrl-K`: command picker for the highlighted directory

Main commands:

```zsh
zfh
zfh list
zfh commands
zfh command-pick
```

If you want to try the wrapper from the repo checkout:

```zsh
./bin/zfh
./bin/zfh list
./bin/zfh commands "$HOME"
```

Notes for the wrapper:

- it sources the plugin and runs `zfh` in that shell process
- it is useful for `list`, `commands`, and `command-pick`
- because it runs in a child process, it cannot change the parent shell directory

## Configuration

Set variables before sourcing the plugin:

```zsh
export ZSH_FOLDER_HISTORY_FILE="$HOME/.local/state/zsh-folder-history/directories"
export ZSH_FOLDER_HISTORY_COMMANDS_FILE="$HOME/.local/state/zsh-folder-history/commands.tsv"
export ZSH_FOLDER_HISTORY_MAX_DIRS=500
export ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR=1000
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
- `ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR`: max persisted commands per directory
- `ZSH_FOLDER_HISTORY_AUTO_BIND`: enable or disable default widget binding on load
- `ZSH_FOLDER_HISTORY_AUTO_BIND_FOLDER`: enable or disable automatic folder-widget binding
- `ZSH_FOLDER_HISTORY_AUTO_BIND_COMMAND`: enable or disable automatic command-widget binding
- `ZSH_FOLDER_HISTORY_BINDKEY`: key for folder picker binding
- `ZSH_FOLDER_HISTORY_COMMAND_BINDKEY`: key for command picker binding
- `ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK`: enable or disable command search from inside folder picker
- `ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY`: key used inside folder picker to open command search
- `ZSH_FOLDER_HISTORY_ENABLE_ALIASES`: enable or disable aliases like `folder-history`

Defaults:

- `ZSH_FOLDER_HISTORY_FILE`: `${XDG_STATE_HOME:-$HOME/.local/state}/zsh-folder-history/directories`
- `ZSH_FOLDER_HISTORY_COMMANDS_FILE`: `${ZSH_FOLDER_HISTORY_FILE:h}/commands.tsv`
- `ZSH_FOLDER_HISTORY_MAX_DIRS`: `500`
- `ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR`: `1000`
- `ZSH_FOLDER_HISTORY_AUTO_BIND`: `1`
- `ZSH_FOLDER_HISTORY_AUTO_BIND_FOLDER`: `1`
- `ZSH_FOLDER_HISTORY_AUTO_BIND_COMMAND`: `1`
- `ZSH_FOLDER_HISTORY_ENABLE_ALIASES`: `0`
- `ZSH_FOLDER_HISTORY_BINDKEY`: `^H`
- `ZSH_FOLDER_HISTORY_COMMAND_BINDKEY`: `^K`
- `ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK`: `1`
- `ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY`: `ctrl-k`

## How it works

- Directory history is appended on navigation and compacted when `zfh` folder-history commands run.
- Command history is appended on execution and trimmed only for the requested directory.
- Command previews are generated lazily so the picker opens faster.

## Tests

```zsh
zsh -n zsh-folder-history.plugin.zsh
zsh tests/run.zsh
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT.
