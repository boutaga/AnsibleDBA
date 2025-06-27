#!/bin/bash
# Oracle Database Exporter Deployment Script for PMM/Prometheus
# Supports both Oracle official exporter and iamseth/oracledb_exporter

set -euo pipefail

# Configuration
EXPORTER_VERSION="${EXPORTER_VERSION:-0.6.0}"
EXPORTER_USER="${EXPORTER_USER:-sql_exporter}"
EXPORTER_GROUP="${EXPORTER_GROUP:-sql_exporter}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${CONFIG_DIR:-/etc/oracledb_exporter}"
SERVICE_NAME="oracledb_exporter"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Create system user and group
create_user() {
    log_info "Creating system user and group: $EXPORTER_USER"
    
    if ! getent group "$EXPORTER_GROUP" >/dev/null 2>&1; then
        groupadd --system "$EXPORTER_GROUP"
        log_success "Created group: $EXPORTER_GROUP"
    else
        log_info "Group $EXPORTER_GROUP already exists"
    fi
    
    if ! getent passwd "$EXPORTER_USER" >/dev/null 2>&1; then
        useradd --system \
                --home /nonexistent \
                --shell /usr/sbin/nologin \
                --gid "$EXPORTER_GROUP" \
                "$EXPORTER_USER"
        log_success "Created user: $EXPORTER_USER"
    else
        log_info "User $EXPORTER_USER already exists"
    fi
}

# Download and install Oracle exporter binary
install_exporter() {
    log_info "Downloading Oracle DB Exporter v${EXPORTER_VERSION}"
    
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    local download_url="https://github.com/iamseth/oracledb_exporter/releases/download/${EXPORTER_VERSION}/oracledb_exporter.tar.gz"
    
    if ! wget -q --show-progress "$download_url"; then
        log_error "Failed to download Oracle exporter from $download_url"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    log_info "Extracting Oracle exporter"
    tar xfz oracledb_exporter.tar.gz
    
    # Find the binary (path may vary)
    local binary_path
    if [[ -f "oracledb_exporter-${EXPORTER_VERSION}.linux-amd64/oracledb_exporter" ]]; then
        binary_path="oracledb_exporter-${EXPORTER_VERSION}.linux-amd64/oracledb_exporter"
    elif [[ -f "oracledb_exporter" ]]; then
        binary_path="oracledb_exporter"
    else
        log_error "Could not find oracledb_exporter binary in archive"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Install binary
    install -o root -g root -m 755 "$binary_path" "${INSTALL_DIR}/oracledb_exporter"
    log_success "Installed Oracle exporter to ${INSTALL_DIR}/oracledb_exporter"
    
    # Verify installation
    if "${INSTALL_DIR}/oracledb_exporter" --version >/dev/null 2>&1; then
        log_success "Oracle exporter installation verified"
    else
        log_warning "Could not verify Oracle exporter version (may still work)"
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
}

# Setup configuration directory and files
setup_config() {
    log_info "Setting up configuration directory: $CONFIG_DIR"
    
    # Create config directory
    mkdir -p "$CONFIG_DIR"
    
    # Copy custom metrics file
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [[ -f "${script_dir}/custom-metrics.toml" ]]; then
        cp "${script_dir}/custom-metrics.toml" "${CONFIG_DIR}/"
        log_success "Copied custom metrics configuration"
    else
        log_warning "custom-metrics.toml not found in script directory"
        log_info "Creating basic custom metrics file"
        
        cat > "${CONFIG_DIR}/custom-metrics.toml" << 'EOF'
# Basic Oracle metrics configuration
[[metric]]
context = "oracle_instance_status"
labels = ["instance_name"]
metrics = [
  { name = "up", help = "Oracle instance status (1=up)", kind = "gauge" }
]
request = "SELECT instance_name, 1 as up FROM v$instance"
EOF
    fi
    
    # Set permissions
    chown -R "${EXPORTER_USER}:${EXPORTER_GROUP}" "$CONFIG_DIR"
    chmod 750 "$CONFIG_DIR"
    chmod 640 "${CONFIG_DIR}"/*.toml
    log_success "Set configuration permissions"
}

# Install systemd service
install_service() {
    log_info "Installing systemd service"
    
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"
    
    if [[ -f "${script_dir}/oracledb_exporter.service" ]]; then
        cp "${script_dir}/oracledb_exporter.service" "$service_file"
        log_success "Copied systemd service file"
    else
        log_warning "Service file not found, creating basic service"
        
        cat > "$service_file" << EOF
[Unit]
Description=Prometheus Oracle DB Exporter
After=network-online.target
Wants=network-online.target

[Service]
User=${EXPORTER_USER}
Group=${EXPORTER_GROUP}
Type=simple
Restart=on-failure

Environment="DATA_SOURCE_NAME=oracle://C##PMM:password@127.0.0.1:1521/ORCLCDB"

ExecStart=${INSTALL_DIR}/oracledb_exporter \\
  --web.listen-address=":9161" \\
  --custom.metrics="${CONFIG_DIR}/custom-metrics.toml" \\
  --default.metrics=true

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    log_success "Systemd service installed and enabled"
}

# Check Oracle connectivity prerequisites
check_oracle_prereqs() {
    log_info "Checking Oracle prerequisites"
    
    # Check if Oracle client is available
    if command -v sqlplus >/dev/null 2>&1; then
        log_success "Oracle SQL*Plus client found"
    else
        log_warning "Oracle SQL*Plus not found - you may need Oracle Instant Client"
        log_info "Modern Oracle exporters may use Go drivers and not require Oracle client"
    fi
    
    # Check for Oracle environment variables
    if [[ -n "${ORACLE_HOME:-}" ]]; then
        log_info "ORACLE_HOME is set: $ORACLE_HOME"
    fi
    
    if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
        log_info "LD_LIBRARY_PATH is set: $LD_LIBRARY_PATH"
    fi
}

# Start and check service
start_service() {
    log_info "Starting Oracle exporter service"
    
    if systemctl start "$SERVICE_NAME"; then
        log_success "Service started successfully"
        
        # Wait a moment for startup
        sleep 3
        
        # Check service status
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            log_success "Service is running"
            
            # Test metrics endpoint
            if curl -s http://localhost:9161/metrics >/dev/null; then
                log_success "Metrics endpoint is responding"
            else
                log_warning "Metrics endpoint not responding - check configuration"
            fi
        else
            log_error "Service failed to start"
            log_info "Check logs with: journalctl -u $SERVICE_NAME -n 50"
            return 1
        fi
    else
        log_error "Failed to start service"
        return 1
    fi
}

# Show status and next steps
show_status() {
    echo
    log_info "=== Oracle Exporter Deployment Complete ==="
    echo
    echo "Service Status:"
    systemctl status "$SERVICE_NAME" --no-pager -l || true
    echo
    echo "Configuration:"
    echo "  - Binary: ${INSTALL_DIR}/oracledb_exporter"
    echo "  - Config: ${CONFIG_DIR}/custom-metrics.toml"
    echo "  - Service: /etc/systemd/system/${SERVICE_NAME}.service"
    echo "  - Metrics: http://localhost:9161/metrics"
    echo
    echo "Next Steps:"
    echo "  1. Edit ${CONFIG_DIR}/custom-metrics.toml with your Oracle connection details"
    echo "  2. Update DATA_SOURCE_NAME in /etc/systemd/system/${SERVICE_NAME}.service"
    echo "  3. Restart service: systemctl restart ${SERVICE_NAME}"
    echo "  4. Check logs: journalctl -u ${SERVICE_NAME} -f"
    echo "  5. Add to Prometheus scrape_configs:"
    echo "     - job_name: oracle"
    echo "       static_configs:"
    echo "         - targets: ['localhost:9161']"
    echo
}

# Main execution
main() {
    log_info "Starting Oracle Exporter deployment"
    echo
    
    check_root
    check_oracle_prereqs
    create_user
    install_exporter
    setup_config
    install_service
    
    # Ask if user wants to start service now
    read -p "Start Oracle exporter service now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        start_service
    else
        log_info "Service not started. Start manually with: systemctl start $SERVICE_NAME"
    fi
    
    show_status
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Oracle Exporter Deployment Script"
        echo
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Environment Variables:"
        echo "  EXPORTER_VERSION  Version to install (default: $EXPORTER_VERSION)"
        echo "  EXPORTER_USER     System user name (default: $EXPORTER_USER)"
        echo "  INSTALL_DIR       Binary installation directory (default: $INSTALL_DIR)"
        echo "  CONFIG_DIR        Configuration directory (default: $CONFIG_DIR)"
        echo
        echo "Examples:"
        echo "  $0                           # Install with defaults"
        echo "  EXPORTER_VERSION=0.5.0 $0   # Install specific version"
        echo
        exit 0
        ;;
    --version|-v)
        echo "Oracle Exporter Deployment Script v1.0"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown argument: $1"
        echo "Use $0 --help for usage information"
        exit 1
        ;;
esac