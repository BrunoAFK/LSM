# Llama Script Manager

Llama Script Manager is a Bash script designed to simplify the management of "llama" scripts from GitHub or local files, handling installation, updates, and removals seamlessly.

## Description

This script fetches and installs "llama" components from a specified GitHub repository or local files. It also sets up necessary symbolic links and provides options for updating or removing the components.

## How It Works

- **Fetching**: Downloads components from GitHub or uses local files if GitHub is unavailable.
- **Installation**: Installs scripts into designated directories and sets up symbolic links for easy access.
- **Updates**: Checks for the latest version from GitHub and updates if needed.
- **Removal**: Cleans up all installed components and symbolic links.

## Key Variables

- `VERSION`: Current version of the script.
- `DEV_DIR`: Directory for storing the main script and components.
- `SCRIPTS_DIR`: Directory for storing executable scripts.
- `GITHUB_USER`, `GITHUB_REPO`, `GITHUB_BRANCH`: GitHub details for fetching scripts.

## Usage

```bash
llama [COMMAND] [ARGUMENTS]
llama [OPTIONS]
```

### Commands

| Command      | Description                                     |
|--------------|-------------------------------------------------|
| `help`, `-h` | Show this help message                          |
| `install`, `-i` | Install llama script and its components       |
| `remove`, `-r` | Remove llama script and its components        |
| `update`, `-u` | Update llama script and its components        |

## Available Scripts

The available scripts are listed dynamically from the `SCRIPTS_DIR`. Use `llama help` to view the current scripts installed.

## Installation

To install the Llama Script Manager:

1. Clone the repository or download the script.
2. Run the script with the install command:
   ```bash
   ./llama -i
   ```
3. Follow the on-screen instructions to complete the setup.

## Updating

To update the script to the latest version:

```bash
llama -u
```

The script will fetch the latest version from GitHub and update if a newer version is available.

## Removal

To remove the script and its components:

```bash
llama -r
```

This will remove all installed files and symbolic links.

## Contributing

Feel free to fork the repository and submit pull requests with improvements or new features. Your contributions are welcome!

## Troubleshooting

If you encounter any issues:

- Ensure you have the correct permissions for script execution.
- Verify that the GitHub details are correctly configured in the script.
- Check for updates and re-install if necessary.

---

> **Note**: This script requires `curl` for downloading files and `sudo` for administrative permissions when creating directories and symbolic links.

## Author Information

- **Author**: Bruno Pavelja - Bruno_AFK - Paveljame IT
- **Website**: [pavelja.me](https://pavelja.me)
- **GitHub**: [github.com/brunoafk](https://github.com/brunoafk)
- **Version**: 1.0.0


## License

This script is open-source and licensed under the [MIT License](LICENSE).
