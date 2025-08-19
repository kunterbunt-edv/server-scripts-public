# KuBu VPS Server Scripts - Public

Public initialization scripts for KuBu VPS server management.

## Quick Setup

Initialize a new KuBu VPS server with one command:

```bash
wget https://raw.githubusercontent.com/kunterbunt-edv/server-scripts-public/main/initialize-kubu-vps.sh -O /tmp/initialize-kubu-vps.sh && chmod +x /tmp/initialize-kubu-vps.sh && /tmp/initialize-kubu-vps.sh
```

## What this does

1. **Downloads the initialization script** to `/tmp/`
2. **Guides you through GitHub token creation** for private repository access
3. **Downloads the main management script** from the private repository
4. **Deploys the complete KuBu configuration** to your VPS
5. **Shows the welcome message** and available commands
6. **Cleans up temporary files** after successful deployment

## Requirements

- Ubuntu VPS with `wget`, `git`, and `curl` installed
- Access to the KuBu GitHub account for token creation
- `sudo` privileges on the target VPS

## What gets installed

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

## Available commands after setup

- `welcome` - Show server status and welcome message
- `install-docker` - Install Docker and Docker Compose
- `setup-groups` - Add user to sudo and docker groups
- `kubu-manage` - Main management tool for deployment and updates
- `dockerdir` - Navigate to Docker projects directory

## Repository Structure

This is the **public** repository containing only the initialization script.

The main configuration and management scripts are in the **private** repository:
`https://github.com/kunterbunt-edv/server-scripts`

## Support

For issues or questions, contact the KuBu system administrator.
