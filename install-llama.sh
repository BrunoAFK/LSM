#!/bin/bash

# Llama Script Manager Installer
# This script handles the first-time installation of LSM from GitHub

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error handling
set -e  # Exit on error
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
    
    if ! command -v git &> /dev/null; then
        echo -e "${RED}Error: git is not installed${NC}"
        echo "Please install git first:"
        echo "  For Ubuntu/Debian: sudo apt-get install git"
        echo "  For MacOS: brew install git"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
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

# Copy files
copy_files() {
    echo -e "${YELLOW}Copying files...${NC}"
    
    if [ ! -f "$TEMP_DIR/repo/llama" ]; then
        echo -e "${RED}Error: Main script 'llama' not found in repository${NC}"
        exit 1
    fi
    
    sudo cp "$TEMP_DIR/repo/llama" "$INSTALL_DIR/llama"
    sudo chmod +x "$INSTALL_DIR/llama"
    
    if [ -d "$TEMP_DIR/repo/scripts" ]; then
        sudo cp -r "$TEMP_DIR/repo/scripts/"* "$INSTALL_DIR/scripts/" 2>/dev/null || true
        sudo find "$INSTALL_DIR/scripts" -type f -exec chmod +x {} \;
    else
        echo -e "${YELLOW}Warning: No scripts directory found${NC}"
    fi
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
    copy_files
    create_symlink
    
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "Run ${YELLOW}llama help${NC} to get started."
}

main