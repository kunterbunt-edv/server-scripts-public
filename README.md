# VPS Server Scripts - Public

Public initialization scripts for VPS server management.

## Quick Setup

Initialize a new VPS server with one command:

```bash
wget https://raw.githubusercontent.com/kunterbunt-edv/server-scripts-public/main/initialize-kubu-vps.sh -O /tmp/initialize-kubu-vps.sh && chmod +x /tmp/initialize-kubu-vps.sh && /tmp/initialize-kubu-vps.sh
```

## What This Does

1. **Downloads the initialization script** to `/tmp/`
2. **Guides you through GitHub token creation** for private repository access
3. **Downloads the main management script** from the private repository
4. **Deploys the complete server configuration** to your VPS
5. **Shows the welcome message** and available commands
6. **Cleans up temporary files** after successful deployment

## Requirements

- Ubuntu VPS with `wget`, `git`, and `curl` installed
- Access to the GitHub account for token creation
- `sudo` privileges on the target VPS

## What Gets Installed

After successful deployment, your VPS will have:

```
/srv/
├── scripts/           # Management and server-specific scripts
├── docs/             # Documentation 
├── docker/           # Docker projects (Traefik + server-specific)
└── tokens/           # Secure token storage

/etc/profile.d/
└── kubu-vps-startup.sh    # Auto-loaded welcome message and aliases
```

## Available Commands After Setup

- `welcome` - Show server status and welcome message
- `install-docker` - Install Docker and Docker Compose
- `setup-groups` - Add user to sudo and docker groups
- `manage-kubu-vps` - Main management tool for deployment and updates
- `dockerdir` - Navigate to Docker projects directory
- `update-docker` - Update Docker packages
- `setup-keyboard` - Configure keyboard layout interactively

## Repository Structure

This is the **public** repository containing only the initialization script.

The main configuration and management scripts are in the **private** repository.

## Security Notes

- GitHub tokens are stored securely with 600 permissions
- Tokens are moved to `/srv/tokens/` after successful deployment
- All temporary files are cleaned up automatically
- Existing files are backed up before being overwritten

## Troubleshooting

If initialization fails:
- Ensure you have sudo access: `sudo -v`
- Check internet connectivity: `ping github.com`
- Verify GitHub token has 'repo' scope for private repositories
- Check available disk space: `df -h`

For manual deployment after downloading:
```bash
cd /srv/scripts
sudo GITHUB_TOKEN='your_token_here' ./manage-kubu-vps.sh --deploy
```

## Support

For issues or questions, contact the system administrator.
