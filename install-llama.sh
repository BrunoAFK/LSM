#!/bin/bash

# Llama Script Manager Installer
# This script handles the first-time installation of LSM from GitHub

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Version
VERSION="1.0.19"

# Error handling
set -e # Exit on error
trap 'echo -e "${RED}Installation failed${NC}"; exit 1' ERR

# Configuration
GITHUB_USER="BrunoAFK"
GITHUB_REPO="LSM"
GITHUB_BRANCH="main"
INSTALL_DIR="/usr/local/lib/llama"
BIN_DIR="/usr/local/bin"
REPO_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO.git"

# Debug flag
DEBUG=true  # Set to true to enable debug output

# Add this helper function after the color definitions
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}DEBUG: $1${NC}"
    fi
}

# Check required tools
check_requirements() {
    if ! command -v git &>/dev/null; then
        echo -e "${RED}Error: git is not installed${NC}"
        echo "Please install git first:"
        echo "  For Ubuntu/Debian: sudo apt-get install git"
        echo "  For MacOS: brew install git"
        exit 1
    fi

    if ! command -v curl &>/dev/null; then
        echo -e "${RED}Error: curl is not installed${NC}"
        echo "Please install curl first:"
        echo "  For Ubuntu/Debian: sudo apt-get install curl"
        echo "  For MacOS: brew install curl"
        exit 1
    fi
}

# Check repository availability
check_repository() {
    echo -e "${YELLOW}Checking repository availability... \(Installer v${VERSION}\)${NC}"

    if ! curl --output /dev/null --silent --head --fail "https://github.com/$GITHUB_USER/$GITHUB_REPO"; then
        echo -e "${RED}Error: Repository $REPO_URL is not accessible${NC}"
        echo "Please check:"
        echo "  1. Repository exists and is public"
        echo "  2. Your internet connection"
        echo "  3. GitHub is accessible"
        exit 1
    fi
}

# Setup temporary directory and files
setup_temp_dir() {
    echo -e "${YELLOW}Setting up temporary directory... (Installer v${VERSION})${NC}"
    TEMP_DIR=$(mktemp -d)
    TEMP_FILE=$(mktemp)
    DESC_FILE=$(mktemp)
    
    # Consolidated cleanup trap for all temporary files and directories
    trap 'cleanup_temp_files' EXIT INT TERM
}

# Add new cleanup function
cleanup_temp_files() {
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    # Remove temporary directory and its contents
    [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
    # Remove temporary files
    [ -f "$TEMP_FILE" ] && rm -f "$TEMP_FILE"
    [ -f "$DESC_FILE" ] && rm -f "$DESC_FILE"
}

# Clone repository
clone_repository() {
    echo -e "${YELLOW}Cloning repository... (Installer v${VERSION})${NC}"
    if ! git clone "$REPO_URL" "$TEMP_DIR/repo" 2>/dev/null; then
        echo -e "${RED}Error: Failed to clone repository${NC}"
        exit 1
    fi
}

# Create directories
create_directories() {
    echo -e "${YELLOW}Creating installation directories... (Installer v${VERSION})${NC}"
    sudo mkdir -p "$INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR/scripts"
}
# Declare the associative array globally
declare -A selected_scripts
declare -A script_descriptions

# Script selection interface using dialog
select_scripts() {
    local scripts_dir="$TEMP_DIR/repo/scripts"

    # Check if directory exists and is not empty
    if [ ! -d "$scripts_dir" ]; then
        echo -e "${YELLOW}Warning: Scripts directory not found${NC}"
        return 1
    fi

    # Count number of files
    file_count=$(find "$scripts_dir" -type f -name "*" | wc -l)
    if [ "$file_count" -eq 0 ]; then
        echo -e "${YELLOW}Warning: No scripts found in repository${NC}"
        return 1
    fi

    # Check if dialog is installed, if not - try to install it
    if ! command -v dialog >/dev/null 2>&1; then
        echo -e "${YELLOW}Dialog is not installed. Attempting to install...${NC}"

        # Detect package manager and install dialog
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y dialog
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y dialog
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y dialog
        elif command -v brew >/dev/null 2>&1; then
            brew install dialog
        else
            echo -e "${RED}Error: Could not install dialog automatically${NC}"
            echo "Please install dialog manually for your system"
            exit 1
        fi

        # Check if installation was successful
        if ! command -v dialog >/dev/null 2>&1; then
            echo -e "${RED}Error: Failed to install dialog${NC}"
            exit 1
        fi
    fi

    # Use global temp files instead of creating new ones
    # Build the checklist options
    local script_num=1
    while IFS= read -r -d '' script; do
        script_basename=$(basename "$script")

        # Extract description more safely
        description="No description available"
        if [ -f "$script" ]; then
            desc=$(head -n 20 "$script" | grep -i "^#.*description:" |
                head -n 1 | sed 's/^#[ ]*[Dd]escription:[ ]*//')
            [ -n "$desc" ] && description=${desc:0:60}
        fi
        script_descriptions[$script_basename]=$description

        printf '%s\n' "$script_basename" "\"$description\"" "off" >>"$TEMP_FILE"
        ((script_num++))
    done < <(find "$scripts_dir" -type f -name "*" -print0)

    # Calculate dialog dimensions based on number of scripts
    local height=$((script_num + 10))
    [[ $height -gt 40 ]] && height=40 # Max height

    # Display dialog checklist with extra button
    dialog --title "Script Selection" \
        --backtitle "Llama Script Manager Installer v${VERSION}" \
        --extra-button --extra-label "Install All" \
        --checklist "Select scripts to install (use SPACE to select/unselect):" \
        $height 100 $((height - 8)) \
        --file "$TEMP_FILE" \
        2>"$DESC_FILE"

    local dialog_status=$?

    # Process selection
    if [ $dialog_status -eq 0 ]; then
        # Normal selection processing
        # Reset all selections
        for script in "${!selected_scripts[@]}"; do
            selected_scripts[$script]=0
        done

        # Read selected scripts safely
        while IFS= read -r selected; do
            selected=${selected//\"/}
            [ -n "$selected" ] && selected_scripts[$selected]=1
        done < <(tr ' ' '\n' <"$DESC_FILE" | grep -v '^$')

        # Show selected scripts
        clear
        echo -e "\n${BLUE}Selected scripts to install:${NC}"
        for script in "${!selected_scripts[@]}"; do
            [ "${selected_scripts[$script]}" -eq 1 ] && echo "  - $script"
        done
    elif [ $dialog_status -eq 3 ]; then  # Extra button returns 3
        # Install all scripts
        clear
        echo -e "\n${BLUE}Installing all scripts${NC}"
        while IFS= read -r script; do
            script_basename=$(basename "$script")
            selected_scripts[$script_basename]=1
            echo "  - $script_basename"
        done < <(find "$scripts_dir" -type f -name "*")
        return 0  # Ensure we don't exit here
    else
        echo -e "\n${YELLOW}Installation cancelled by user${NC}"
        exit 1
    fi
}

# Copy files with enhanced debugging
copy_files() {
    echo -e "${YELLOW}Copying files... (Installer v${VERSION})${NC}"

    debug_log "Selected scripts for installation:"
    for script_name in "${!selected_scripts[@]}"; do
        if [ "${selected_scripts[$script_name]}" -eq 1 ]; then
            debug_log "  - $script_name"
        fi
    done

    # Copy main script
    debug_log "Copying main script 'llama'"
    sudo cp "$TEMP_DIR/repo/llama" "$INSTALL_DIR/llama"
    sudo chmod +x "$INSTALL_DIR/llama"

    # Copy only selected scripts
    if [ -d "$TEMP_DIR/repo/scripts" ]; then
        for script in "$TEMP_DIR/repo/scripts"/*; do
            if [ -f "$script" ]; then
                script_name=$(basename "$script")
                if [ "${selected_scripts[$script_name]:-0}" -eq 1 ]; then
                    echo -e "${GREEN}Installing: $script_name${NC}"
                    sudo cp "$script" "$INSTALL_DIR/scripts/"
                    sudo chmod +x "$INSTALL_DIR/scripts/$script_name"
                else
                    debug_log "Skipping: $script_name (not selected)"
                fi
            fi
        done
    fi
}

# Create symlink
create_symlink() {
    echo -e "${YELLOW}Creating symlink... (Installer v${VERSION})${NC}"
    sudo ln -sf "$INSTALL_DIR/llama" "$BIN_DIR/llama"
}

# Add this new function before the main() function
cleanup_dialog() {
    echo -e "${YELLOW}Cleaning up dialog installation...${NC}"
    if command -v dialog >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get remove -y dialog
            sudo apt-get autoremove -y
        elif command -v yum >/dev/null 2>&1; then
            sudo yum remove -y dialog
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf remove -y dialog
        elif command -v brew >/dev/null 2>&1; then
            brew uninstall dialog
        fi
    fi
}

# Main installation process
main() {
    echo -e "${GREEN}Starting Llama Script Manager Installation v${VERSION}...${NC}"

    check_requirements
    check_repository
    setup_temp_dir
    clone_repository
    create_directories
    select_scripts
    copy_files
    create_symlink
    cleanup_dialog

    echo -e "${GREEN}Installation v${VERSION} completed successfully!${NC}"
    echo -e "Run ${YELLOW}llama help${NC} to get started."
    
    # Add llama status check
    if command -v llama >/dev/null 2>&1; then
        echo -e "\n${YELLOW}Checking LSM installation status:${NC}"
        llama status
    else
        echo -e "\n${RED}Warning: 'llama' command not found in PATH${NC}"
    fi
}

main
