#!/bin/bash

# Service User Creation Script
# Creates a dedicated system user with standard directory structure
# for running native applications or services.

set -e  # Exit on any error

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m'

# --- Safety Checks ---
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}This script must be run as root. Please use 'sudo'.${NC}" >&2
  exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Service User Creation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# --- User Input ---
read -p "Enter the desired username for the new service (e.g., grafana, prometheus): " APP_NAME

# --- Validation ---

# Check if input is empty
if [ -z "$APP_NAME" ]; then
  echo -e "${RED}Error: No username entered. Exiting.${NC}" >&2
  exit 1
fi

# Validate username format (lowercase alphanumeric + underscore, must start with letter, max 32 chars)
if ! [[ "$APP_NAME" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
  echo -e "${RED}Error: Invalid username format.${NC}" >&2
  echo -e "${YELLOW}Username must:${NC}" >&2
  echo -e "  - Start with a lowercase letter" >&2
  echo -e "  - Contain only lowercase letters, numbers, underscores, and hyphens" >&2
  echo -e "  - Be 1-32 characters long" >&2
  echo -e "${YELLOW}Examples: ${GREEN}homeassistant, grafana, node-exporter${NC}" >&2
  exit 1
fi

# Check if user already exists
if id "$APP_NAME" &>/dev/null; then
  echo -e "${RED}Error: User '${APP_NAME}' already exists.${NC}" >&2
  echo -e "${YELLOW}To view existing user:${NC} id ${APP_NAME}" >&2
  exit 1
fi

# Check if directories already exist
EXISTING_DIRS=""
[ -e "/opt/${APP_NAME}" ] && EXISTING_DIRS+="/opt/${APP_NAME} "
[ -e "/etc/${APP_NAME}" ] && EXISTING_DIRS+="/etc/${APP_NAME} "
[ -e "/var/lib/${APP_NAME}" ] && EXISTING_DIRS+="/var/lib/${APP_NAME} "

if [ -n "$EXISTING_DIRS" ]; then
  echo -e "${YELLOW}Warning: The following directories already exist:${NC}"
  echo -e "  ${EXISTING_DIRS}"
  read -p "Continue anyway? [y/N]: " CONTINUE
  if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 0
  fi
fi

# --- Summary and Confirmation ---
echo -e "\n${BLUE}Configuration Summary:${NC}"
echo -e "  Username:    ${YELLOW}${APP_NAME}${NC}"
echo -e "  Home Dir:    ${YELLOW}/opt/${APP_NAME}${NC}"
echo -e "  Config Dir:  ${YELLOW}/etc/${APP_NAME}${NC}"
echo -e "  Data Dir:    ${YELLOW}/var/lib/${APP_NAME}${NC}"
echo -e "  Shell:       ${YELLOW}/usr/sbin/nologin${NC} (no login)"
echo -e "  Type:        ${YELLOW}System user${NC} (-r flag)\n"

read -p "Create this user? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
  echo -e "${YELLOW}Aborted.${NC}"
  exit 0
fi

# --- Execution ---
echo -e "\n${GREEN}Creating system user '${APP_NAME}'...${NC}"

# Create system user
if ! useradd -r -c "${APP_NAME} service user" -d "/opt/${APP_NAME}" -s /usr/sbin/nologin "${APP_NAME}"; then
  echo -e "${RED}Error: Failed to create user '${APP_NAME}'.${NC}" >&2
  exit 1
fi
echo -e "  ${GREEN}✓${NC} User created successfully"

# Create directories with proper ownership and permissions
echo -e "\n${GREEN}Creating directory structure...${NC}"

for DIR in "/opt/${APP_NAME}" "/etc/${APP_NAME}" "/var/lib/${APP_NAME}"; do
  if [ ! -d "$DIR" ]; then
    if ! install -d -m 750 -o "${APP_NAME}" -g "${APP_NAME}" "$DIR"; then
      echo -e "${RED}Error: Failed to create directory '$DIR'.${NC}" >&2
      # Cleanup: remove user if directory creation failed
      userdel "${APP_NAME}" 2>/dev/null
      exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Created: ${DIR}"
  else
    # Directory exists, fix ownership
    chown "${APP_NAME}:${APP_NAME}" "$DIR"
    chmod 750 "$DIR"
    echo -e "  ${YELLOW}⚠${NC} Already exists (ownership updated): ${DIR}"
  fi
done

# Grant file management access to admin user (if exists)
ADMIN_USER="admin"
if id "$ADMIN_USER" &>/dev/null; then
  echo -e "\n${GREEN}Granting management access to '${ADMIN_USER}' user...${NC}"
  if ! usermod -aG "${APP_NAME}" "$ADMIN_USER"; then
    echo -e "${YELLOW}Warning: Could not add '${ADMIN_USER}' to group '${APP_NAME}'.${NC}" >&2
  else
    echo -e "  ${GREEN}✓${NC} User '${ADMIN_USER}' added to group '${APP_NAME}'"
    echo -e "  ${YELLOW}Note:${NC} '${ADMIN_USER}' must log out and back in for group changes to take effect"
  fi
else
  echo -e "\n${YELLOW}Note: User '${ADMIN_USER}' not found - skipping group assignment.${NC}"
fi

# --- Verification ---
echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Setup complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo -e "${BLUE}User Information:${NC}"
id "$APP_NAME"

echo -e "\n${BLUE}Directory Permissions:${NC}"
ls -ld "/opt/${APP_NAME}" "/etc/${APP_NAME}" "/var/lib/${APP_NAME}"

echo -e "\n${BLUE}Next Steps:${NC}"
echo -e "  - Place application files in: ${YELLOW}/opt/${APP_NAME}/${NC}"
echo -e "  - Place configuration files in: ${YELLOW}/etc/${APP_NAME}/${NC}"
echo -e "  - Application data will go in: ${YELLOW}/var/lib/${APP_NAME}/${NC}"
echo -e "  - Create a systemd service: ${YELLOW}/etc/systemd/system/${APP_NAME}.service${NC}"
echo ""
