#!/bin/bash

# Llama Script Manager Installer
# This script handles the first-time installation of LSM from GitHub

echo "Installing Llama Script Manager..."
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

INSTALL_DIR="/usr/local/lib/llama"
BIN_DIR="/usr/local/bin"

# Clone repository
git clone "https://github.com/BrunoAFK/LSM.git" "$TEMP_DIR/repo"

if [ -d "$TEMP_DIR/repo" ]; then
    # Create installation directories
    sudo mkdir -p "$INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR/scripts"
    
    # Copy files
    sudo cp "$TEMP_DIR/repo/llama" "$INSTALL_DIR/llama"
    sudo chmod +x "$INSTALL_DIR/llama"
    
    # Copy scripts
    if [ -d "$TEMP_DIR/repo/scripts" ]; then
        sudo cp -r "$TEMP_DIR/repo/scripts/"* "$INSTALL_DIR/scripts/"
        sudo find "$INSTALL_DIR/scripts" -type f -exec chmod +x {} \;
    fi
    
    # Create symlink
    sudo ln -sf "$INSTALL_DIR/llama" "$BIN_DIR/llama"
    
    echo "Installation completed. Run 'llama help' to get started."
else
    echo "Installation failed: Could not download repository"
    exit 1
fi