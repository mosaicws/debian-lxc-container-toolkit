# Debian LXC Container Toolkit

A set of Bash scripts for setting up and managing Debian 13 service containers using Podman and systemd Quadlet.

Designed for LXC environments with best practices for security, automation, and maintainability.

## Overview

This project provides a standardized workflow for deploying both containerized and native services on Debian 13 systems. The scripts automate common system administration tasks including user management, container orchestration, and system monitoring.

## Features

- **Automated System Initialization**: Set up fresh Debian 13 installations with proper user accounts, SSH configuration, and standard security hardening
- **Enhanced MOTD**: Dynamic login messages showing system resources, running containers, and useful commands
- **Podman Integration**: One-command installation of Podman container runtime with Cockpit web interface
- **Interactive Service Generator**: Guided creation of systemd-managed container services using Quadlet
- **User Management**: Automated creation of dedicated system users for native applications
- **Security Focused**: Non-root container execution, proper file permissions, and passwordless sudo for automation

## Requirements

### Target System

- **Operating System**: Debian 13 (Trixie) or later (ideally)
- **Environment**: LXC container (unprivileged recommended)
- **Architecture**: amd64/x86_64
- **Network**: Internet access for package installation and container images

### Hypervisor

- Proxmox VE 8.x or later (recommended)
- Any LXC-compatible host

### Development

- Scripts are developed on Ubuntu WSL2 but **must only be executed on Debian 13 LXC containers**

## Installation

### Method 1: Quick Install (Recommended)

Download and run the bootstrap installer in one command:

```bash
curl -fsSL https://raw.githubusercontent.com/mosaicws/debian-lxc-container-toolkit/main/install.sh | sudo bash
```

### Method 2: Review Before Install (Safer)

Download the installer, review it, then execute:

```bash
curl -fsSL https://raw.githubusercontent.com/USER/debian_base_scripts/main/install.sh -o install.sh
less install.sh  # Review the script
sudo bash install.sh
```

### Method 3: Git Clone (For Contributors)

Clone the repository and run the installer:

```bash
git clone https://github.com/USER/debian_base_scripts.git
cd debian_base_scripts
sudo ./install.sh
```

The installer will:

1. Verify the target system is Debian 13 (not WSL2/Ubuntu)
2. Install all scripts to `/usr/local/sbin/`
3. Set proper executable permissions
4. Optionally run the initialization script on fresh systems

## Usage

### Initial Setup Workflow

Run the scripts in the following order on a fresh Debian 13 installation:

#### Step 1: System Initialization

```bash
sudo init-service-container.sh
```

This script will:

- Update system packages
- Install core utilities (sudo, openssh-server, curl, wget, ca-certificates)
- Create an 'admin' user with passwordless sudo
- Configure bash aliases for convenience
- Secure SSH access (optionally disable root login)
- Provide WinSCP configuration guidance

**Important**: Log out and log back in after this step for group changes to take effect.

#### Step 2: Enhanced MOTD

```bash
sudo setup-enhanced-motd.sh
```

Configures a dynamic Message of the Day that displays:

- System resources (memory and disk usage)
- Running container count and names
- Network information and Cockpit URL
- Useful command references

#### Step 3: Install Podman and Cockpit

```bash
sudo install-podman-cockpit.sh
```

Installs and configures:

- Podman container runtime
- Cockpit web interface (accessible at `http://<ip>:9090`)
- Cockpit-Podman plugin for container management
- Removes non-functional modules in LXC environments

#### Step 4: Deploy Services

**For containerized services:**

```bash
sudo create-podman-service.sh
```

Interactive wizard that guides you through:

- Container image selection with automatic FQIN conversion
- User mode selection (dedicated non-root, root, or root-with-PUID)
- Network configuration (host or bridge mode)
- Volume mappings with smart path expansion
- Environment variables and timezone configuration
- Health checks and auto-update settings
- Automatic service activation and verification

**For native (non-containerized) services:**

```bash
sudo create-service-user.sh
```

Creates a dedicated system user with:

- Home directory at `/opt/<service-name>`
- Configuration directory at `/etc/<service-name>`
- Data directory at `/var/lib/<service-name>`
- Proper ownership and permissions (mode 750)
- Admin user added to service group for management access

## Script Reference

### init-service-container.sh

**Purpose**: Initial system setup for fresh Debian 13 installations

**What it does**:

- System package updates
- Core utility installation
- Admin user creation with passwordless sudo
- Bash environment configuration
- SSH hardening

**When to use**: First script to run on a new LXC container

### setup-enhanced-motd.sh

**Purpose**: Configure informative login messages

**What it does**:

- Creates dynamic MOTD scripts in `/etc/update-motd.d/`
- Displays system resources, containers, and network information
- Disables conflicting default MOTD scripts
- Provides command references for new users

**When to use**: After initial system setup

### install-podman-cockpit.sh

**Purpose**: Install container runtime and web management interface

**What it does**:

- Installs Podman from Debian repositories
- Adds Debian backports for latest Cockpit
- Installs Cockpit and cockpit-podman plugin
- Removes non-functional LXC modules
- Enables required systemd services

**When to use**: Before deploying container services

### create-podman-service.sh

**Purpose**: Interactive Quadlet service generator for containers

**What it does**:

- Guided container service creation
- Automatic FQIN (Fully Qualified Image Name) conversion
- User mode selection for security
- Volume path expansion (`./data` becomes `/var/lib/<service>/data`)
- Generates systemd Quadlet files
- Pulls container images
- Activates and verifies services
- Creates deployment documentation

**When to use**: To deploy each new containerized service

**Key Features**:

- Three user modes: dedicated non-root (default), root-only, root-with-PUID
- Two network modes: host (default), bridge with port mapping
- Smart path warnings for absolute paths that should be relative
- Health check configuration
- Auto-update support with `podman auto-update`

### create-service-user.sh

**Purpose**: Create dedicated system users for native applications

**What it does**:

- Username validation (Linux-compliant format)
- System user creation with `useradd -r`
- Directory structure creation with proper permissions
- Admin group membership for file management

**When to use**: For non-containerized services that run directly on the host

## Directory Structure

After installation, the repository structure is:

```
debian_base_scripts/
├── .gitignore              # Git ignore rules
├── README.md               # This file
├── CLAUDE.md               # AI assistant guidance
├── install.sh              # Bootstrap installer
└── scripts/                # Script directory
    ├── init-service-container.sh
    ├── setup-enhanced-motd.sh
    ├── install-podman-cockpit.sh
    ├── create-service-user.sh
    └── create-podman-service.sh
```

On the target system, scripts are installed to `/usr/local/sbin/` and are globally accessible.

## Service Management

### Container Services

All container services are managed via systemd:

```bash
# Check service status
systemctl status <service>.service

# View live logs
journalctl -u <service>.service -f

# Restart service
systemctl restart <service>.service

# Stop service
systemctl stop <service>.service

# Disable service (prevent auto-start)
systemctl disable <service>.service
```

### Editing Quadlet Configuration

Container configurations are stored as Quadlet files:

```bash
# Edit configuration
sudo nano /etc/containers/systemd/<service>.container

# Apply changes
sudo systemctl daemon-reload
sudo systemctl restart <service>.service
```

### Updating Containers

For services with AutoUpdate enabled:

```bash
# Check for and apply updates
podman auto-update

# Dry run (check without applying)
podman auto-update --dry-run
```

## Important Concepts

### User Modes

**Dedicated Non-Root (Default)**:

- Container runs as service UID from start
- Files owned by dedicated service user
- Most secure option
- Recommended for most applications

**Root-Only**:

- Container runs as root (UID 0) throughout
- Required for applications needing privileged ports without PUID/PGID support
- Examples: nginx-proxy-manager, traefik

**Root with PUID/PGID**:

- Container starts as root, drops to PUID/PGID
- Required for linuxserver.io images
- Examples: plex, sonarr, radarr

### Network Modes

**Host Mode (Default)**:

- Container shares LXC network namespace
- Can bind to any port including privileged ports (<1024)
- Best performance
- Container sees all host network interfaces

**Bridge Mode**:

- Isolated container network
- Requires explicit port mapping
- Cannot bind to privileged ports with non-root user
- Better network isolation

### Path Expansion

The `create-podman-service.sh` script supports shorthand path notation:

- `./data` expands to `/var/lib/<service>/data`
- `./config` expands to `/var/lib/<service>/config`
- Absolute paths (e.g., `/data`) are used as-is with warnings

### Directory Conventions

All services follow this structure:

- `/opt/<service-name>` - Application binaries and home directory
- `/etc/<service-name>` - Configuration files
- `/var/lib/<service-name>` - Persistent data and volumes

## Safety and Security

### Development vs. Target Environment

**CRITICAL**: These scripts make system-wide changes and must **NEVER** be run on your development machine.

- **Development Environment**: Ubuntu WSL2 (for editing scripts only)
- **Target Environment**: Debian 13 LXC containers (for execution)

The installer includes safety checks to prevent execution on WSL2 or Ubuntu systems.

### Security Features

- Non-root container execution by default
- Passwordless sudo for automation (admin user only)
- SSH hardening options
- Proper file permissions (mode 750 for service directories)
- SELinux/AppArmor label disabling only when explicitly needed

### Best Practices

1. Always review scripts before running them (especially with curl-to-bash)
2. Test on non-production systems first
3. Keep systems updated: `apt update && apt upgrade`
4. Use dedicated service users instead of running as root
5. Enable auto-updates for containers when appropriate
6. Monitor logs: `journalctl -u <service>.service -f`
7. Back up configuration and data directories regularly

## Troubleshooting

### Service Won't Start

Check the service logs:

```bash
journalctl -u <service>.service -n 50
```

Common issues:

- Port already in use
- Missing volume paths
- Container image not found
- Incorrect user permissions

### Container Image Pull Failures

Verify the image name:

```bash
podman search <image-name>
```

Test manual pull:

```bash
podman pull <full-image-name>
```

### Permission Denied Errors

Ensure proper ownership:

```bash
ls -la /var/lib/<service>/
sudo chown -R <service>:<service> /var/lib/<service>/
```

### Cockpit Not Accessible

Check if the service is running:

```bash
systemctl status cockpit.socket
```

Verify firewall settings (if applicable):

```bash
ss -tlnp | grep 9090
```

## Contributing

Contributions are welcome! Please follow these guidelines:

1. **Test thoroughly**: All changes must be tested on fresh Debian 13 LXC containers
2. **Follow conventions**: Use existing color codes, error handling, and structure patterns
3. **Update documentation**: Modify README.md and CLAUDE.md to reflect changes
4. **Safety first**: Maintain all safety checks (root detection, OS validation, etc.)

## Acknowledgments

Inspired by the [Proxmox VE Helper-Scripts](https://github.com/community-scripts/ProxmoxVE) project and best practices from the container and DevOps communities.

## Support

For issues, questions, or suggestions:

- Open an issue on GitHub
- Review the CLAUDE.md file for development guidance
- Check script comments for implementation details

---

**Note**: Replace `USER` in all URLs with your actual GitHub username or organization name before deployment.
