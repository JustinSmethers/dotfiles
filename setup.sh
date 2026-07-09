#!/bin/bash

# Exit on any error
set -e

# Error handling
trap 'echo "Error occurred at line $LINENO"; exit 1' ERR

# Define paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$SCRIPT_DIR}"
BACKUP_DIR="$HOME/dotfiles_backup"
BASHRC="$HOME/.bashrc"
ZSHRC="$HOME/.zshrc"
POSH_THEME_FILE="pure_python_custom.omp.json"
NVIM_CONFIG_DIR="$HOME/.config/nvim"
STOW_PACKAGES=(
    "tmux"
    "posh"
    "scripts"
)
STOW_TARGETS=(
    "$HOME/.tmux.conf|$DOTFILES_DIR/tmux/.tmux.conf"
    "$HOME/.poshthemes/$POSH_THEME_FILE|$DOTFILES_DIR/posh/.poshthemes/$POSH_THEME_FILE"
    "$HOME/bin/wt|$DOTFILES_DIR/scripts/bin/wt"
    "$HOME/bin/ghp|$DOTFILES_DIR/scripts/bin/ghp"
)

# Parse command line arguments
DRY_RUN=false
FORCE=false
PREVIEW=true

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
    "stow"
    "unzip"
)

# Array to store preview actions
declare -a PREVIEW_ACTIONS=()

# Function to add action to preview
add_preview_action() {
    PREVIEW_ACTIONS+=("$1")
}

# Function to display preview
show_preview() {
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
}

# Function to display preview and get confirmation
show_preview_and_confirm() {
    show_preview

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

# Function to detect user's shell
detect_shell() {
    # Detect current shell from $SHELL environment variable
    if [[ "$SHELL" == *"zsh"* ]]; then
        USER_SHELL="zsh"
        add_preview_action "Detected zsh as default shell"
    elif [[ "$SHELL" == *"bash"* ]]; then
        USER_SHELL="bash"
        add_preview_action "Detected bash as default shell"
    else
        # Default to bash if unable to detect
        USER_SHELL="bash"
        add_preview_action "Unable to detect shell, defaulting to bash"
    fi
}

setup_kickstart() {
    if [ -e "$NVIM_CONFIG_DIR" ]; then
        echo "Neovim config already exists at $NVIM_CONFIG_DIR; skipping kickstart.nvim setup"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would setup kickstart.nvim"
        return
    fi

    echo "Setting up kickstart.nvim..."
    git clone https://github.com/nvim-lua/kickstart.nvim.git "$NVIM_CONFIG_DIR"
}

package_command() {
    local package=$1
    case "$package" in
        neovim) echo "nvim" ;;
        *) echo "$package" ;;
    esac
}

package_available() {
    local package=$1
    local binary
    binary=$(package_command "$package")

    command -v "$binary" &>/dev/null || $PKG_CHECK_CMD "$package" &>/dev/null
}

# Function to check required packages
check_packages() {
    local packages_to_install=()
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! package_available "$package"; then
            packages_to_install+=("$package")
        fi
    done
    
    if [ ${#packages_to_install[@]} -ne 0 ]; then
        add_preview_action "Will install packages: ${packages_to_install[*]}"
    fi
}

# Function to check oh-my-posh installation
check_oh_my_posh() {
    if ! command -v oh-my-posh &>/dev/null; then
        add_preview_action "Will install oh-my-posh"
    fi
}

# Function to check shell modifications
check_shell_modifications() {
    # Check bashrc
    if ! grep -Fq "source $DOTFILES_DIR/.bashrc" "$BASHRC" 2>/dev/null; then
        if [[ -e "$BASHRC" && ! -L "$BASHRC" ]]; then
            add_preview_action "Will copy a backup of $BASHRC before appending dotfiles source"
        fi
        add_preview_action "Will append dotfiles source block to $BASHRC"
    fi

    if ! grep -q "oh-my-posh" "$BASHRC" 2>/dev/null; then
        add_preview_action "Will add oh-my-posh configuration to $BASHRC"
    fi

    if ! grep -q "exec tmux" "$BASHRC" 2>/dev/null; then
        add_preview_action "Will update $BASHRC to default to tmux"
    fi

    # Check zshrc
    if ! grep -Fq "source $DOTFILES_DIR/.zshrc" "$ZSHRC" 2>/dev/null; then
        if [[ -e "$ZSHRC" && ! -L "$ZSHRC" ]]; then
            add_preview_action "Will copy a backup of $ZSHRC before appending dotfiles source"
        fi
        add_preview_action "Will append dotfiles source block to $ZSHRC"
    fi

    if ! grep -q "oh-my-posh" "$ZSHRC" 2>/dev/null; then
        add_preview_action "Will add oh-my-posh configuration to $ZSHRC"
    fi

    if ! grep -q "exec tmux" "$ZSHRC" 2>/dev/null; then
        add_preview_action "Will update $ZSHRC to default to tmux"
    fi
}

# Function to check tmux plugin manager
check_tmux_plugins() {
    if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
        add_preview_action "Will install tmux plugin manager"
    fi
}

check_stow_targets() {
    add_preview_action "Will stow packages into $HOME: ${STOW_PACKAGES[*]}"

    local target
    local source
    local link_target
    for pair in "${STOW_TARGETS[@]}"; do
        target=${pair%%|*}
        source=${pair#*|}

        if [[ -L "$target" ]]; then
            link_target=$(readlink "$target")
            if [[ "$link_target" == "$source" ]]; then
                add_preview_action "Stow target already linked: $target -> $source"
            elif [[ "$link_target" == "$DOTFILES_DIR/"* ]]; then
                add_preview_action "Will replace old dotfiles symlink before stowing: $target -> $link_target"
            elif [[ "$FORCE" = true ]]; then
                add_preview_action "Will backup existing symlink before stowing: $target -> $link_target"
            else
                add_preview_action "Existing symlink may conflict with stow: $target -> $link_target"
            fi
        elif [[ -e "$target" ]]; then
            add_preview_action "Will backup existing file before stowing: $target"
        else
            add_preview_action "Will create stow link: $target -> $source"
        fi
    done
}

# Preview function
generate_preview() {
    # Verify dotfiles directory exists
    if [ ! -d "$DOTFILES_DIR" ]; then
        echo "Error: Dotfiles directory not found at $DOTFILES_DIR"
        exit 1
    fi

    detect_os
    detect_shell
    check_packages

    # Check regular configs
    check_stow_targets
    check_oh_my_posh
    check_shell_modifications
    check_tmux_plugins

    if [ -d "$DOTFILES_DIR/scripts/bin" ]; then
        add_preview_action "Will ensure scripts in $DOTFILES_DIR/scripts/bin are executable"
    fi

    # Check Neovim setup
    if [ ! -e "$NVIM_CONFIG_DIR" ]; then
        add_preview_action "Will clone kickstart.nvim to: $NVIM_CONFIG_DIR"
    fi
    
    # Add general setup actions
    add_preview_action "Will create backup directory at: $BACKUP_DIR"
    add_preview_action "Will set up oh-my-posh theme via stow at: $HOME/.poshthemes/$POSH_THEME_FILE"
    
    # Add Neovim-specific setup info
    if command -v nvim &>/dev/null; then
        add_preview_action "Neovim is already installed ($(nvim --version | head -n1))"
    else
        add_preview_action "Will install Neovim"
    fi
    if [ -e "$NVIM_CONFIG_DIR" ]; then
        add_preview_action "Will leave existing Neovim configuration in place: $NVIM_CONFIG_DIR"
    else
        add_preview_action "Will setup Neovim configuration at: $NVIM_CONFIG_DIR"
    fi
}

# Function to backup a file
backup_file() {
    local file=$1
    if [[ -e $file || -L $file ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        if [ "$DRY_RUN" = true ]; then
            echo "[DRY RUN] Would backup $file to $BACKUP_DIR/$(basename $file)_${timestamp}.bak"
        else
            mv "$file" "$BACKUP_DIR/$(basename $file)_${timestamp}.bak"
            echo "Backed up $file to $BACKUP_DIR"
        fi
    fi
}

backup_file_copy() {
    local file=$1
    if [[ -e $file && ! -L $file ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        if [ "$DRY_RUN" = true ]; then
            echo "[DRY RUN] Would copy backup of $file to $BACKUP_DIR/$(basename $file)_${timestamp}.bak"
        else
            cp "$file" "$BACKUP_DIR/$(basename $file)_${timestamp}.bak"
            echo "Copied backup of $file to $BACKUP_DIR"
        fi
    fi
}

backup_stow_conflicts() {
    local target
    local source
    local link_target

    for pair in "${STOW_TARGETS[@]}"; do
        target=${pair%%|*}
        source=${pair#*|}

        if [[ -L "$target" ]]; then
            link_target=$(readlink "$target")
            if [[ "$link_target" == "$source" ]]; then
                continue
            fi
            if [[ "$link_target" == "$DOTFILES_DIR/"* || "$FORCE" = true ]]; then
                backup_file "$target"
            fi
        elif [[ -e "$target" ]]; then
            backup_file "$target"
        fi
    done
}

apply_stow() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would run: stow --dir $DOTFILES_DIR --target $HOME --restow ${STOW_PACKAGES[*]}"
        return
    fi

    echo "Stowing packages: ${STOW_PACKAGES[*]}"
    stow --dir "$DOTFILES_DIR" --target "$HOME" --restow "${STOW_PACKAGES[@]}"
}

# Function to install oh-my-posh
install_oh_my_posh() {
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would install oh-my-posh"
        return
    fi

    echo "Installing oh-my-posh..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        check_sudo

        # For Linux systems
        if command -v curl &>/dev/null; then
            curl -s https://ohmyposh.dev/install.sh | sudo bash -s
            
            # Ensure binary is in a PATH location
            if [ -f "/usr/local/bin/oh-my-posh" ]; then
                sudo chmod +x /usr/local/bin/oh-my-posh
            elif [ -f "$HOME/.local/bin/oh-my-posh" ]; then
                sudo mv "$HOME/.local/bin/oh-my-posh" /usr/local/bin/
                sudo chmod +x /usr/local/bin/oh-my-posh
            fi
        else
            echo "Error: curl is required for oh-my-posh installation"
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # For macOS
        if command -v brew &>/dev/null; then
            brew install jandedobbeleer/oh-my-posh/oh-my-posh
        else
            echo "Error: Homebrew is required for oh-my-posh installation on macOS"
            exit 1
        fi
    else
        echo "Unsupported operating system for oh-my-posh installation"
        exit 1
    fi
    
    # Verify installation and setup
    if ! command -v oh-my-posh &>/dev/null; then
        # Try to source the updated PATH
        export PATH=$PATH:/usr/local/bin:/usr/bin
        if ! command -v oh-my-posh &>/dev/null; then
            echo "Error: oh-my-posh installation failed or not in PATH"
            exit 1
        fi
    fi
    
    echo "oh-my-posh installed successfully"
    
    # Update bashrc with oh-my-posh configuration
    if ! grep -q "oh-my-posh init bash" "$BASHRC"; then
        echo -e "\n# oh-my-posh configuration" >> "$BASHRC"
        echo 'export PATH=$PATH:/usr/local/bin:/usr/bin' >> "$BASHRC"
        echo 'if command -v oh-my-posh &>/dev/null; then' >> "$BASHRC"
        echo 'eval "$(oh-my-posh init bash --config "$HOME/.poshthemes/'"${POSH_THEME_FILE}"'")"' >> "$BASHRC"
        echo 'fi' >> "$BASHRC"
        echo "Added oh-my-posh configuration to $BASHRC"
    fi

    # Update zshrc with oh-my-posh configuration
    if ! grep -q "oh-my-posh init zsh" "$ZSHRC"; then
        echo -e "\n# oh-my-posh configuration" >> "$ZSHRC"
        echo 'export PATH=$PATH:/usr/local/bin:/usr/bin' >> "$ZSHRC"
        echo 'if command -v oh-my-posh &>/dev/null; then' >> "$ZSHRC"
        echo 'eval "$(oh-my-posh init zsh --config "$HOME/.poshthemes/'"${POSH_THEME_FILE}"'")"' >> "$ZSHRC"
        echo 'fi' >> "$ZSHRC"
        echo "Added oh-my-posh configuration to $ZSHRC"
    fi
}

ensure_bin_executables() {
    local bin_dir="$DOTFILES_DIR/scripts/bin"

    if [ ! -d "$bin_dir" ]; then
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN] Would ensure scripts in $bin_dir are executable"
        return
    fi

    chmod +x "$bin_dir"/*

    echo "Ensured executable permission on scripts in $bin_dir"
}

# Function to install required packages
install_packages() {
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! package_available "$package"; then
            if [ "$DRY_RUN" = true ]; then
                echo "[DRY RUN] Would install $package"
            else
                echo "Installing $package..."
                $INSTALL_CMD $package
            fi
        else
            echo "$package is already installed"
        fi
    done
}

# Function to set up shell configurations
setup_shell_config() {
    # Set up .bashrc
    if [ "$DRY_RUN" = false ]; then
        if ! grep -Fq "source $DOTFILES_DIR/.bashrc" "$BASHRC" 2>/dev/null; then
            backup_file_copy "$BASHRC"
            echo -e "\n# DOTFILES CONFIG\nsource $DOTFILES_DIR/.bashrc" >> "$BASHRC"
            echo "Updated $BASHRC to source dotfiles bashrc"
        else
            echo "$BASHRC already updated with dotfiles config"
        fi
    fi

    # Set up .zshrc
    if [ "$DRY_RUN" = false ]; then
        if ! grep -Fq "source $DOTFILES_DIR/.zshrc" "$ZSHRC" 2>/dev/null; then
            backup_file_copy "$ZSHRC"
            echo -e "\n# DOTFILES CONFIG\nsource $DOTFILES_DIR/.zshrc" >> "$ZSHRC"
            echo "Updated $ZSHRC to source dotfiles zshrc"
        else
            echo "$ZSHRC already updated with dotfiles config"
        fi
    fi

    # Add tmux auto-launch to bashrc if not present
    if [ "$DRY_RUN" = false ]; then
        if ! grep -q "exec tmux" "$BASHRC"; then
            echo 'if command -v tmux &> /dev/null && [ -n "$PS1" ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ]; then exec tmux; fi' >> "$BASHRC"
            echo "Added tmux auto-launch to $BASHRC"
        else
            echo "Tmux auto-launch already present in $BASHRC"
        fi
    fi

    # Add tmux auto-launch to zshrc if not present
    if [ "$DRY_RUN" = false ]; then
        if ! grep -q "exec tmux" "$ZSHRC"; then
            echo 'if command -v tmux &> /dev/null && [ -n "$PS1" ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ]; then exec tmux; fi' >> "$ZSHRC"
            echo "Added tmux auto-launch to $ZSHRC"
        else
            echo "Tmux auto-launch already present in $ZSHRC"
        fi
    fi
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

    ensure_bin_executables
    backup_stow_conflicts
    apply_stow

    # Detect user's shell
    detect_shell

    # Set up shell configurations (bash and zsh)
    setup_shell_config

    # Install oh-my-posh if not present
    if ! command -v oh-my-posh &>/dev/null; then
        install_oh_my_posh
    else
        echo "oh-my-posh is already installed"
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

    # Setup Neovim configuration
    setup_kickstart

    echo "Setup complete! Please restart your terminal or run: source $BASHRC"
}

# Run script
if [ "$DRY_RUN" = true ]; then
    echo "Running in dry-run mode - no changes will be made"
    generate_preview
    show_preview
    exit 0
elif [ "$PREVIEW" = true ]; then
    generate_preview
    show_preview_and_confirm
fi

main

echo "Setup complete! Please restart your terminal to apply all changes."
