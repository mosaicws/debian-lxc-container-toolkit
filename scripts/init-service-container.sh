#!/bin/bash

# Service Container Initialization Script
# This script performs the initial setup of a fresh Debian 13 LXC container
# to prepare it as a base template for running containerized services.
#
# Run this FIRST on a clean Debian 13 installation before other setup scripts.

set -e

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m'

# --- Safety Checks ---
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}This script must be run as root. Please use 'sudo' or run as root.${NC}" >&2
  exit 1
fi

# Check if running Debian
if [ ! -f /etc/debian_version ]; then
  echo -e "${RED}Error: This script is designed for Debian systems.${NC}" >&2
  exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   Service Container - Initial Setup${NC}"
echo -e "${BLUE}   Debian $(cat /etc/debian_version)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

# --- Configuration ---
ADMIN_USER="admin"

echo -e "${YELLOW}This script will:${NC}"
echo -e "  1. Update the system"
echo -e "  2. Install core packages (sudo, openssh-server)"
echo -e "  3. Create '${ADMIN_USER}' user (you'll set SSH login password)"
echo -e "  4. Configure sudo access (you'll choose security level)"
echo -e "  5. Add bash shortcuts (cls=clear, ll, la, dps, etc.)"
echo -e "  6. Set up SSH for secure access"
echo ""

read -p "Continue with initialization? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
  echo -e "${YELLOW}Aborted.${NC}"
  exit 0
fi

# ============================================================================
# STEP 1: System Update
# ============================================================================

echo -e "\n${BLUE}──── Step 1: Updating System ────${NC}"
export DEBIAN_FRONTEND=noninteractive

echo "Running apt update..."
apt update

echo "Running apt upgrade..."
apt upgrade -y

echo -e "${GREEN}✓ System updated successfully${NC}"

# ============================================================================
# STEP 2: Install Core Packages
# ============================================================================

echo -e "\n${BLUE}──── Step 2: Installing Core Packages ────${NC}"

# Core packages needed for administration
# Note: curl is already installed by the installer
PACKAGES=(
  sudo
  openssh-server
  wget
  ca-certificates
  gnupg
  lsb-release
)

echo "Installing: ${PACKAGES[*]}"
apt install -y "${PACKAGES[@]}"

echo -e "${GREEN}✓ Core packages installed${NC}"

# ============================================================================
# STEP 3: Create Admin User
# ============================================================================

echo -e "\n${BLUE}──── Step 3: Creating Admin User ────${NC}"

# Check if admin user already exists
if id "$ADMIN_USER" &>/dev/null; then
  echo -e "${YELLOW}User '${ADMIN_USER}' already exists. Skipping creation.${NC}"
else
  echo "Creating user '${ADMIN_USER}'..."

  # Create user with home directory
  useradd -m -s /bin/bash -c "System Administrator" "$ADMIN_USER"

  # Set password
  echo -e "\n${YELLOW}Please set a password for user '${ADMIN_USER}':${NC}"
  passwd "$ADMIN_USER"

  echo -e "${GREEN}✓ User '${ADMIN_USER}' created${NC}"
fi

# ============================================================================
# STEP 4: Configure Sudo Access
# ============================================================================

echo -e "\n${BLUE}──── Step 4: Configuring Sudo Access ────${NC}"

SUDOERS_FILE="/etc/sudoers.d/90-admin-nopasswd"
NOPASSWD_SUDO=false

if [ -f "$SUDOERS_FILE" ]; then
  echo -e "${YELLOW}Sudo is already configured (NOPASSWD enabled)${NC}"
  NOPASSWD_SUDO=true
else
  echo ""
  echo -e "${YELLOW}Remote File Management Configuration:${NC}"
  echo ""
  echo "Do you need to edit system files remotely using GUI file transfer tools?"
  echo "  (WinSCP, FileZilla, Cyberduck, Transmit, etc.)"
  echo ""
  echo -e "${BLUE}If YES:${NC}"
  echo -e "  - Sudo will ${YELLOW}not${NC} prompt for password"
  echo -e "  - Remote file managers can edit any file on the system"
  echo -e "  - ${YELLOW}Security trade-off:${NC} Anyone with ${ADMIN_USER} credentials has instant root access"
  echo ""
  echo -e "${BLUE}If NO (recommended):${NC}"
  echo -e "  - Sudo will prompt for password (standard security practice)"
  echo -e "  - You can still use SSH, terminal editors, and manual file transfers"
  echo -e "  - More secure: requires password confirmation for privileged operations"
  echo ""
  read -p "Enable remote GUI file editing via SFTP/FTP tools? [y/N]: " ENABLE_NOPASSWD

  if [[ "$ENABLE_NOPASSWD" =~ ^[Yy]$ ]]; then
    echo "Creating sudoers file: ${SUDOERS_FILE}"

    # Create sudoers file with proper permissions
    cat > "$SUDOERS_FILE" << EOF
# Allow admin user to run any command without password
# This enables non-interactive tools like WinSCP to access files via sudo
${ADMIN_USER} ALL=(ALL:ALL) NOPASSWD: ALL
EOF

    # Set correct permissions (must be 0440 or 0640)
    chmod 0440 "$SUDOERS_FILE"

    # Validate sudoers syntax
    if visudo -c -f "$SUDOERS_FILE"; then
      echo -e "${GREEN}✓ Sudo configured (no password prompts)${NC}"
      NOPASSWD_SUDO=true
    else
      echo -e "${RED}Error: Invalid sudoers syntax. Removing file.${NC}" >&2
      rm -f "$SUDOERS_FILE"
      exit 1
    fi
  else
    echo -e "${GREEN}✓ Sudo will require password (standard configuration)${NC}"
    NOPASSWD_SUDO=false
  fi
fi

# ============================================================================
# STEP 5: Configure Bash Aliases
# ============================================================================

echo -e "\n${BLUE}──── Step 5: Configuring Bash Environment ────${NC}"

BASHRC="/home/${ADMIN_USER}/.bashrc"

# Add cls alias if not already present
if grep -q "alias cls=" "$BASHRC" 2>/dev/null; then
  echo -e "${YELLOW}Bash aliases already configured${NC}"
else
  echo "Adding bash aliases to ${BASHRC}"

  cat >> "$BASHRC" << 'EOF'

# Custom aliases
alias cls='clear'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Useful Docker/Podman aliases (if/when installed)
alias dps='podman ps'
alias dpsa='podman ps -a'
alias dimg='podman images'
EOF

  # Set ownership
  chown "${ADMIN_USER}:${ADMIN_USER}" "$BASHRC"

  echo -e "${GREEN}✓ Bash aliases configured${NC}"
fi

# ============================================================================
# STEP 6: Configure SSH
# ============================================================================

echo -e "\n${BLUE}──── Step 6: Configuring SSH ────${NC}"

SSHD_CONFIG="/etc/ssh/sshd_config"

# Ensure SSH service is enabled and started
systemctl enable ssh
systemctl start ssh

echo -e "${GREEN}✓ SSH service enabled and started${NC}"

# Optional: Secure SSH configuration
echo ""
read -p "Apply secure SSH configuration? (Disable root login, password auth optional) [y/N]: " SECURE_SSH

if [[ "$SECURE_SSH" =~ ^[Yy]$ ]]; then
  echo "Applying secure SSH configuration..."

  # Backup original config
  cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"

  # Disable root login via SSH
  if grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
  else
    echo "PermitRootLogin no" >> "$SSHD_CONFIG"
  fi

  echo -e "${GREEN}✓ Disabled root login via SSH${NC}"
  echo -e "${YELLOW}Note: You can still use 'sudo' after logging in as '${ADMIN_USER}'${NC}"

  # Restart SSH service (reload can fail in LXC due to socket conflicts)
  echo "Restarting SSH service..."
  if systemctl restart ssh; then
    echo -e "${GREEN}✓ SSH service restarted successfully${NC}"
  else
    echo -e "${YELLOW}⚠ SSH restart failed, but config is valid${NC}"
    echo -e "${YELLOW}  SSH will work correctly after next reboot${NC}"
  fi
fi

# ============================================================================
# STEP 7: Remote File Management Setup Info
# ============================================================================

if [ "$NOPASSWD_SUDO" = true ]; then
  echo -e "\n${BLUE}──── Step 7: Remote File Manager Configuration ────${NC}"
  echo ""
  echo -e "${YELLOW}To enable root file access in your SFTP/FTP client:${NC}"
  echo ""
  echo -e "${GREEN}WinSCP (Windows):${NC}"
  echo -e "  1. Edit Site → Advanced → Environment → SFTP"
  echo -e "  2. SFTP server: ${YELLOW}sudo /usr/lib/openssh/sftp-server${NC}"
  echo ""
  echo -e "${GREEN}FileZilla (Windows/Mac/Linux):${NC}"
  echo -e "  1. Edit → Settings → SFTP → Add key file (if using SSH keys)"
  echo -e "  2. Connect via SFTP using ${ADMIN_USER}@<ip>"
  echo -e "  3. Note: FileZilla may have limited sudo support"
  echo ""
  echo -e "${GREEN}Cyberduck / Transmit (Mac):${NC}"
  echo -e "  1. Connect via SFTP protocol"
  echo -e "  2. Use username: ${YELLOW}${ADMIN_USER}${NC}"
  echo -e "  3. Configure 'Transfer Files' → 'Use sudo' if available"
  echo ""
  echo -e "${YELLOW}You can now edit any system file through your file manager.${NC}"
  echo ""
fi

# ============================================================================
# STEP 8: Summary
# ============================================================================

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   Initialization Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

IP_ADDRESS=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d'/' -f1 | head -1)

echo -e "${BLUE}System Information:${NC}"
echo -e "  OS:         Debian $(cat /etc/debian_version)"
echo -e "  Hostname:   $(hostname)"
if [ -n "$IP_ADDRESS" ]; then
  echo -e "  IP Address: ${YELLOW}${IP_ADDRESS}${NC}"
fi
echo ""

echo -e "${BLUE}Admin User:${NC}"
echo -e "  Username:   ${YELLOW}${ADMIN_USER}${NC}"
if [ "$NOPASSWD_SUDO" = true ]; then
  echo -e "  Sudo:       ${GREEN}Enabled${NC} ${YELLOW}(no password prompts - remote file editing enabled)${NC}"
else
  echo -e "  Sudo:       ${GREEN}Enabled${NC} (requires password - standard security)"
fi
echo -e "  SSH:        ${GREEN}Enabled${NC}"
echo ""

echo -e "${BLUE}Next Steps:${NC}"
echo -e "  1. ${YELLOW}Log out and log back in${NC} for all changes to take effect"
echo ""
echo -e "  2. ${YELLOW}Test SSH access:${NC}"
echo -e "     ssh ${ADMIN_USER}@${IP_ADDRESS:-<ip-address>}"
echo ""
echo -e "  3. ${YELLOW}Continue setup by running:${NC}"
echo -e "     ${GREEN}setup-enhanced-motd.sh${NC}      - Configure login message"
echo -e "     ${GREEN}install-podman-cockpit.sh${NC}   - Install Podman + Cockpit"
echo ""
echo -e "  4. ${YELLOW}Deploy services using:${NC}"
echo -e "     ${GREEN}create-podman-service.sh${NC}    - For containerized services"
echo -e "     ${GREEN}create-service-user.sh${NC}      - For native applications"
echo ""
