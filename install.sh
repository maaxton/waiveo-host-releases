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

# Install dependencies
install_dependencies() {
    info "Installing dependencies..."
    
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
    
    # Cleanup
    rm -rf "$temp_dir"
    
    success "Files extracted successfully"
}

# Configure system
configure_system() {
    info "Configuring system..."
    
    # Set hostname if not already waiveo
    local current_hostname=$(hostname)
    if [ "$current_hostname" != "waiveo" ]; then
        info "Setting hostname to 'waiveo'..."
        hostnamectl set-hostname waiveo
        
        # Update /etc/hosts
        if ! grep -q "waiveo" /etc/hosts; then
            echo "127.0.1.1 waiveo" >> /etc/hosts
        fi
    fi
    
    # Enable Avahi for mDNS (waiveo.local)
    systemctl enable avahi-daemon 2>/dev/null || true
    systemctl start avahi-daemon 2>/dev/null || true
    
    # Create waiveo user if it doesn't exist
    if ! id -u waiveo &>/dev/null; then
        info "Creating waiveo user..."
        useradd -m -s /bin/bash -G sudo,docker waiveo 2>/dev/null || true
        echo 'waiveo:TemporaryBootstrapPassword123!' | chpasswd
    fi
    
    # Add waiveo to docker group
    usermod -aG docker waiveo 2>/dev/null || true
    
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
    
    # Start management server
    systemctl start waiveo-management.service
    
    success "Services enabled"
}

# Get local IP address
get_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown"
}

# Print completion message
print_complete() {
    local ip=$(get_local_ip)
    
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Installation Complete!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "Access Waiveo at:"
    echo -e "  ${BOLD}http://${ip}${NC}"
    echo -e "  ${BOLD}http://waiveo.local${NC} (if mDNS works)"
    echo ""
    echo -e "Default credentials:"
    echo -e "  Username: ${BOLD}waiveo${NC}"
    echo -e "  Password: ${BOLD}TemporaryBootstrapPassword123!${NC}"
    echo ""
    echo -e "${YELLOW}You will be prompted to change the password on first login.${NC}"
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
            --help|-h)
                echo "Waiveo Installer"
                echo ""
                echo "Usage: curl -fsSL https://raw.githubusercontent.com/maaxton/waiveo-host-releases/main/install.sh | sudo bash"
                echo "       curl -fsSL https://raw.githubusercontent.com/maaxton/waiveo-host-releases/main/install.sh | sudo bash -s -- [options]"
                echo ""
                echo "Options:"
                echo "  --version, -v VERSION   Install specific version (e.g., v1.0.0)"
                echo "  --help, -h              Show this help message"
                echo ""
                echo "Environment variables:"
                echo "  WAIVEO_VERSION          Specific version to install"
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
    
    # Determine version
    if [ "$WAIVEO_VERSION" = "latest" ]; then
        WAIVEO_VERSION=$(get_latest_version)
    fi
    info "Installing version: $WAIVEO_VERSION"
    
    download_release "$WAIVEO_VERSION" "$arch"
    configure_system
    enable_services
    
    print_complete
}

# Run main function
main "$@"
