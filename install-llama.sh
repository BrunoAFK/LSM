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
VERSION="1.0.26"

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
        echo -e "${BLUE}DEBUG: $1${NC}" >&2  # Write to stderr
        echo "$(date '+%Y-%m-%d %H:%M:%S') - DEBUG: $1" >> "/tmp/lsm_install_debug.log"
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
select_scriptsBACK() {
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

    # Debug: Show content of TEMP_FILE before dialog
    debug_log "Content of TEMP_FILE before dialog:"
    if [ "$DEBUG" = true ]; then
        cat "$TEMP_FILE"
    fi

    # Store dialog command and show if debugging
    DIALOG_CMD="dialog --title 'Script Selection' \
        --backtitle 'Llama Script Manager Installer v${VERSION}' \
        --extra-button --extra-label 'Install All' \
        --checklist 'Select scripts to install (use SPACE to select/unselect):' \
        $height 100 $((height - 8)) \
        --file '$TEMP_FILE'"

    debug_log "Dialog command: $DIALOG_CMD"

    # Run dialog with conditional debug output
    if [ "$DEBUG" = true ]; then
        dialog --title "Script Selection" \
            --backtitle "Llama Script Manager Installer v${VERSION}" \
            --extra-button --extra-label "Install All" \
            --checklist "Select scripts to install (use SPACE to select/unselect):" \
            $height 100 $((height - 8)) \
            --file "$TEMP_FILE" \
            2> >(tee "$DESC_FILE" >/tmp/dialog_debug.log)
    else
        dialog --title "Script Selection" \
            --backtitle "Llama Script Manager Installer v${VERSION}" \
            --extra-button --extra-label "Install All" \
            --checklist "Select scripts to install (use SPACE to select/unselect):" \
            $height 100 $((height - 8)) \
            --file "$TEMP_FILE" \
            2>"$DESC_FILE"
    fi

    # Store and debug dialog exit status
    dialog_status=$?
    debug_log "Dialog exit status: $dialog_status"

    # Debug: Show content of DESC_FILE and debug log
    if [ "$DEBUG" = true ]; then
        debug_log "Content of DESC_FILE after dialog:"
        cat "$DESC_FILE"

        debug_log "Dialog debug output:"
        [ -f "/tmp/dialog_debug.log" ] && cat "/tmp/dialog_debug.log"
    fi

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
    elif [ $dialog_status -eq 3 ]; then # Extra button returns 3
        # Install all scripts
        # clear
        echo -e "\n${BLUE}Installing all scripts${NC}"
        debug_log "Install All option selected"

        local found_scripts=false
        while IFS= read -r script; do
            script_basename=$(basename "$script")
            selected_scripts[$script_basename]=1
            echo "  - $script_basename"
            found_scripts=true
            debug_log "Added to selection: $script_basename"
        done < <(find "$scripts_dir" -type f -name "*")

        if [ "$found_scripts" = false ]; then
            debug_log "No scripts found in $scripts_dir"
            echo -e "${RED}Error: No scripts found to install${NC}"
            exit 1
        fi

        debug_log "All scripts have been selected for installation"
    else
        echo -e "\n${YELLOW}Installation cancelled by user${NC}"
        exit 1
    fi
}

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

        # Log package manager detection
        if command -v apt-get >/dev/null 2>&1; then
            debug_log "Using apt-get to install dialog"
        elif command -v yum >/dev/null 2>&1; then
            debug_log "Using yum to install dialog"
        elif command -v dnf >/dev/null 2>&1; then
            debug_log "Using dnf to install dialog"
        elif command -v brew >/dev/null 2>&1; then
            debug_log "Using brew to install dialog"
        else
            debug_log "ERROR: No supported package manager found"
        fi

        # ... [rest of package manager installation code remains the same]
    fi

    debug_log "Building script list for dialog"
    # Clear the temp file before writing to it
    > "$TEMP_FILE"
    
    local script_num=1
    while IFS= read -r -d '' script; do
        script_basename=$(basename "$script")
        debug_log "Processing script: $script_basename"

        # Extract description more safely
        description="No description available"
        if [ -f "$script" ]; then
            desc=$(head -n 20 "$script" | grep -i "^#.*description:" |
                head -n 1 | sed 's/^#[ ]*[Dd]escription:[ ]*//')
            [ -n "$desc" ] && description=${desc:0:60}
        fi
        script_descriptions[$script_basename]=$description

        debug_log "Adding to dialog: $script_basename with description: $description"
        printf '%s\n' "$script_basename" "\"$description\"" "off" >>"$TEMP_FILE"
        ((script_num++))
    done < <(find "$scripts_dir" -type f -name "*" -print0)

    debug_log "Total scripts processed: $((script_num-1))"

    # Calculate dialog dimensions
    local height=$((script_num + 10))
    [[ $height -gt 40 ]] && height=40
    debug_log "Dialog height calculated as: $height"

    debug_log "Launching dialog command..."
    
    # Run dialog with output to both debug log and DESC_FILE
    if [ "$DEBUG" = true ]; then
        debug_log "Running dialog in debug mode"
        dialog --title "Script Selection" \
            --backtitle "Llama Script Manager Installer v${VERSION}" \
            --extra-button --extra-label "Install All" \
            --checklist "Select scripts to install (use SPACE to select/unselect):" \
            $height 100 $((height - 8)) \
            --file "$TEMP_FILE" \
            2> >(tee "$DESC_FILE" >/tmp/dialog_debug.log)
    else
        debug_log "Running dialog in normal mode"
        dialog --title "Script Selection" \
            --backtitle "Llama Script Manager Installer v${VERSION}" \
            --extra-button --extra-label "Install All" \
            --checklist "Select scripts to install (use SPACE to select/unselect):" \
            $height 100 $((height - 8)) \
            --file "$TEMP_FILE" \
            2>"$DESC_FILE"
    fi

    # Store and debug dialog exit status
    dialog_status=$?
    debug_log "Dialog exit status: $dialog_status"
    
    # Debug the contents of DESC_FILE right after dialog
    debug_log "DESC_FILE contents after dialog:"
    debug_log "$(cat "$DESC_FILE")"

    if [ $dialog_status -eq 0 ]; then
        debug_log "Processing normal selection"
        # ... [rest of normal selection processing]
    elif [ $dialog_status -eq 3 ]; then
        debug_log "Install All option selected"
        clear
        echo -e "\n${BLUE}Installing all scripts${NC}"
        
        while IFS= read -r script; do
            script_basename=$(basename "$script")
            selected_scripts[$script_basename]=1
            echo "  - $script_basename"
            debug_log "Selected for installation: $script_basename"
        done < <(find "$scripts_dir" -type f -name "*")
        
        debug_log "Completed Install All selection process"
    else
        debug_log "Dialog cancelled with status $dialog_status"
        echo -e "\n${YELLOW}Installation cancelled by user${NC}"
        exit 1
    fi
    
    debug_log "Exiting select_scripts function normally"
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
