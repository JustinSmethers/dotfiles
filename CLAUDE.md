# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a dotfiles repository for shell and development environment configuration. The setup is designed for cross-platform use (macOS and Linux) and includes configurations for bash, zsh, tmux, Neovim, and oh-my-posh prompt customization.

**Platform Support:**
- ✅ macOS (bash and zsh)
- ✅ Linux (bash and zsh)
- ✅ Windows via WSL (Windows Subsystem for Linux required)

## Setup and Installation

### Initial Setup

```bash
# Run the setup script (includes preview mode by default)
./setup.sh

# Dry run mode (preview only, no changes)
./setup.sh --dry-run

# Skip preview and install immediately
./setup.sh --no-preview

# Force overwrite existing configurations
./setup.sh --force
```

The setup script:
- Detects OS (macOS/Linux) and configures appropriate package manager
- Detects user's default shell (bash or zsh)
- Installs required packages (git, curl, wget, tmux, neovim, unzip)
- Creates backups of existing configs in `~/dotfiles_backup` with timestamps
- Configures **both bash and zsh** (allowing you to switch shells freely)
- Sets up symlinks to dotfiles from home directory
- Installs oh-my-posh for shell prompt customization
- Installs tmux plugin manager (TPM)
- Sets up kickstart.nvim as the Neovim configuration

### System Requirements

Required packages are automatically installed by setup.sh:
- git
- curl/wget
- tmux
- neovim
- unzip

## Repository Structure

### Core Configuration Files

- **`.bashrc`** — Bash-specific configuration that sources `.shell_common`
- **`.zshrc`** — Zsh-specific configuration that sources `.shell_common`
- **`.shell_common`** — Shared shell configuration (used by both bash and zsh) containing:
  - Aliases (`ll`, `la`, `vim` → `nvim`, `python` → `python3`, etc.)
  - Python virtual environment shortcuts (`s`, `d`)
  - nvm (Node Version Manager) configuration
  - dbt profiles directory configuration
  - Local bin PATH addition
- **`.tmux.conf`** — Tmux configuration with:
  - Prefix remapped from `Ctrl-b` to `Ctrl-a`
  - Mouse mode enabled with scroll wheel support
  - Vi-style copy mode keybindings
  - Clipboard integration using `pbcopy`

### Oh-My-Posh Theme

- **`.poshthemes/pure_python_custom.omp.json`** — Custom oh-my-posh theme with:
  - Username and path display
  - Git status indicators (ahead/behind, working/staging changes, stash count)
  - Python version and virtual environment display
  - Hatch environment indicator
  - Command execution time tracking
  - Custom prompt symbol (❯) that turns red on error

### Neovim Configuration

- **`.config/nvim/`** — Currently empty; setup script clones kickstart.nvim here
- The setup script removes any existing nvim config and installs kickstart.nvim from https://github.com/nvim-lua/kickstart.nvim

### Utility Scripts

- **`bin/wt`** — Git worktree manager for feature branch workflows
  - Creates worktrees under `<repo_root>/wt/<branch>`
  - Automatically handles upstream branch setup
  - Usage: `wt feature/branch-name` or `wt -n draft/branch` (no push)
  - Supports `WT_BASE` env var to override base branch (default: `origin/main`)

## Platform-Specific Notes

### macOS
- Uses Homebrew as package manager
- **Default shell is zsh** (since macOS Catalina 10.15 in 2019)
- oh-my-posh installed via `brew install jandedobbeleer/oh-my-posh/oh-my-posh`
- Neovim installed/upgraded via Homebrew
- Both bash and zsh configurations are set up automatically

### Linux
- Supports apt (Debian/Ubuntu) and dnf (Fedora/RHEL) package managers
- oh-my-posh installed via curl script to `/usr/local/bin`
- Neovim built from source (stable branch) for latest version
- Both bash and zsh configurations are set up automatically

### Windows
- **WSL (Windows Subsystem for Linux) is required**
- Once in WSL, the setup works the same as Linux
- Not supported on native Windows (PowerShell/CMD)

## Important Setup Behaviors

1. **Backup Strategy**: All existing configs are backed up with timestamps to `~/dotfiles_backup` before being replaced
2. **Symlink Management**: The setup creates symlinks from home directory to dotfiles directory, enabling version control of configs
3. **Dual Shell Support**: The setup configures **both bash and zsh** automatically:
   - Appends to existing `.bashrc` and `.zshrc` rather than replacing them
   - Adds source lines for `~/dotfiles/.bashrc` and `~/dotfiles/.zshrc`
   - Configures oh-my-posh for both shells (with shell-specific init commands)
   - Adds tmux auto-launch to both shells (if not already in tmux)
   - Allows switching between bash and zsh without reconfiguring
4. **Idempotency**: Running setup multiple times is safe; it checks for existing installations and configurations
5. **Shell Detection**: Setup automatically detects your default shell and reports it during installation

## Development Workflow Tools

### Python Development
- Virtual environment activation: `s` (activates `.venv`)
- Deactivation: `d`
- Python/pip aliased to python3/pip3
- dbt profiles configured in `~/.dbt`

### Node.js Development
- nvm (Node Version Manager) automatically loaded in shell

### Git Worktrees
- Use `bin/wt` to manage feature branch worktrees
- All worktrees organized under `wt/` in repo root
- Automatic upstream setup and branch pushing (unless `-n` flag used)
