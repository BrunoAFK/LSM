#!/bin/bash
#==============================================================================
# Llama Script Manager (LSM) Installer
#
# A comprehensive installation script that:
# - Provides an interactive UI for script selection
# - Handles dependencies automatically
# - Manages error cases and provides debugging
# - Ensures clean installation with proper permissions
#==============================================================================

#------------------------------------------------------------------------------
# Global Configuration
#------------------------------------------------------------------------------
# Terminal output color definitions
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

# Configuration
GITHUB_USER="BrunoAFK"
GITHUB_REPO="LSM"
GITHUB_BRANCH="dev"
INSTALL_DIR="/usr/local/lib/llama"
BIN_DIR="/usr/local/bin"
REPO_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO.git"

#------------------------------------------------------------------------------
# Error Management
#------------------------------------------------------------------------------
# Handles cleanup of temporary files and directories
# Returns the original exit code to maintain error state
cleanup_temp_files() {
    # Disable error handling during cleanup
    set +e
    trap - ERR

    debug_log "Starting cleanup of temporary files"
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"

    # Store the original exit code
    local exit_code=$?

    # Remove all temporary files created during script execution
    for tmp_file in /tmp/tmp.*; do
        if [[ -f "$tmp_file" || -d "$tmp_file" ]]; then
            debug_log "Removing temporary file/directory: $tmp_file"
            rm -rf "$tmp_file" 2>/dev/null || {
                debug_log "Failed to remove: $tmp_file, trying with sudo"
                sudo rm -rf "$tmp_file" 2>/dev/null
            }
        fi
    done

    debug_log "Cleanup completed"

    # Re-enable error handling
    set -e
    trap 'handle_error $? $LINENO' ERR

    return $exit_code
}

# Central error handler that processes all script failures
# Parameters: $1=exit_code, $2=line_number
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

#------------------------------------------------------------------------------
# Package Management
#------------------------------------------------------------------------------
# Cross-platform package installation handler
# Supports apt, yum, dnf, and brew package managers
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

# Verifies and installs all required system dependencies
ensure_requirements() {
    print_section_header "Checking and Installing Requirements"
    local required_packages=(jq dialog git curl)
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

        # Specific verification for dialog
        if [ "$package" = "dialog" ] && ! dialog --version >/dev/null 2>&1; then
            debug_log "Dialog installation verification failed"
            echo -e "${RED}Error: Dialog installation failed${NC}"
            exit 1
        fi

        echo -e "${GREEN}Successfully installed $package${NC}"
    done

    sleep 2
    debug_log "All required packages are now installed"
    return 0
}

#------------------------------------------------------------------------------
# Repository Management
#------------------------------------------------------------------------------
# Validates repository accessibility before installation
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

# Creates and configures temporary working directory
setup_temp_dir() {
    print_section_header "Setting up Temporary Directory"
    TEMP_DIR=$(mktemp -d)
    TEMP_FILE=$(mktemp)
    DESC_FILE=$(mktemp)

    # Consolidated cleanup trap for all temporary files and directories
    trap 'cleanup_temp_files' EXIT INT TERM
}

# Retrieves installation files from repository
clone_repository() {
    print_section_header "Cloning Repository"
    if ! git clone "$REPO_URL" "$TEMP_DIR/repo" 2>/dev/null; then
        echo -e "${RED}Error: Failed to clone repository${NC}"
        exit 1
    fi
}

# Prepares installation directory structure
create_directories() {
    print_section_header "Creating Installation Directories"
    sudo mkdir -p "$INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR/scripts"
}

#------------------------------------------------------------------------------
# Script Selection Interface
#------------------------------------------------------------------------------
sync_selections() {
    local dialog_list="$1"
    local output_file=$(mktemp)

    while IFS= read -r line; do
        if [ $((++count % 3)) -eq 1 ]; then
            name=$line
        elif [ $((count % 3)) -eq 2 ]; then
            desc=$line
        else
            if [ "${SELECTED_SCRIPTS[$name]+_}" ]; then
                echo "$name"
                echo "$desc"
                echo "on"
            else
                echo "$name"
                echo "$desc"
                echo "off"
            fi
        fi
    done <"$dialog_list" >"$output_file"

    mv "$output_file" "$dialog_list"
}
# Provides interactive UI for script selection
# Supports featured scripts, search, and bulk installation
select_scriptsb() {
    print_section_header "Script Selection"
    local scripts_dir="$TEMP_DIR/repo/scripts"
    debug_log "Starting select_scripts function"
    debug_log "Scripts directory: $scripts_dir"

    # Create temporary files
    local SCRIPT_LIST_FILE=$(mktemp)
    local FEATURED_LIST_FILE=$(mktemp)
    local ALL_LIST_FILE=$(mktemp)
    local FILTERED_LIST_FILE=$(mktemp)
    local CURRENT_SELECTIONS=$(mktemp)

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

    # Function to mark previously selected scripts
    mark_selections() {
        local input_file="$1"
        local output_file=$(mktemp)
        local count=0

        while IFS= read -r line; do
            ((count++))
            if [ $((count % 3)) -eq 1 ]; then
                # Check if script is in SELECTED_SCRIPTS
                if [ "${SELECTED_SCRIPTS[$line]+_}" ]; then
                    echo "$line"
                    read -r desc
                    echo "$desc"
                    echo "on"
                    continue
                fi
            fi
            echo "$line"
        done <"$input_file" >"$output_file"

        mv "$output_file" "$input_file"
    }

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
    0)
        debug_log "Installing all scripts"
        while IFS= read -r line; do
            if [ $((++count % 3)) -eq 1 ]; then
                SELECTED_SCRIPTS["$line"]=1
                debug_log "Adding all script: $line"
            fi
        done <"$ALL_LIST_FILE"
        return 0
        ;;
    1) ;;
    *)
        debug_log "Installation cancelled"
        return 1
        ;;
    esac

    # Show Featured Scripts Dialog
    while true; do
        mark_selections "$FEATURED_LIST_FILE"

        dialog --title "Featured Scripts" \
            --backtitle "Llama Script Manager Installer v${VERSION}" \
            --ok-label "Next" \
            --cancel-label "Skip" \
            --colors \
            --checklist "\Zn\Z3Featured Scripts\Zn (use SPACE to select/unselect):" \
            $DIALOG_HEIGHT $DIALOG_WIDTH $((DIALOG_HEIGHT - 8)) \
            --file "$FEATURED_LIST_FILE" \
            2>"$CURRENT_SELECTIONS"

        local featured_status=$?
        debug_log "Featured dialog status: $featured_status"

        # Process featured selections
        if [ -s "$CURRENT_SELECTIONS" ]; then
            # Clear previous selections from featured scripts
            while IFS= read -r line; do
                if [ $((++count % 3)) -eq 1 ]; then
                    unset "SELECTED_SCRIPTS[$line]"
                fi
            done <"$FEATURED_LIST_FILE"

            # Add new selections
            eval "selected_array=($(cat "$CURRENT_SELECTIONS"))"
            for selected in "${selected_array[@]}"; do
                selected=${selected//\"/}
                if [ -n "$selected" ]; then
                    SELECTED_SCRIPTS[$selected]=1
                    debug_log "Selected featured script: $selected"
                fi
            done
        fi

        break
    done

    # Exit if Skip was pressed
    if [ "$featured_status" -eq 1 ]; then
        debug_log "Featured scripts skipped, exiting"
        return 1
    fi

    # Always show market dialog unless ESC was pressed
    if [ "$featured_status" -ne 255 ]; then
        # All Scripts Dialog with Search
        current_list="$ALL_LIST_FILE"
        search_active=false
        last_search=""

        # Mark any featured selections in the market dialog
        if [ ${#SELECTED_SCRIPTS[@]} -gt 0 ]; then
            debug_log "Marking previously selected scripts in market dialog"
            mark_selections "$current_list"
        fi

        while true; do
            debug_log "Showing all scripts dialog with current_list: $current_list"

            dialog --title "Script Market" \
                --backtitle "Llama Script Manager Installer v${VERSION}" \
                --ok-label "Install Selected" \
                --cancel-label "Exit" \
                --help-button --help-label "Search" \
                --extra-button --extra-label "Show All" \
                --colors \
                --checklist "\Zn\Z2Available Scripts\Zn (use SPACE to select/unselect):\n\Z3Current filter: ${last_search:-none}\Zn" \
                $DIALOG_HEIGHT $DIALOG_WIDTH $((DIALOG_HEIGHT - 8)) \
                --file "$current_list" \
                2>"$CURRENT_SELECTIONS"

            local market_status=$?
            debug_log "Market dialog status: $market_status"

            case $market_status in
            0) # Install Selected
                debug_log "Processing final selections from all scripts dialog"
                # Clear all previous selections since market dialog is final
                SELECTED_SCRIPTS=()
                if [ -s "$CURRENT_SELECTIONS" ]; then
                    eval "selected_array=($(cat "$CURRENT_SELECTIONS"))"
                    for selected in "${selected_array[@]}"; do
                        selected=${selected//\"/}
                        if [ -n "$selected" ]; then
                            SELECTED_SCRIPTS[$selected]=1
                            debug_log "Added to final selection: $selected"
                        fi
                    done
                fi
                debug_log "Final selection complete, returning with success"
                break
                ;;
            1 | 255) # Exit or ESC
                debug_log "Exit selected or ESC pressed"
                return 1
                ;;
            2) # Search
                debug_log "Search button pressed"
                local search_term=$(dialog --title "Search Scripts" \
                    --backtitle "Llama Script Manager Installer v${VERSION}" \
                    --inputbox "Enter search term (leave empty to show all):" \
                    8 60 \
                    2>"$DESC_FILE")

                local search_status=$?
                debug_log "Search dialog status: $search_status"

                if [ $search_status -eq 0 ]; then
                    search_term=$(cat "$DESC_FILE")
                    if [ -n "$search_term" ]; then
                        debug_log "Searching for: '$search_term'"
                        filter_scripts "$search_term" "$ALL_LIST_FILE" "$FILTERED_LIST_FILE"
                        current_list="$FILTERED_LIST_FILE"
                        search_active=true
                        last_search="$search_term"
                    else
                        debug_log "Empty search term, showing all scripts"
                        current_list="$ALL_LIST_FILE"
                        search_active=false
                        last_search=""
                    fi
                fi
                # Re-mark selections after search
                mark_selections "$current_list"
                ;;
            3) # Show All
                debug_log "Show All button pressed"
                current_list="$ALL_LIST_FILE"
                search_active=false
                last_search=""
                # Re-mark selections after showing all
                mark_selections "$current_list"
                ;;
            esac
        done
    fi

    # At the end of select_scripts function
    if [ ${#SELECTED_SCRIPTS[@]} -gt 0 ]; then
        debug_log "Installation will proceed with selected scripts"
        return 0
    else
        debug_log "No scripts selected for installation"
        return 1
    fi
}

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
    local CURRENT_SELECTIONS=$(mktemp)

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

    # Function to mark previously selected scripts
    mark_selections() {
        local input_file="$1"
        local output_file=$(mktemp)
        local count=0

        while IFS= read -r line; do
            ((count++))
            if [ $((count % 3)) -eq 1 ]; then
                # Check if script is in SELECTED_SCRIPTS
                if [ "${SELECTED_SCRIPTS[$line]+_}" ]; then
                    echo "$line"
                    read -r desc
                    echo "$desc"
                    echo "on"
                    continue
                fi
            fi
            echo "$line"
        done <"$input_file" >"$output_file"

        mv "$output_file" "$input_file"
    }

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
    1) ;; # Continue with custom selection
    *)
        debug_log "Installation cancelled"
        return 1
        ;;
    esac

    # Show Featured Scripts Dialog
    local featured_selections=()
    while true; do
        mark_selections "$FEATURED_LIST_FILE"

        dialog --title "Featured Scripts" \
            --backtitle "Llama Script Manager Installer v${VERSION}" \
            --ok-label "Next" \
            --cancel-label "Exit" \
            --colors \
            --checklist "\Zn\Z3Featured Scripts\Zn (use SPACE to select/unselect):" \
            $DIALOG_HEIGHT $DIALOG_WIDTH $((DIALOG_HEIGHT - 8)) \
            --file "$FEATURED_LIST_FILE" \
            2>"$CURRENT_SELECTIONS"

        local featured_status=$?
        debug_log "Featured dialog status: $featured_status"

        # Process featured selections
        if [ -s "$CURRENT_SELECTIONS" ]; then
            eval "featured_selections=($(cat "$CURRENT_SELECTIONS"))"
            for selected in "${featured_selections[@]}"; do
                selected=${selected//\"/}
                if [ -n "$selected" ]; then
                    SELECTED_SCRIPTS[$selected]=1
                    debug_log "Selected featured script: $selected"
                fi
            done
        fi

        break
    done

    # Exit if ESC was pressed in featured dialog
    if [[ "$featured_status" -eq 255 || "$featured_status" -eq 1 ]]; then
        debug_log "Featured scripts dialog cancelled"
        return 1
    fi

    # Always show market dialog unless ESC was pressed
    if [ "$featured_status" -eq 0 ]; then
        # All Scripts Dialog with Search
        current_list="$ALL_LIST_FILE"
        search_active=false
        last_search=""

        # Mark any featured selections in the market dialog
        debug_log "Marking previously selected scripts in market dialog"
        mark_selections "$current_list"

        while true; do
            debug_log "Showing all scripts dialog with current_list: $current_list"
            cat $current_list
            debug_log "$(cat $current_list)"
            dialog --title "Script Market" \
                --backtitle "Llama Script Manager Installer v${VERSION}" \
                --ok-label "Install Selected" \
                --cancel-label "Exit" \
                --help-button --help-label "Search" \
                --extra-button --extra-label "Show All" \
                --colors \
                --checklist "\Zn\Z2Available Scripts\Zn (use SPACE to select/unselect):\n\Z3Current filter: ${last_search:-none}\Zn" \
                $DIALOG_HEIGHT $DIALOG_WIDTH $((DIALOG_HEIGHT - 8)) \
                --file "$current_list" \
                2>"$CURRENT_SELECTIONS"

            local market_status=$?
            debug_log "Market dialog status: $market_status"

            case $market_status in
            0) # Install Selected
                debug_log "Processing final selections from all scripts dialog"
                # Clear all previous selections since market dialog is final
                SELECTED_SCRIPTS=()
                if [ -s "$CURRENT_SELECTIONS" ]; then
                    eval "selected_array=($(cat "$CURRENT_SELECTIONS"))"
                    for selected in "${selected_array[@]}"; do
                        selected=${selected//\"/}
                        if [ -n "$selected" ]; then
                            SELECTED_SCRIPTS[$selected]=1
                            debug_log "Added to final selection: $selected"
                        fi
                    done
                fi
                debug_log "Final selection complete, returning with success"
                return 0
                ;;
            1 | 255) # Exit or ESC
                debug_log "Exit selected or ESC pressed"
                return 1
                ;;
            2) # Search
                debug_log "Search button pressed"
                local search_term=$(dialog --title "Search Scripts" \
                    --backtitle "Llama Script Manager Installer v${VERSION}" \
                    --inputbox "Enter search term (leave empty to show all):" \
                    8 60 \
                    2>&1)

                local search_status=$?
                debug_log "Search dialog status: $search_status"

                if [ $search_status -eq 0 ]; then
                    if [ -n "$search_term" ]; then
                        debug_log "Searching for: '$search_term'"
                        filter_scripts "$search_term" "$ALL_LIST_FILE" "$FILTERED_LIST_FILE"
                        current_list="$FILTERED_LIST_FILE"
                        search_active=true
                        last_search="$search_term"
                    else
                        debug_log "Empty search term, showing all scripts"
                        current_list="$ALL_LIST_FILE"
                        search_active=false
                        last_search=""
                    fi
                fi
                # Re-mark selections after search
                mark_selections "$current_list"
                ;;
            3) # Show All
                debug_log "Show All button pressed"
                current_list="$ALL_LIST_FILE"
                search_active=false
                last_search=""
                # Re-mark selections after showing all
                mark_selections "$current_list"
                ;;
            esac
        done
    fi

    # Final check for selected scripts
    if [ ${#SELECTED_SCRIPTS[@]} -gt 0 ]; then
        debug_log "Installation will proceed with selected scripts"
        return 0
    else
        debug_log "No scripts selected for installation"
        return 1
    fi
}

# Improve cleanup function
cleanup_temp_files() {
    # Disable error handling during cleanup
    set +e
    trap - ERR

    debug_log "Starting cleanup of temporary files"
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"

    # Store the original exit code
    local exit_code=$?

    # Remove all temporary files created during script execution
    for tmp_file in /tmp/tmp.*; do
        if [[ -f "$tmp_file" || -d "$tmp_file" ]]; then
            debug_log "Removing temporary file/directory: $tmp_file"
            rm -rf "$tmp_file" 2>/dev/null || {
                debug_log "Failed to remove: $tmp_file, trying with sudo"
                sudo rm -rf "$tmp_file" 2>/dev/null
            }
        fi
    done

    debug_log "Cleanup completed"

    # Re-enable error handling
    set -e
    trap 'handle_error $? $LINENO' ERR

    return $exit_code
}

#------------------------------------------------------------------------------
# Installation Process
#------------------------------------------------------------------------------
# Validates script executability and permissions
verify_script_execution() {
    local script="$1"
    debug_log "Verifying script execution: $script"

    # Check shebang
    local shebang=$(head -n 1 "$script")
    debug_log "Script shebang: $shebang"

    # Check permissions
    local perms=$(stat -c "%a" "$script")
    debug_log "Script permissions: $perms"

    # Try executing with various methods
    debug_log "Testing direct execution"
    if ! "$script" --help >/dev/null 2>&1; then
        debug_log "Direct execution failed, trying with bash"
        if ! bash "$script" --help >/dev/null 2>&1; then
            debug_log "Bash execution failed"
            return 1
        fi
    fi

    return 0
}

# Copies selected scripts to installation directory
copy_files() {
    print_section_header "Copying Files"
    debug_log "Number of selected scripts: ${#SELECTED_SCRIPTS[@]}"

    # Verify we have scripts to install
    if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
        debug_log "ERROR: No scripts selected for installation"
        echo -e "${RED}Error: No scripts selected for installation${NC}"
        exit 1
    fi

    # List selected scripts
    echo -e "${BLUE}Installing selected scripts:${NC}"
    for script_name in "${!SELECTED_SCRIPTS[@]}"; do
        debug_log "Script marked for installation: $script_name"
        echo -e "${GREEN}- $script_name${NC}"
    done

    # Copy main script and update paths
    debug_log "Copying main script 'llama'"
    sudo cp "$TEMP_DIR/repo/llama" "$INSTALL_DIR/llama"
    sudo chmod +x "$INSTALL_DIR/llama"

    # Update the script paths
    sudo sed -i "s|/opt/llama|$INSTALL_DIR|g" "$INSTALL_DIR/llama"

    # Copy selected scripts
    for script_name in "${!SELECTED_SCRIPTS[@]}"; do
        debug_log "Installing: $script_name"
        sudo cp "$TEMP_DIR/repo/scripts/$script_name" "$INSTALL_DIR/scripts/"
        sudo chmod +x "$INSTALL_DIR/scripts/$script_name"
    done

    # Verify installation
    debug_log "Verifying installation..."
    local installed_count=$(ls -1 "$INSTALL_DIR/scripts" 2>/dev/null | wc -l)
    debug_log "Number of installed scripts: $installed_count"

    if [ $installed_count -eq 0 ]; then
        debug_log "ERROR: No scripts found in installation directory"
        echo -e "${RED}Error: Installation verification failed${NC}"
        exit 1
    fi

    echo -e "${GREEN}Successfully installed ${installed_count} scripts${NC}"
    return 0
}

# Creates system-wide command symlink
create_symlink() {
    print_section_header "Creating Symlink"
    debug_log "Creating symlink from $INSTALL_DIR/llama to $BIN_DIR/llama"

    # Remove existing symlink if it exists
    if [ -L "$BIN_DIR/llama" ]; then
        debug_log "Removing existing symlink"
        sudo rm -f "$BIN_DIR/llama"
    fi

    # Create new symlink
    if ! sudo ln -sf "$INSTALL_DIR/llama" "$BIN_DIR/llama"; then
        debug_log "ERROR: Failed to create symlink"
        echo -e "${RED}Error: Failed to create symlink${NC}"
        exit 1
    fi

    # Verify symlink
    if [ ! -L "$BIN_DIR/llama" ]; then
        debug_log "ERROR: Symlink verification failed"
        echo -e "${RED}Error: Symlink verification failed${NC}"
        exit 1
    fi

    debug_log "Symlink created successfully"
    debug_log "Symlink details: $(ls -la $BIN_DIR/llama)"
}

# Removes dialog if it was temporarily installed
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
# Installation Orchestration
#------------------------------------------------------------------------------
# Coordinates the complete installation process
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

    # Verify symlink
    debug_log "Verifying installation"
    status_output=$($BIN_DIR/llama status)
    # Check if the output contains "Llama Script Manager Status"
    if [[ "$status_output" != *"Llama Script Manager Status"* ]]; then
        debug_log "ERROR: 'Llama Script Manager Status' not found in status output"
        echo -e "${RED}Error: 'Llama Script Manager Status' not found${NC}"
        exit 1
    fi

    echo -e "\n${GREEN}Installation completed successfully!${NC}"
    echo -e "Try these commands:"
    echo -e "${YELLOW}llama help${NC} - Show help"
    echo -e "${YELLOW}llama status${NC} - Show status"
    echo -e "${YELLOW}llama list${NC} - List available scripts"

    debug_log "Installation completed successfully"
    exit 0
}

# Initialize installation
main
