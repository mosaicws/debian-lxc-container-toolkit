#!/bin/bash

# This script installs Podman, Cockpit, and the Cockpit-Podman plugin.
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
LOG_FILE="/var/log/cockpit-backports-install.err"

# --- Safety Checks ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use 'sudo'." >&2
  exit 1
fi

# --- Execution ---
set -e # Exit immediately if a command exits with a non-zero status.
export DEBIAN_FRONTEND=noninteractive

echo "--- Step 1: Updating system and installing Podman ---"
apt update
apt upgrade -y
apt install -y podman

echo "--- Step 2: Adding Debian Backports for Cockpit ---"
. /etc/os-release
echo "deb http://deb.debian.org/debian ${VERSION_CODENAME}-backports main" > /etc/apt/sources.list.d/backports.list

echo "--- Step 3: Installing Cockpit and Cockpit-Podman from Backports ---"
apt update

# To keep your console clean in an unprivileged LXC:
# 1) Force dpkg to avoid using a PTY (so redirection works reliably)
# 2) Temporarily redirect ALL stderr during this step into a logfile
# 3) Use --no-install-recommends to avoid pulling in udisks2 and other LXC-incompatible packages
APT_OPTS=(-y -o Dpkg::Use-Pty=0 -t "${VERSION_CODENAME}-backports" --no-install-recommends)

# Save current stderr on fd 3, redirect stderr to the log, then restore it after.
exec 3>&2
{
  # Install only the packages we need, avoiding cockpit-storaged and cockpit-packagekit
  # cockpit-system: base system monitoring
  # cockpit-ws: web server
  # cockpit-podman: container management
  apt "${APT_OPTS[@]}" install cockpit-system cockpit-ws cockpit-podman
} 2>>"$LOG_FILE"
exec 2>&3
exec 3>&-

echo "  ✓ Installed Cockpit with LXC-compatible modules only"

# --- Verification & Final Output ---
echo "--- Step 4: Enabling Services ---"
# Enable and start Cockpit web interface
systemctl is-active --quiet cockpit.socket || systemctl enable --now cockpit.socket || true

# Enable Podman API socket for cockpit-podman integration
# This ensures the REST API is available for cockpit-podman to manage containers
echo "Enabling Podman API socket for Cockpit integration..."
systemctl enable --now podman.socket

IP_ADDRESS=$(ip -4 addr show scope global | awk "/inet /{print \$2}" | cut -d'/' -f1 | head -n1)

echo -e "\n${GREEN}Installation complete.${NC}\n"
if [ -n "$IP_ADDRESS" ]; then
  echo -e "Cockpit is running and can be accessed at: ${YELLOW}http://${IP_ADDRESS}:9090${NC}\n"
fi
echo -e "Services enabled:"
echo -e "  ${GREEN}✓${NC} cockpit.socket  - Web console"
echo -e "  ${GREEN}✓${NC} podman.socket   - Podman REST API (for cockpit-podman)"
echo -e "\nAny install warnings/errors were saved to: ${YELLOW}$LOG_FILE${NC}"
echo -e "View with: sudo tail -n +1 $LOG_FILE"
echo -e "\nNext, you can create a container service by running:"
echo -e "   ${GREEN}sudo create-podman-service.sh${NC}\n"
