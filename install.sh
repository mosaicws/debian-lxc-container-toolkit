#!/bin/bash

# Debian Base Scripts - Bootstrap Installer
# This script installs the debian_base_scripts suite to /usr/local/sbin/
# and optionally runs the initial setup.

set -e

# --- Color Definitions ---
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m'

# --- Configuration ---
GITHUB_REPO="mosaicws/debian-lxc-container-toolkit"
GITHUB_BRANCH="main"
INSTALL_DIR="/usr/local/sbin"
SCRIPT_LIST=(
  "init-service-container.sh"
  "setup-enhanced-motd.sh"
  "install-podman-cockpit.sh"
  "create-service-user.sh"
  "create-podman-service.sh"
)

# --- Helper Functions ---
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

# --- Safety Checks ---

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  log_error "This script must be run as root. Please use 'sudo'."
  exit 1
fi

# Check if running on WSL2
if grep -qi microsoft /proc/version 2>/dev/null; then
  log_error "CRITICAL: This script is running on WSL2!"
  log_error "These scripts are for Debian 13 LXC containers only."
  log_error "Running on WSL2 will modify your development environment."
  exit 1
fi

# Check if running on Ubuntu (additional safety check)
if [ -f /etc/lsb-release ]; then
  if grep -qi ubuntu /etc/lsb-release; then
    log_error "CRITICAL: This script is running on Ubuntu!"
    log_error "These scripts are for Debian 13 LXC containers only."
    exit 1
  fi
fi

# Check if running on Debian
if [ ! -f /etc/debian_version ]; then
  log_error "This script is designed for Debian systems only."
  exit 1
fi

# Check Debian version
DEBIAN_VERSION=$(cat /etc/debian_version | cut -d. -f1)
if [ "$DEBIAN_VERSION" -lt 13 ]; then
  log_warn "This script is designed for Debian 13 or later."
  log_warn "You are running Debian $DEBIAN_VERSION."
  read -p "Continue anyway? [y/N]: " CONTINUE
  if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
    log_info "Installation aborted."
    exit 0
  fi
fi

# --- Display Header ---
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Debian Base Scripts - Installation                       ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo ""

# --- Detect Installation Method ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

if [ -d "$LOCAL_SCRIPTS_DIR" ] && [ -f "${LOCAL_SCRIPTS_DIR}/init-service-container.sh" ]; then
  INSTALL_METHOD="local"
  log_info "Detected local installation (git clone or extracted archive)"
  log_info "Source directory: ${LOCAL_SCRIPTS_DIR}"
else
  INSTALL_METHOD="remote"
  log_info "Detected remote installation (curl method)"
  log_info "Will download scripts from GitHub: ${GITHUB_REPO}"
fi

echo ""

# --- Installation Methods ---

install_local() {
  log_info "Installing scripts from local directory..."

  for script in "${SCRIPT_LIST[@]}"; do
    local src="${LOCAL_SCRIPTS_DIR}/${script}"
    local dst="${INSTALL_DIR}/${script}"

    if [ ! -f "$src" ]; then
      log_error "Script not found: ${src}"
      exit 1
    fi

    cp "$src" "$dst"
    chmod +x "$dst"
    log_success "Installed: ${script}"
  done
}

install_remote() {
  log_info "Downloading scripts from GitHub..."

  # Check if curl is available
  if ! command -v curl &> /dev/null; then
    log_error "curl is required but not installed."
    log_info "Install it with: apt update && apt install -y curl"
    exit 1
  fi

  for script in "${SCRIPT_LIST[@]}"; do
    local url="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/scripts/${script}"
    local dst="${INSTALL_DIR}/${script}"

    log_info "Downloading: ${script}..."
    if ! curl -fsSL "$url" -o "$dst"; then
      log_error "Failed to download: ${script}"
      log_error "URL: ${url}"
      exit 1
    fi

    chmod +x "$dst"
    log_success "Installed: ${script}"
  done
}

# --- Execute Installation ---

if [ "$INSTALL_METHOD" = "local" ]; then
  install_local
else
  install_remote
fi

echo ""
log_success "All scripts installed successfully to ${INSTALL_DIR}/"
echo ""

# --- Verify Installation ---

log_info "Verifying installation..."
for script in "${SCRIPT_LIST[@]}"; do
  if [ -x "${INSTALL_DIR}/${script}" ]; then
    echo "  [OK] ${script}"
  else
    log_error "Verification failed for: ${script}"
    exit 1
  fi
done
echo ""

# --- Post-Installation Instructions ---

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Installation Complete                                    ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo ""

log_info "The following scripts are now available:"
echo ""
echo -e "  1. ${GREEN}init-service-container.sh${NC}"
echo "     - Run FIRST on a fresh Debian 13 installation"
echo "     - Sets up admin user, SSH, and basic system configuration"
echo ""
echo -e "  2. ${GREEN}setup-enhanced-motd.sh${NC}"
echo "     - Configures informative login message with system stats"
echo ""
echo -e "  3. ${GREEN}install-podman-cockpit.sh${NC}"
echo "     - Installs Podman and Cockpit web interface"
echo ""
echo -e "  4. ${GREEN}create-service-user.sh${NC}"
echo "     - Creates dedicated system user for native applications"
echo ""
echo -e "  5. ${GREEN}create-podman-service.sh${NC}"
echo "     - Interactive Quadlet service generator for containers"
echo ""

# --- Offer to Run Init Script ---

if [ ! -f "/home/admin/.bashrc" ]; then
  echo -e "${YELLOW}It appears this is a fresh system (admin user not found).${NC}"
  echo ""
  read -p "Would you like to run init-service-container.sh now? [Y/n]: " RUN_INIT

  if [[ ! "$RUN_INIT" =~ ^[Nn]$ ]]; then
    echo ""
    log_info "Running init-service-container.sh..."
    echo ""
    exec "${INSTALL_DIR}/init-service-container.sh"
  else
    echo ""
    log_info "Skipping initialization. You can run it later with:"
    echo -e "  ${GREEN}${INSTALL_DIR}/init-service-container.sh${NC}"
  fi
else
  echo -e "${GREEN}System appears to be already initialized.${NC}"
  echo ""
  log_info "Recommended next steps:"
  echo -e "  1. Run: ${GREEN}${INSTALL_DIR}/setup-enhanced-motd.sh${NC}"
  echo -e "  2. Run: ${GREEN}${INSTALL_DIR}/install-podman-cockpit.sh${NC}"
  echo -e "  3. Deploy services with: ${GREEN}${INSTALL_DIR}/create-podman-service.sh${NC}"
fi

echo ""
log_info "For more information, visit:"
echo "  https://github.com/${GITHUB_REPO}"
echo ""
