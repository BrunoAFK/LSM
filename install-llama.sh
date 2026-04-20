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
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m' # No Color

# Version
VERSION="1.1.3"

# Global array for selected scripts
declare -A SELECTED_SCRIPTS

# Debug flag
DEBUG=false # Set to true to enable debug output

# Track whether dialog was installed by this script
DIALOG_INSTALLED_BY_LSM=false
INSTALL_SUDO_READY=false
DIALOG_SUDO_READY=false
USE_SUDO=true

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
    
    echo "${RED}Installation failed at line $line_number with exit code $exit_code${NC}" >&2
    if [ "$DEBUG" = true ]; then
        echo "${BLUE}Debug log is available at: /tmp/lsm_install_debug.log${NC}" >&2
    fi
    exit 1
}

cleanup_temp_files() {
    # Prevent re-entrancy
    if [ "${_CLEANING_UP:-}" = "1" ]; then
        return
    fi
    _CLEANING_UP=1

    # Disable error handling during cleanup
    set +e
    trap - ERR INT TERM

    echo "${YELLOW}Cleaning up temporary files...${NC}"

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
}

trap 'cleanup_temp_files' EXIT
trap 'cleanup_temp_files; exit 130' INT TERM
trap 'handle_error $? $LINENO' ERR

# Configuration
GITHUB_USER="BrunoAFK"
GITHUB_REPO="LSM"
GITHUB_BRANCH="main"
DEFAULT_INSTALL_DIR="/usr/local/lib/llama"
DEFAULT_BIN_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/llama_env"
INSTALL_CONFIG_FILE="$CONFIG_DIR/install.conf"
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
BIN_DIR="$DEFAULT_BIN_DIR"
REPO_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO.git"
GITHUB_API_BASE="https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO"

#------------------------------------------------------------------------------
# Utility Functions
#------------------------------------------------------------------------------
# debug_log: Handles debug output when DEBUG=true
# Parameters:
#   $1 - Debug message to log
# Add this helper function after the color definitions
debug_log() {
    if [ "$DEBUG" = true ]; then
        echo "${BLUE}DEBUG: $1${NC}" >&2 # Write to stderr
        echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: $1" >>"/tmp/lsm_install_debug.log"
    fi
}

# Add this helper function after the debug_log function
print_section_header() {
    local title=$1
    if [ "$DEBUG" = true ]; then
        echo "${BLUE}=== $title (v${VERSION}) ===${NC}"
        debug_log "Starting section: $title"
    fi
}

prompt_for_sudo_access() {
    local cache_var="$1"
    local reason="$2"
    shift 2
    local step reply cache_value

    eval "cache_value=\${$cache_var:-false}"
    if [ "$(id -u)" -eq 0 ] || [ "$cache_value" = true ]; then
        return 0
    fi

    echo
    echo "${YELLOW}${reason}${NC}"
    if [ $# -gt 0 ]; then
        echo "It will run commands like:"
        for step in "$@"; do
            echo "  - $step"
        done
    fi

    if [ -r /dev/tty ] && [ -w /dev/tty ]; then
        printf "Continue and allow sudo? [y/N] " > /dev/tty
        read -r reply < /dev/tty || return 1
        case "$reply" in
            y|Y|yes|YES)
                ;;
            *)
                return 1
                ;;
        esac
    else
        echo "Requesting sudo access now..."
    fi

    if ! sudo -v; then
        echo "${RED}Error: Could not obtain sudo access${NC}"
        return 1
    fi

    eval "$cache_var=true"
    return 0
}

persist_install_config() {
    mkdir -p "$CONFIG_DIR"
    if [ "$INSTALL_DIR" = "$DEFAULT_INSTALL_DIR" ] && [ "$BIN_DIR" = "$DEFAULT_BIN_DIR" ]; then
        rm -f "$INSTALL_CONFIG_FILE"
        return 0
    fi

    {
        printf 'INSTALL_DIR=%s\n' "$INSTALL_DIR"
        printf 'BIN_DIR=%s\n' "$BIN_DIR"
    } > "$INSTALL_CONFIG_FILE"
    chmod 600 "$INSTALL_CONFIG_FILE" 2>/dev/null || true
}

is_path_writable() {
    local path="$1"
    local parent

    if [ -e "$path" ]; then
        [ -w "$path" ]
        return $?
    fi

    parent=$(dirname "$path")
    while [ ! -d "$parent" ] && [ "$parent" != "/" ]; do
        parent=$(dirname "$parent")
    done

    [ -w "$parent" ]
}

run_install_command() {
    if [ "$USE_SUDO" = true ] && [ "$(id -u)" -ne 0 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

ensure_path_note() {
    case ":$PATH:" in
        *":$BIN_DIR:"*)
            ;;
        *)
            echo
            echo "${YELLOW}Note:${NC} $BIN_DIR is not currently in PATH."
            echo "Add it to your shell profile if you want to run 'llama' directly."
            ;;
    esac
}

prompt_for_user_install_location() {
    local input_install_dir input_bin_dir
    local default_install_dir="$HOME/.local/lib/llama"
    local default_bin_dir="$HOME/.local/bin"

    if ! [ -r /dev/tty ] || ! [ -w /dev/tty ]; then
        return 1
    fi

    echo
    echo "${YELLOW}You can continue without sudo by installing in your home directory.${NC}"
    echo "Choose where llama should be stored and where the 'llama' command symlink should be created."
    echo "The bin directory must be in PATH."

    printf "Install directory [%s]: " "$default_install_dir" > /dev/tty
    read -r input_install_dir < /dev/tty || return 1
    printf "Bin directory for the 'llama' command [%s]: " "$default_bin_dir" > /dev/tty
    read -r input_bin_dir < /dev/tty || return 1

    INSTALL_DIR="${input_install_dir:-$default_install_dir}"
    BIN_DIR="${input_bin_dir:-$default_bin_dir}"
    USE_SUDO=false
    persist_install_config

    echo
    echo "${GREEN}Using user install paths:${NC}"
    echo "  Install: $INSTALL_DIR"
    echo "  Bin:     $BIN_DIR"
    ensure_path_note
    return 0
}

configure_install_target() {
    if [ "$(id -u)" -eq 0 ]; then
        USE_SUDO=false
        persist_install_config
        return 0
    fi

    if is_path_writable "$INSTALL_DIR" && is_path_writable "$INSTALL_DIR/scripts" && is_path_writable "$BIN_DIR"; then
        USE_SUDO=false
        persist_install_config
        return 0
    fi

    if prompt_for_sudo_access INSTALL_SUDO_READY \
        "Installing LSM system-wide requires administrator access." \
        "mkdir -p $INSTALL_DIR" \
        "mkdir -p $INSTALL_DIR/scripts" \
        "copy llama into $INSTALL_DIR" \
        "copy selected scripts into $INSTALL_DIR/scripts" \
        "mkdir -p $BIN_DIR" \
        "ln -sf $INSTALL_DIR/llama $BIN_DIR/llama"; then
        USE_SUDO=true
        persist_install_config
        return 0
    fi

    prompt_for_user_install_location
}

select_scripts_text() {
    local scripts_dir="$1"
    local script selection raw_index script_name description index selected_index
    local -a script_names=()
    SELECTED_SCRIPTS=()

    echo
    echo "${YELLOW}Continuing without dialog.${NC}"
    echo "Available scripts:"

    index=1
    while IFS= read -r -d '' script; do
        script_name=$(basename "$script")
        description=$(head -n 20 "$script" | grep -i "^#.*description:" | head -n 1 | sed 's/^#[ ]*[Dd]escription:[ ]*//')
        description="${description:-No description}"
        script_names+=("$script_name")
        printf "  [%d] %-16s %s\n" "$index" "$script_name" "$description"
        index=$((index + 1))
    done < <(find "$scripts_dir" -type f -print0)

    echo
    echo "Enter comma-separated numbers to install, 'all' for everything, or press ENTER for core install only."
    if [ -r /dev/tty ] && [ -w /dev/tty ]; then
        printf "Selection: " > /dev/tty
        IFS= read -r selection < /dev/tty || return 1
    else
        return 1
    fi

    case "$selection" in
        "" )
            echo "${BLUE}No optional scripts selected. Only llama will be installed.${NC}"
            return 0
            ;;
        all|ALL|All)
            while IFS= read -r -d '' script; do
                script_name=$(basename "$script")
                SELECTED_SCRIPTS["$script_name"]=1
            done < <(find "$scripts_dir" -type f -print0)
            echo "${GREEN}Selected all scripts.${NC}"
            return 0
            ;;
    esac

    IFS=',' read -r -a raw_indices <<< "$selection"
    for raw_index in "${raw_indices[@]}"; do
        selected_index=$(printf '%s' "$raw_index" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -z "$selected_index" ] && continue
        if [[ "$selected_index" =~ ^[0-9]+$ ]] && [ "$selected_index" -ge 1 ] && [ "$selected_index" -le "${#script_names[@]}" ]; then
            script_name="${script_names[$((selected_index - 1))]}"
            SELECTED_SCRIPTS["$script_name"]=1
        else
            echo "${YELLOW}Skipping unknown selection:${NC} $selected_index"
        fi
    done

    if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
        echo "${BLUE}No valid optional scripts selected. Only llama will be installed.${NC}"
    fi

    return 0
}

install_dialog_package() {
    local reply

    echo
    echo "${YELLOW}The 'dialog' package is not installed.${NC}"
    echo "It is only needed for the interactive checkbox UI."
    echo "If you do not want that, the installer will continue with a plain text selection prompt."

    if command -v apt-get >/dev/null 2>&1; then
        echo "Package manager commands:"
        echo "  - apt-get update"
        echo "  - apt-get install -y dialog"
        if [ -r /dev/tty ] && [ -w /dev/tty ]; then
            printf "Install dialog temporarily? [y/N] " > /dev/tty
            read -r reply < /dev/tty || return 1
        else
            return 1
        fi
        case "$reply" in
            y|Y|yes|YES)
                if ! prompt_for_sudo_access DIALOG_SUDO_READY \
                    "Installing dialog temporarily requires administrator access." \
                    "apt-get update" \
                    "apt-get install -y dialog"; then
                    return 1
                fi
                if ! sudo apt-get update 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
                    debug_log "Failed to update apt"
                    exit 1
                fi
                if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y dialog 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
                    debug_log "Failed to install dialog"
                    exit 1
                fi
                DIALOG_INSTALLED_BY_LSM=true
                ;;
            *)
                return 1
                ;;
        esac
    elif command -v yum >/dev/null 2>&1; then
        echo "Package manager command:"
        echo "  - yum install -y dialog"
        if [ -r /dev/tty ] && [ -w /dev/tty ]; then
            printf "Install dialog temporarily? [y/N] " > /dev/tty
            read -r reply < /dev/tty || return 1
        else
            return 1
        fi
        case "$reply" in
            y|Y|yes|YES)
                if ! prompt_for_sudo_access DIALOG_SUDO_READY \
                    "Installing dialog temporarily requires administrator access." \
                    "yum install -y dialog"; then
                    return 1
                fi
                if ! sudo yum install -y dialog 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
                    debug_log "Failed to install dialog"
                    exit 1
                fi
                DIALOG_INSTALLED_BY_LSM=true
                ;;
            *)
                return 1
                ;;
        esac
    elif command -v dnf >/dev/null 2>&1; then
        echo "Package manager command:"
        echo "  - dnf install -y dialog"
        if [ -r /dev/tty ] && [ -w /dev/tty ]; then
            printf "Install dialog temporarily? [y/N] " > /dev/tty
            read -r reply < /dev/tty || return 1
        else
            return 1
        fi
        case "$reply" in
            y|Y|yes|YES)
                if ! prompt_for_sudo_access DIALOG_SUDO_READY \
                    "Installing dialog temporarily requires administrator access." \
                    "dnf install -y dialog"; then
                    return 1
                fi
                if ! sudo dnf install -y dialog 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
                    debug_log "Failed to install dialog"
                    exit 1
                fi
                DIALOG_INSTALLED_BY_LSM=true
                ;;
            *)
                return 1
                ;;
        esac
    elif command -v brew >/dev/null 2>&1; then
        echo "Package manager command:"
        echo "  - brew install dialog"
        if [ -r /dev/tty ] && [ -w /dev/tty ]; then
            printf "Install dialog with Homebrew? [y/N] " > /dev/tty
            read -r reply < /dev/tty || return 1
        else
            return 1
        fi
        case "$reply" in
            y|Y|yes|YES)
                if ! brew install dialog 2>&1 | tee -a "/tmp/lsm_install_debug.log"; then
                    debug_log "Failed to install dialog"
                    exit 1
                fi
                DIALOG_INSTALLED_BY_LSM=true
                ;;
            *)
                return 1
                ;;
        esac
    else
        echo "${YELLOW}No supported package manager found for automatic dialog install.${NC}"
        return 1
    fi

    if ! command -v dialog >/dev/null 2>&1; then
        echo "${RED}Error: Failed to install dialog${NC}"
        exit 1
    fi

    return 0
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
        echo "${RED}Error: git is not installed${NC}"
        echo "Please install git first:"
        echo "  For Ubuntu/Debian: sudo apt-get install git"
        echo "  For MacOS: brew install git"
        exit 1
    fi

    if ! command -v curl &>/dev/null; then
        echo "${RED}Error: curl is not installed${NC}"
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
        echo "${RED}Error: Repository $REPO_URL is not accessible${NC}"
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
    trap 'cleanup_temp_files' EXIT
    trap 'cleanup_temp_files; exit 130' INT TERM
}

# sha256_file: Cross-platform SHA256 hash
sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        echo ""
    fi
}

# verify_checksums: Verify downloaded files against checksums.txt
verify_checksums() {
    local checksum_file="$1"
    local target_dir="$2"
    local failed=0

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local expected_hash file_name
        expected_hash=$(echo "$line" | awk '{print $1}')
        file_name=$(basename "$(echo "$line" | awk '{print $2}')")

        local target_file="$target_dir/$file_name"
        if [ ! -f "$target_file" ]; then
            target_file="$target_dir/scripts/$file_name"
            [ ! -f "$target_file" ] && continue
        fi

        local actual_hash
        actual_hash=$(sha256_file "$target_file")

        if [ "$expected_hash" != "$actual_hash" ]; then
            echo "${RED}Checksum FAILED:${NC} $file_name"
            failed=1
        else
            debug_log "Checksum OK: $file_name"
        fi
    done < "$checksum_file"

    return $failed
}

# clone_repository: Retrieves latest LSM code from GitHub release (with checksum
# verification) or falls back to branch clone for older setups.
clone_repository() {
    print_section_header "Downloading LSM"

    # Try to get latest release info
    local api_response release_tag checksum_url
    api_response=$(curl -fsSL "$GITHUB_API_BASE/releases/latest" 2>/dev/null) || true

    if [ -n "$api_response" ]; then
        release_tag=$(echo "$api_response" | grep '"tag_name"' | head -1 | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
        checksum_url=$(echo "$api_response" | grep '"browser_download_url"' | grep 'checksums.txt' | head -1 | sed -E 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    fi

    if [ -n "$release_tag" ]; then
        echo "${GREEN}Installing from release ${release_tag}${NC}"
        debug_log "Found release: $release_tag"

        if git clone --depth 1 --branch "$release_tag" --single-branch \
            "$REPO_URL" "$TEMP_DIR/repo" 2>/dev/null; then

            # Verify checksums if available
            if [ -n "$checksum_url" ]; then
                echo "Verifying checksums..."
                if curl -fsSL -o "$TEMP_DIR/checksums.txt" "$checksum_url"; then
                    if verify_checksums "$TEMP_DIR/checksums.txt" "$TEMP_DIR/repo"; then
                        echo "${GREEN}Checksums verified${NC}"
                    else
                        echo "${RED}Checksum verification failed — aborting${NC}"
                        exit 1
                    fi
                else
                    echo "${YELLOW}Warning: Could not download checksums${NC}"
                fi
            fi
            return 0
        fi
        echo "${YELLOW}Release clone failed, falling back to branch...${NC}"
    fi

    # Fallback: clone from branch
    debug_log "Falling back to branch clone"
    if ! git clone --depth 1 --branch "$GITHUB_BRANCH" --single-branch \
        "$REPO_URL" "$TEMP_DIR/repo" 2>/dev/null; then
        echo "${RED}Error: Failed to clone repository${NC}"
        exit 1
    fi
}

# create_directories: Sets up LSM installation directory structure
# Creates required directories with appropriate permissions
# Add this function after the color definitions
create_directories() {
    print_section_header "Creating Installation Directories"
    run_install_command mkdir -p "$INSTALL_DIR"
    run_install_command mkdir -p "$INSTALL_DIR/scripts"
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
        echo "${YELLOW}Warning: Scripts directory not found${NC}"
        return 1
    fi

    # Count number of files
    file_count=$(find "$scripts_dir" -type f -name "*" | wc -l)
    debug_log "Found $file_count files in scripts directory"

    if [ "$file_count" -eq 0 ]; then
        debug_log "ERROR: No scripts found in repository"
        echo "${YELLOW}Warning: No scripts found in repository${NC}"
        return 1
    fi

    # Check if dialog is installed
    debug_log "Checking for dialog installation"
    if ! command -v dialog >/dev/null 2>&1; then
        debug_log "Dialog not found"
        if ! install_dialog_package; then
            debug_log "Continuing with text selection"
            select_scripts_text "$scripts_dir"
            return $?
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
    echo "${BLUE}Launching dialog...${NC}"

    # In the select_scripts function, replace the dialog command with:
    if dialog --title "Script Selection" \
        --backtitle "Llama Script Manager Installer v${VERSION}" \
        --extra-button --extra-label "Install All" \
        --checklist "Select scripts to install (use SPACE to select/unselect):" \
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
        echo
        echo "${BLUE}Installing all scripts...${NC}"

        # Clear and reinitialize the SELECTED_SCRIPTS array
        declare -A SELECTED_SCRIPTS=()

        # Find all scripts in the directory
        while IFS= read -r -d '' script; do
            script_basename=$(basename "$script")
            SELECTED_SCRIPTS[$script_basename]=1
            debug_log "Marking for installation: $script_basename"
            echo "  - ${GREEN}$script_basename${NC}"
        done < <(find "$scripts_dir" -type f -print0)

        # Verify selections
        if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
            debug_log "ERROR: No scripts were marked for installation"
            echo "${RED}Error: No scripts were marked for installation${NC}"
            exit 1
        fi

        # Before copying each script:
        echo "${YELLOW}Installing ${#SELECTED_SCRIPTS[@]} scripts...${NC}"
        for script_name in "${!SELECTED_SCRIPTS[@]}"; do
            echo "${GREEN}- Installing: $script_name${NC}"
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
        echo
        echo "${YELLOW}Installation cancelled or error occurred${NC}"
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

    for script_name in "${!SELECTED_SCRIPTS[@]}"; do
        debug_log "Script marked for installation: $script_name"
    done

    # Copy main script
    debug_log "Copying main script 'llama'"
    run_install_command cp "$TEMP_DIR/repo/llama" "$INSTALL_DIR/llama"
    run_install_command chmod +x "$INSTALL_DIR/llama"

    # Copy selected scripts
    if [ -d "$TEMP_DIR/repo/scripts" ]; then
        for script in "$TEMP_DIR/repo/scripts"/*; do
            if [ -f "$script" ]; then
                script_name=$(basename "$script")
                debug_log "Checking script: $script_name (selected: ${SELECTED_SCRIPTS[$script_name]:-0})"
                if [ "${SELECTED_SCRIPTS[$script_name]:-0}" -eq 1 ]; then
                    echo "${GREEN}Installing: $script_name${NC}"
                    debug_log "Copying $script_name to $INSTALL_DIR/scripts/"
                    run_install_command cp "$script" "$INSTALL_DIR/scripts/"
                    run_install_command chmod +x "$INSTALL_DIR/scripts/$script_name"
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
    run_install_command mkdir -p "$BIN_DIR"
    run_install_command ln -sf "$INSTALL_DIR/llama" "$BIN_DIR/llama"
}

# cleanup_dialog: Removes dialog package if it was auto-installed
# Cleanup happens after script selection is complete
# Add this function after the color definitions
cleanup_dialog() {
    print_section_header "Cleaning Up Dialog"
    if [ "$DIALOG_INSTALLED_BY_LSM" = true ] && command -v dialog >/dev/null 2>&1; then
        local reply
        echo
        echo "${YELLOW}LSM installed 'dialog' temporarily for the script selection UI.${NC}"
        if [ -r /dev/tty ] && [ -w /dev/tty ]; then
            printf "Remove dialog now? [Y/n] " > /dev/tty
            read -r reply < /dev/tty || reply=""
        else
            reply=""
        fi
        case "$reply" in
            n|N|no|NO)
                echo "${BLUE}Keeping dialog installed.${NC}"
                return 0
                ;;
        esac

        if command -v apt-get >/dev/null 2>&1; then
            prompt_for_sudo_access DIALOG_SUDO_READY \
                "Removing the temporary dialog package requires administrator access." \
                "apt-get remove -y dialog" \
                "apt-get autoremove -y" || return 0
            sudo apt-get remove -y dialog
            sudo apt-get autoremove -y
        elif command -v yum >/dev/null 2>&1; then
            prompt_for_sudo_access DIALOG_SUDO_READY \
                "Removing the temporary dialog package requires administrator access." \
                "yum remove -y dialog" || return 0
            sudo yum remove -y dialog
        elif command -v dnf >/dev/null 2>&1; then
            prompt_for_sudo_access DIALOG_SUDO_READY \
                "Removing the temporary dialog package requires administrator access." \
                "dnf remove -y dialog" || return 0
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
    echo "${GREEN}Starting Llama Script Manager Installation...${NC}"

    debug_log "Checking requirements"
    check_requirements

    debug_log "Checking repository"
    check_repository

    debug_log "Setting up temporary directory"
    setup_temp_dir

    debug_log "Cloning repository"
    clone_repository

    debug_log "Starting script selection"
    if ! select_scripts; then
        cleanup_dialog
        set +e
        trap - ERR
        exit 1
    fi
    debug_log "Script selection completed"

    if ! configure_install_target; then
        echo "Installation cancelled before privileged changes."
        cleanup_dialog
        set +e
        trap - ERR
        exit 0
    fi

    debug_log "Creating directories"
    create_directories

    debug_log "Copying files"
    copy_files

    debug_log "Creating symlink"
    create_symlink

    persist_install_config

    debug_log "Cleaning up dialog"
    cleanup_dialog

    echo "${GREEN}Installation completed successfully!${NC}"
    echo "Run ${YELLOW}llama help${NC} to get started."
    debug_log "Installation completed"
    echo
    "$INSTALL_DIR/llama" status
    echo
    echo "${GREEN}Installation completed successfully!${NC}"
    echo "Run ${YELLOW}llama help${NC} to get started."
    ensure_path_note
    
    # Disable error handling before exiting
    set +e
    trap - ERR
    exit 0
}

main
