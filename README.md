# Llama Script Manager (LSM)

A lightweight script manager for Linux and macOS. Manages a collection of shell scripts with self-updating, environment detection, and per-script configuration.

## Quick Start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/BrunoAFK/LSM/main/install-llama.sh)
```

```bash
llama help          # Show commands and available scripts
llama status        # Show installation info
```

## Installation

### Production (recommended)

Uses the one-line installer above. Installs to `/usr/local/lib/llama`, creates a `llama` symlink in `/usr/local/bin`.

Updates are fetched from GitHub Releases with SHA256 checksum verification.

### Development

```bash
git clone https://github.com/BrunoAFK/LSM.git /opt/llama
cd /opt/llama
./llama install
```

Installs from local files. Run `./llama update` to sync local changes to the production directory.

## Commands

```
llama help              Show help and list available scripts
llama install           Install or reinstall llama and scripts
llama update            Check for updates and install them
llama remove            Uninstall llama and all scripts
llama status            Show environment and installed scripts
llama <script> [args]   Run an installed script
```

## Updates

`llama update` checks for new versions via the GitHub Releases API.

When a release includes a `checksums.txt` asset, downloaded files are verified against SHA256 checksums before installation. If checksums don't match, the update is aborted.

If no releases exist yet, it falls back to pulling from the `main` branch. Only scripts already installed on your system are updated — new scripts are not added automatically.

## Included Scripts

### docker-update

Updates all running Docker containers to their latest images. Automatically detects Docker Compose projects (via container labels) and standalone containers.

```bash
llama docker-update run         # Update all containers
llama docker-update check       # Dry run — check without changing anything
llama docker-update env generate  # Configure notifications
llama docker-update env show      # Show current config
```

**How it works:**
1. Iterates all running containers
2. Pulls latest image, compares digest with running container
3. Compose containers: `docker compose pull && docker compose up -d` (grouped by project)
4. Standalone containers: backs up old image, recreates container with the same ports, volumes, env vars, restart policy, and network
5. Prunes dangling images
6. Sends notifications if configured

**Backups:** Before recreating standalone containers, the old image is tagged as `llama-backup/<image>:pre-update`. Run `llama docker-update backups` to list them.

**Notifications** are optional. Configure zero or more channels:

| Channel   | Required config                                        |
|-----------|--------------------------------------------------------|
| Telegram  | `NOTIFY_TELEGRAM_BOT_TOKEN`, `NOTIFY_TELEGRAM_CHAT_ID` |
| Slack     | `NOTIFY_SLACK_WEBHOOK_URL`                              |
| Discord   | `NOTIFY_DISCORD_WEBHOOK_URL`                            |
| Email     | `NOTIFY_SMTP_SERVER`, `NOTIFY_SMTP_PORT`, `NOTIFY_SMTP_USER`, `NOTIFY_SMTP_PASSWORD`, `NOTIFY_SMTP_FROM`, `NOTIFY_SMTP_TO` |
| Webhook   | `NOTIFY_WEBHOOK_URL` (receives JSON POST)               |

Config is stored in `~/.config/llama_env/.env` with `600` permissions.

### pocketFeed

Extracts URLs from an RSS/Atom feed and adds them to an ArchiveBox instance.

```bash
llama pocketFeed <feed_url>
```

### test

Development/testing utility with system info and directory listing.

```bash
llama test info         # System information
llama test list         # Directory listing
```

## System Requirements

- Bash 4.0+
- `curl`
- `git`
- `sudo` access for installation
- Docker (for docker-update script only)

## Author

- **Author**: Bruno Pavelja
- **Website**: [pavelja.me](https://pavelja.me)
- **GitHub**: [github.com/brunoafk](https://github.com/brunoafk)

## License

MIT License — see [LICENSE](LICENSE) for details.
