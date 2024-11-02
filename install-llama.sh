#!/bin/bash

# Llama Script Manager Installer
# This script handles the first-time installation of LSM from GitHub

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${YELLOW}Checking requirements...${NC}"

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
    echo -e "${YELLOW}Checking repository availability...${NC}"

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
    echo -e "${YELLOW}Setting up temporary directory...${NC}"
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT
    echo "Using temporary directory: $TEMP_DIR"
}

# Clone repository
clone_repository() {
    echo -e "${YELLOW}Cloning repository...${NC}"
    if ! git clone "$REPO_URL" "$TEMP_DIR/repo" 2>/dev/null; then
        echo -e "${RED}Error: Failed to clone repository${NC}"
        exit 1
    fi
}

# Create directories
create_directories() {
    echo -e "${YELLOW}Creating installation directories...${NC}"
    sudo mkdir -p "$INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR/scripts"
}

# Script selection interface with additional debugging
select_scripts() {
    local scripts_dir="$TEMP_DIR/repo/scripts"
    if [ ! -d "$scripts_dir" ] || [ -z "$(ls -A "$scripts_dir")" ]; then
        echo -e "${YELLOW}Warning: No scripts found in repository${NC}"
        return
    fi

    declare -A selected_scripts
    local all_scripts=()

    # Collect all available scripts
    echo -e "${BLUE}Collecting available scripts...${NC}"
    while IFS= read -r script; do
        script_basename=$(basename "$script")
        all_scripts+=("$script_basename")
        selected_scripts["$script_basename"]=0
        echo "Found script: $script_basename"
    done < <(find "$scripts_dir" -type f -name "*")

    echo -e "${BLUE}Initial selection status of scripts:${NC}"
    for script in "${all_scripts[@]}"; do
        echo "Script: $script, Selected: ${selected_scripts[$script]}"
    done

    while true; do
        clear
        echo -e "${BLUE}Available Scripts:${NC}"
        echo "0) Install All"
        echo "A) Toggle All"

        local idx=1
        for script in "${all_scripts[@]}"; do
            local status="${selected_scripts[$script]}"
            local marker
            if [[ "$status" -eq 1 ]]; then
                marker="[×]"
            else
                marker="[ ]"
            fi
            printf "%d) %s %s\n" $idx "$marker" "$script"
            ((idx++))
        done

        echo -e "\nC) Continue with installation"
        echo -e "Q) Quit installation"

        echo -e "\n${YELLOW}Select an option (0-$((idx - 1)), A, C, Q):${NC} "
        read -r choice

        case "$choice" in
        [0-9]*)
            if [ "$choice" -eq 0 ]; then
                # Install all
                for script in "${all_scripts[@]}"; do
                    selected_scripts["$script"]=1
                done
            elif [ "$choice" -le "${#all_scripts[@]}" ]; then
                # Toggle individual script
                local script="${all_scripts[$((choice - 1))]}"
                selected_scripts["$script"]=$((1 - ${selected_scripts[$script]:-0}))
            fi
            ;;
        [Aa])
            # Toggle all
            local first_value="${selected_scripts[${all_scripts[0]}]}"
            local new_value=$((1 - ${first_value:-0}))
            for script in "${all_scripts[@]}"; do
                selected_scripts["$script"]=$new_value
            done
            ;;
        [Cc])
            # Continue with installation
            break
            ;;
        [Qq])
            echo -e "${YELLOW}Installation cancelled by user${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option, please try again.${NC}"
            ;;
        esac
    done

    # Final debug output to show selected scripts after selection
    echo -e "${BLUE}Final selection status of scripts:${NC}"
    for script in "${all_scripts[@]}"; do
        echo "Script: $script, Selected: ${selected_scripts[$script]}"
    done
}


# Copy files
# Copy files with enhanced debugging
copy_files() {
    echo -e "${YELLOW}Copying files...${NC}"

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
    echo -e "${YELLOW}Creating symlink...${NC}"
    sudo ln -sf "$INSTALL_DIR/llama" "$BIN_DIR/llama"
}

# Main installation process
main() {
    echo -e "${GREEN}Starting Llama Script Manager Installation...${NC}"

    check_requirements
    check_repository
    setup_temp_dir
    clone_repository
    create_directories
    select_scripts
    copy_files
    create_symlink

    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "Run ${YELLOW}llama help${NC} to get started."
}

main
