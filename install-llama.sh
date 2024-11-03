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
VERSION="2.0.6"

# Global array for selected scripts
declare -A SELECTED_SCRIPTS

# Debug flag
DEBUG=true # Set to true to enable debug output

#------------------------------------------------------------------------------
# Core Error Handling Functions
#------------------------------------------------------------------------------

cleanup_temp_files() {
    # Disable error handling during cleanup
    set +e
    trap - ERR

    debug_log "Starting cleanup of temporary files"
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"

    # Store the original exit code
    local exit_code=$?

    # Only remove the temporary directory we created
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        debug_log "Removing specific temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR" 2>/dev/null || {
            debug_log "Failed to remove directory: $TEMP_DIR"
            sudo rm -rf "$TEMP_DIR" 2>/dev/null
        }
    fi

    # Only remove specific temp files we created
    for file in "$TEMP_FILE" "$DESC_FILE" "$SCRIPT_LIST_FILE" "$FEATURED_LIST_FILE" "$ALL_LIST_FILE" "$FILTERED_LIST_FILE"; do
        if [ -n "$file" ] && [ -f "$file" ]; then
            debug_log "Removing specific temporary file: $file"
            rm -f "$file" 2>/dev/null || {
                debug_log "Failed to remove file: $file"
                sudo rm -f "$file" 2>/dev/null
            }
        fi
    done

    debug_log "Cleanup completed"

    # Re-enable error handling
    set -e
    trap 'handle_error $? $LINENO' ERR

    return $exit_code
}

handle_error() {
    local exit_code=$1
    local line_number=$2

    # Call cleanup before handling the error
    cleanup_temp_files

    echo -e "${RED}Installation failed at line $line_number with exit code $exit_code${NC}" >&2
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}Debug log is available at: /tmp/lsm_install_debug.log${NC}" >&2
    fi
    exit 1
}

# Update trap setup
trap 'cleanup_temp_files' EXIT
trap 'handle_error $? $LINENO' ERR INT TERM

# Configuration
GITHUB_USER="BrunoAFK"
GITHUB_REPO="LSM"
GITHUB_BRANCH="dev"
INSTALL_DIR="/usr/local/lib/llama"
BIN_DIR="/usr/local/bin"
REPO_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO.git"

#------------------------------------------------------------------------------
# Utility Functions
#------------------------------------------------------------------------------
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}DEBUG: $1${NC}" >&2 # Write to stderr
        echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: $1" >>"/tmp/lsm_install_debug.log"
    fi
}

print_section_header() {
    local title=$1
    if [ "$DEBUG" = true ]; then
        echo -e "${BLUE}=== $title (v${VERSION}) ===${NC}"
        debug_log "Starting section: $title"
    fi
}

check_platform() {
    print_section_header "Platform Check"
    local platform=$(uname)
    debug_log "Detected platform: $platform"

    # Global variables for platform-specific settings
    declare -g DIALOG_HEIGHT
    declare -g DIALOG_WIDTH

    case "$platform" in
    Darwin)
        # macOS-specific adjustments
        DIALOG_HEIGHT=$(($(tput lines) - 10))
        DIALOG_WIDTH=$(($(tput cols) - 10))
        debug_log "Set macOS dialog dimensions: $DIALOG_HEIGHT x $DIALOG_WIDTH"
        ;;
    Linux)
        # Linux-specific adjustments
        DIALOG_HEIGHT=40
        DIALOG_WIDTH=100
        debug_log "Set Linux dialog dimensions: $DIALOG_HEIGHT x $DIALOG_WIDTH"
        ;;
    *)
        debug_log "Unsupported platform: $platform"
        echo -e "${YELLOW}Warning: Unsupported platform $platform${NC}"
        DIALOG_HEIGHT=40
        DIALOG_WIDTH=100
        ;;
    esac
}

verify_dialog() {
    print_section_header "Dialog Verification"
    debug_log "Verifying dialog installation"

    if ! command -v dialog >/dev/null 2>&1; then
        debug_log "Dialog not found, attempting installation"
        install_package dialog
    fi

    # Verify dialog works
    if ! dialog --version >/dev/null 2>&1; then
        debug_log "Dialog installation verification failed"
        echo -e "${RED}Error: Dialog installation failed${NC}"
        exit 1
    fi

    debug_log "Dialog verification successful"
}

verify_selections() {
    print_section_header "Selection Verification"
    debug_log "Verifying script selections..."

    if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
        debug_log "No scripts selected"
        return 1
    fi

    echo -e "${BLUE}Selected scripts:${NC}"
    for script in "${!SELECTED_SCRIPTS[@]}"; do
        debug_log "Selected: $script (value: ${SELECTED_SCRIPTS[$script]})"
        echo -e "${GREEN}- $script${NC}"
    done

    return 0
}

#------------------------------------------------------------------------------
# Package Installation Functions
#------------------------------------------------------------------------------
install_package() {
    local package=$1
    debug_log "Attempting to install $package"
    echo -e "${YELLOW}$package is not installed. Attempting to install...${NC}"

    if command -v apt-get >/dev/null 2>&1; then
        debug_log "Using apt-get to install $package"
        if ! sudo apt-get update 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
            debug_log "Failed to update apt"
            return 1
        fi
        if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $package 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
            debug_log "Failed to install $package"
            return 1
        fi
    elif command -v yum >/dev/null 2>&1; then
        debug_log "Using yum to install $package"
        if ! sudo yum install -y $package 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
            debug_log "Failed to install $package"
            return 1
        fi
    elif command -v dnf >/dev/null 2>&1; then
        debug_log "Using dnf to install $package"
        if ! sudo dnf install -y $package 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
            debug_log "Failed to install $package"
            return 1
        fi
    elif command -v brew >/dev/null 2>&1; then
        debug_log "Using brew to install $package"
        if ! brew install $package 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
            debug_log "Failed to install $package"
            return 1
        fi
    else
        debug_log "ERROR: No supported package manager found"
        echo -e "${RED}Error: Could not install $package automatically${NC}"
        echo "Please install $package manually according to your system's package manager."
        return 1
    fi

    # Verify installation
    if ! command -v $package >/dev/null 2>&1; then
        debug_log "ERROR: $package installation verification failed"
        echo -e "${RED}Error: Failed to install $package${NC}"
        return 1
    fi
    debug_log "$package installation verified successfully"
    return 0
}

ensure_requirementsB() {
    print_section_header "Checking and Installing Requirements"
    local required_packages=(jq dialog)
    local missing_packages=()
    local all_installed=true

    # Check for git and curl first as they are essential
    for cmd in git curl; do
        if ! command -v $cmd &>/dev/null; then
            echo -e "${RED}Error: $cmd is not installed${NC}"
            echo "Please install $cmd first:"
            echo "  For Ubuntu/Debian: sudo apt-get install $cmd"
            echo "  For MacOS: brew install $cmd"
            exit 1
        fi
    done

    # Check for other required packages
    for package in "${required_packages[@]}"; do
        if ! command -v $package &>/dev/null; then
            debug_log "$package is not installed"
            missing_packages+=("$package")
            all_installed=false
        else
            debug_log "$package is already installed"
        fi
    done

    # If all packages are installed, return early
    if [ "$all_installed" = true ]; then
        debug_log "All required packages are already installed"
        return 0
    fi

    # Install missing packages
    for package in "${missing_packages[@]}"; do
        if ! install_package "$package"; then
            echo -e "${RED}Failed to install $package. Please install it manually:${NC}"
            echo "  For Ubuntu/Debian: sudo apt-get install $package"
            echo "  For MacOS: brew install $package"
            echo "  For CentOS/RHEL: sudo yum install $package"
            echo "  For Fedora: sudo dnf install $package"
            exit 1
        fi
        echo -e "${GREEN}Successfully installed $package${NC}"
    done

    # Add a small delay after installation
    sleep 2
    debug_log "All required packages are now installed"
    return 0
}

ensure_requirements() {
    print_section_header "Checking and Installing Requirements"
    local required_packages=(jq dialog)
    local missing_packages=()
    local all_installed=true

    # Check platform first
    check_platform

    # Check for git and curl first as they are essential
    for cmd in git curl; do
        if ! command -v $cmd &>/dev/null; then
            echo -e "${RED}Error: $cmd is not installed${NC}"
            echo "Please install $cmd first:"
            echo "  For Ubuntu/Debian: sudo apt-get install $cmd"
            echo "  For MacOS: brew install $cmd"
            exit 1
        fi
    done

    # Verify dialog specifically
    verify_dialog

    # Check for other required packages
    for package in "${required_packages[@]}"; do
        if ! command -v $package &>/dev/null; then
            debug_log "$package is not installed"
            missing_packages+=("$package")
            all_installed=false
        else
            debug_log "$package is already installed"
        fi
    done

    # If all packages are installed, return early
    if [ "$all_installed" = true ]; then
        debug_log "All required packages are already installed"
        return 0
    fi

    # Install missing packages
    for package in "${missing_packages[@]}"; do
        if ! install_package "$package"; then
            echo -e "${RED}Failed to install $package. Please install it manually:${NC}"
            echo "  For Ubuntu/Debian: sudo apt-get install $package"
            echo "  For MacOS: brew install $package"
            echo "  For CentOS/RHEL: sudo yum install $package"
            echo "  For Fedora: sudo dnf install $package"
            exit 1
        fi
        echo -e "${GREEN}Successfully installed $package${NC}"
    done
    sleep 2
    debug_log "All required packages are now installed"
    return 0
}

#------------------------------------------------------------------------------
# Repository Functions
#------------------------------------------------------------------------------
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

setup_temp_dir() {
    print_section_header "Setting up Temporary Directory"
    TEMP_DIR=$(mktemp -d)
    TEMP_FILE=$(mktemp)
    DESC_FILE=$(mktemp)

    # Consolidated cleanup trap for all temporary files and directories
    trap 'cleanup_temp_files' EXIT INT TERM
}

clone_repository() {
    print_section_header "Cloning Repository"
    if ! git clone "$REPO_URL" "$TEMP_DIR/repo" 2>/dev/null; then
        echo -e "${RED}Error: Failed to clone repository${NC}"
        exit 1
    fi
}

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

select_scripts() {
    print_section_header "Script Selection"
    local scripts_dir="$TEMP_DIR/repo/scripts"
    debug_log "Starting select_scripts function"
    debug_log "Scripts directory: $scripts_dir"

    # Create temporary files
    local SCRIPT_LIST_FILE=$(mktemp)
    local FEATURED_LIST_FILE=$(mktemp)
    local ALL_LIST_FILE=$(mktemp)
    local FILTERED_LIST_FILE=$(mktemp)

    # Download and parse script_list.json
    debug_log "Downloading script_list.json"
    local json_url="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/script_list.json"
    debug_log "Attempting to download from: $json_url"

    local json_content=$(curl -sS -w "\nHTTP_CODE:%{http_code}" "$json_url")
    local http_code=$(echo "$json_content" | grep "HTTP_CODE:" | cut -d":" -f2)
    json_content=$(echo "$json_content" | grep -v "HTTP_CODE:")

    # Validate download and JSON
    if [ "$http_code" != "200" ] || ! echo "$json_content" | jq '.' >/dev/null 2>&1; then
        debug_log "ERROR: Failed to download or parse script_list.json"
        echo -e "${RED}Error: Failed to get script list${NC}"
        return 1
    fi

    echo "$json_content" >"$SCRIPT_LIST_FILE"

    # Prepare lists
    jq -r '.scripts[] | select(.rank | contains("Featured")) | "\(.name)\n\"\(.description)\"\noff"' "$SCRIPT_LIST_FILE" >"$FEATURED_LIST_FILE"
    jq -r '.scripts[] | select(.path | contains("./scripts/")) | "\(.name)\n\"\(.description)\"\noff"' "$SCRIPT_LIST_FILE" >"$ALL_LIST_FILE"

    # First dialog: Choose installation mode
    dialog --title "Installation Mode" \
        --backtitle "Llama Script Manager Installer v${VERSION}" \
        --yes-label "Install All" \
        --no-label "Custom Selection" \
        --yesno "\nChoose installation mode:\n\nInstall All: Install all available scripts\nCustom Selection: Choose which scripts to install" \
        12 60

    local mode_choice=$?
    debug_log "Installation mode choice: $mode_choice"

    case $mode_choice in
    0) # Install All
        debug_log "Installing all scripts"
        local count=0
        while IFS= read -r line; do
            if [ $((++count % 3)) -eq 1 ]; then
                SELECTED_SCRIPTS["$line"]=1
                debug_log "Adding all script: $line"
            fi
        done <"$ALL_LIST_FILE"
        return 0
        ;;
    1) # Custom Selection
        # Continue to featured scripts
        ;;
    *) # Cancel
        debug_log "Installation cancelled"
        return 1
        ;;
    esac

    # Function to filter scripts based on search term
    filter_scripts() {
        local search_term="$1"
        local source_file="$2"
        local target_file="$3"

        debug_log "Filtering scripts with search term: $search_term"
        if [ -z "$search_term" ]; then
            cp "$source_file" "$target_file"
        else
            awk -v search="${search_term,,}" '
            {
                if (NR % 3 == 1) script=$0;
                if (NR % 3 == 2) desc=$0;
                if (NR % 3 == 0) {
                    if (tolower(script) ~ search || tolower(desc) ~ search) {
                        print prev2; print prev1; print $0;
                    }
                }
                prev2=script;
                prev1=desc;
            }' "$source_file" >"$target_file"
        fi
    }

    # Show Featured Scripts
    local featured_count=$(wc -l <"$FEATURED_LIST_FILE")
    featured_count=$((featured_count / 3))
    debug_log "Found $featured_count featured scripts"

    if [ $featured_count -gt 0 ]; then
        local height=$((featured_count + 10))
        [[ $height -gt 40 ]] && height=40

        dialog --title "Featured Scripts" \
            --backtitle "Llama Script Manager Installer v${VERSION}" \
            --no-ok \
            --extra-button --extra-label "Next" \
            --colors \
            --checklist "\Zn\Z3Featured Scripts\Zn (use SPACE to select/unselect):" \
            $height 100 $((height - 8)) \
            --file "$FEATURED_LIST_FILE" \
            2>"$DESC_FILE"

        local featured_status=$?
        debug_log "Featured dialog status: $featured_status"

        # Process featured selections if any
        if [ -s "$DESC_FILE" ]; then
            while IFS= read -r selected; do
                selected=${selected//\"/}
                if [ -n "$selected" ]; then
                    SELECTED_SCRIPTS[$selected]=1
                    debug_log "Selected featured script: $selected"
                fi
            done <"$DESC_FILE"
        fi

        if [ $featured_status -ne 3 ]; then
            debug_log "Featured selection cancelled"
            return 1
        fi
    fi

    # Market Loop
    local current_list="$ALL_LIST_FILE"
    while true; do
        dialog --title "Script Market" \
            --backtitle "Llama Script Manager Installer v${VERSION}" \
            --ok-label "Install Selected" \
            --cancel-label "Exit" \
            --help-button --help-label "Search" \
            --colors \
            --checklist "\Zn\Z2Available Scripts\Zn (use SPACE to select/unselect):" \
            40 100 32 \
            --file "$current_list" \
            2>"$DESC_FILE"

        local market_status=$?
        debug_log "Market dialog status: $market_status"

        case $market_status in
        0)
            debug_log "Processing final selections"
            while IFS= read -r selected; do
                selected=${selected//\"/}
                if [ -n "$selected" ]; then
                    SELECTED_SCRIPTS[$selected]=1
                    debug_log "Added to selection: $selected"
                fi
            done <"$DESC_FILE"
            debug_log "Final selections: ${!SELECTED_SCRIPTS[*]}"
            return 0
            ;;
        2)
            debug_log "Search requested"
            local search_term=$(dialog --title "Search Scripts" \
                --backtitle "Llama Script Manager Installer v${VERSION}" \
                --inputbox "Enter search term (leave empty to show all):" \
                8 60 \
                2>"$DESC_FILE")

            local search_status=$?
            debug_log "Search dialog status: $search_status"

            if [ $search_status -eq 0 ]; then
                search_term=$(cat "$DESC_FILE")
                debug_log "Searching for: '$search_term'"
                if [ -z "$search_term" ]; then
                    current_list="$ALL_LIST_FILE"
                else
                    filter_scripts "$search_term" "$ALL_LIST_FILE" "$FILTERED_LIST_FILE"
                    current_list="$FILTERED_LIST_FILE"
                fi
            fi
            continue
            ;;
        *)
            debug_log "Market selection cancelled"
            if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
                return 1
            fi
            return 0
            ;;
        esac
    done

    # Clean up temporary files
    rm -f "$SCRIPT_LIST_FILE" "$FEATURED_LIST_FILE" "$ALL_LIST_FILE" "$FILTERED_LIST_FILE"
}

#------------------------------------------------------------------------------
# Installation Functions
#------------------------------------------------------------------------------

copy_files() {
    print_section_header "Copying Files"
    debug_log "Number of selected scripts: ${#SELECTED_SCRIPTS[@]}"
    debug_log "Current directory: $(pwd)"
    debug_log "Temp directory contents: $(ls -la $TEMP_DIR)"
    debug_log "Repo directory contents: $(ls -la $TEMP_DIR/repo)"
    debug_log "Scripts directory contents: $(ls -la $TEMP_DIR/repo/scripts 2>/dev/null || echo 'Scripts directory not found')"
    debug_log "Install directory: $INSTALL_DIR"
    debug_log "Install directory contents before: $(ls -la $INSTALL_DIR 2>/dev/null || echo 'Install directory not found')"

    # Verify selections before proceeding
    if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
        debug_log "ERROR: No scripts selected for installation"
        echo -e "${RED}Error: No scripts selected for installation${NC}"
        exit 1
    fi

    # Dump selected scripts array content
    debug_log "Selected scripts array content:"
    for key in "${!SELECTED_SCRIPTS[@]}"; do
        debug_log "  Key: '$key' Value: '${SELECTED_SCRIPTS[$key]}'"
    done

    # List all selected scripts for verification
    echo -e "${BLUE}Installing selected scripts:${NC}"
    for script_name in "${!SELECTED_SCRIPTS[@]}"; do
        debug_log "Script marked for installation: $script_name"
        echo -e "${GREEN}- $script_name${NC}"
    done

    # Copy main script with error checking
    debug_log "Copying main script 'llama'"
    debug_log "Source path: $TEMP_DIR/repo/llama"
    debug_log "Target path: $INSTALL_DIR/llama"
    debug_log "Main script exists: $([ -f "$TEMP_DIR/repo/llama" ] && echo "Yes" || echo "No")"

    if [ ! -f "$TEMP_DIR/repo/llama" ]; then
        debug_log "ERROR: Main script not found at $TEMP_DIR/repo/llama"
        debug_log "Directory contents: $(ls -la $TEMP_DIR/repo)"
        echo -e "${RED}Error: Main script not found${NC}"
        exit 1
    fi

    if ! sudo cp "$TEMP_DIR/repo/llama" "$INSTALL_DIR/llama"; then
        debug_log "ERROR: Failed to copy main script"
        debug_log "cp exit code: $?"
        echo -e "${RED}Error: Failed to copy main script${NC}"
        exit 1
    fi

    sudo chmod +x "$INSTALL_DIR/llama"
    debug_log "Main script permissions after chmod: $(ls -la $INSTALL_DIR/llama)"

    # Create scripts directory if it doesn't exist
    debug_log "Checking scripts directory: $INSTALL_DIR/scripts"
    if [ ! -d "$INSTALL_DIR/scripts" ]; then
        debug_log "Creating scripts directory"
        if ! sudo mkdir -p "$INSTALL_DIR/scripts"; then
            debug_log "ERROR: Failed to create scripts directory"
            debug_log "mkdir exit code: $?"
            echo -e "${RED}Error: Failed to create scripts directory${NC}"
            exit 1
        fi
    fi
    debug_log "Scripts directory permissions: $(ls -ld $INSTALL_DIR/scripts)"

    # Copy selected scripts with explicit path checking and error handling
    local install_success=false
    for script_name in "${!SELECTED_SCRIPTS[@]}"; do
        debug_log "========================================="
        debug_log "Processing script: $script_name"

        local script_path="$TEMP_DIR/repo/scripts/$script_name"
        local target_path="$INSTALL_DIR/scripts/$script_name"

        debug_log "Source path: $script_path"
        debug_log "Target path: $target_path"
        debug_log "Source exists: $([ -f "$script_path" ] && echo "Yes" || echo "No")"
        if [ -f "$script_path" ]; then
            debug_log "Source file permissions: $(ls -la $script_path)"
        fi

        # Verify source file exists
        if [ ! -f "$script_path" ]; then
            debug_log "ERROR: Source file not found: $script_path"
            debug_log "Directory contents: $(ls -la $TEMP_DIR/repo/scripts)"
            echo -e "${RED}Error: Script file not found: $script_name${NC}"
            continue
        fi

        echo -e "${GREEN}Installing: $script_name${NC}"

        # Copy with explicit error checking
        debug_log "Attempting to copy file..."
        if ! sudo cp "$script_path" "$target_path"; then
            debug_log "ERROR: Failed to copy $script_name"
            debug_log "cp exit code: $?"
            debug_log "Source readable: $([ -r "$script_path" ] && echo "Yes" || echo "No")"
            debug_log "Target directory writable: $([ -w "$(dirname "$target_path")" ] && echo "Yes" || echo "No")"
            echo -e "${RED}Error: Failed to copy $script_name${NC}"
            continue
        fi

        debug_log "File copied successfully"
        debug_log "Target file exists: $([ -f "$target_path" ] && echo "Yes" || echo "No")"

        # Set permissions with error checking
        debug_log "Setting executable permissions..."
        if ! sudo chmod +x "$target_path"; then
            debug_log "ERROR: Failed to set executable permissions for $script_name"
            debug_log "chmod exit code: $?"
            echo -e "${RED}Error: Failed to set permissions for $script_name${NC}"
            continue
        fi

        debug_log "Permissions set successfully"
        debug_log "Final file permissions: $(ls -la $target_path)"
        debug_log "Successfully installed $script_name"
        install_success=true
    done

    # Verify final installation
    debug_log "========================================="
    debug_log "Verifying installation..."
    debug_log "Install directory contents after: $(ls -la $INSTALL_DIR)"
    debug_log "Scripts directory contents after: $(ls -la $INSTALL_DIR/scripts)"

    local installed_count=$(ls -1 "$INSTALL_DIR/scripts" 2>/dev/null | wc -l)
    debug_log "Number of installed scripts: $installed_count"

    if [ $installed_count -eq 0 ]; then
        debug_log "ERROR: No scripts found in installation directory"
        echo -e "${RED}Error: Installation verification failed${NC}"
        exit 1
    fi

    if [ "$install_success" = false ]; then
        debug_log "ERROR: No scripts were successfully installed"
        echo -e "${RED}Error: No scripts were successfully installed${NC}"
        exit 1
    fi

    echo -e "${GREEN}Successfully installed ${installed_count} scripts${NC}"
    return 0
}

create_symlink() {
    print_section_header "Creating Symlink"
    sudo ln -sf "$INSTALL_DIR/llama" "$BIN_DIR/llama"
}

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
main() {
    debug_log "Starting main installation process"
    echo -e "${GREEN}Starting Llama Script Manager Installation...${NC}"

    debug_log "Checking and installing requirements"
    ensure_requirements

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
    if [ $? -ne 0 ]; then
        debug_log "Script selection cancelled or failed"
        echo -e "${YELLOW}Installation cancelled by user${NC}"
        exit 0
    fi
    debug_log "Script selection completed"

    debug_log "Copying files"
    copy_files

    debug_log "Creating symlink"
    create_symlink

    debug_log "Cleaning up dialog"
    cleanup_dialog

    # Add verification after cleanup
    debug_log "Performing final verification"
    if [ ! -f "$INSTALL_DIR/llama" ]; then
        debug_log "ERROR: Main script missing after installation"
        echo -e "${RED}Error: Installation verification failed${NC}"
        exit 1
    fi

    # Verify scripts
    debug_log "Verifying installed scripts"
    for script_name in "${!SELECTED_SCRIPTS[@]}"; do
        if [ ! -f "$INSTALL_DIR/scripts/$script_name" ]; then
            debug_log "ERROR: Script $script_name missing after installation"
            echo -e "${RED}Error: Script $script_name missing after installation${NC}"
            exit 1
        fi
        debug_log "Verified script: $script_name"
    done

    debug_log "All scripts verified after cleanup"

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

# Start the installation
main
