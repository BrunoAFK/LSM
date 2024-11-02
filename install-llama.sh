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
VERSION="1.0.44"

# Global array for selected scripts
declare -A SELECTED_SCRIPTS

# Error handling
# Add this function near the top of the script
handle_error() {
    local exit_code=$1
    local line_number=$2
    echo -e "${RED}Installation failed at line $line_number with exit code $exit_code${NC}" >&2
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}Debug log is available at: /tmp/lsm_install_debug.log${NC}" >&2
    fi
    exit 1
}

set -e # Exit on error
trap 'handle_error $? $LINENO' ERR

# Configuration
GITHUB_USER="BrunoAFK"
GITHUB_REPO="LSM"
GITHUB_BRANCH="main"
INSTALL_DIR="/usr/local/lib/llama"
BIN_DIR="/usr/local/bin"
REPO_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO.git"

# Debug flag
DEBUG=true # Set to true to enable debug output

# Add this helper function after the color definitions
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}DEBUG: $1${NC}" >&2 # Write to stderr
        echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: $1" >>"/tmp/lsm_install_debug.log"
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
    # Remove debug log only if DEBUG is true
    if [ "$DEBUG" = true ]; then
        [ -f "/tmp/dialog_debug.log" ] && rm -f "/tmp/dialog_debug.log"
    fi
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
    debug_log "Starting select_scripts function"
    debug_log "Scripts directory: $scripts_dir"

    # Check if directory exists and is not empty
    if [ ! -d "$scripts_dir" ]; then
        debug_log "ERROR: Scripts directory not found: $scripts_dir"
        echo -e "${YELLOW}Warning: Scripts directory not found${NC}"
        return 1
    fi

    # Count number of files
    file_count=$(find "$scripts_dir" -type f -name "*" | wc -l)
    debug_log "Found $file_count files in scripts directory"

    if [ "$file_count" -eq 0 ]; then
        debug_log "ERROR: No scripts found in repository"
        echo -e "${YELLOW}Warning: No scripts found in repository${NC}"
        return 1
    fi

    # Check if dialog is installed
    debug_log "Checking for dialog installation"
    if ! command -v dialog >/dev/null 2>&1; then
        debug_log "Dialog not found, attempting installation"
        echo -e "${YELLOW}Dialog is not installed. Attempting to install...${NC}"

        if command -v apt-get >/dev/null 2>&1; then
            debug_log "Using apt-get to install dialog"
            # Add error checking and output capture
            if ! sudo apt-get update 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
                debug_log "Failed to update apt"
                exit 1
            fi
            debug_log "apt-get update completed"

            if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y dialog 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
                debug_log "Failed to install dialog"
                exit 1
            fi
            debug_log "dialog installation completed"
        elif command -v yum >/dev/null 2>&1; then
            debug_log "Using yum to install dialog"
            if ! sudo yum install -y dialog 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
                debug_log "Failed to install dialog"
                exit 1
            fi
        elif command -v dnf >/dev/null 2>&1; then
            debug_log "Using dnf to install dialog"
            if ! sudo dnf install -y dialog 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
                debug_log "Failed to install dialog"
                exit 1
            fi
        elif command -v brew >/dev/null 2>&1; then
            debug_log "Using brew to install dialog"
            if ! brew install dialog 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
                debug_log "Failed to install dialog"
                exit 1
            fi
        else
            debug_log "ERROR: No supported package manager found"
            echo -e "${RED}Error: Could not install dialog automatically${NC}"
            exit 1
        fi

        # Verify dialog installation
        if ! command -v dialog >/dev/null 2>&1; then
            debug_log "ERROR: Dialog installation verification failed"
            echo -e "${RED}Error: Failed to install dialog${NC}"
            exit 1
        fi
        debug_log "Dialog installation verified successfully"
    fi

    # Add a small delay after dialog installation
    sleep 2
    debug_log "Proceeding with dialog command preparation"

    # Prepare script list for dialog
    >"$TEMP_FILE"
    local script_num=1
    while IFS= read -r -d '' script; do
        script_basename=$(basename "$script")
        debug_log "Processing script: $script_basename"

        description="No description available"
        if [ -f "$script" ]; then
            desc=$(head -n 20 "$script" | grep -i "^#.*description:" | head -n 1 | sed 's/^#[ ]*[Dd]escription:[ ]*//')
            [ -n "$desc" ] && description=${desc:0:60}
        fi
        printf '%s\n' "$script_basename" "\"$description\"" "off" >>"$TEMP_FILE"
        ((script_num++))
    done < <(find "$scripts_dir" -type f -name "*" -print0)

    debug_log "Total scripts processed: $((script_num - 1))"
    local height=$((script_num + 10))
    [[ $height -gt 40 ]] && height=40
    debug_log "Dialog height calculated as: $height"

    # Clear the global array
    SELECTED_SCRIPTS=()

    # Run dialog with different handling
    tempfile=$(mktemp)
    debug_log "Created temporary output file: $tempfile"

    # Display dialog and capture its exit status
    dialog --title "Script Selection" \
        --backtitle "Llama Script Manager Installer v${VERSION}" \
        --extra-button --extra-label "Install All" \
        --separate-output \
        --checklist "Select scripts to install (use SPACE to select/unselect):" \
        20 80 15 --file "$temp_list" 2>"$tempfile"

    local ret=$?
    debug_log "Dialog return code: $ret"

    if [ $ret -eq 3 ]; then # Install All was pressed
        debug_log "Install All selected"
        echo -e "\n${BLUE}Installing all scripts:${NC}"

        while IFS= read -r -d '' script; do
            script_basename=$(basename "$script")
            SELECTED_SCRIPTS["$script_basename"]=1
            echo -e "  - ${GREEN}$script_basename${NC}"
            debug_log "Added to install list: $script_basename"
        done < <(find "$scripts_dir" -type f -print0)

    elif [ $ret -eq 0 ]; then # OK was pressed
        debug_log "OK selected, processing selections"

        if [ -s "$tempfile" ]; then
            while IFS= read -r script; do
                SELECTED_SCRIPTS["$script"]=1
                echo -e "  - ${GREEN}$script${NC}"
                debug_log "Added to install list: $script"
            done <"$tempfile"
        fi
    else
        debug_log "Dialog cancelled (return code: $ret)"
        echo -e "${YELLOW}Installation cancelled${NC}"
        rm -f "$temp_list" "$tempfile"
        exit 1
    fi

    # Clean up
    rm -f "$temp_list" "$tempfile"

    # Verify selections
    if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
        debug_log "No scripts were selected"
        echo -e "${RED}Error: No scripts were selected for installation${NC}"
        exit 1
    fi

    debug_log "Selected scripts: ${!SELECTED_SCRIPTS[*]}"
    return 0
}

# Copy files with enhanced debugging
copy_filesBACK() {
    echo -e "${YELLOW}Copying files... (Installer v${VERSION})${NC}"

    debug_log "Beginning copy_files function"
    debug_log "Number of selected scripts: ${#SELECTED_SCRIPTS[@]}"

    # List all selected scripts
    for script_name in "${!SELECTED_SCRIPTS[@]}"; do
        debug_log "Script '$script_name' is marked as: ${SELECTED_SCRIPTS[$script_name]}"
    done

    # Copy main script
    debug_log "Copying main script 'llama'"
    sudo cp "$TEMP_DIR/repo/llama" "$INSTALL_DIR/llama"
    sudo chmod +x "$INSTALL_DIR/llama"

    # Copy selected scripts
    if [ -d "$TEMP_DIR/repo/scripts" ]; then
        for script in "$TEMP_DIR/repo/scripts"/*; do
            if [ -f "$script" ]; then
                script_name=$(basename "$script")
                debug_log "Checking script: $script_name (selected: ${SELECTED_SCRIPTS[$script_name]:-0})"
                if [ "${SELECTED_SCRIPTS[$script_name]:-0}" -eq 1 ]; then
                    echo -e "${GREEN}Installing: $script_name${NC}"
                    debug_log "Copying $script_name to $INSTALL_DIR/scripts/"
                    sudo cp "$script" "$INSTALL_DIR/scripts/"
                    sudo chmod +x "$INSTALL_DIR/scripts/$script_name"
                else
                    debug_log "Skipping: $script_name (not selected)"
                fi
            fi
        done
    else
        debug_log "ERROR: Scripts directory not found: $TEMP_DIR/repo/scripts"
    fi
}
copy_files() {
    echo -e "${YELLOW}Copying files... (Installer v${VERSION})${NC}"
    debug_log "Beginning copy_files function"
    debug_log "Number of selected scripts: ${#SELECTED_SCRIPTS[@]}"

    # Debug output of what's selected
    for script in "${!SELECTED_SCRIPTS[@]}"; do
        debug_log "Script '$script' is marked as: ${SELECTED_SCRIPTS[$script]}"
    done

    # Copy main script
    debug_log "Copying main script 'llama'"
    sudo cp "$TEMP_DIR/repo/llama" "$INSTALL_DIR/llama"
    sudo chmod +x "$INSTALL_DIR/llama"

    # Copy selected scripts
    if [ -d "$TEMP_DIR/repo/scripts" ]; then
        for script in "$TEMP_DIR/repo/scripts"/*; do
            if [ -f "$script" ]; then
                script_name=$(basename "$script")
                if [ "${SELECTED_SCRIPTS[$script_name]:-0}" -eq 1 ]; then
                    echo -e "${GREEN}Installing: $script_name${NC}"
                    debug_log "Copying $script_name to $INSTALL_DIR/scripts/"
                    sudo cp "$script" "$INSTALL_DIR/scripts/"
                    sudo chmod +x "$INSTALL_DIR/scripts/$script_name"
                else
                    debug_log "Skipping: $script_name (not selected)"
                fi
            fi
        done
    else
        debug_log "ERROR: Scripts directory not found: $TEMP_DIR/repo/scripts"
        echo -e "${RED}Error: Scripts directory not found${NC}"
        exit 1
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
    debug_log "Starting main installation process"
    echo -e "${GREEN}Starting Llama Script Manager Installation v${VERSION}...${NC}"

    debug_log "Checking requirements"
    check_requirements

    debug_log "Checking repository"
    check_repository

    debug_log "Setting up temporary directory"
    setup_temp_dir

    debug_log "Cloning repository"
    clone_repository

    debug_log "Creating directories"
    create_directories

    debug_log "Starting script selection"
    select_scripts
    debug_log "Script selection completed"

    debug_log "Copying files"
    copy_files

    debug_log "Creating symlink"
    create_symlink

    debug_log "Cleaning up dialog"
    cleanup_dialog

    debug_log "Installation completed"
    echo -e "${GREEN}Installation v${VERSION} completed successfully!${NC}"
    echo -e "Run ${YELLOW}llama help${NC} to get started."
}

main
