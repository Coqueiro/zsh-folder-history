# zsh-folder-history

[![Tests](https://github.com/Coqueiro/zsh-folder-history/actions/workflows/test.yml/badge.svg)](https://github.com/Coqueiro/zsh-folder-history/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Track the directories you visit and the commands you run there, then jump back with `fzf`.

## What it does

- Records visited directories across shell sessions.
- Records commands per directory across shell sessions.
- Opens a folder picker with `Ctrl-H` by default.
- Opens a command picker with `Alt-J` by default.
- Lets you open command search for the highlighted folder from inside the folder picker.

## Requirements

- `zsh`
- `fzf`

## Installation

### Plain zsh

Source the plugin from your `~/.zshrc`:

```zsh
source /path/to/zsh-folder-history/zsh-folder-history.plugin.zsh
```

### Oh My Zsh

Clone into your custom plugins directory and add it to `plugins=(...)`:

```zsh
git clone https://github.com/Coqueiro/zsh-folder-history.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-folder-history
# then add zsh-folder-history to your existing plugins list, for example:
plugins=(git zsh-folder-history)
```

## Quick start

Default bindings:

- `Ctrl-H`: folder picker
- `Alt-J`: command picker
- inside folder picker, `Alt-J`: command picker for the highlighted directory

If you already have a command in the prompt, `Ctrl-H` changes directory and keeps your command line intact.

Commands:

```zsh
zfh
zfh list
zfh commands
zfh command-pick
zfh help
```

If you want to test the wrapper from the repo checkout:

```zsh
./bin/zfh
./bin/zfh list
./bin/zfh commands "$HOME"
```

The wrapper is useful for quick testing, but it cannot change the parent shell directory.

## Configuration

Defaults:

| Variable | Default | Purpose |
| --- | --- | --- |
| `ZSH_FOLDER_HISTORY_FILE` | `${XDG_STATE_HOME:-$HOME/.local/state}/zsh-folder-history/directories` | persisted directory history |
| `ZSH_FOLDER_HISTORY_COMMANDS_DIR` | `${ZSH_FOLDER_HISTORY_FILE:h}/commands` | per-directory command history files |
| `ZSH_FOLDER_HISTORY_MAX_DIRS` | `500` | max tracked directories |
| `ZSH_FOLDER_HISTORY_MAX_COMMANDS_PER_DIR` | `1000` | max commands kept per directory |
| `ZSH_FOLDER_HISTORY_AUTO_BIND` | `1` | enable default widget binding on load |
| `ZSH_FOLDER_HISTORY_AUTO_BIND_FOLDER` | `1` | enable automatic folder-picker binding |
| `ZSH_FOLDER_HISTORY_AUTO_BIND_COMMAND` | `1` | enable automatic command-picker binding |
| `ZSH_FOLDER_HISTORY_BINDKEY` | `^H` | folder picker key |
| `ZSH_FOLDER_HISTORY_COMMAND_BINDKEY` | `^[j` | command picker key |
| `ZSH_FOLDER_HISTORY_ENABLE_FZF_COMMAND_PICK` | `1` | enable command search inside folder picker |
| `ZSH_FOLDER_HISTORY_FZF_OPEN_COMMANDS_KEY` | `alt-j` | key used inside folder picker to open command search |
| `ZSH_FOLDER_HISTORY_ENABLE_ALIASES` | `0` | enable aliases like `folder-history` |

> **Note:** `Ctrl-H` (`^H`) is also the Backspace key in many terminals. If this conflicts with your setup, change the binding with `ZSH_FOLDER_HISTORY_BINDKEY`.

Common tweaks:

```zsh
# Change the folder picker key
export ZSH_FOLDER_HISTORY_BINDKEY='^G'

# Disable automatic bindings
export ZSH_FOLDER_HISTORY_AUTO_BIND=0

# Use a custom state location
export ZSH_FOLDER_HISTORY_FILE="$HOME/.local/state/my-zfh/directories"
export ZSH_FOLDER_HISTORY_COMMANDS_DIR="$HOME/.local/state/my-zfh/commands"
```

## How it works

- Directory history is recorded as you move around and persisted across shell sessions.
- Commands are stored per directory and trimmed to the configured limit for that directory.
- Previews are generated on demand so the picker opens quickly.

## Tests

```zsh
zsh -n zsh-folder-history.plugin.zsh
zsh tests/run.zsh
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT.
