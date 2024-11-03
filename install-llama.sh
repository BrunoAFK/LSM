#!/bin/bash
#==============================================================================
# Llama Script Manager (LSM) Installer
# 
# This script automates the installation of LSM from GitHub, providing:
# - Interactive script selection via dialog interface
# - Automatic dependency handling
# - Comprehensive error handling and debugging
# - Clean installation with proper permissions
#==============================================================================

#------------------------------------------------------------------------------
# Configuration and Setup
#------------------------------------------------------------------------------
# Color codes for consistent output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Version
VERSION="1.1.0"

# Global array for selected scripts
declare -A SELECTED_SCRIPTS

# Debug flag
DEBUG=false # Set to true to enable debug output

#------------------------------------------------------------------------------
# Core Error Handling Functions
#------------------------------------------------------------------------------
# handle_error: Manages script failures and provides debug information
# Parameters:
#   $1 - Exit code from failed command
#   $2 - Line number where error occurred
# Add this function near the top of the script
handle_error() {
    local exit_code=$1
    local line_number=$2
    
    # Disable error handling
    set +e
    trap - ERR
    
    echo -e "${RED}Installation failed at line $line_number with exit code $exit_code${NC}" >&2
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}Debug log is available at: /tmp/lsm_install_debug.log${NC}" >&2
    fi
    exit 1
}

cleanup_temp_files() {
    # Disable error handling during cleanup
    set +e
    trap - ERR
    
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    
    # Remove temporary directory and its contents
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR" || true
    fi
    
    # Remove temporary files
    if [ -f "$TEMP_FILE" ]; then
        rm -f "$TEMP_FILE" || true
    fi
    if [ -f "$DESC_FILE" ]; then
        rm -f "$DESC_FILE" || true
    fi
    
    # Remove debug log only if DEBUG is true
    if [ "$DEBUG" = true ] && [ -f "/tmp/dialog_debug.log" ]; then
        rm -f "/tmp/dialog_debug.log" || true
    fi
    
    # Re-enable error handling
    set -e
}

trap 'cleanup_temp_files' EXIT
trap 'handle_error $? $LINENO' ERR

# Configuration
GITHUB_USER="BrunoAFK"
GITHUB_REPO="LSM"
GITHUB_BRANCH="main"
INSTALL_DIR="/usr/local/lib/llama"
BIN_DIR="/usr/local/bin"
REPO_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO.git"

#------------------------------------------------------------------------------
# Utility Functions
#------------------------------------------------------------------------------
# debug_log: Handles debug output when DEBUG=true
# Parameters:
#   $1 - Debug message to log
# Add this helper function after the color definitions
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}DEBUG: $1${NC}" >&2 # Write to stderr
        echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: $1" >>"/tmp/lsm_install_debug.log"
    fi
}

# Add this helper function after the debug_log function
print_section_header() {
    local title=$1
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}=== $title (v${VERSION}) ===${NC}"
        debug_log "Starting section: $title"
    fi
}

#------------------------------------------------------------------------------
# Installation Prerequisites
#------------------------------------------------------------------------------
# check_requirements: Verifies all required system tools are available
# Checks for: git, curl
# Provides installation instructions if missing
# Add this function after the color definitions
check_requirements() {
    print_section_header "Checking Requirements"
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

# check_repository: Validates GitHub repository accessibility
# Ensures the LSM repository exists and is publicly accessible
# Add this function after the color definitions
check_repository() {
    print_section_header "Checking Repository"
    if ! curl --output /dev/null --silent --head --fail "https://github.com/$GITHUB_USER/$GITHUB_REPO"; then
        echo -e "${RED}Error: Repository $REPO_URL is not accessible${NC}"
        echo "Please check:"
        echo "  1. Repository exists and is public"
        echo "  2. Your internet connection"
        echo "  3. GitHub is accessible"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Installation Setup Functions
#------------------------------------------------------------------------------
# setup_temp_dir: Creates temporary working directory and files
# Sets up cleanup handlers for proper resource management
# Add this function after the color definitions
setup_temp_dir() {
    print_section_header "Setting up Temporary Directory"
    TEMP_DIR=$(mktemp -d)
    TEMP_FILE=$(mktemp)
    DESC_FILE=$(mktemp)

    # Consolidated cleanup trap for all temporary files and directories
    trap 'cleanup_temp_files' EXIT INT TERM
}

# clone_repository: Retrieves latest LSM code from GitHub
# Clones repository to temporary directory for installation
# Add this function after the color definitions
clone_repository() {
    print_section_header "Cloning Repository"
    if ! git clone "$REPO_URL" "$TEMP_DIR/repo" 2>/dev/null; then
        echo -e "${RED}Error: Failed to clone repository${NC}"
        exit 1
    fi
}

# create_directories: Sets up LSM installation directory structure
# Creates required directories with appropriate permissions
# Add this function after the color definitions
create_directories() {
    print_section_header "Creating Installation Directories"
    sudo mkdir -p "$INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR/scripts"
}

# Declare the associative array globally
declare -A selected_scripts
declare -A script_descriptions

#------------------------------------------------------------------------------
# Script Selection Interface
#------------------------------------------------------------------------------
# select_scripts: Provides interactive script selection via dialog
# Features:
# - Automatic dialog installation if needed
# - Script description parsing
# - "Install All" option
# - Individual script selection
# Add this function after the color definitions
select_scripts() {
    print_section_header "Script Selection"
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

    # Print debug messages before launching dialog
    debug_log "Launching dialog command..."
    echo -e "${BLUE}Launching dialog...${NC}"

    if dialog --title "Script Selection" \
        --backtitle "Llama Script Manager Installer v${VERSION}" \
        --extra-button --extra-label "Install All" \
        --item-help \
        --searchbox "Search scripts (press Enter to show results):" \
        $height 100 $((height - 8)) \
        --file "$TEMP_FILE" \
        2>"$DESC_FILE"; then
        dialog_status=$?
        debug_log "Normal selection completed with status: $dialog_status"
    else
        dialog_status=$?
        debug_log "Dialog completed with status: $dialog_status"
        if [ $dialog_status -eq 3 ]; then
            debug_log "Install All option selected"
            # Process all scripts
            while IFS= read -r -d '' script; do
                script_basename=$(basename "$script")
                SELECTED_SCRIPTS[$script_basename]=1
                debug_log "Adding script to install: $script_basename"
            done < <(find "$scripts_dir" -type f -print0)
            return 0
        elif [ $dialog_status -ne 0 ]; then
            debug_log "Dialog cancelled or error occurred"
            return 1
        fi
    fi

    # In the select_scripts function, modify the dialog status handling:
    dialog_status=$?
    debug_log "Dialog exit status: $dialog_status"

    # Add explicit debug logging for the Install All case
    if [ "$dialog_status" -eq 3 ]; then
        debug_log "Install All option selected"
        echo -e "\n${BLUE}Installing all scripts...${NC}"

        # Clear and reinitialize the SELECTED_SCRIPTS array
        declare -A SELECTED_SCRIPTS=()

        # Find all scripts in the directory
        while IFS= read -r -d '' script; do
            script_basename=$(basename "$script")
            SELECTED_SCRIPTS[$script_basename]=1
            debug_log "Marking for installation: $script_basename"
            echo -e "  - ${GREEN}$script_basename${NC}"
        done < <(find "$scripts_dir" -type f -print0)

        # Verify selections
        if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
            debug_log "ERROR: No scripts were marked for installation"
            echo -e "${RED}Error: No scripts were marked for installation${NC}"
            exit 1
        fi

        # Before copying each script:
        echo -e "${YELLOW}Installing ${#SELECTED_SCRIPTS[@]} scripts...${NC}"
        for script_name in "${!SELECTED_SCRIPTS[@]}"; do
            echo -e "${GREEN}- Installing: $script_name${NC}"
        done

        debug_log "Total scripts marked for installation: ${#SELECTED_SCRIPTS[@]}"
        return 0
    elif [ "$dialog_status" -eq 0 ]; then # Normal selection
        debug_log "Processing normal selection"

        # Clear the global array
        SELECTED_SCRIPTS=()

        # Process selected scripts from dialog output
        while IFS= read -r selected; do
            selected=${selected//\"/} # Remove quotes
            if [ -n "$selected" ]; then
                SELECTED_SCRIPTS[$selected]=1
                debug_log "Selected script: $selected"
            fi
        done < <(tr ' ' '\n' <"$DESC_FILE" | grep -v '^$')

        debug_log "Total scripts selected: ${#SELECTED_SCRIPTS[@]}"
    else
        debug_log "Dialog cancelled or error occurred (status: $dialog_status)"
        echo -e "\n${YELLOW}Installation cancelled or error occurred${NC}"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Installation Functions
#------------------------------------------------------------------------------
# copy_files: Handles the actual installation of selected scripts
# - Copies main LSM script
# - Installs selected utility scripts
# - Sets appropriate permissions
# Add this function after the color definitions
copy_files() {
    print_section_header "Copying Files"
    debug_log "Number of selected scripts: ${#SELECTED_SCRIPTS[@]}"

    # Add verification of selected scripts
    if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
        debug_log "ERROR: No scripts selected for installation"
        echo -e "${RED}Error: No scripts selected for installation${NC}"
        exit 1
    fi
    # List all selected scripts for verification
    for script_name in "${!SELECTED_SCRIPTS[@]}"; do
        debug_log "Script marked for installation: $script_name"
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

# create_symlink: Creates system-wide command access
# Links LSM into standard PATH for easy access
# Add this function after the color definitions
create_symlink() {
    print_section_header "Creating Symlink"
    sudo ln -sf "$INSTALL_DIR/llama" "$BIN_DIR/llama"
}

# cleanup_dialog: Removes dialog package if it was auto-installed
# Cleanup happens after script selection is complete
# Add this function after the color definitions
cleanup_dialog() {
    print_section_header "Cleaning Up Dialog"
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

#------------------------------------------------------------------------------
# Main Installation Process
#------------------------------------------------------------------------------
# main: Orchestrates the entire installation process
# Executes all installation steps in sequence with error handling
# Add this function after the color definitions
main() {
    debug_log "Starting main installation process"
    echo -e "${GREEN}Starting Llama Script Manager Installation...${NC}"

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

    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "Run ${YELLOW}llama help${NC} to get started."
    debug_log "Installation completed"
    echo
    llama status
    echo
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "Run ${YELLOW}llama help${NC} to get started."
    
    # Disable error handling before exiting
    set +e
    trap - ERR
    exit 0
}

main
