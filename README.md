# Dotfiles

Personal shell and development environment configuration for macOS, Linux, and Windows (WSL).

## Quick Start

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles
cd ~/dotfiles
./setup.sh
```

The setup script will preview all changes before applying them. Restart your terminal when complete.

## What's Included

- **Shell configs** for bash and zsh (both configured automatically)
- **Tmux** configuration with vim-style keybindings and mouse support
- **Neovim** setup using [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)
- **Oh-my-posh** custom theme with git status, Python env indicators, and execution time
- **Utility scripts** including `wt` for git worktree management
- **Development aliases** for Python, Node.js, and common workflows

## Platform Support

- ✅ macOS (zsh default, bash supported)
- ✅ Linux (Debian/Ubuntu, Fedora/RHEL)
- ✅ Windows via WSL

## Features

- **Safe setup**: Backs up existing configs before making changes
- **Idempotent**: Run setup multiple times safely
- **Dual shell support**: Configures both bash and zsh automatically
- **Cross-platform**: Detects OS and uses appropriate package manager

## Setup Options

```bash
./setup.sh              # Interactive preview mode (default)
./setup.sh --dry-run    # Preview only, no changes
./setup.sh --no-preview # Skip preview, install immediately
./setup.sh --force      # Overwrite existing configurations
```

## Key Aliases

- `vim` → `nvim`
- `python` → `python3`
- `s` → activate Python venv
- `d` → deactivate venv
- `ll`, `la`, `l` → ls variants

## Custom Tools

**Git Worktree Manager (`wt`)**
```bash
wt feature/new-feature    # Create worktree and push to origin
wt -n draft/experiment    # Local only, no push
```

## Documentation

See [CLAUDE.md](CLAUDE.md) for detailed architecture and development guidance.
