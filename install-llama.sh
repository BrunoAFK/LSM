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
VERSION="1.0.10"

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

# Script selection interface with additional debugging
select_scripts() {
    local scripts_dir="$TEMP_DIR/repo/scripts"
    if [ ! -d "$scripts_dir" ] || [ -z "$(ls -A "$scripts_dir")" ]; then
        echo -e "${YELLOW}Warning: No scripts found in repository${NC}"
        return
    fi

    local all_scripts=()

    # Collect all available scripts and their descriptions
    echo -e "${BLUE}Collecting available scripts... (Installer v${VERSION})${NC}"
    while IFS= read -r script; do
        script_basename=$(basename "$script")
        all_scripts+=("$script_basename")
        selected_scripts["$script_basename"]=0
        
        # Extract description from script file
        if [ -f "$script" ]; then
            description=$(awk '/^#/ && !done {sub(/^# ?/,""); print; if($0=="") done=1}' "$script" | \
                         grep -i "description:" | \
                         sed 's/^[Dd]escription: *//')
            
            if [ -z "$description" ]; then
                description="No description available"
            fi
            script_descriptions["$script_basename"]="$description"
        fi
    done < <(find "$scripts_dir" -type f -name "*")

    # Enable terminal mouse and keyboard input
    tput smcup
    stty -echo
    printf "\033[?1000h"  # Enable mouse tracking
    
    local selected_idx=0
    local scroll_pos=0
    local max_display=10

    while true; do
        clear
        echo -e "${BLUE}Available Scripts (Installer v${VERSION})${NC}"
        echo -e "${YELLOW}Use UP/DOWN arrows or mouse to select, SPACE to toggle, ENTER to continue, Q to quit${NC}\n"

        # Display scripts with scrolling
        local displayed=0
        for ((i=scroll_pos; i<${#all_scripts[@]} && displayed<max_display; i++)); do
            local script="${all_scripts[$i]}"
            local status="${selected_scripts[$script]}"
            local marker
            if [[ "$status" -eq 1 ]]; then
                marker="[×]"
            else
                marker="[ ]"
            fi

            # Highlight current selection
            if [ $i -eq $selected_idx ]; then
                echo -en "\033[7m"  # Reverse video
            fi

            printf "%-3d %s %-30s %s\n" \
                   $((i+1)) "$marker" "$script" "${script_descriptions[$script]}"

            if [ $i -eq $selected_idx ]; then
                echo -en "\033[0m"  # Normal video
            fi
            ((displayed++))
        done

        # Read a single character or mouse event
        read -rsn1 key
        case "$key" in
            $'\x1B')  # ESC sequence
                read -rsn2 key
                case "$key" in
                    '[A')  # Up arrow
                        ((selected_idx > 0)) && ((selected_idx--))
                        if ((selected_idx < scroll_pos)); then
                            ((scroll_pos--))
                        fi
                        ;;
                    '[B')  # Down arrow
                        ((selected_idx < ${#all_scripts[@]}-1)) && ((selected_idx++))
                        if ((selected_idx >= scroll_pos + max_display)); then
                            ((scroll_pos++))
                        fi
                        ;;
                esac
                ;;
            ' ')  # Space
                local script="${all_scripts[$selected_idx]}"
                selected_scripts["$script"]=$((1 - ${selected_scripts[$script]:-0}))
                ;;
            $'\x0A')  # Enter
                break
                ;;
            'q'|'Q')
                echo -e "\n${YELLOW}Installation cancelled by user${NC}"
                # Cleanup terminal settings
                printf "\033[?1000l"  # Disable mouse tracking
                stty echo
                tput rmcup
                exit 0
                ;;
        esac
    done

    # Cleanup terminal settings
    printf "\033[?1000l"  # Disable mouse tracking
    stty echo
    tput rmcup
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
