#!/bin/bash

# Enhanced Podman Quadlet Service Generator
# This script interactively creates a systemd-managed Podman container using Quadlet.
# Incorporates 2025 best practices for robust, production-ready container services.

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m'

# --- Pre-flight Checks ---
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}This script must be run as root. Please use 'sudo'.${NC}" >&2
  exit 1
fi

if ! command -v podman &> /dev/null; then
    echo -e "\n${YELLOW}Podman is not installed, but is required to continue.${NC}"
    read -p "Would you like to run the installer for Podman and Cockpit now? [Y/n]: " INSTALL_CHOICE
    if [[ ! "$INSTALL_CHOICE" =~ ^[Nn]$ ]]; then
        echo "Running the installer..."
        if ! /usr/local/sbin/install-podman-cockpit.sh; then
            echo -e "\n${RED}The installation script failed. Please review the output above. Exiting.${NC}" >&2
            exit 1
        fi
        echo -e "\n${GREEN}Installation complete. Continuing with service creation...${NC}\n"
    else
        echo "Installation declined. Exiting."
        exit 0
    fi
fi

# --- Get LXC IP for Prompts ---
LXC_IP=$(ip -4 addr show scope global | awk "/inet /{print \$2}" | cut -d'/' -f1 | head -n1)

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   Podman Quadlet Service Generator${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

# ============================================================================
# SECTION 1: Basic Configuration
# ============================================================================

echo -e "${BLUE}──── Basic Configuration ────${NC}"

read -p "Service name (e.g., homeassistant, nginxpm): " SERVICE_NAME
if [ -z "$SERVICE_NAME" ]; then
  echo -e "${RED}Error: Service name cannot be empty.${NC}" >&2
  exit 1
fi

read -p "Container image (e.g., homeassistant/home-assistant, jc21/nginx-proxy-manager): " IMAGE_NAME
if [ -z "$IMAGE_NAME" ]; then
  echo -e "${RED}Error: Image name cannot be empty.${NC}" >&2
  exit 1
fi

# --- Smart Image Name Validation and FQIN Conversion ---
# Extract the first component (before first slash)
FIRST_COMPONENT="${IMAGE_NAME%%/*}"

# Check if the first component looks like a registry (contains . or : or is localhost)
if [[ "$FIRST_COMPONENT" == *"."* ]] || [[ "$FIRST_COMPONENT" == *":"* ]] || [[ "$FIRST_COMPONENT" == "localhost" ]]; then
    # Already has a registry
    FQIN_IMAGE_NAME="$IMAGE_NAME"
elif [[ "$IMAGE_NAME" == *"/"* ]]; then
    # Has namespace but no registry - assume docker.io
    FQIN_IMAGE_NAME="docker.io/$IMAGE_NAME"
    echo -e "${YELLOW}Converting to fully qualified name: ${FQIN_IMAGE_NAME}${NC}"
else
    # Just a name - assume docker.io/library
    FQIN_IMAGE_NAME="docker.io/library/$IMAGE_NAME"
    echo -e "${YELLOW}Converting to fully qualified name: ${FQIN_IMAGE_NAME}${NC}"
fi

# ============================================================================
# SECTION 2: User and Permissions
# ============================================================================

echo -e "\n${BLUE}──── User and Permissions ────${NC}"
echo -e "How should this container run?"
echo -e " ${YELLOW}1)${NC} As a dedicated non-root user (RECOMMENDED for most applications)"
echo -e "    - Container runs as UID ${YELLOW}<service-uid>${NC} from the start"
echo -e "    - Files are owned by the dedicated service user"
echo -e "    - More secure for applications that don't need root"
echo -e ""
echo -e " ${YELLOW}2)${NC} As root only (for apps requiring root + low ports)"
echo -e "    - Container runs as root (UID 0) throughout"
echo -e "    - Required for: nginx-proxy-manager, traefik, etc."
echo -e "    - Use when app needs ports 80/443 and doesn't support PUID/PGID"
echo -e ""
echo -e " ${YELLOW}3)${NC} As root with PUID/PGID (for linuxserver.io images)"
echo -e "    - Container starts as root, then drops to PUID/PGID"
echo -e "    - Required for: linuxserver.io containers (plex, sonarr, etc.)"
echo -e "    - Use when image explicitly supports PUID/PGID variables"

read -p "Enter choice [1]: " USER_MODE_CHOICE

USER_MODE_CHOICE=${USER_MODE_CHOICE:-1}  # Default to 1

case "$USER_MODE_CHOICE" in
  1)
    USER_MODE="dedicated"
    echo -e "${GREEN}Container will run as a dedicated non-root user.${NC}"
    ;;
  2)
    USER_MODE="root"
    echo -e "${YELLOW}Container will run as root.${NC}"
    ;;
  3)
    USER_MODE="root-with-puid"
    echo -e "${YELLOW}Container will run as root with PUID/PGID for privilege dropping.${NC}"
    ;;
  *)
    echo -e "${RED}Invalid choice. Defaulting to dedicated user mode.${NC}"
    USER_MODE="dedicated"
    ;;
esac

# --- Create Service User if Needed ---
SERVICE_USER="$SERVICE_NAME"
if ! id "$SERVICE_USER" &>/dev/null; then
  echo -e "\n${YELLOW}Creating system user '${SERVICE_USER}'...${NC}"
  useradd -r -c "${SERVICE_USER} service user" -d "/opt/${SERVICE_USER}" -s /usr/sbin/nologin "${SERVICE_USER}"
  install -d -m 750 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "/opt/${SERVICE_USER}"
  install -d -m 750 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "/etc/${SERVICE_USER}"
  install -d -m 750 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "/var/lib/${SERVICE_USER}"
  usermod -aG "${SERVICE_USER}" admin
  echo -e "${GREEN}User and directories created successfully.${NC}"
else
  echo -e "${GREEN}User '${SERVICE_USER}' already exists.${NC}"
fi

SERVICE_UID=$(id -u "$SERVICE_USER")
SERVICE_GID=$(id -g "$SERVICE_USER")

# ============================================================================
# SECTION 3: Network Configuration
# ============================================================================

echo -e "\n${BLUE}──── Network Configuration ────${NC}"
echo -e "Select the container's network mode:"
echo -e " ${YELLOW}1)${NC} Host networking (container shares LXC's network namespace)"
if [ -n "$LXC_IP" ]; then
    echo -e "    Access at: ${YELLOW}${LXC_IP}${NC} on the application's native port"
fi
echo -e "    ${GREEN}✓${NC} Can bind to any port including <1024"
echo -e "    ${GREEN}✓${NC} Best performance"
echo -e "    ${RED}✗${NC} Container sees all host network interfaces"
echo -e ""
echo -e " ${YELLOW}2)${NC} Bridge networking (isolated container network with port mapping)"
if [ -n "$LXC_IP" ]; then
    echo -e "    Access at: ${YELLOW}${LXC_IP}${NC} on ports you choose"
fi
echo -e "    ${GREEN}✓${NC} Network isolation"
echo -e "    ${RED}✗${NC} Requires port mapping (PublishPort)"
echo -e "    ${RED}✗${NC} Cannot bind to ports <1024 with non-root user"

read -p "Enter choice [1]: " NETWORK_CHOICE
NETWORK_CHOICE=${NETWORK_CHOICE:-1}

case "$NETWORK_CHOICE" in
  2)
    NETWORK_MODE="bridge"
    echo -e "\n${YELLOW}Bridge mode selected.${NC}"
    read -p "Enter ports to publish (comma-separated, e.g., 8080:80, 8443:443): " PORTS_INPUT
    ;;
  *)
    NETWORK_MODE="host"
    PORTS_INPUT=""
    echo -e "${GREEN}Host mode selected.${NC}"
    ;;
esac

# --- Process Port Mappings ---
PROCESSED_PORTS=""
if [ "$NETWORK_MODE" = "bridge" ] && [ -n "$PORTS_INPUT" ]; then
  IFS=',' read -ra PORT_ARRAY <<< "$PORTS_INPUT"
  for PORT_MAPPING in "${PORT_ARRAY[@]}"; do
    PORT_MAPPING=$(echo "$PORT_MAPPING" | xargs)  # Trim whitespace
    if [ -n "$PORT_MAPPING" ]; then
        PROCESSED_PORTS+="PublishPort=${PORT_MAPPING}\n"
    fi
  done
fi

# ============================================================================
# SECTION 4: Volume Mappings
# ============================================================================

echo -e "\n${BLUE}──── Volume Mappings ────${NC}"
echo -e "Enter volume mappings (comma-separated)."
echo -e "You can use ${YELLOW}./<name>${NC} as shorthand for ${YELLOW}/var/lib/${SERVICE_NAME}/<name>${NC}"
echo -e ""
echo -e "Examples:"
echo -e "  nginx-proxy-manager: ${YELLOW}./data:/data, ./letsencrypt:/etc/letsencrypt${NC}"
echo -e "  Home Assistant:      ${YELLOW}./config:/config, /etc/localtime:/etc/localtime:ro${NC}"
echo -e "  Empty for none:      ${YELLOW}(just press Enter)${NC}"

read -p "Volume mappings: " VOLUMES_INPUT

# --- Process Volume Mappings with Smart Path Expansion ---
PROCESSED_VOLUMES_STRING=""
if [ -n "$VOLUMES_INPUT" ]; then
  echo -e "\n${YELLOW}Preparing volume mounts...${NC}"
  IFS=',' read -ra VOL_ARRAY <<< "$VOLUMES_INPUT"
  for VOL_MAPPING_RAW in "${VOL_ARRAY[@]}"; do
    VOL_MAPPING_RAW=$(echo "$VOL_MAPPING_RAW" | xargs)  # Trim whitespace
    if [ -z "$VOL_MAPPING_RAW" ]; then continue; fi

    # Split on first colon to get host path and container path
    HOST_PATH_RAW=$(echo "$VOL_MAPPING_RAW" | cut -d: -f1)
    CONTAINER_PART=$(echo "$VOL_MAPPING_RAW" | cut -d: -f2-)

    # Validate and warn about potentially incorrect absolute paths
    if [[ "$HOST_PATH_RAW" == /* ]] && [[ ! "$HOST_PATH_RAW" =~ ^/(etc|run|dev|sys|proc|usr|var|opt|home|root|tmp|mnt|media|boot)/ ]]; then
      echo -e "\n${RED}⚠ WARNING:${NC} Suspicious host path detected: ${YELLOW}${HOST_PATH_RAW}${NC}"
      echo -e "This looks like you might want a data directory, not a path at the filesystem root."
      echo -e ""
      echo -e "Did you mean to use a relative path?"
      echo -e "  Current:  ${RED}${HOST_PATH_RAW}:${CONTAINER_PART}${NC}"
      echo -e "  Suggest:  ${GREEN}.${HOST_PATH_RAW}:${CONTAINER_PART}${NC}"
      echo -e "            (expands to ${YELLOW}/var/lib/${SERVICE_NAME}${HOST_PATH_RAW}${NC})"
      echo -e ""
      read -p "Use suggested path with ./ prefix? [Y/n]: " USE_RELATIVE
      if [[ ! "$USE_RELATIVE" =~ ^[Nn]$ ]]; then
        HOST_PATH_RAW=".${HOST_PATH_RAW}"
        echo -e "${GREEN}✓${NC} Using relative path: ${HOST_PATH_RAW}"
      else
        echo -e "${YELLOW}⚠${NC} Keeping absolute path: ${HOST_PATH_RAW}"
        echo -e "${RED}Note:${NC} This will create a directory at the filesystem root (requires careful consideration)"
      fi
      echo ""
    fi

    # Expand relative paths
    if [[ "$HOST_PATH_RAW" == "./"* ]]; then
        RELATIVE_PATH="${HOST_PATH_RAW#./}"
        HOST_PATH_EXPANDED="/var/lib/${SERVICE_NAME}/${RELATIVE_PATH}"
        FINAL_VOL_MAPPING="${HOST_PATH_EXPANDED}:${CONTAINER_PART}"
        echo -e "  ${YELLOW}→${NC} ${HOST_PATH_RAW} expands to ${HOST_PATH_EXPANDED}"
    else
        HOST_PATH_EXPANDED="$HOST_PATH_RAW"
        FINAL_VOL_MAPPING="$VOL_MAPPING_RAW"
    fi

    # Create directory if not a system path
    if [[ "$HOST_PATH_EXPANDED" =~ ^/(etc|run|dev|sys|proc)/ ]]; then
      echo -e "  ${BLUE}→${NC} Using system path: ${HOST_PATH_EXPANDED}"
    else
      if [ ! -e "$HOST_PATH_EXPANDED" ]; then
        echo -e "  ${GREEN}→${NC} Creating: ${HOST_PATH_EXPANDED}"
        install -d -m 750 -o "${SERVICE_USER}" -g "${SERVICE_USER}" "${HOST_PATH_EXPANDED}"
      else
        echo -e "  ${GREEN}✓${NC} Already exists: ${HOST_PATH_EXPANDED}"
      fi
    fi

    PROCESSED_VOLUMES_STRING+="Volume=${FINAL_VOL_MAPPING}\n"
  done
fi

# ============================================================================
# SECTION 5: Environment Variables
# ============================================================================

echo -e "\n${BLUE}──── Environment Variables ────${NC}"

# Initialize environment string
PROCESSED_ENV_STRING=""

# Add PUID/PGID if user mode requires it
if [ "$USER_MODE" = "root-with-puid" ]; then
    PROCESSED_ENV_STRING+="Environment=PUID=${SERVICE_UID}\n"
    PROCESSED_ENV_STRING+="Environment=PGID=${SERVICE_GID}\n"
    echo -e "${GREEN}✓${NC} Adding PUID=${SERVICE_UID} and PGID=${SERVICE_GID}"
fi

# Prompt for timezone
read -p "Set container timezone to match host? [Y/n]: " SET_TIMEZONE
if [[ ! "$SET_TIMEZONE" =~ ^[Nn]$ ]]; then
    USE_TIMEZONE="yes"
    echo -e "${GREEN}✓${NC} Timezone will be set to 'local'"
else
    USE_TIMEZONE="no"
fi

# Prompt for additional environment variables
echo -e "\nEnter any additional environment variables (comma-separated)"
echo -e "Example: ${YELLOW}TZ=Europe/London, LANG=en_US.UTF-8${NC}"
read -p "Additional environment variables: " EXTRA_ENV_VARS

if [ -n "$EXTRA_ENV_VARS" ]; then
    IFS=',' read -ra ENV_ARRAY <<< "$EXTRA_ENV_VARS"
    for ENV_VAR in "${ENV_ARRAY[@]}"; do
        ENV_VAR=$(echo "$ENV_VAR" | xargs)  # Trim whitespace
        if [ -n "$ENV_VAR" ]; then
            PROCESSED_ENV_STRING+="Environment=${ENV_VAR}\n"
            echo -e "${GREEN}✓${NC} Adding: ${ENV_VAR}"
        fi
    done
fi

# ============================================================================
# SECTION 6: Advanced Options
# ============================================================================

echo -e "\n${BLUE}──── Advanced Options ────${NC}"

# Security label (for hardware access, etc.)
read -p "Disable SELinux/AppArmor labels? (needed for hardware access) [y/N]: " DISABLE_LABELS
if [[ "$DISABLE_LABELS" =~ ^[Yy]$ ]]; then
    SECURITY_LABEL_DISABLE="yes"
    echo -e "${YELLOW}⚠${NC}  SecurityLabelDisable will be enabled"
else
    SECURITY_LABEL_DISABLE="no"
fi

# Pull policy
echo -e "\nImage pull policy:"
echo -e " ${YELLOW}1)${NC} missing - Only pull if image is not present locally (fastest)"
echo -e " ${YELLOW}2)${NC} always  - Always check for newer image (keeps up to date)"
echo -e " ${YELLOW}3)${NC} never   - Never pull, use local only (for offline/testing)"
read -p "Enter choice [1]: " PULL_CHOICE
PULL_CHOICE=${PULL_CHOICE:-1}

case "$PULL_CHOICE" in
  2) PULL_POLICY="always" ;;
  3) PULL_POLICY="never" ;;
  *) PULL_POLICY="missing" ;;
esac
echo -e "${GREEN}✓${NC} Pull policy set to: ${PULL_POLICY}"

# Auto-update
read -p "Enable automatic container updates with 'podman auto-update'? [Y/n]: " ENABLE_AUTOUPDATE
if [[ ! "$ENABLE_AUTOUPDATE" =~ ^[Nn]$ ]]; then
    AUTO_UPDATE="yes"
    echo -e "${GREEN}✓${NC} AutoUpdate enabled (run 'podman auto-update' to update)"
else
    AUTO_UPDATE="no"
fi

# Health check
echo -e "\nConfigure container health check?"
echo -e "Health checks monitor container health and can auto-restart on failure."
read -p "Add health check? [y/N]: " ADD_HEALTHCHECK

if [[ "$ADD_HEALTHCHECK" =~ ^[Yy]$ ]]; then
    echo -e "\nHealth check configuration:"
    read -p "  Health check command (e.g., 'curl -f http://localhost:8123/ || exit 1'): " HEALTH_CMD
    read -p "  Check interval (default: 30s): " HEALTH_INTERVAL
    HEALTH_INTERVAL=${HEALTH_INTERVAL:-30s}
    read -p "  Retries before unhealthy (default: 3): " HEALTH_RETRIES
    HEALTH_RETRIES=${HEALTH_RETRIES:-3}

    HEALTHCHECK_STRING="HealthCmd=${HEALTH_CMD}\n"
    HEALTHCHECK_STRING+="HealthInterval=${HEALTH_INTERVAL}\n"
    HEALTHCHECK_STRING+="HealthRetries=${HEALTH_RETRIES}\n"
    HEALTHCHECK_STRING+="HealthOnFailure=kill\n"

    echo -e "${GREEN}✓${NC} Health check configured"
else
    HEALTHCHECK_STRING=""
fi

# ============================================================================
# SECTION 7: Pull Container Image
# ============================================================================

echo -e "\n${BLUE}──── Pulling Container Image ────${NC}"
echo -e "Pulling: ${YELLOW}${FQIN_IMAGE_NAME}${NC}"
echo "This may take a few minutes for large images..."

if ! podman pull "$FQIN_IMAGE_NAME"; then
    echo -e "\n${RED}Error: Failed to pull the container image.${NC}" >&2
    echo -e "Please check:" >&2
    echo -e "  - Image name is correct: ${FQIN_IMAGE_NAME}" >&2
    echo -e "  - You have network connectivity" >&2
    echo -e "  - The image exists in the registry" >&2
    exit 1
fi
echo -e "${GREEN}✓ Image pulled successfully.${NC}"

# ============================================================================
# SECTION 8: Generate Quadlet File
# ============================================================================

echo -e "\n${BLUE}──── Generating Quadlet Configuration ────${NC}"

DEST_DIR="/etc/containers/systemd"
DEST_FILE="${DEST_DIR}/${SERVICE_NAME}.container"
mkdir -p "${DEST_DIR}"

echo -e "Creating: ${YELLOW}${DEST_FILE}${NC}"

# --- Generate [Unit] Section ---
cat > "${DEST_FILE}" <<EOC
[Unit]
Description=Podman container - ${SERVICE_NAME}
Wants=network-online.target
After=network-online.target

EOC

# --- Generate [Container] Section ---
cat >> "${DEST_FILE}" <<EOC
[Container]
Image=${FQIN_IMAGE_NAME}
ContainerName=${SERVICE_NAME}
EOC

# Add User directive if in dedicated user mode
if [ "$USER_MODE" = "dedicated" ]; then
    echo "User=${SERVICE_UID}" >> "${DEST_FILE}"
fi

# Add Network mode
echo "Network=${NETWORK_MODE}" >> "${DEST_FILE}"

# Add Pull policy
echo "Pull=${PULL_POLICY}" >> "${DEST_FILE}"

# Add Timezone if requested
if [ "$USE_TIMEZONE" = "yes" ]; then
    echo "Timezone=local" >> "${DEST_FILE}"
fi

# Add AutoUpdate if requested
if [ "$AUTO_UPDATE" = "yes" ]; then
    echo "AutoUpdate=registry" >> "${DEST_FILE}"
fi

# Add SecurityLabelDisable if requested
if [ "$SECURITY_LABEL_DISABLE" = "yes" ]; then
    echo "SecurityLabelDisable=true" >> "${DEST_FILE}"
fi

# Add port mappings
if [ -n "$PROCESSED_PORTS" ]; then
    echo -e "${PROCESSED_PORTS}" >> "${DEST_FILE}"
fi

# Add volume mappings
if [ -n "$PROCESSED_VOLUMES_STRING" ]; then
    echo -e "${PROCESSED_VOLUMES_STRING}" >> "${DEST_FILE}"
fi

# Add environment variables
if [ -n "$PROCESSED_ENV_STRING" ]; then
    echo -e "${PROCESSED_ENV_STRING}" >> "${DEST_FILE}"
fi

# Add health check
if [ -n "$HEALTHCHECK_STRING" ]; then
    echo -e "${HEALTHCHECK_STRING}" >> "${DEST_FILE}"
fi

# --- Generate [Service] Section ---
cat >> "${DEST_FILE}" <<EOC

[Service]
Restart=always
RestartSec=10
TimeoutStartSec=900

EOC

# --- Generate [Install] Section ---
cat >> "${DEST_FILE}" <<EOC
[Install]
WantedBy=default.target
EOC

echo -e "${GREEN}✓ Quadlet file created successfully.${NC}"

# ============================================================================
# SECTION 9: Activate Service
# ============================================================================

echo -e "\n${BLUE}──── Activating Service ────${NC}"

SERVICE_FILE="${SERVICE_NAME}.service"

echo -e "1. Reloading systemd daemon..."
if ! systemctl daemon-reload; then
    echo -e "${RED}Error: Failed to reload systemd.${NC}" >&2
    echo -e "Check: ${YELLOW}journalctl -xe${NC}" >&2
    exit 1
fi
echo -e "   ${GREEN}✓ Success${NC}"

echo -e "2. Starting ${SERVICE_FILE}..."
if ! systemctl start "$SERVICE_FILE"; then
    echo -e "${RED}Error: Failed to start the service.${NC}" >&2
    echo -e "This is often due to:" >&2
    echo -e "  - Configuration error in the Quadlet file" >&2
    echo -e "  - Port already in use" >&2
    echo -e "  - Missing volume paths" >&2
    echo -e "  - Container entrypoint failure" >&2
    echo -e "\nDiagnose with: ${YELLOW}journalctl -u ${SERVICE_FILE} -n 50${NC}" >&2
    exit 1
fi
echo -e "   ${GREEN}✓ Service started${NC}"

echo -e "3. Waiting for service to stabilize..."
sleep 5

# ============================================================================
# SECTION 10: Final Status and Summary
# ============================================================================

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   Deployment Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

if systemctl is-active --quiet "$SERVICE_FILE"; then
    echo -e "${GREEN}✓ SUCCESS${NC} - Service is active and running\n"

    echo -e "${BLUE}Service Details:${NC}"
    echo -e "  Name:        ${YELLOW}${SERVICE_NAME}${NC}"
    echo -e "  Image:       ${YELLOW}${FQIN_IMAGE_NAME}${NC}"
    echo -e "  User Mode:   ${YELLOW}${USER_MODE}${NC}"
    echo -e "  Network:     ${YELLOW}${NETWORK_MODE}${NC}"
    if [ -n "$LXC_IP" ] && [ "$NETWORK_MODE" = "host" ]; then
        echo -e "  Access:      ${YELLOW}http://${LXC_IP}${NC} (on app's port)"
    fi

    echo -e "\n${BLUE}Useful Commands:${NC}"
    echo -e "  Status:      ${YELLOW}systemctl status ${SERVICE_FILE}${NC}"
    echo -e "  Logs:        ${YELLOW}journalctl -u ${SERVICE_FILE} -f${NC}"
    echo -e "  Restart:     ${YELLOW}systemctl restart ${SERVICE_FILE}${NC}"
    echo -e "  Stop:        ${YELLOW}systemctl stop ${SERVICE_FILE}${NC}"
    echo -e "  Disable:     ${YELLOW}systemctl disable ${SERVICE_FILE}${NC}"
    echo -e "  Inspect:     ${YELLOW}podman inspect ${SERVICE_NAME}${NC}"
    echo -e "  Exec shell:  ${YELLOW}podman exec -it ${SERVICE_NAME} /bin/sh${NC}"

    if [ "$AUTO_UPDATE" = "yes" ]; then
        echo -e "\n${BLUE}Auto-Update:${NC}"
        echo -e "  Update now:  ${YELLOW}podman auto-update${NC}"
        echo -e "  Dry run:     ${YELLOW}podman auto-update --dry-run${NC}"
    fi

    echo -e "\n${BLUE}Configuration:${NC}"
    echo -e "  Quadlet:     ${YELLOW}${DEST_FILE}${NC}"
    echo -e "  Edit config: ${YELLOW}nano ${DEST_FILE}${NC} (then run ${YELLOW}systemctl daemon-reload && systemctl restart ${SERVICE_FILE}${NC})"

    # ========================================================================
    # Generate Markdown Summary File
    # ========================================================================

    SUMMARY_FILE="/home/admin/${SERVICE_NAME}-deployment.md"
    DEPLOYMENT_DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')

    cat > "${SUMMARY_FILE}" <<EOF
# ${SERVICE_NAME} - Deployment Summary

**Generated:** ${DEPLOYMENT_DATE}
**Status:** ✅ Active and Running

---

## Service Details

| Property | Value |
|----------|-------|
| **Service Name** | \`${SERVICE_NAME}\` |
| **Container Image** | \`${FQIN_IMAGE_NAME}\` |
| **User Mode** | ${USER_MODE} |
| **Network Mode** | ${NETWORK_MODE} |
EOF

    if [ -n "$LXC_IP" ] && [ "$NETWORK_MODE" = "host" ]; then
        echo "| **Access URL** | http://${LXC_IP} (on app's native port) |" >> "${SUMMARY_FILE}"
    fi

    cat >> "${SUMMARY_FILE}" <<EOF
| **Quadlet Config** | \`${DEST_FILE}\` |
| **Auto-Update** | ${AUTO_UPDATE} |
| **Pull Policy** | ${PULL_POLICY} |

---

## Volume Mounts

EOF

    if [ -n "$VOLUMES_INPUT" ]; then
        echo "| Host Path | Container Path |" >> "${SUMMARY_FILE}"
        echo "|-----------|----------------|" >> "${SUMMARY_FILE}"
        IFS=',' read -ra VOL_ARRAY <<< "$VOLUMES_INPUT"
        for VOL_MAPPING_RAW in "${VOL_ARRAY[@]}"; do
            VOL_MAPPING_RAW=$(echo "$VOL_MAPPING_RAW" | xargs)
            if [ -z "$VOL_MAPPING_RAW" ]; then continue; fi
            HOST_PATH_RAW=$(echo "$VOL_MAPPING_RAW" | cut -d: -f1)
            CONTAINER_PART=$(echo "$VOL_MAPPING_RAW" | cut -d: -f2-)
            if [[ "$HOST_PATH_RAW" == "./"* ]]; then
                RELATIVE_PATH="${HOST_PATH_RAW#./}"
                HOST_PATH_EXPANDED="/var/lib/${SERVICE_NAME}/${RELATIVE_PATH}"
            else
                HOST_PATH_EXPANDED="$HOST_PATH_RAW"
            fi
            echo "| \`${HOST_PATH_EXPANDED}\` | \`${CONTAINER_PART}\` |" >> "${SUMMARY_FILE}"
        done
    else
        echo "*No volumes configured*" >> "${SUMMARY_FILE}"
    fi

    cat >> "${SUMMARY_FILE}" <<EOF

---

## Useful Commands

### Service Management

\`\`\`bash
# Check service status
systemctl status ${SERVICE_FILE}

# View live logs
journalctl -u ${SERVICE_FILE} -f

# Restart service
systemctl restart ${SERVICE_FILE}

# Stop service
systemctl stop ${SERVICE_FILE}

# Disable service (prevent auto-start on boot)
systemctl disable ${SERVICE_FILE}
\`\`\`

### Container Operations

\`\`\`bash
# Inspect container configuration
podman inspect ${SERVICE_NAME}

# Execute commands in the container
podman exec -it ${SERVICE_NAME} /bin/sh

# View container resource usage
podman stats ${SERVICE_NAME}

# View container processes
podman top ${SERVICE_NAME}
\`\`\`

EOF

    if [ "$AUTO_UPDATE" = "yes" ]; then
        cat >> "${SUMMARY_FILE}" <<EOF
### Auto-Update

\`\`\`bash
# Check for and apply updates
podman auto-update

# Dry run (check without applying)
podman auto-update --dry-run
\`\`\`

EOF
    fi

    cat >> "${SUMMARY_FILE}" <<EOF
---

## Configuration Management

### Editing the Quadlet File

1. Edit the configuration:
   \`\`\`bash
   sudo nano ${DEST_FILE}
   \`\`\`

2. Reload systemd and restart:
   \`\`\`bash
   sudo systemctl daemon-reload
   sudo systemctl restart ${SERVICE_FILE}
   \`\`\`

### Current Quadlet Configuration

\`\`\`ini
EOF

    cat "${DEST_FILE}" >> "${SUMMARY_FILE}"

    cat >> "${SUMMARY_FILE}" <<EOF
\`\`\`

---

## Troubleshooting

### View Recent Logs
\`\`\`bash
journalctl -u ${SERVICE_FILE} -n 50
\`\`\`

### View All Logs
\`\`\`bash
journalctl -u ${SERVICE_FILE} --no-pager
\`\`\`

### Check Container Health
\`\`\`bash
podman ps -a | grep ${SERVICE_NAME}
podman logs ${SERVICE_NAME}
\`\`\`

### Manual Container Test
\`\`\`bash
# Stop the service first
systemctl stop ${SERVICE_FILE}

# Run container manually for testing
podman run --rm -it ${FQIN_IMAGE_NAME}
\`\`\`

---

## Additional Resources

- **Podman Documentation:** https://docs.podman.io/
- **Quadlet Documentation:** https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html
- **systemd Documentation:** https://www.freedesktop.org/software/systemd/man/

---

*This summary was automatically generated by the Podman Quadlet Service Generator*
EOF

    # Set ownership to admin user
    chown admin:admin "${SUMMARY_FILE}"
    chmod 644 "${SUMMARY_FILE}"

    echo -e "\n${GREEN}✓${NC} Deployment summary saved to: ${YELLOW}${SUMMARY_FILE}${NC}"

else
    echo -e "${RED}✗ FAILED${NC} - Service failed to become active\n"
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo -e "  View logs:   ${YELLOW}journalctl -u ${SERVICE_FILE} -n 50${NC}"
    echo -e "  Full logs:   ${YELLOW}journalctl -u ${SERVICE_FILE} --no-pager${NC}"
    echo -e "  Check config:${YELLOW}cat ${DEST_FILE}${NC}"
    echo -e "  Manual test: ${YELLOW}podman run --rm ${FQIN_IMAGE_NAME}${NC}"
fi

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
