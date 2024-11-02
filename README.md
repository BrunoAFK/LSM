# Llama Script Manager (LSM)

LSM is a powerful script management system designed to handle installation, updates, and management of "llama" scripts. It supports both production and development environments.

## Quick Start (Production Installation)

Install LSM directly from GitHub:

```bash
bash <(curl -s https://raw.githubusercontent.com/BrunoAFK/LSM/main/install-llama.sh)
```

Once installed, access LSM commands through the `llama` command:

```bash
llama help          # Show available commands
llama status        # Check installation status
```

## Installation & Environments

LSM supports two environments: Production and Development.

### Production Environment (Recommended)
- **Installation Directory**: `/usr/local/lib/llama`
- **Command Access**: `llama` (available system-wide)
- **Updates**: Automatically fetched from GitHub
- **Installation Method**: Use the one-line installer above

### Development Environment
- **Location**: `/opt/llama`
- **Command Access**: `./llama` (must be in dev directory)
- **Updates**: Local files only
- **Installation Method**:
  ```bash
  git clone https://github.com/BrunoAFK/LSM.git /opt/llama
  cd /opt/llama
  ./llama install
  ```

## Usage

### Basic Commands
```bash
llama help          # Show help message
llama install       # Install or reinstall components
llama update        # Update to latest version
llama remove        # Remove installation
llama status        # Show current status
```

### Available Scripts
Run `llama help` to see all available scripts in your installation.

## Configuration

LSM automatically configures itself based on your environment:
- Production: Uses GitHub for updates and installations
- Development: Uses local files for all operations

## Command Reference

| Command | Production Usage | Development Usage | Description |
|---------|-----------------|-------------------|-------------|
| Help | `llama help` | `./llama help` | Show available commands |
| Install | `llama install` | `./llama install` | Install/reinstall components |
| Update | `llama update` | `./llama update` | Update components |
| Remove | `llama remove` | `./llama remove` | Remove installation |
| Status | `llama status` | `./llama status` | Show environment status |

## System Requirements

- Bash 4.0 or later
- `curl` for downloading files
- `git` for cloning repository
- `sudo` access for installation

## Troubleshooting

### Common Issues

1. **Command Not Found**
   ```bash
   # Reinstall production version
   bash <(curl -s https://raw.githubusercontent.com/BrunoAFK/LSM/main/install-llama.sh)
   ```

2. **Permission Denied**
   ```bash
   # Check script permissions
   ls -l $(which llama)
   # Fix permissions if needed
   sudo chmod +x $(which llama)
   ```

3. **Updates Not Working**
   - Ensure you're using the production version (`which llama`)
   - Check your internet connection
   - Verify GitHub repository access

## Author Information

- **Author**: Bruno Pavelja
- **Website**: [pavelja.me](https://pavelja.me)
- **GitHub**: [github.com/brunoafk](https://github.com/brunoafk)
- **Version**: 1.0.2

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.