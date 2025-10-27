# Debian Proxmox LXC Container Toolkit

A suite of bash scripts for deploying containerized services on Debian 13 LXC containers using Podman and systemd Quadlet. Designed specifically for Proxmox LXC environments as an alternative to running Docker in containers.

## Why Podman in LXC?

LXC containers provide efficient isolation with minimal overhead, easy snapshots, and template creation. While Docker is common, running it inside LXC containers is problematic. Podman offers a cleaner solution that:

- Runs rootless containers by default
- Integrates natively with systemd
- Avoids Docker-in-LXC complications
- Provides Cockpit web UI for management

## Features

- **Automated initialization** of fresh Debian 13 installations
- **Podman + Cockpit** installation in one command
- **Interactive service generator** for creating systemd-managed containers
- **Enhanced MOTD** with system resources and container status
- **Security focused**: non-root execution, proper permissions, SSH hardening

## Requirements

- Debian 13+ LXC container (unprivileged recommended)
- Proxmox VE 8.x or compatible LXC host
- Internet access for packages and container images

## Installation

### Quick Install

```bash
apt update && apt install -y curl && bash -c "$(curl -fsSL https://raw.githubusercontent.com/mosaicws/debian-lxc-container-toolkit/main/install.sh)"
```

This single command installs curl (if needed) and runs the installer. Works on fresh Debian 13 installations.

### Review First (Recommended)

```bash
apt update && apt install -y curl
curl -fsSL https://raw.githubusercontent.com/mosaicws/debian-lxc-container-toolkit/main/install.sh -o install.sh
less install.sh
bash install.sh
```

The installer verifies you're on Debian 13 (not WSL2), installs scripts to `/usr/local/sbin/`, and optionally runs initialization. Note that `sudo` is not required if running as root, and will be installed by the initialization script if not present.

## Usage

Run scripts in order on a fresh Debian 13 installation:

### 1. System Initialization

```bash
sudo init-service-container.sh
```

Updates system, installs core utilities, creates admin user with passwordless sudo, configures SSH and bash aliases. **Log out and back in after this step.**

### 2. Enhanced MOTD

```bash
sudo setup-enhanced-motd.sh
```

Configures dynamic login message showing system resources, running containers, and useful commands.

### 3. Install Podman and Cockpit

```bash
sudo install-podman-cockpit.sh
```

Installs Podman runtime and Cockpit web UI (accessible at `http://<ip>:9090`).

### 4. Deploy Services

**For containerized services:**

```bash
sudo create-podman-service.sh
```

Interactive wizard for creating systemd-managed containers. Guides through image selection, user/network modes, volumes, environment variables, health checks, and auto-updates.

**For native services:**

```bash
sudo create-service-user.sh
```

Creates dedicated system user with directories at `/opt/<service>`, `/etc/<service>`, and `/var/lib/<service>`

## Key Concepts

### User Modes (for containers)

- **Dedicated non-root** (default): Container runs as service UID, most secure
- **Root-only**: Runs as root throughout (for apps needing privileged ports)
- **Root with PUID/PGID**: Starts as root, drops to PUID/PGID (linuxserver.io images)

### Network Modes

- **Host** (default): Shares LXC network, can bind any port, best performance
- **Bridge**: Isolated network with port mapping, better isolation

### Path Shortcuts

The service generator supports shorthand paths:

- `./data` → `/var/lib/<service>/data`
- `./config` → `/var/lib/<service>/config`

## Service Management

**Basic commands:**

```bash
systemctl status <service>.service          # Check status
journalctl -u <service>.service -f          # View live logs
systemctl restart <service>.service         # Restart
```

**Edit configuration:**

```bash
sudo nano /etc/containers/systemd/<service>.container
sudo systemctl daemon-reload && sudo systemctl restart <service>.service
```

**Update containers:**

```bash
podman auto-update                          # Apply updates (if AutoUpdate enabled)
```

## Troubleshooting

**Service won't start:**

```bash
journalctl -u <service>.service -n 50       # Check logs
```

Common issues: port conflicts, missing volumes, incorrect permissions

**Permission errors:**

```bash
sudo chown -R <service>:<service> /var/lib/<service>/
```

**Cockpit not accessible:**

```bash
systemctl status cockpit.socket
ss -tlnp | grep 9090
```

## Important Notes

**CRITICAL**: These scripts make system-wide changes. Never run on development machines - only on target Debian 13 LXC containers. The installer includes WSL2/Ubuntu detection to prevent accidents.

**Directory structure:** Services use `/opt/<service>` (binaries), `/etc/<service>` (config), `/var/lib/<service>` (data).

---

Inspired by [Proxmox VE Helper-Scripts](https://github.com/community-scripts/ProxmoxVE). For issues or questions, open a GitHub issue.
