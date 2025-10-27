# Debian Proxmox LXC Container Toolkit

A suite of bash scripts for deploying containerized services on Debian 13 LXC containers using Podman and systemd Quadlet. Designed specifically for Proxmox LXC environments as an alternative to running Docker in containers.

## Why Podman in LXC?

LXC containers provide efficient isolation with minimal overhead, easy snapshots, and template creation. While Docker is common, running it inside LXC containers is problematic. Podman offers a cleaner solution that:

- Integrates natively with systemd via Quadlet
- Avoids Docker-in-LXC complications
- Works well in unprivileged LXC containers
- Containers can run as dedicated non-root users
- Provides Cockpit web UI for management

## Features

- **Automated initialization** of fresh Debian 13 installations
- **Podman + Cockpit** installation in one command
- **Interactive service generator** for creating systemd-managed containers
- **Dynamic MOTD** that adapts to system state (shows Podman status, Cockpit URL, relevant commands)
- **Security focused**: secure defaults, optional remote file management, SSH hardening

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

The installer automatically offers to run initialization. If you skip it, or want to run it manually later:

### 1. System Initialization (Automatic)

```bash
sudo init-service-container.sh
```

This script will:

- Update system packages
- Install core utilities (sudo, openssh-server, wget, ca-certificates, etc.)
- Create an 'admin' user (you'll set the SSH login password)
- **Ask about sudo configuration:**
  - Default [N]: Require password for sudo (more secure, standard practice)
  - Optional [y]: Allow sudo without password (enables WinSCP/FileZilla/Cyberduck remote file editing)
- **Ask about SSH security:**
  - Default [Y]: Disable root login via SSH (recommended)
  - Optional [n]: Keep root login enabled
- Configure bash shortcuts (cls=clear, ll, la, dps, etc.)
- **Automatically set up dynamic MOTD** (adapts to system state)

**Log out and back in after this step.**

### 2. Install Podman and Cockpit (Optional)

```bash
sudo install-podman-cockpit.sh
```

Installs Podman runtime and Cockpit web UI (accessible at `http://<ip>:9090`).

**Note:** The MOTD will automatically update to show Podman status and relevant commands after installation.

### 3. Deploy Services

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

### Sudo Configuration

During initialization, you'll choose how sudo works:

- **Require password** (default, recommended): Standard security practice. You must enter your password when running sudo commands. Remote GUI file managers (WinSCP, FileZilla, etc.) cannot edit system files.

- **Skip password prompts** (optional): No password needed for sudo. Enables remote GUI tools to edit any system file via SFTP. **Trade-off:** Less secure - anyone with admin credentials has instant root access.

### Dynamic MOTD

The login message automatically adapts to your system:

- Shows "Debian 13" or "Debian 13 (Podman + Quadlet)" based on what's installed
- Displays Cockpit URL when available (`http://<ip>:9090`)
- Shows only relevant commands (e.g., podman commands only appear if Podman is installed)
- Guides you on next steps based on system state

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

**Security defaults**: The toolkit follows security best practices by default - sudo requires password, and SSH root login is disabled. You can choose less secure but more convenient options during initialization if needed for your use case.

**Remote file editing**: If you enabled sudo without password prompts, configure your SFTP client:

- **WinSCP**: Advanced → Environment → SFTP → Set server to `sudo /usr/lib/openssh/sftp-server`
- **FileZilla/Cyberduck**: Connect via SFTP using the admin user (limited sudo support)

**Directory structure:** Services use `/opt/<service>` (binaries), `/etc/<service>` (config), `/var/lib/<service>` (data).

---

Inspired by [Proxmox VE Helper-Scripts](https://github.com/community-scripts/ProxmoxVE). For issues or questions, open a GitHub issue.
