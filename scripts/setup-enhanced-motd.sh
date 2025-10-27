#!/bin/bash

# Enhanced MOTD Setup Script for Debian 13 Service Containers
# This script configures a clean, informative MOTD showing system resources,
# running containers, network info, and useful commands.

set -e

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Safety Checks ---
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}This script must be run as root. Please use 'sudo'.${NC}" >&2
  exit 1
fi

echo -e "${GREEN}Setting up enhanced MOTD...${NC}\n"

# --- Step 1: Remove default/conflicting MOTD scripts ---
echo "Step 1: Cleaning up default MOTD scripts..."
rm -f /etc/update-motd.d/10-uname
echo "  ✓ Removed default uname script"

# --- Step 2: Disable Cockpit's issue file (if Cockpit is installed) ---
if systemctl list-unit-files | grep -q cockpit-issue.service; then
    echo "Step 2: Disabling Cockpit issue service..."
    systemctl mask cockpit-issue.service 2>/dev/null || true
    systemctl stop cockpit-issue.service 2>/dev/null || true
    rm -f /run/cockpit/issue
    echo "  ✓ Cockpit issue service disabled"
else
    echo "Step 2: Cockpit not installed, skipping..."
fi

# --- Step 3: Create enhanced MOTD scripts ---
echo "Step 3: Creating enhanced MOTD scripts..."

# 10-welcome: Header and setup instructions (dynamic based on installed tools)
cat > /etc/update-motd.d/10-welcome << 'EOF'
#!/bin/bash
GREEN='\033[1;32m'
BLUE='\033[1;34m'
NC='\033[0m'

# Dynamic title based on whether Podman is installed
if command -v podman &>/dev/null; then
  TITLE="Service Container - Debian 13 (Podman + Quadlet)"
else
  TITLE="Service Container - Debian 13"
fi

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  ${TITLE}${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Show setup instructions if Podman isn't installed yet
if ! command -v podman &>/dev/null; then
  echo -e "${BLUE}To install Podman and Cockpit:${NC}"
  echo -e "  ${GREEN}sudo install-podman-cockpit.sh${NC}\n"
fi

echo -e "Deploy services:\n"
echo -e "  ${GREEN}1.${NC} Create a dedicated user for a native application:"
echo -e "     ${GREEN}sudo create-service-user.sh${NC}\n"

if command -v podman &>/dev/null; then
  echo -e "  ${GREEN}2.${NC} Create a Podman container service:"
  echo -e "     ${GREEN}sudo create-podman-service.sh${NC}\n"
fi
EOF

# 40-system-info: System resources
cat > /etc/update-motd.d/40-system-info << 'EOF'
#!/bin/bash
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

# Memory info
MEM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
MEM_USED=$(free -h | awk '/^Mem:/ {print $3}')

# Disk info (root filesystem)
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_PERCENT=$(df -h / | awk 'NR==2 {print $5}')

echo -e "${CYAN}System Resources:${NC}"
echo -e "  Memory: ${YELLOW}${MEM_USED}${NC} / ${MEM_TOTAL}    Disk: ${YELLOW}${DISK_USED}${NC} / ${DISK_TOTAL} (${DISK_PERCENT})\n"
EOF

# 45-containers: Container information
cat > /etc/update-motd.d/45-containers << 'EOF'
#!/bin/bash
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[1;36m'
NC='\033[0m'

# Get container info
CONTAINER_COUNT=$(podman ps --format "{{.Names}}" 2>/dev/null | wc -l)
CONTAINER_NAMES=$(podman ps --format "{{.Names}}" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')

if [ "$CONTAINER_COUNT" -gt 0 ]; then
    echo -e "${CYAN}Running Containers:${NC} ${GREEN}${CONTAINER_COUNT}${NC}"
    echo -e "  ${CONTAINER_NAMES}\n"
elif podman info &>/dev/null; then
    echo -e "${CYAN}Running Containers:${NC} ${YELLOW}0${NC} (none active)\n"
fi
EOF

# 50-ip-address: Network info and useful commands (dynamic based on installed tools)
cat > /etc/update-motd.d/50-ip-address << 'EOF'
#!/bin/bash
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
NC='\033[0m'

IP_ADDRESS=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d'/' -f1 | head -1)

if [ -n "$IP_ADDRESS" ]; then
  echo -e "${CYAN}Network & Access:${NC}"
  echo -e "  IP Address: ${YELLOW}${IP_ADDRESS}${NC}"

  # Check if Cockpit is running
  if systemctl is-active --quiet cockpit.socket 2>/dev/null; then
    echo -e "  Cockpit:    ${YELLOW}http://${IP_ADDRESS}:9090${NC}"
  fi
  echo ""
fi

# Dynamic command list based on installed tools
echo -e "${CYAN}Useful Commands:${NC}"

# Always show these basic commands
echo -e "  ${GREEN}systemctl --type=service${NC}    - List all services"
echo -e "  ${GREEN}journalctl -f${NC}               - View live system logs"

# Only show Podman commands if Podman is installed
if command -v podman &>/dev/null; then
  echo -e "  ${GREEN}podman ps${NC}                   - List running containers"
  echo -e "  ${GREEN}podman auto-update${NC}          - Update containers with AutoUpdate enabled"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
EOF

echo "  ✓ Created 10-welcome"
echo "  ✓ Created 40-system-info"
echo "  ✓ Created 45-containers"
echo "  ✓ Created 50-ip-address"

# --- Step 4: Make scripts executable ---
echo "Step 4: Setting permissions..."
chmod +x /etc/update-motd.d/10-welcome
chmod +x /etc/update-motd.d/40-system-info
chmod +x /etc/update-motd.d/45-containers
chmod +x /etc/update-motd.d/50-ip-address
echo "  ✓ All scripts are executable"

# --- Step 5: Generate the MOTD ---
echo "Step 5: Generating MOTD..."
run-parts /etc/update-motd.d/ > /run/motd.dynamic
echo "  ✓ MOTD generated successfully"

# --- Final Output ---
echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Enhanced MOTD setup complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo "The following MOTD scripts have been installed:"
echo "  - /etc/update-motd.d/10-welcome       (Header and instructions)"
echo "  - /etc/update-motd.d/40-system-info   (Memory and disk usage)"
echo "  - /etc/update-motd.d/45-containers    (Running container info)"
echo "  - /etc/update-motd.d/50-ip-address    (Network and commands)"
echo ""
echo "Preview the MOTD:"
echo -e "  ${YELLOW}cat /run/motd.dynamic${NC}"
echo ""
echo "The new MOTD will be displayed on the next SSH login."
echo ""
