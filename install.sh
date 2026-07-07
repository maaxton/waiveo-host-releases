#!/bin/bash
# Waiveo Universal Installer
# Supports: Ubuntu 20.04+, Debian 11+
# Architectures: x86_64, arm64
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/maaxton/waiveo-host-releases/main/install.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/maaxton/waiveo-host-releases/main/install.sh | sudo bash -s -- --version v1.0.0
#
# Environment variables:
#   WAIVEO_VERSION - specific version to install (default: latest)

set -e

# Configuration
WAIVEO_VERSION="${WAIVEO_VERSION:-latest}"
GITHUB_REPO="maaxton/waiveo-host-releases"
RELEASES_URL="https://github.com/${GITHUB_REPO}/releases"
INSTALL_DIR="/opt/waiveo"

# Install options (can be set via command line)
SET_HOSTNAME="${SET_HOSTNAME:-false}"
WAIVEO_PORT="${WAIVEO_PORT:-80}"
WAIVEO_DOCKER_TAG="${WAIVEO_DOCKER_TAG:-latest}"
INTERACTIVE_MODE="true"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

fatal() {
    error "$1"
    exit 1
}

# Print banner
print_banner() {
    echo -e "${BOLD}${CYAN}"
    echo '  __        __    _                '
    echo '  \ \      / /_ _(_)_   _____  ___ '
    echo '   \ \ /\ / / _` | \ \ / / _ \/ _ \'
    echo '    \ V  V / (_| | |\ V /  __/ (_) |'
    echo '     \_/\_/ \__,_|_| \_/ \___|\___/'
    echo -e "${NC}"
    echo -e "${BOLD}Universal Installer${NC}"
    echo ""
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        fatal "This script must be run as root. Use: curl ... | sudo bash"
    fi
}

# Detect architecture
detect_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            warn "32-bit ARM detected. Performance may be limited."
            echo "armv7"
            ;;
        *)
            fatal "Unsupported architecture: $arch"
            ;;
    esac
}

# Detect OS
detect_os() {
    if [ ! -f /etc/os-release ]; then
        fatal "Cannot detect OS. /etc/os-release not found."
    fi
    
    . /etc/os-release
    
    case "$ID" in
        ubuntu)
            # Check version (need 20.04+)
            local version=$(echo "$VERSION_ID" | cut -d. -f1)
            if [ "$version" -lt 20 ]; then
                fatal "Ubuntu 20.04 or later required. Found: $VERSION_ID"
            fi
            echo "ubuntu"
            ;;
        debian)
            # Check version (need 11+)
            local version=$(echo "$VERSION_ID" | cut -d. -f1)
            if [ "$version" -lt 11 ]; then
                fatal "Debian 11 or later required. Found: $VERSION_ID"
            fi
            echo "debian"
            ;;
        raspbian)
            echo "raspbian"
            ;;
        *)
            warn "Unsupported OS: $ID. Proceeding anyway, but may encounter issues."
            echo "$ID"
            ;;
    esac
}

# Check for Raspberry Pi
is_raspberry_pi() {
    if [ -f /proc/device-tree/model ]; then
        grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null && return 0
    fi
    return 1
}

# Check system requirements
check_requirements() {
    info "Checking system requirements..."
    
    # Check memory (need at least 2GB, recommend 4GB)
    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$((mem_kb / 1024 / 1024))
    
    if [ "$mem_gb" -lt 2 ]; then
        fatal "Minimum 2GB RAM required. Found: ${mem_gb}GB"
    elif [ "$mem_gb" -lt 4 ]; then
        warn "4GB+ RAM recommended for best performance. Found: ${mem_gb}GB"
    fi
    
    # Check disk space (need at least 5GB free)
    local free_gb=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
    if [ "$free_gb" -lt 5 ]; then
        fatal "Minimum 5GB free disk space required. Found: ${free_gb}GB"
    fi
    
    success "System requirements met (RAM: ${mem_gb}GB, Disk: ${free_gb}GB free)"
}

# Correct a badly-wrong system clock before apt. A freshly-imaged box whose RTC is
# wrong — and whose network blocks NTP (UDP 123) — makes apt reject repository
# Release files as "not valid yet", which aborts the install. Try NTP first; if the
# clock is still off by more than an hour, set it from an HTTP Date header (HTTP
# works where NTP is firewalled). A correct clock is never touched.
ensure_clock_sane() {
    timedatectl set-ntp true 2>/dev/null || true
    local http_date http_epoch now_epoch skew
    http_date=$(curl -sI --max-time 10 http://archive.ubuntu.com 2>/dev/null \
        | grep -i '^date:' | cut -d' ' -f2- | tr -d '\r')
    [ -n "$http_date" ] || return 0
    http_epoch=$(date -d "$http_date" +%s 2>/dev/null || echo 0)
    [ "$http_epoch" -gt 0 ] || return 0
    now_epoch=$(date +%s)
    skew=$(( http_epoch - now_epoch )); skew=${skew#-}
    if [ "$skew" -gt 3600 ]; then
        warn "System clock off by ~$(( skew / 3600 ))h — setting from network time so apt can validate repositories"
        timedatectl set-ntp false 2>/dev/null || true
        date -s "$http_date" >/dev/null 2>&1 || true
        hwclock --systohc 2>/dev/null || true
        success "Clock set to $(date -u '+%Y-%m-%d %H:%M UTC')"
    fi
}

# Install dependencies
install_dependencies() {
    info "Installing dependencies..."

    # A wrong clock makes apt reject repo metadata — fix it before any apt call.
    ensure_clock_sane

    # Update package list
    apt-get update -qq
    
    # Install required packages
    apt-get install -y -qq \
        curl \
        ca-certificates \
        gnupg \
        avahi-daemon \
        avahi-utils \
        python3 \
        > /dev/null
    
    success "Dependencies installed"
}

# Install Docker if not present
install_docker() {
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
        success "Docker already installed (version $docker_version)"
        
        # Ensure Docker is running
        if ! systemctl is-active --quiet docker; then
            info "Starting Docker service..."
            systemctl start docker
        fi
        return 0
    fi
    
    info "Installing Docker..."
    
    # Use official Docker install script
    curl -fsSL https://get.docker.com | sh
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    success "Docker installed successfully"
}

# Show interactive configuration menu using Python
show_interactive_menu() {
    # Check if we have a terminal available
    if [ ! -e /dev/tty ]; then
        warn "No terminal available for interactive mode, using defaults"
        return
    fi
    
    info "Starting interactive configuration..."
    echo ""
    
    # Run Python script for interactive prompts
    local config_output
    config_output=$(python3 << 'PYTHON_SCRIPT'
import sys

# ANSI colors
CYAN = '\033[0;36m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BOLD = '\033[1m'
NC = '\033[0m'  # No Color

def get_input(prompt, default=""):
    """Get input from /dev/tty to work with piped scripts"""
    try:
        with open('/dev/tty', 'r') as tty:
            sys.stderr.write(prompt)
            sys.stderr.flush()
            return tty.readline().strip()
    except:
        return default

def ask_yes_no(question, default=False):
    """Ask a yes/no question"""
    hint = "[Y/n]" if default else "[y/N]"
    response = get_input(f"{CYAN}{question}{NC} {hint}: ")
    if not response:
        return default
    return response.lower() in ('y', 'yes')

def ask_input(question, default, hint=""):
    """Ask for text input"""
    prompt = f"{CYAN}{question}{NC}"
    if hint:
        prompt += f" {hint}"
    prompt += f" [{default}]: "
    response = get_input(prompt)
    return response if response else default

# Print header
sys.stderr.write(f"\n{BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{NC}\n")
sys.stderr.write(f"{BOLD}       Waiveo Configuration{NC}\n")
sys.stderr.write(f"{BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{NC}\n\n")

# Hostname question
sys.stderr.write(f"Setting the hostname to 'waiveo' enables access via:\n")
sys.stderr.write(f"  {GREEN}http://waiveo.local{NC}\n\n")
set_hostname = ask_yes_no("Set hostname to 'waiveo'?", default=True)

sys.stderr.write("\n")

# Port question
sys.stderr.write(f"The web interface runs on port 80 by default.\n")
sys.stderr.write(f"Change this if port 80 is already in use.\n\n")
port = ask_input("Web server port", "80")

# Validate port
try:
    port_num = int(port)
    if not (1 <= port_num <= 65535):
        port = "80"
except:
    port = "80"

sys.stderr.write("\n")

# Docker tag question
sys.stderr.write(f"The Docker image tag controls which build of Waiveo is installed.\n")
sys.stderr.write(f"  {GREEN}latest{NC} - stable release (recommended)\n")
sys.stderr.write(f"  {YELLOW}alpha{NC}  - pre-release (may be unstable)\n\n")
docker_tag = ask_input("Docker tag", "latest", "(e.g. latest, alpha, 20260409)")

# Sanitize tag: only alphanumeric + dash + dot + underscore
import re
if not re.match(r'^[a-zA-Z0-9.\-_]+$', docker_tag):
    docker_tag = "latest"

sys.stderr.write(f"\n{BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{NC}\n\n")

# Output configuration to stdout (captured by bash)
print(f"SET_HOSTNAME={'true' if set_hostname else 'false'}")
print(f"WAIVEO_PORT={port}")
print(f"WAIVEO_DOCKER_TAG={docker_tag}")
PYTHON_SCRIPT
)
    
    # Parse Python output (explicit variable extraction — never eval untrusted output)
    if [ -n "$config_output" ]; then
        SET_HOSTNAME=$(echo "$config_output" | grep '^SET_HOSTNAME=' | cut -d= -f2-)
        WAIVEO_PORT=$(echo "$config_output" | grep '^WAIVEO_PORT=' | cut -d= -f2-)
        WAIVEO_DOCKER_TAG=$(echo "$config_output" | grep '^WAIVEO_DOCKER_TAG=' | cut -d= -f2-)
    fi

    # Display confirmation
    if [ "$SET_HOSTNAME" = "true" ]; then
        success "Hostname will be set to 'waiveo'"
    else
        info "Keeping current hostname"
    fi
    success "Web server will run on port $WAIVEO_PORT"
    success "Docker tag: $WAIVEO_DOCKER_TAG"
    echo ""
}

# Get latest release version from GitHub
get_latest_version() {
    local latest=$(curl -fsSL "${RELEASES_URL}/latest" 2>/dev/null | grep -o 'tag/v[^"]*' | head -1 | cut -d/ -f2)
    if [ -z "$latest" ]; then
        fatal "Could not determine latest version. Check your internet connection."
    fi
    echo "$latest"
}

# Download and extract release
download_release() {
    local version="$1"
    local arch="$2"
    
    info "Downloading Waiveo ${version}..."
    
    local tarball_url="${RELEASES_URL}/download/${version}/waiveo-cli.tar.gz"
    local temp_dir=$(mktemp -d)
    local tarball="${temp_dir}/waiveo-cli.tar.gz"
    
    # Download tarball
    if ! curl -fsSL "$tarball_url" -o "$tarball"; then
        rm -rf "$temp_dir"
        fatal "Failed to download release from: $tarball_url"
    fi
    
    # Create directories
    mkdir -p "$INSTALL_DIR"/{templates,static,backups}
    mkdir -p /usr/local/bin
    mkdir -p /etc/systemd/system
    
    # Extract tarball
    info "Extracting files..."
    tar -xzf "$tarball" -C / --no-same-owner
    
    # Set execute permissions on CLI tools
    chmod +x /usr/local/bin/waiveo* 2>/dev/null || true
    
    # Cleanup
    rm -rf "$temp_dir"
    
    success "Files extracted successfully"
}

# Configure system
configure_system() {
    info "Configuring system..."
    
    local hostname_changed="false"
    
    # Set hostname to 'waiveo' if on Pi or if user requested it
    if is_raspberry_pi || [ "$SET_HOSTNAME" = "true" ]; then
        local current_hostname=$(hostname)
        if [ "$current_hostname" != "waiveo" ]; then
            info "Setting hostname to 'waiveo'..."
            hostnamectl set-hostname waiveo
            
            # Update /etc/hosts
            if ! grep -q "127.0.1.1.*waiveo" /etc/hosts; then
                # Remove any existing 127.0.1.1 entry first
                sed -i '/^127.0.1.1/d' /etc/hosts 2>/dev/null || true
                echo "127.0.1.1 waiveo" >> /etc/hosts
            fi
            
            hostname_changed="true"
            success "Hostname set to 'waiveo'"
            
            # Wait for hostname change to propagate
            sleep 2
        fi
    fi
    
    # Configure Avahi for mDNS (hostname.local)
    info "Configuring mDNS (Avahi)..."
    
    # Ensure avahi is configured to publish hostname
    if [ -f /etc/avahi/avahi-daemon.conf ]; then
        # Enable publish-hostname if not already set
        if ! grep -q "^publish-hostname=yes" /etc/avahi/avahi-daemon.conf; then
            sed -i 's/^#*publish-hostname=.*/publish-hostname=yes/' /etc/avahi/avahi-daemon.conf 2>/dev/null || true
        fi
    fi
    
    # Enable and restart Avahi (always restart to ensure it picks up current hostname)
    systemctl enable avahi-daemon 2>/dev/null || true
    systemctl restart avahi-daemon 2>/dev/null || true
    
    # Give avahi a moment to start publishing
    sleep 1
    
    # Open firewall for mDNS if ufw is active
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        info "Opening firewall for mDNS..."
        ufw allow 5353/udp comment 'mDNS' >/dev/null 2>&1 || true
    fi
    
    # Verify Avahi is running and publishing
    if systemctl is-active --quiet avahi-daemon; then
        success "mDNS configured - accessible at http://waiveo.local"
    else
        warn "Avahi service not running - waiveo.local may not work"
    fi
    
    # Configure custom port if specified
    if [ "$WAIVEO_PORT" != "80" ]; then
        info "Configuring web server on port $WAIVEO_PORT..."
        
        # Create systemd override directory
        mkdir -p /etc/systemd/system/waiveo-management.service.d
        
        # Create override file with custom port
        cat > /etc/systemd/system/waiveo-management.service.d/port.conf << EOF
[Service]
Environment=WAIVEO_PORT=$WAIVEO_PORT
EOF
        
        success "Web server configured on port $WAIVEO_PORT"
    fi
    
    # On x86, don't create a waiveo user - users have their own accounts
    # The management UI authenticates against existing system users via PAM
    # Just ensure the current user (who ran sudo) can use Docker
    if ! is_raspberry_pi; then
        # Add the user who ran sudo to docker group
        if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
            usermod -aG docker "$SUDO_USER" 2>/dev/null || true
            info "Added $SUDO_USER to docker group (re-login to take effect)"
        fi
    fi
    
    success "System configured"
}

# Enable and start services
enable_services() {
    info "Enabling services..."
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable services
    systemctl enable waiveo-management.service 2>/dev/null || true
    systemctl enable waiveo.service 2>/dev/null || true

    # Boot-time factory-reset processor: reads /boot/firmware/waiveo/ flags before
    # sysinit and acts on them. The Pi image enables this in stage-waiveo/00-run.sh;
    # the universal (x86/arm64) installer must too — otherwise `waiveo reset` writes
    # a flag that nothing ever processes and the reboot appears to do nothing.
    if [ -f /etc/systemd/system/waiveo-factory-reset.service ]; then
        systemctl enable waiveo-factory-reset.service 2>/dev/null || true
    fi

    # Start management server
    systemctl start waiveo-management.service
    
    success "Services enabled"
}

# Write Docker tag into state.json so the management server uses it on first boot
configure_docker_tag() {
    local tag="${WAIVEO_DOCKER_TAG:-latest}"
    local state_file="${INSTALL_DIR}/state.json"

    # Validate tag (alphanumeric + dash + dot + underscore only)
    if ! echo "$tag" | grep -qE '^[a-zA-Z0-9._-]+$'; then
        warn "Invalid Docker tag '$tag', defaulting to 'latest'"
        tag="latest"
    fi

    if [ -f "$state_file" ]; then
        # Update existing state.json: set docker_tag field using Python (stdlib JSON)
        python3 - "$state_file" "$tag" << 'PYEOF'
import json, sys
path, tag = sys.argv[1], sys.argv[2]
with open(path) as f:
    state = json.load(f)
state['docker_tag'] = tag
tmp = path + '.tmp'
with open(tmp, 'w') as f:
    json.dump(state, f, indent=2)
import os; os.rename(tmp, path)
PYEOF
        success "Docker tag set to: $tag"
    else
        info "state.json not found yet — tag will be applied on first setup"
    fi

    # Also update docker-compose.yml image reference if it exists
    local compose_file="${INSTALL_DIR}/docker-compose.yml"
    if [ -f "$compose_file" ]; then
        # Replace the image: maaxton/waiveo:* line
        sed -i "s|image: maaxton/waiveo:.*|image: maaxton/waiveo:${tag}|g" "$compose_file"
        success "docker-compose.yml updated: maaxton/waiveo:${tag}"
    fi
}

# Get local IP address
get_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown"
}

# Print completion message
print_complete() {
    local ip=$(get_local_ip)
    local port_suffix=""
    
    # Add port to URL if not default
    if [ "$WAIVEO_PORT" != "80" ]; then
        port_suffix=":${WAIVEO_PORT}"
    fi
    
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Installation Complete!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "Access Waiveo at:"
    echo -e "  ${BOLD}http://${ip}${port_suffix}${NC}"
    
    if is_raspberry_pi || [ "$SET_HOSTNAME" = "true" ]; then
        echo -e "  ${BOLD}http://waiveo.local${port_suffix}${NC}"
    fi
    
    if is_raspberry_pi; then
        echo ""
        echo -e "Default credentials:"
        echo -e "  Username: ${BOLD}waiveo${NC}"
        echo -e "  Password: ${BOLD}TemporaryBootstrapPassword123!${NC}"
        echo ""
        echo -e "${YELLOW}You will be prompted to change the password on first login.${NC}"
    else
        echo ""
        echo -e "Login with your ${BOLD}existing Linux username and password${NC}."
        echo -e "(The management UI uses your system credentials)"
    fi
    echo ""
    echo -e "Docker image: ${BOLD}maaxton/waiveo:${WAIVEO_DOCKER_TAG}${NC}"
    echo ""
    echo -e "CLI commands available:"
    echo -e "  ${CYAN}waiveo status${NC}   - Check service status"
    echo -e "  ${CYAN}waiveo logs${NC}     - View logs"
    echo -e "  ${CYAN}waiveo update${NC}   - Update to latest version"
    echo -e "  ${CYAN}waiveo --help${NC}   - Show all commands"
    echo ""
}

# Parse command line arguments
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --version|-v)
                WAIVEO_VERSION="$2"
                shift 2
                ;;
            --set-hostname)
                SET_HOSTNAME="true"
                INTERACTIVE_MODE="false"
                shift
                ;;
            --port|-p)
                WAIVEO_PORT="$2"
                INTERACTIVE_MODE="false"
                shift 2
                ;;
            --tag|-t)
                WAIVEO_DOCKER_TAG="$2"
                INTERACTIVE_MODE="false"
                shift 2
                ;;
            --non-interactive|-y)
                INTERACTIVE_MODE="false"
                shift
                ;;
            --help|-h)
                echo "Waiveo Installer"
                echo ""
                echo "Usage: curl -fsSL https://raw.githubusercontent.com/maaxton/waiveo-host-releases/main/install.sh | sudo bash"
                echo "       curl -fsSL https://raw.githubusercontent.com/maaxton/waiveo-host-releases/main/install.sh | sudo bash -s -- [options]"
                echo ""
                echo "By default, the installer runs in interactive mode with dialog prompts."
                echo ""
                echo "Options:"
                echo "  --version, -v VERSION   Install specific version (e.g., v1.0.0)"
                echo "  --set-hostname          Set hostname to 'waiveo' for waiveo.local access"
                echo "  --port, -p PORT         Set web server port (default: 80)"
                echo "  --tag, -t TAG           Docker image tag to use (default: latest)"
                echo "  --non-interactive, -y   Skip interactive prompts, use defaults/flags"
                echo "  --help, -h              Show this help message"
                echo ""
                echo "Environment variables:"
                echo "  WAIVEO_VERSION          Specific version to install"
                echo "  SET_HOSTNAME            Set to 'true' to enable waiveo.local"
                echo "  WAIVEO_PORT             Web server port (default: 80)"
                echo "  WAIVEO_DOCKER_TAG       Docker image tag to pull (default: latest)"
                echo ""
                echo "Examples:"
                echo "  # Interactive install (prompts for options)"
                echo "  curl -fsSL ... | sudo bash"
                echo ""
                echo "  # Non-interactive with waiveo.local hostname"
                echo "  curl -fsSL ... | sudo bash -s -- --set-hostname"
                echo ""
                echo "  # Non-interactive on custom port 8080"
                echo "  curl -fsSL ... | sudo bash -s -- --port 8080"
                echo ""
                echo "  # Non-interactive with defaults (no prompts)"
                echo "  curl -fsSL ... | sudo bash -s -- -y"
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
}

# Main installation function
main() {
    parse_args "$@"
    
    print_banner
    check_root
    
    # Detect system
    local arch=$(detect_arch)
    local os=$(detect_os)
    local is_pi="no"
    is_raspberry_pi && is_pi="yes"
    
    echo -e "System detected:"
    echo -e "  Architecture: ${BOLD}$arch${NC}"
    echo -e "  OS: ${BOLD}$os${NC}"
    echo -e "  Raspberry Pi: ${BOLD}$is_pi${NC}"
    echo ""
    
    if [ "$is_pi" = "yes" ]; then
        warn "Raspberry Pi detected. Consider using the pre-built image instead:"
        echo "  https://github.com/${GITHUB_REPO}/releases"
        echo ""
    fi
    
    check_requirements
    install_dependencies
    install_docker
    
    # Show interactive menu if no CLI flags were passed
    if [ "$INTERACTIVE_MODE" = "true" ]; then
        show_interactive_menu
    fi
    
    # Determine version
    if [ "$WAIVEO_VERSION" = "latest" ]; then
        WAIVEO_VERSION=$(get_latest_version)
    fi
    info "Installing version: $WAIVEO_VERSION"
    
    download_release "$WAIVEO_VERSION" "$arch"
    # Record the installed version so the mgmt server reports it accurately
    # (get_host_image_version reads /etc/waiveo-host-release; without this the
    # dashboard shows host_image "unknown" on a universal install).
    echo "${WAIVEO_VERSION#v}" > /etc/waiveo-host-release 2>/dev/null || true
    configure_system
    configure_docker_tag
    enable_services
    
    print_complete
}

# Run main function
main "$@"
