#!/bin/bash
#
# Alta Relay Server Deployment Script
#
# Usage: curl -sSL https://raw.githubusercontent.com/nmelo/alta-releases/main/deploy-server.sh | sudo bash
#    or: ./deploy-server.sh [OPTIONS]
#
# Options:
#   --version VERSION    Version to install (default: latest)
#   --port PORT          Control port (default: 5000)
#   --min-port PORT      Min tunnel port (default: 5010)
#   --max-port PORT      Max tunnel port (default: 5100)
#   --api-key KEY        API key for authentication
#   --no-firewall        Skip firewall configuration
#   --uninstall          Remove alta-relay
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Defaults
VERSION="latest"
CONTROL_PORT=5000
MIN_PORT=5010
MAX_PORT=5100
API_KEY=""
CONFIGURE_FIREWALL=true
UNINSTALL=false

BINARY_NAME="alta-relay"
BINARY_PATH="/usr/local/bin/${BINARY_NAME}"
SERVICE_NAME="alta-relay"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
GITHUB_REPO="nmelo/alta-releases"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --port)
            CONTROL_PORT="$2"
            shift 2
            ;;
        --min-port)
            MIN_PORT="$2"
            shift 2
            ;;
        --max-port)
            MAX_PORT="$2"
            shift 2
            ;;
        --api-key)
            API_KEY="$2"
            shift 2
            ;;
        --no-firewall)
            CONFIGURE_FIREWALL=false
            shift
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

log() {
    echo -e "${GREEN}[+]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[x]${NC} $1"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="arm"
            ;;
        *)
            error "Unsupported architecture: $ARCH"
            ;;
    esac
    log "Detected architecture: $ARCH"
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
    local url="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/alta-server-linux-${ARCH}"
    log "Downloading from: $url"

    if ! curl -sSL -o /tmp/alta-relay "$url"; then
        error "Failed to download binary"
    fi

    chmod +x /tmp/alta-relay
    mv /tmp/alta-relay "$BINARY_PATH"
    log "Installed to: $BINARY_PATH"
}

create_service() {
    log "Creating systemd service..."

    local extra_args=""
    if [[ -n "$API_KEY" ]]; then
        extra_args="$extra_args -api-key $API_KEY"
    fi

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Alta Relay Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BINARY_PATH} -port ${CONTROL_PORT} -bind 0.0.0.0 -min-port ${MIN_PORT} -max-port ${MAX_PORT} -stats -stats-interval 5${extra_args}
Restart=always
RestartSec=5
LimitNOFILE=65535

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    log "Service created: $SERVICE_FILE"
}

configure_firewall() {
    if [[ "$CONFIGURE_FIREWALL" != true ]]; then
        warn "Skipping firewall configuration"
        return
    fi

    log "Configuring firewall..."

    # Check for ufw
    if command -v ufw &> /dev/null; then
        ufw allow ${CONTROL_PORT}/udp comment "Alta Relay Control"
        ufw allow ${MIN_PORT}:${MAX_PORT}/udp comment "Alta Relay Tunnels"
        ufw allow ${MIN_PORT}:${MAX_PORT}/tcp comment "Alta Relay RTSP"
        log "UFW rules added"
    # Check for firewalld
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=${CONTROL_PORT}/udp
        firewall-cmd --permanent --add-port=${MIN_PORT}-${MAX_PORT}/udp
        firewall-cmd --permanent --add-port=${MIN_PORT}-${MAX_PORT}/tcp
        firewall-cmd --reload
        log "Firewalld rules added"
    # Check for iptables
    elif command -v iptables &> /dev/null; then
        iptables -A INPUT -p udp --dport ${CONTROL_PORT} -j ACCEPT
        iptables -A INPUT -p udp --dport ${MIN_PORT}:${MAX_PORT} -j ACCEPT
        iptables -A INPUT -p tcp --dport ${MIN_PORT}:${MAX_PORT} -j ACCEPT
        log "iptables rules added (not persisted)"
        warn "Run 'iptables-save > /etc/iptables/rules.v4' to persist"
    else
        warn "No firewall detected, skipping"
    fi
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

show_status() {
    echo ""
    echo "========================================"
    echo "  Alta Relay Server Deployed"
    echo "========================================"
    echo ""
    echo "  Version:      $VERSION"
    echo "  Control Port: $CONTROL_PORT/udp"
    echo "  Tunnel Ports: $MIN_PORT-$MAX_PORT"
    echo "  Binary:       $BINARY_PATH"
    echo "  Service:      $SERVICE_NAME"
    echo ""
    echo "  Commands:"
    echo "    Status:   systemctl status $SERVICE_NAME"
    echo "    Logs:     journalctl -u $SERVICE_NAME -f"
    echo "    Restart:  systemctl restart $SERVICE_NAME"
    echo "    Stop:     systemctl stop $SERVICE_NAME"
    echo ""
    echo "  Connect proxy/client to: $(curl -s ifconfig.me):$CONTROL_PORT"
    echo ""
}

uninstall() {
    log "Uninstalling Alta Relay..."

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
    echo "Alta Relay Server Deployment"
    echo "============================"
    echo ""

    check_root

    if [[ "$UNINSTALL" == true ]]; then
        uninstall
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
    configure_firewall
    start_service
    show_status
}

main
