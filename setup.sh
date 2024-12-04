#!/bin/bash

# Exit on any error
set -e

# Error handling
trap 'echo "Error occurred at line $LINENO"; exit 1' ERR

# Define paths
DOTFILES_DIR="$HOME/dotfiles"
BACKUP_DIR="$HOME/dotfiles_backup"
BASHRC="$HOME/.bashrc"
TMUX_CONF="$HOME/.tmux.conf"
POSH_THEME_DIR="$HOME/.poshthemes"
POSH_THEME_FILE="pure_python_custom.omp.json"
NVIM_CONFIG_DIR="$HOME/.config/nvim"

# Parse command line arguments
DRY_RUN=false
FORCE=false
PREVIEW=true  # New flag for preview mode, default true

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true ;;
        -f|--force) FORCE=true ;;
        --no-preview) PREVIEW=false ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Required packages
REQUIRED_PACKAGES=(
    "git"
    "curl"
    "wget"
    "tmux"
    "neovim"
)

# Array to store preview actions
declare -a PREVIEW_ACTIONS=()

# Function to add action to preview
add_preview_action() {
    PREVIEW_ACTIONS+=("$1")
}

# Function to display preview and get confirmation
show_preview_and_confirm() {
    echo -e "\n=== Installation Preview ===\n"
    echo "The following actions will be performed:"
    local i=1
    for action in "${PREVIEW_ACTIONS[@]}"; do
        echo "$i. $action"
        ((i++))
    done
    
    echo -e "\nSystem Information:"
    echo "- Operating System: $(uname -s)"
    echo "- Dotfiles Directory: $DOTFILES_DIR"
    echo "- Backup Directory: $BACKUP_DIR"
    
    if [ "$FORCE" = true ]; then
        echo "- Force mode: Enabled (will overwrite existing configurations)"
    fi
    
    echo -e "\nWould you like to proceed with the installation? [y/N] "
    read -r response
    
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            echo "Installation cancelled."
            exit 0
            ;;
    esac
}

# Function to check sudo privileges
check_sudo() {
    if ! sudo -v &> /dev/null; then
        echo "Error: Sudo privileges required but not available"
        exit 1
    fi
}

# Function to detect OS and set package manager
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        INSTALL_CMD="brew install"
        PKG_CHECK_CMD="brew list"
        add_preview_action "Using macOS package manager (Homebrew)"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &>/dev/null; then
            INSTALL_CMD="sudo apt-get install -y"
            PKG_CHECK_CMD="dpkg -l"
            add_preview_action "Using Debian/Ubuntu package manager (apt)"
        elif command -v dnf &>/dev/null; then
            INSTALL_CMD="sudo dnf install -y"
            PKG_CHECK_CMD="rpm -q"
            add_preview_action "Using Fedora/RHEL package manager (dnf)"
        else
            echo "Unsupported package manager"
            exit 1
        fi
    else
        echo "Unsupported platform: $OSTYPE"
        exit 1
    fi
}

# Function to check required packages
check_packages() {
    local packages_to_install=()
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! $PKG_CHECK_CMD $package &>/dev/null; then
            packages_to_install+=("$package")
        fi
    done
    
    if [ ${#packages_to_install[@]} -ne 0 ]; then
        add_preview_action "Will install packages: ${packages_to_install[*]}"
    fi
}

# Function to backup a file
check_backup_needed() {
    local file=$1
    if [[ -e $file && ! -L $file ]]; then
        add_preview_action "Will backup existing file: $file"
    fi
}

# Function to check symlink creation
check_symlink_needed() {
    local src=$1
    local dest=$2
    if [[ ! -L $dest ]] || [[ "$FORCE" = true ]]; then
        add_preview_action "Will create symlink: $dest -> $src"
    fi
}

# Function to check oh-my-posh installation
check_oh_my_posh() {
    if ! command -v oh-my-posh &>/dev/null; then
        add_preview_action "Will install oh-my-posh"
    fi
}

# Function to check bashrc modifications
check_bashrc_modifications() {
    if ! grep -q "# DOTFILES CONFIG" "$BASHRC" 2>/dev/null; then
        add_preview_action "Will update $BASHRC to source dotfiles configuration"
    fi
    
    if ! grep -q "oh-my-posh" "$BASHRC" 2>/dev/null; then
        add_preview_action "Will add oh-my-posh configuration to $BASHRC"
    fi
}

# Function to check tmux plugin manager
check_tmux_plugins() {
    if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
        add_preview_action "Will install tmux plugin manager"
    fi
}

# Preview function
generate_preview() {
    # Verify dotfiles directory exists
    if [ ! -d "$DOTFILES_DIR" ]; then
        echo "Error: Dotfiles directory not found at $DOTFILES_DIR"
        exit 1
    fi

    detect_os
    check_packages
    
    # Check regular configs
    check_backup_needed "$BASHRC"
    check_backup_needed "$TMUX_CONF"
    check_symlink_needed "$DOTFILES_DIR/tmux.conf" "$TMUX_CONF"
    check_oh_my_posh
    check_bashrc_modifications
    check_tmux_plugins
    
    # Check Neovim setup
    check_backup_needed "$NVIM_CONFIG_DIR"
    check_symlink_needed "$DOTFILES_DIR/kickstart.nvim" "$NVIM_CONFIG_DIR"
    
    # Git submodule status
    if [ -f "$DOTFILES_DIR/.gitmodules" ]; then
        if ! git -C "$DOTFILES_DIR" submodule status kickstart.nvim 2>/dev/null | grep -q '^[^ ]'; then
            add_preview_action "Will initialize kickstart.nvim submodule"
        else
            add_preview_action "Will update kickstart.nvim submodule"
        fi
    else
        add_preview_action "WARNING: No .gitmodules file found. Kickstart.nvim might not be set up correctly."
    fi
    
    # Add general setup actions
    add_preview_action "Will create backup directory at: $BACKUP_DIR"
    add_preview_action "Will set up oh-my-posh theme at: $POSH_THEME_DIR/$POSH_THEME_FILE"
    
    # Add Neovim-specific setup info
    if command -v nvim &>/dev/null; then
        add_preview_action "Neovim is already installed ($(nvim --version | head -n1))"
    else
        add_preview_action "Will install Neovim"
    fi
    add_preview_action "Will setup Neovim configuration at: $NVIM_CONFIG_DIR"
}

# Main setup function
main() {
    # Verify dotfiles directory exists
    if [ ! -d "$DOTFILES_DIR" ]; then
        echo "Error: Dotfiles directory not found at $DOTFILES_DIR"
        exit 1
    fi

    # Create backup directory
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$BACKUP_DIR"
    fi

    # Detect OS and set package manager
    detect_os

    # Install required packages
    install_packages

    # Set up .bashrc
    backup_file "$BASHRC"
    if [ "$DRY_RUN" = false ]; then
        if ! grep -q "# DOTFILES CONFIG" "$BASHRC" 2>/dev/null; then
            echo -e "\n# DOTFILES CONFIG\nsource $DOTFILES_DIR/bashrc" >> "$BASHRC"
            echo "Updated $BASHRC to source dotfiles bashrc"
        else
            echo "$BASHRC already updated with dotfiles config"
        fi
    fi

    # Set up tmux configuration
    backup_file "$TMUX_CONF"
    create_symlink "$DOTFILES_DIR/tmux.conf" "$TMUX_CONF"

    # Install oh-my-posh if not present
    if ! command -v oh-my-posh &>/dev/null; then
        install_oh_my_posh
    else
        echo "oh-my-posh is already installed"
    fi

    # Set up oh-my-posh theme
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$POSH_THEME_DIR"
    fi
    create_symlink "$DOTFILES_DIR/$POSH_THEME_FILE" "$POSH_THEME_DIR/$POSH_THEME_FILE"

    # Update .bashrc for oh-my-posh
    if [ "$DRY_RUN" = false ]; then
        if ! grep -q "oh-my-posh" "$BASHRC"; then
            echo 'eval "$(oh-my-posh --init --shell bash --config $HOME/.poshthemes/my_theme.omp.json)"' >> "$BASHRC"
            echo "Added oh-my-posh configuration to $BASHRC"
        else
            echo "oh-my-posh configuration already present in $BASHRC"
        fi
    fi

    # Install tmux plugins
    if [ "$DRY_RUN" = false ]; then
        if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
            echo "Installing tmux plugin manager..."
            git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
        else
            echo "Tmux plugin manager already installed"
        fi
    fi

    echo "Setup complete! Please restart your terminal or run: source $BASHRC"
}

# Run script
if [ "$DRY_RUN" = true ]; then
    echo "Running in dry-run mode - no changes will be made"
    generate_preview
    show_preview_and_confirm
    exit 0
elif [ "$PREVIEW" = true ]; then
    generate_preview
    show_preview_and_confirm
fi

main
