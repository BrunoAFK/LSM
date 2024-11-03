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

cleanup_temp_files() {
    # Disable error handling during cleanup
    set +e
    trap - ERR

    debug_log "Starting cleanup of temporary files"
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"

    # Store the original exit code
    local exit_code=$?

    # Remove temporary directory and its contents
    if [ -d "$TEMP_DIR" ]; then
        debug_log "Removing temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR" 2>/dev/null || {
            debug_log "Failed to remove directory: $TEMP_DIR"
            sudo rm -rf "$TEMP_DIR" 2>/dev/null
        }
    fi

    # Clean up all temp files created during this session
    for tmp_file in $(find /tmp -maxdepth 1 -name "tmp.*" -user $(id -u) -mmin -5); do
        debug_log "Cleaning up temporary file: $tmp_file"
        rm -f "$tmp_file" 2>/dev/null || {
            debug_log "Failed to remove file: $tmp_file"
            sudo rm -f "$tmp_file" 2>/dev/null
        }
    done

    # Remove specific temporary files
    for file in "$TEMP_FILE" "$DESC_FILE" "$SCRIPT_LIST_FILE" "$FEATURED_LIST_FILE" "$ALL_LIST_FILE" "$FILTERED_LIST_FILE"; do
        if [ -f "$file" ]; then
            debug_log "Removing temporary file: $file"
            rm -f "$file" 2>/dev/null || {
                debug_log "Failed to remove file: $file"
                sudo rm -f "$file" 2>/dev/null
            }
        fi
    done

    # Remove debug log if DEBUG is true
    if [ "$DEBUG" = true ] && [ -f "/tmp/dialog_debug.log" ]; then
        debug_log "Removing dialog debug log"
        rm -f "/tmp/dialog_debug.log" 2>/dev/null || sudo rm -f "/tmp/dialog_debug.log"
    fi

    debug_log "Cleanup completed"

    # Re-enable error handling
    set -e
    trap 'handle_error $? $LINENO' ERR

    # Return the original exit code
    return $exit_code
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

ensure_requirements() {
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
select_scriptsB() {
    print_section_header "Script Selection"
    local scripts_dir="$TEMP_DIR/repo/scripts"
    debug_log "Starting select_scripts function"
    debug_log "Scripts directory: $scripts_dir"

    # Create temporary files
    local SCRIPT_LIST_FILE=$(mktemp)
    local FEATURED_LIST_FILE=$(mktemp)
    local ALL_LIST_FILE=$(mktemp)
    local FILTERED_LIST_FILE=$(mktemp)

    # Download and parse script_list.json with better error handling
    debug_log "Downloading script_list.json"
    local json_url="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/script_list.json"
    debug_log "Attempting to download from: $json_url"

    # Use curl with detailed error reporting
    local json_content=$(curl -sS -w "\nHTTP_CODE:%{http_code}" "$json_url")
    local http_code=$(echo "$json_content" | grep "HTTP_CODE:" | cut -d":" -f2)
    json_content=$(echo "$json_content" | grep -v "HTTP_CODE:")

    debug_log "HTTP Response Code: $http_code"
    debug_log "Response Content Length: ${#json_content}"
    debug_log "Response Content: $json_content"

    # Check HTTP response
    if [ "$http_code" != "200" ]; then
        debug_log "ERROR: Failed to download script_list.json - HTTP $http_code"
        debug_log "Full Response: $json_content"
        echo -e "${RED}Error: Failed to download script list (HTTP $http_code)${NC}"
        return 1
    fi

    # Validate JSON content
    if ! echo "$json_content" | jq '.' >/dev/null 2>&1; then
        debug_log "ERROR: Invalid JSON content"
        debug_log "JSON Content (first 100 chars): ${json_content:0:100}"
        echo -e "${RED}Error: Invalid JSON format in script list${NC}"
        return 1
    fi

    # Save cleaned JSON
    echo "$json_content" >"$SCRIPT_LIST_FILE"
    debug_log "JSON content successfully validated and saved"

    # Prepare featured scripts list
    debug_log "Preparing featured scripts list"
    jq -r '.scripts[] | select(.rank | contains("Featured")) | "\(.name)\n\"\(.description)\"\noff"' "$SCRIPT_LIST_FILE" >"$FEATURED_LIST_FILE"

    # Prepare all scripts list
    debug_log "Preparing all scripts list"
    jq -r '.scripts[] | select(.path | contains("./scripts/")) | "\(.name)\n\"\(.description)\"\noff"' "$SCRIPT_LIST_FILE" >"$ALL_LIST_FILE"

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

    # Show Featured Scripts First
    local featured_count=$(wc -l <"$FEATURED_LIST_FILE")
    featured_count=$((featured_count / 3))
    debug_log "Found $featured_count featured scripts"

    if [ $featured_count -gt 0 ]; then
        local height=$((featured_count + 10))
        [[ $height -gt 40 ]] && height=40

        echo -e "${BLUE}Showing featured scripts...${NC}"
        dialog --title "Featured Scripts" \
            --backtitle "Llama Script Manager Installer v${VERSION}" \
            --extra-button --extra-label "Next" \
            --colors \
            --checklist "\Zn\Z3Featured Scripts\Zn (use SPACE to select/unselect):" \
            $height 100 $((height - 8)) \
            --file "$FEATURED_LIST_FILE" \
            2>"$DESC_FILE"

        dialog_status=$?

        # Process featured selections
        if [ $dialog_status -eq 0 ] || [ $dialog_status -eq 3 ]; then
            debug_log "Processing featured script selections"
            while IFS= read -r selected; do
                selected=${selected//\"/}
                if [ -n "$selected" ]; then
                    SELECTED_SCRIPTS[$selected]=1
                    debug_log "Selected featured script: $selected"
                fi
            done <"$DESC_FILE"
        elif [ $dialog_status -ne 3 ]; then
            debug_log "Featured script selection cancelled"
            return 1
        fi
    fi

    # Main Market Loop
    while true; do
        echo -e "${BLUE}Showing script marketplace...${NC}"
        # Show script selection dialog with all scripts
        if dialog --title "Script Market" \
            --backtitle "Llama Script Manager Installer v${VERSION}" \
            --extra-button --extra-label "Install All" \
            --extra-button --extra-label "Search" \
            --ok-label "Install Selected" \
            --cancel-label "Exit" \
            --colors \
            --checklist "\Zn\Z2Available Scripts\Zn (use SPACE to select/unselect):" \
            40 100 32 \
            --file "$ALL_LIST_FILE" \
            2>"$DESC_FILE"; then

            dialog_status=$?
            debug_log "Market dialog returned status: $dialog_status"

            case $dialog_status in
            0) # Normal selection
                debug_log "Processing normal script selection"
                while IFS= read -r selected; do
                    selected=${selected//\"/}
                    if [ -n "$selected" ]; then
                        SELECTED_SCRIPTS[$selected]=1
                        debug_log "Selected script: $selected"
                    fi
                done <"$DESC_FILE"
                break
                ;;
            3) # Install All
                debug_log "Install All selected"
                while IFS= read -r line; do
                    if [ $((++count % 3)) -eq 1 ]; then
                        SELECTED_SCRIPTS["$line"]=1
                        debug_log "Adding all script: $line"
                    fi
                done <"$ALL_LIST_FILE"
                break
                ;;
            4) # Search
                debug_log "Search requested"
                search_term=$(dialog --title "Search Scripts" \
                    --backtitle "Llama Script Manager Installer v${VERSION}" \
                    --inputbox "Enter search term (leave empty to show all):" \
                    8 60 \
                    2>&1 >/dev/tty)

                if [ $? -eq 0 ]; then
                    debug_log "Searching for: $search_term"
                    filter_scripts "$search_term" "$ALL_LIST_FILE" "$FILTERED_LIST_FILE"
                    cp "$FILTERED_LIST_FILE" "$ALL_LIST_FILE"
                else
                    debug_log "Search cancelled"
                fi
                continue
                ;;
            *) # Cancel
                debug_log "Market selection cancelled"
                if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
                    return 1
                fi
                break
                ;;
            esac
        else
            debug_log "Market dialog cancelled"
            if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
                return 1
            fi
            break
        fi
    done

    # Clean up temporary files
    rm -f "$SCRIPT_LIST_FILE" "$FEATURED_LIST_FILE" "$ALL_LIST_FILE" "$FILTERED_LIST_FILE"

    debug_log "Script selection completed with ${#SELECTED_SCRIPTS[@]} scripts selected"
    return 0
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

    # Download and parse script_list.json with better error handling
    debug_log "Downloading script_list.json"
    local json_url="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/script_list.json"
    debug_log "Attempting to download from: $json_url"

    # Use curl with detailed error reporting
    local json_content=$(curl -sS -w "\nHTTP_CODE:%{http_code}" "$json_url")
    local http_code=$(echo "$json_content" | grep "HTTP_CODE:" | cut -d":" -f2)
    json_content=$(echo "$json_content" | grep -v "HTTP_CODE:")

    debug_log "HTTP Response Code: $http_code"
    debug_log "Response Content Length: ${#json_content}"
    debug_log "Response Content: $json_content"

    # Check HTTP response
    if [ "$http_code" != "200" ]; then
        debug_log "ERROR: Failed to download script_list.json - HTTP $http_code"
        debug_log "Full Response: $json_content"
        echo -e "${RED}Error: Failed to download script list (HTTP $http_code)${NC}"
        return 1
    fi

    # Validate JSON content
    if ! echo "$json_content" | jq '.' >/dev/null 2>&1; then
        debug_log "ERROR: Invalid JSON content"
        debug_log "JSON Content (first 100 chars): ${json_content:0:100}"
        echo -e "${RED}Error: Invalid JSON format in script list${NC}"
        return 1
    fi

    # Save cleaned JSON
    echo "$json_content" >"$SCRIPT_LIST_FILE"
    debug_log "JSON content successfully validated and saved"

    # Prepare featured scripts list
    debug_log "Preparing featured scripts list"
    jq -r '.scripts[] | select(.rank | contains("Featured")) | "\(.name)\n\"\(.description)\"\noff"' "$SCRIPT_LIST_FILE" >"$FEATURED_LIST_FILE"

    # Prepare all scripts list
    debug_log "Preparing all scripts list"
    jq -r '.scripts[] | select(.path | contains("./scripts/")) | "\(.name)\n\"\(.description)\"\noff"' "$SCRIPT_LIST_FILE" >"$ALL_LIST_FILE"

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

    # Show Featured Scripts First
    local featured_count=$(wc -l <"$FEATURED_LIST_FILE")
    featured_count=$((featured_count / 3))
    debug_log "Found $featured_count featured scripts"

    # Modified Featured Scripts Dialog
    if [ $featured_count -gt 0 ]; then
        local height=$((featured_count + 10))
        [[ $height -gt 40 ]] && height=40

        echo -e "${BLUE}Showing featured scripts...${NC}"
        dialog --title "Featured Scripts" \
            --backtitle "Llama Script Manager Installer v${VERSION}" \
            --no-ok \
            --extra-button --extra-label "Next" \
            --colors \
            --checklist "\Zn\Z3Featured Scripts\Zn (use SPACE to select/unselect):" \
            $height 100 $((height - 8)) \
            --file "$FEATURED_LIST_FILE" \
            2>"$DESC_FILE"

        dialog_status=$?

        case $dialog_status in
        3) # Next button
            debug_log "Next button pressed, processing selections"
            while IFS= read -r selected; do
                selected=${selected//\"/}
                if [ -n "$selected" ]; then
                    SELECTED_SCRIPTS[$selected]=1
                    debug_log "Selected featured script: $selected"
                fi
            done <"$DESC_FILE"
            ;;
        *) # Cancel
            debug_log "Featured script selection cancelled"
            return 1
            ;;
        esac
    fi

    # Modified Market Loop
    while true; do
        echo -e "${BLUE}Showing script marketplace...${NC}"

        dialog --title "Script Market" \
            --backtitle "Llama Script Manager Installer v${VERSION}" \
            --extra-button --extra-label "Install All" \
            --help-button --help-label "Search" \
            --ok-label "Install Selected" \
            --cancel-label "Exit" \
            --colors \
            --checklist "\Zn\Z2Available Scripts\Zn (use SPACE to select/unselect):" \
            40 100 32 \
            --file "$ALL_LIST_FILE" \
            2>"$DESC_FILE"

        dialog_status=$?
        debug_log "Market dialog returned status: $dialog_status"

        case $dialog_status in
        0) # Install Selected
            debug_log "Processing script selections"
            while IFS= read -r selected; do
                selected=${selected//\"/}
                if [ -n "$selected" ]; then
                    SELECTED_SCRIPTS[$selected]=1
                    debug_log "Selected script: $selected"
                fi
            done <"$DESC_FILE"
            return 0
            ;;
        2) # Search (Help button)
            debug_log "Search requested"
            search_term=$(dialog --title "Search Scripts" \
                --backtitle "Llama Script Manager Installer v${VERSION}" \
                --inputbox "Enter search term (leave empty to show all):" \
                8 60 \
                2>&1)

            if [ $? -eq 0 ]; then
                debug_log "Searching for: $search_term"
                filter_scripts "$search_term" "$ALL_LIST_FILE" "$FILTERED_LIST_FILE"
                cp "$FILTERED_LIST_FILE" "$ALL_LIST_FILE"
            fi
            continue
            ;;
        3) # Install All
            debug_log "Install All selected"
            count=0
            while IFS= read -r line; do
                if [ $((++count % 3)) -eq 1 ]; then
                    SELECTED_SCRIPTS["$line"]=1
                    debug_log "Adding all script: $line"
                fi
            done <"$ALL_LIST_FILE"
            return 0
            ;;
        *) # Exit
            debug_log "Market selection cancelled"
            if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
                return 1
            fi
            return 0
            ;;
        esac
    done
}

#------------------------------------------------------------------------------
# Installation Functions
#------------------------------------------------------------------------------
copy_filesB() {
    print_section_header "Copying Files"
    debug_log "Number of selected scripts: ${#SELECTED_SCRIPTS[@]}"

    # Add verification of selected scripts
    if [ ${#SELECTED_SCRIPTS[@]} -eq 0 ]; then
        debug_log "ERROR: No scripts selected for installation"
        echo -e "${RED}Error: No scripts selected for installation${NC}"
        exit 1
    fi

    # List all selected scripts for verification
    echo -e "${BLUE}Installing selected scripts:${NC}"
    for script_name in "${!SELECTED_SCRIPTS[@]}"; do
        debug_log "Script marked for installation: $script_name"
        echo -e "${GREEN}- $script_name${NC}"
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
        echo -e "${RED}Error: Scripts directory not found${NC}"
        exit 1
    fi
}


copy_files() {
    print_section_header "Copying Files"
    debug_log "Number of selected scripts: ${#SELECTED_SCRIPTS[@]}"

    # Verification of selected scripts
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

    # Copy main script with error checking
    debug_log "Copying main script 'llama'"
    if ! sudo cp "$TEMP_DIR/repo/llama" "$INSTALL_DIR/llama"; then
        debug_log "ERROR: Failed to copy main script"
        echo -e "${RED}Error: Failed to copy main script${NC}"
        exit 1
    fi
    sudo chmod +x "$INSTALL_DIR/llama"

    # Copy selected scripts with error checking
    local install_success=false
    if [ -d "$TEMP_DIR/repo/scripts" ]; then
        for script in "$TEMP_DIR/repo/scripts"/*; do
            if [ -f "$script" ]; then
                script_name=$(basename "$script")
                debug_log "Checking script: $script_name"
                if [ "${SELECTED_SCRIPTS[$script_name]:-0}" -eq 1 ]; then
                    echo -e "${GREEN}Installing: $script_name${NC}"
                    if ! sudo cp "$script" "$INSTALL_DIR/scripts/"; then
                        debug_log "ERROR: Failed to copy $script_name"
                        echo -e "${RED}Error: Failed to copy $script_name${NC}"
                        continue
                    fi
                    sudo chmod +x "$INSTALL_DIR/scripts/$script_name"
                    install_success=true
                fi
            fi
        done
    else
        debug_log "ERROR: Scripts directory not found"
        echo -e "${RED}Error: Scripts directory not found${NC}"
        exit 1
    fi

    if [ "$install_success" = false ]; then
        debug_log "ERROR: No scripts were successfully installed"
        echo -e "${RED}Error: No scripts were successfully installed${NC}"
        exit 1
    fi
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
