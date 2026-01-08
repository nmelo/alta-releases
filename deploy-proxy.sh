#!/bin/bash
#
# Alta Relay Proxy Deployment Script (for Raspberry Pi / Linux)
#
# Usage: curl -sSL https://raw.githubusercontent.com/nmelo/alta-releases/main/deploy-proxy.sh | sudo bash -s -- [OPTIONS]
#    or: ./deploy-proxy.sh [OPTIONS]
#
# Options:
#   --version VERSION    Version to install (default: latest)
#   --server HOST:PORT   Relay server address (required)
#   --session ID         Session ID (required)
#   --drone IP           Drone IP address (default: 192.168.0.203)
#   --uninstall          Remove alta-proxy
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Defaults
VERSION="latest"
SERVER=""
SESSION=""
DRONE_IP="192.168.0.203"
UNINSTALL=false

BINARY_NAME="alta-proxy"
BINARY_PATH="/usr/local/bin/${BINARY_NAME}"
SERVICE_NAME="alta-proxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
GITHUB_REPO="nmelo/alta-releases"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --server)
            SERVER="$2"
            shift 2
            ;;
        --session)
            SESSION="$2"
            shift 2
            ;;
        --drone)
            DRONE_IP="$2"
            shift 2
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            BINARY_SUFFIX="linux-amd64"
            ;;
        aarch64)
            BINARY_SUFFIX="linux-arm64"
            ;;
        armv7l|armv6l)
            BINARY_SUFFIX="linux-arm"
            ;;
        *)
            error "Unsupported architecture: $ARCH"
            ;;
    esac
    log "Detected architecture: $ARCH -> $BINARY_SUFFIX"
}

get_latest_version() {
    if [[ "$VERSION" == "latest" ]]; then
        VERSION=$(curl -sSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ -z "$VERSION" ]]; then
            error "Failed to get latest version"
        fi
    fi
    log "Version: $VERSION"
}

download_binary() {
    local url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/alta-proxy-${BINARY_SUFFIX}"
    log "Downloading from: $url"

    if ! curl -sSL -o /tmp/alta-proxy "$url"; then
        error "Failed to download binary"
    fi

    chmod +x /tmp/alta-proxy
    mv /tmp/alta-proxy "$BINARY_PATH"
    log "Installed to: $BINARY_PATH"
}

create_service() {
    log "Creating systemd service..."

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Alta Relay Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BINARY_PATH} -server ${SERVER} -session ${SESSION} -drone ${DRONE_IP}
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log "Service created: $SERVICE_FILE"
}

start_service() {
    log "Starting service..."
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log "Service started successfully"
    else
        error "Service failed to start. Check: journalctl -u $SERVICE_NAME"
    fi
}

setup_wifi_gui() {
    log "Setting up WiFi management..."

    # Install wpa_gui if not present
    if ! command -v wpa_gui &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq wpagui
    fi

    # Ensure wpa_supplicant has ctrl_interface
    if ! grep -q "ctrl_interface" /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null; then
        cat > /etc/wpa_supplicant/wpa_supplicant.conf <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US
EOF
        systemctl restart wpa_supplicant
    fi

    log "WiFi GUI available: run 'wpa_gui' on desktop"
}

show_status() {
    echo ""
    echo "========================================"
    echo "  Alta Relay Proxy Deployed"
    echo "========================================"
    echo ""
    echo "  Version:    $VERSION"
    echo "  Server:     $SERVER"
    echo "  Session:    $SESSION"
    echo "  Drone:      $DRONE_IP"
    echo "  Binary:     $BINARY_PATH"
    echo ""
    echo "  Commands:"
    echo "    Status:   systemctl status $SERVICE_NAME"
    echo "    Logs:     journalctl -u $SERVICE_NAME -f"
    echo "    Restart:  systemctl restart $SERVICE_NAME"
    echo ""
    echo "  WiFi:       Run 'wpa_gui' on desktop to switch networks"
    echo ""
}

uninstall() {
    log "Uninstalling Alta Proxy..."

    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME"
    fi

    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME"
    fi

    rm -f "$SERVICE_FILE"
    rm -f "$BINARY_PATH"
    systemctl daemon-reload

    log "Uninstalled successfully"
    exit 0
}

main() {
    echo ""
    echo "Alta Relay Proxy Deployment"
    echo "==========================="
    echo ""

    check_root

    if [[ "$UNINSTALL" == true ]]; then
        uninstall
    fi

    # Validate required args
    if [[ -z "$SERVER" ]]; then
        error "Missing required option: --server HOST:PORT"
    fi
    if [[ -z "$SESSION" ]]; then
        error "Missing required option: --session ID"
    fi

    detect_arch
    get_latest_version

    # Stop existing service if running
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        log "Stopping existing service..."
        systemctl stop "$SERVICE_NAME"
    fi

    download_binary
    create_service
    setup_wifi_gui
    start_service
    show_status
}

main
