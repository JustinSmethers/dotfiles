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

# Dry run mode (preview only, no prompt, no changes)
./setup.sh --dry-run

# Skip preview and install immediately
./setup.sh --no-preview

# Force overwrite existing configurations
./setup.sh --force
```

The setup script:
- Detects OS (macOS/Linux) and configures appropriate package manager
- Detects user's default shell (bash or zsh)
- Installs required packages (git, curl, wget, tmux, neovim, stow, unzip)
- Creates backups of existing configs in `~/dotfiles_backup` with timestamps
- Configures **both bash and zsh** (allowing you to switch shells freely)
- Uses GNU Stow for fully managed links: tmux config, oh-my-posh theme, and helper scripts
- Installs oh-my-posh for shell prompt customization
- Installs tmux plugin manager (TPM)
- Sets up kickstart.nvim only when no Neovim config already exists

### System Requirements

Required packages are automatically installed by setup.sh:
- git
- curl/wget
- tmux
- neovim
- stow
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
- **`tmux/.tmux.conf`** — Tmux configuration stowed to `~/.tmux.conf` with:
  - Prefix remapped from `Ctrl-b` to `Ctrl-a`
  - Mouse mode enabled with scroll wheel support
  - Vi-style copy mode keybindings
  - macOS clipboard integration using `pbcopy` when available, with a tmux-buffer fallback elsewhere

### Oh-My-Posh Theme

- **`posh/.poshthemes/pure_python_custom.omp.json`** — Custom oh-my-posh theme stowed to `~/.poshthemes/pure_python_custom.omp.json` with:
  - Username and path display
  - Git status indicators (ahead/behind, working/staging changes, stash count)
  - Python version and virtual environment display
  - Hatch environment indicator
  - Command execution time tracking
  - Custom prompt symbol (❯) that turns red on error

### Neovim Configuration

- The setup script clones kickstart.nvim from https://github.com/nvim-lua/kickstart.nvim only when `~/.config/nvim` does not already exist

### Utility Scripts

- **`scripts/bin/wt`** — Git worktree manager stowed to `~/bin/wt`
  - Creates worktrees under `<repo_root>/wt/<branch>`
  - Automatically handles upstream branch setup
  - Usage: `wt feature/branch-name` or `wt -n draft/branch` (no push)
  - Supports `WT_BASE` env var to override base branch (default: `origin/main`)

### Daily Digest Tool

- **`daily-digest/`** — Portable Jira/GitHub/daily-note digest tool
  - Run setup from that directory with `claude "/daily-digest setup"`
  - Keep `daily-digest/config.toml` local-only; use `config.toml.example` as the tracked template
  - Keep generated files out of git: `daily-digest/launchd/*.plist`, `daily-digest/logs/`, `daily-digest/apply-jira.sh`, and `daily-digest/.claude/settings.local.json`
  - Do not wire this into root `setup.sh`; it performs interactive auth/config checks and writes machine-specific launchd/Claude settings

## Platform-Specific Notes

### macOS
- Uses Homebrew as package manager
- **Default shell is zsh** (since macOS Catalina 10.15 in 2019)
- oh-my-posh installed via `brew install jandedobbeleer/oh-my-posh/oh-my-posh`
- Neovim installed via Homebrew when missing
- Both bash and zsh configurations are set up automatically

### Linux
- Supports apt (Debian/Ubuntu) and dnf (Fedora/RHEL) package managers
- oh-my-posh installed via curl script to `/usr/local/bin`
- Neovim installed through the detected package manager when missing
- Both bash and zsh configurations are set up automatically

### Windows
- **WSL (Windows Subsystem for Linux) is required**
- Once in WSL, the setup works the same as Linux
- Not supported on native Windows (PowerShell/CMD)

## Important Setup Behaviors

1. **Backup Strategy**: All existing configs are backed up with timestamps to `~/dotfiles_backup` before being replaced
2. **Stow Management**: The setup uses GNU Stow for `tmux`, `posh`, and `scripts`, enabling version control of fully managed config without replacing local shell startup files
3. **Dual Shell Support**: The setup configures **both bash and zsh** automatically:
   - Appends to existing `~/.bashrc` and `~/.zshrc` rather than replacing them
   - Adds source lines for this checkout's `.bashrc` and `.zshrc`
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
- Use `wt` to manage feature branch worktrees after `scripts/` is stowed to `~/bin`
- All worktrees organized under `wt/` in repo root
- Automatic upstream setup and branch pushing (unless `-n` flag used)
