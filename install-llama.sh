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
VERSION="1.0.12"

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

# Check required tools
check_requirements() {
    echo -e "${YELLOW}Checking requirements... (Installer v${VERSION})${NC}"

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
    echo -e "${YELLOW}Checking repository availability... (Installer v${VERSION})${NC}"

    if ! curl --output /dev/null --silent --head --fail "https://github.com/$GITHUB_USER/$GITHUB_REPO"; then
        echo -e "${RED}Error: Repository $REPO_URL is not accessible${NC}"
        echo "Please check:"
        echo "  1. Repository exists and is public"
        echo "  2. Your internet connection"
        echo "  3. GitHub is accessible"
        exit 1
    fi
}

# Setup temporary directory
setup_temp_dir() {
    echo -e "${YELLOW}Setting up temporary directory... (Installer v${VERSION})${NC}"
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT
    echo "Using temporary directory: $TEMP_DIR"
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

    # Create temporary files for dialog with error handling
    local tempfile
    local descfile
    tempfile=$(mktemp) || { echo "Failed to create temp file"; exit 1; }
    descfile=$(mktemp) || { rm -f "$tempfile"; echo "Failed to create temp file"; exit 1; }
    
    # Ensure cleanup on exit
    trap 'rm -f "$tempfile" "$descfile"' EXIT

    # Build the checklist options
    local script_num=1
    while IFS= read -r -d '' script; do
        script_basename=$(basename "$script")
        
        # Extract description more safely
        description="No description available"
        if [ -f "$script" ]; then
            desc=$(head -n 20 "$script" | grep -i "^#.*description:" | 
                  head -n 1 | sed 's/^#[ ]*[Dd]escription:[ ]*//')
            [ -n "$desc" ] && description=${desc:0:60}  # Limit description length
        fi
        script_descriptions[$script_basename]=$description
        
        printf '%s\n' "$script_basename" "\"$description\"" "off" >> "$tempfile"
        ((script_num++))
    done < <(find "$scripts_dir" -type f -name "*" -print0)

    # Calculate dialog dimensions based on number of scripts
    local height=$((script_num + 10))
    [[ $height -gt 40 ]] && height=40  # Max height
    
    # Display dialog checklist
    dialog --title "Script Selection" \
           --backtitle "Llama Script Manager Installer v${VERSION}" \
           --checklist "Select scripts to install (use SPACE to select/unselect):" \
           $height 100 $((height-8)) \
           --file "$tempfile" \
           2>"$descfile"

    local dialog_status=$?

    # Process selection
    if [ $dialog_status -eq 0 ]; then
        # Reset all selections
        for script in "${!selected_scripts[@]}"; do
            selected_scripts[$script]=0
        done

        # Read selected scripts safely
        while IFS= read -r selected; do
            selected=${selected//\"/}
            [ -n "$selected" ] && selected_scripts[$selected]=1
        done < <(tr ' ' '\n' < "$descfile" | grep -v '^$')

        # Show selected scripts
        clear
        echo -e "\n${BLUE}Selected scripts to install:${NC}"
        for script in "${!selected_scripts[@]}"; do
            [ "${selected_scripts[$script]}" -eq 1 ] && echo "  - $script"
        done
    else
        echo -e "\n${YELLOW}Installation cancelled by user${NC}"
        exit 1
    fi
}


# Copy files
# Copy files with enhanced debugging
copy_files() {
    echo -e "${YELLOW}Copying files... (Installer v${VERSION})${NC}"

    # Show the structure of the cloned repository
    echo -e "${BLUE}Contents of the cloned repository:${NC}"
    tree "$TEMP_DIR/repo"  # Use 'tree' command to show the directory structure. Install it if it's not available.

    if [ ! -f "$TEMP_DIR/repo/llama" ]; then
        echo -e "${RED}Error: Main script 'llama' not found in repository${NC}"
        exit 1
    fi

    # Show the contents of the 'scripts' directory
    if [ -d "$TEMP_DIR/repo/scripts" ]; then
        echo -e "${BLUE}Contents of the 'scripts' directory:${NC}"
        ls -l "$TEMP_DIR/repo/scripts"
    else
        echo -e "${RED}'scripts' directory not found in the cloned repository${NC}"
    fi

    # Copy main script
    echo -e "${YELLOW}Copying main script 'llama'...${NC}"
    sudo cp "$TEMP_DIR/repo/llama" "$INSTALL_DIR/llama"
    sudo chmod +x "$INSTALL_DIR/llama"

    # Debugging the selected_scripts associative array
    echo -e "${BLUE}Debugging: Selected scripts before copying...${NC}"
    for script_name in "${!selected_scripts[@]}"; do
        echo "Script: $script_name, Selected: ${selected_scripts[$script_name]}"
    done

    # Copy selected scripts
    if [ -d "$TEMP_DIR/repo/scripts" ]; then
        echo -e "${YELLOW}Checking which scripts are selected for copying...${NC}"
        for script in "$TEMP_DIR/repo/scripts"/*; do
            if [ -f "$script" ]; then
                script_name=$(basename "$script")

                # Show the current script and its selection status
                echo -e "Script: $script_name, Selected: ${selected_scripts[$script_name]:-0}"

                # Use a default value of 0 if selected_scripts[$script_name] is unset or not a valid integer
                if [ "${selected_scripts[$script_name]:-0}" -eq 1 ] 2>/dev/null; then
                    echo -e "${GREEN}Installing: $script_name${NC}"
                    sudo cp "$script" "$INSTALL_DIR/scripts/"
                    sudo chmod +x "$INSTALL_DIR/scripts/$script_name"
                else
                    echo -e "${RED}Skipping: $script_name (not selected)${NC}"
                fi
            fi
        done
    fi

    # Final check after copying
    echo -e "${BLUE}Contents of the installation directory '$INSTALL_DIR/scripts':${NC}"
    ls -l "$INSTALL_DIR/scripts"
}


# Create symlink
create_symlink() {
    echo -e "${YELLOW}Creating symlink... (Installer v${VERSION})${NC}"
    sudo ln -sf "$INSTALL_DIR/llama" "$BIN_DIR/llama"
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

    echo -e "${GREEN}Installation v${VERSION} completed successfully!${NC}"
    echo -e "Run ${YELLOW}llama help${NC} to get started."
}

main
