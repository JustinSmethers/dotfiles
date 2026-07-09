# Dotfiles

Personal shell and development environment configuration for macOS, Linux, and Windows (WSL).

## Quick Start

```bash
git clone https://github.com/JustinSmethers/dotfiles.git ~/GitHub/dotfiles
cd ~/GitHub/dotfiles
./setup.sh
```

The setup script uses the checkout directory it is run from and previews all changes before applying them. Restart your terminal when complete.

## What's Included

- **Shell configs** for bash and zsh (both configured automatically)
- **Tmux** configuration with vim-style keybindings and mouse support
- **Neovim** setup using [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim)
- **Oh-my-posh** custom theme with git status, Python env indicators, and execution time
- **Utility scripts** including `wt` for git worktree management
- **Daily digest tool** for Jira/GitHub/daily-note planning, under `daily-digest/`
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
- **Non-destructive Neovim setup**: Installs Neovim if missing and only clones kickstart.nvim when no Neovim config exists
- **Stow-managed links**: Uses GNU Stow for tmux, oh-my-posh theme, and helper scripts while leaving local shell startup files intact

## Setup Options

```bash
./setup.sh              # Interactive preview mode (default)
./setup.sh --dry-run    # Preview only, no prompt, no changes
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

**Daily Digest (`daily-digest`)**
```bash
cd ~/GitHub/dotfiles/daily-digest
claude "/daily-digest setup"
```

The digest setup creates local machine-specific config, Claude permissions, and launchd
files. It is intentionally not run by `setup.sh`.

## Link Management

`setup.sh` uses GNU Stow for files that can be fully managed by this repo:

- `~/.tmux.conf` from `tmux/`
- `~/.poshthemes/pure_python_custom.omp.json` from `posh/`
- `~/bin/wt` and `~/bin/ghp` from `scripts/`

Shell startup files are intentionally not stowed. Existing `~/.zshrc` and
`~/.bashrc` stay local, and setup appends a small source block when needed.
This keeps private keys and machine-specific shell config out of git.

## Documentation

See [CLAUDE.md](CLAUDE.md) for detailed architecture and development guidance.
