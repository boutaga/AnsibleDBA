#!/bin/bash
# Oracle Database Multi-Instance Exporter Deployment Script
# Supports multiple Oracle exporters on a single monitoring server
# Each exporter targets a different remote Oracle instance

set -euo pipefail

# Configuration
EXPORTER_VERSION="${EXPORTER_VERSION:-0.6.0}"
EXPORTER_USER="${EXPORTER_USER:-sql_exporter}"
EXPORTER_GROUP="${EXPORTER_GROUP:-sql_exporter}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
BASE_CONFIG_DIR="${BASE_CONFIG_DIR:-/etc/oracledb_exporter}"
BASE_PORT="${BASE_PORT:-9161}"

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

# Show usage
show_usage() {
    cat << EOF
Oracle Multi-Instance Exporter Deployment Script

USAGE:
    $0 <command> [options]

COMMANDS:
    setup                           Install base system (binary, user, etc.)
    add <instance-name> [options]   Add new Oracle instance monitoring
    remove <instance-name>          Remove Oracle instance monitoring
    list                           List all configured instances
    status [instance-name]         Show status of instance(s)
    start <instance-name>          Start specific instance
    stop <instance-name>           Stop specific instance
    restart <instance-name>        Restart specific instance
    logs <instance-name>           Show logs for specific instance

ADD OPTIONS:
    --host <hostname>              Oracle server hostname/IP (required)
    --port <port>                  Oracle server port (default: 1521)
    --service <service-name>       Oracle service name (required)
    --user <username>              Oracle monitoring username (default: C##PMM)
    --password <password>          Oracle monitoring password (required)
    --exporter-port <port>         Exporter port (auto-assigned if not specified)
    --config-file <file>           Custom metrics config file (optional)

EXAMPLES:
    # First time setup
    $0 setup

    # Add Oracle instances
    $0 add prod-db1 --host oracle1.company.com --service ORCLCDB --user C##PMM --password secret123
    $0 add test-db2 --host 192.168.1.100 --port 1522 --service TESTDB --user monitoring --password test456
    
    # Manage instances
    $0 list
    $0 status prod-db1
    $0 restart test-db2
    $0 remove old-instance

ENVIRONMENT VARIABLES:
    EXPORTER_VERSION    Version to install (default: $EXPORTER_VERSION)
    EXPORTER_USER       System user name (default: $EXPORTER_USER)
    BASE_CONFIG_DIR     Base configuration directory (default: $BASE_CONFIG_DIR)
    BASE_PORT          Starting port number (default: $BASE_PORT)

EOF
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

# Download and install Oracle exporter binary (if not already installed)
install_exporter() {
    if [[ -f "${INSTALL_DIR}/oracledb_exporter" ]]; then
        log_info "Oracle exporter binary already installed"
        return 0
    fi
    
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

# Setup base configuration
setup_base_config() {
    log_info "Setting up base configuration directory: $BASE_CONFIG_DIR"
    
    # Create base config directory
    mkdir -p "$BASE_CONFIG_DIR"
    chown "${EXPORTER_USER}:${EXPORTER_GROUP}" "$BASE_CONFIG_DIR"
    chmod 750 "$BASE_CONFIG_DIR"
    
    # Create instances registry file
    local registry_file="${BASE_CONFIG_DIR}/instances.conf"
    if [[ ! -f "$registry_file" ]]; then
        cat > "$registry_file" << 'EOF'
# Oracle Exporter Instances Registry
# Format: instance_name:port:config_dir:service_status
# This file is managed automatically by the deployment script
EOF
        chown "${EXPORTER_USER}:${EXPORTER_GROUP}" "$registry_file"
        chmod 640 "$registry_file"
        log_success "Created instances registry"
    fi
    
    # Copy default custom metrics template
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local template_file="${BASE_CONFIG_DIR}/custom-metrics-template.toml"
    
    if [[ ! -f "$template_file" ]]; then
        if [[ -f "${script_dir}/custom-metrics.toml" ]]; then
            cp "${script_dir}/custom-metrics.toml" "$template_file"
            log_success "Copied custom metrics template"
        else
            log_warning "custom-metrics.toml not found, creating basic template"
            cat > "$template_file" << 'EOF'
# Oracle Custom Metrics Template
# This file serves as a template for instance-specific configurations

[[metric]]
context = "oracle_instance_detailed"
labels = ["instance_name", "version", "startup_time"]
metrics = [
  { name = "up", help = "Oracle instance status (1=up)", kind = "gauge" },
  { name = "uptime_seconds", help = "Instance uptime in seconds", kind = "gauge" }
]
request = """
SELECT 
  instance_name,
  version,
  TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI:SS') as startup_time,
  1 as up,
  (SYSDATE - startup_time) * 86400 as uptime_seconds
FROM v$instance
"""
EOF
        fi
        chown "${EXPORTER_USER}:${EXPORTER_GROUP}" "$template_file"
        chmod 640 "$template_file"
    fi
}

# Get next available port
get_next_port() {
    local used_ports
    used_ports=$(awk -F: '/^[^#]/ {print $2}' "${BASE_CONFIG_DIR}/instances.conf" 2>/dev/null | sort -n)
    
    local port=$BASE_PORT
    while [[ -n "$used_ports" ]] && echo "$used_ports" | grep -q "^${port}$"; do
        ((port++))
    done
    
    # Also check if port is actually available
    while netstat -ln 2>/dev/null | grep -q ":${port} "; do
        ((port++))
    done
    
    echo "$port"
}

# Add new Oracle instance
add_instance() {
    local instance_name="$1"
    shift
    
    # Parse arguments
    local host=""
    local port="1521"
    local service=""
    local user="C##PMM"
    local password=""
    local exporter_port=""
    local config_file=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --host)
                host="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --service)
                service="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            --exporter-port)
                exporter_port="$2"
                shift 2
                ;;
            --config-file)
                config_file="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$host" ]]; then
        log_error "Host is required (--host)"
        exit 1
    fi
    
    if [[ -z "$service" ]]; then
        log_error "Service name is required (--service)"
        exit 1
    fi
    
    if [[ -z "$password" ]]; then
        log_error "Password is required (--password)"
        exit 1
    fi
    
    # Check if instance already exists
    if grep -q "^${instance_name}:" "${BASE_CONFIG_DIR}/instances.conf" 2>/dev/null; then
        log_error "Instance '$instance_name' already exists"
        exit 1
    fi
    
    # Get port if not specified
    if [[ -z "$exporter_port" ]]; then
        exporter_port=$(get_next_port)
    fi
    
    log_info "Adding Oracle instance: $instance_name"
    log_info "  Host: $host:$port"
    log_info "  Service: $service"
    log_info "  User: $user"
    log_info "  Exporter Port: $exporter_port"
    
    # Create instance-specific configuration directory
    local instance_config_dir="${BASE_CONFIG_DIR}/${instance_name}"
    mkdir -p "$instance_config_dir"
    
    # Create instance-specific custom metrics file
    local metrics_file="${instance_config_dir}/custom-metrics.toml"
    if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
        cp "$config_file" "$metrics_file"
        log_success "Copied custom config from $config_file"
    else
        cp "${BASE_CONFIG_DIR}/custom-metrics-template.toml" "$metrics_file"
        log_success "Created custom metrics config from template"
    fi
    
    # Create connection string
    local data_source_name="oracle://${user}:${password}@${host}:${port}/${service}"
    
    # Create connection configuration file
    local connection_file="${instance_config_dir}/connection.conf"
    cat > "$connection_file" << EOF
# Oracle connection configuration for ${instance_name}
DATA_SOURCE_NAME=${data_source_name}
EXPORTER_PORT=${exporter_port}
EOF
    
    # Set permissions
    chown -R "${EXPORTER_USER}:${EXPORTER_GROUP}" "$instance_config_dir"
    chmod 750 "$instance_config_dir"
    chmod 640 "$metrics_file"
    chmod 640 "$connection_file"
    
    # Register instance
    echo "${instance_name}:${exporter_port}:${instance_config_dir}:disabled" >> "${BASE_CONFIG_DIR}/instances.conf"
    
    # Ensure systemd template service exists
    local template_service="/etc/systemd/system/oracledb_exporter@.service"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    if [[ ! -f "$template_service" ]] && [[ -f "${script_dir}/oracledb_exporter@.service" ]]; then
        cp "${script_dir}/oracledb_exporter@.service" "$template_service"
        log_success "Installed systemd template service"
    fi
    
    # Reload systemd and enable service
    local service_name="oracledb_exporter@${instance_name}"
    systemctl daemon-reload
    systemctl enable "$service_name"
    
    log_success "Instance '$instance_name' added successfully"
    log_info "Service: $service_name"
    log_info "Config: $instance_config_dir"
    log_info "Metrics: http://localhost:${exporter_port}/metrics"
    log_info ""
    log_info "To start the instance: $0 start $instance_name"
    log_info "To check status: $0 status $instance_name"
}

# Remove Oracle instance
remove_instance() {
    local instance_name="$1"
    
    if ! grep -q "^${instance_name}:" "${BASE_CONFIG_DIR}/instances.conf" 2>/dev/null; then
        log_error "Instance '$instance_name' not found"
        exit 1
    fi
    
    log_info "Removing Oracle instance: $instance_name"
    
    local service_name="oracledb_exporter@${instance_name}"
    
    # Stop and disable service
    if systemctl is-active --quiet "$service_name"; then
        systemctl stop "$service_name"
        log_info "Stopped service"
    fi
    
    if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        systemctl disable "$service_name"
        log_info "Disabled service"
    fi
    
    # Remove service file
    local service_file="/etc/systemd/system/${service_name}.service"
    if [[ -f "$service_file" ]]; then
        rm "$service_file"
        log_info "Removed service file"
    fi
    
    # Remove configuration directory
    local instance_config_dir="${BASE_CONFIG_DIR}/${instance_name}"
    if [[ -d "$instance_config_dir" ]]; then
        rm -rf "$instance_config_dir"
        log_info "Removed configuration directory"
    fi
    
    # Remove from registry
    sed -i "/^${instance_name}:/d" "${BASE_CONFIG_DIR}/instances.conf"
    
    # Reload systemd
    systemctl daemon-reload
    
    log_success "Instance '$instance_name' removed successfully"
}

# List all instances
list_instances() {
    local registry_file="${BASE_CONFIG_DIR}/instances.conf"
    
    if [[ ! -f "$registry_file" ]]; then
        log_info "No instances configured"
        return 0
    fi
    
    echo
    printf "%-20s %-8s %-50s %-10s\n" "INSTANCE" "PORT" "CONFIG" "STATUS"
    printf "%-20s %-8s %-50s %-10s\n" "--------" "----" "------" "------"
    
    while IFS=: read -r name port config_dir status; do
        [[ $name =~ ^[[:space:]]*# ]] && continue
        [[ -z "$name" ]] && continue
        
        local service_name="oracledb_exporter@${name}"
        local actual_status="unknown"
        
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            actual_status="running"
        elif systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
            actual_status="stopped"
        else
            actual_status="disabled"
        fi
        
        printf "%-20s %-8s %-50s %-10s\n" "$name" "$port" "$config_dir" "$actual_status"
    done < "$registry_file"
    
    echo
}

# Show status of instance(s)
show_status() {
    local instance_name="${1:-}"
    
    if [[ -n "$instance_name" ]]; then
        # Show specific instance
        local service_name="oracledb_exporter@${instance_name}"
        if systemctl list-unit-files | grep -q "${service_name}.service"; then
            echo "=== Status for $instance_name ==="
            systemctl status "$service_name" --no-pager -l || true
            echo
            
            # Check metrics endpoint
            local port
            port=$(awk -F: "/^${instance_name}:/ {print \$2}" "${BASE_CONFIG_DIR}/instances.conf" 2>/dev/null)
            if [[ -n "$port" ]]; then
                echo "Metrics endpoint: http://localhost:${port}/metrics"
                if curl -s --connect-timeout 5 "http://localhost:${port}/metrics" >/dev/null 2>&1; then
                    echo "Metrics endpoint: ✓ RESPONDING"
                else
                    echo "Metrics endpoint: ✗ NOT RESPONDING"
                fi
            fi
        else
            log_error "Instance '$instance_name' not found"
            exit 1
        fi
    else
        # Show all instances
        list_instances
    fi
}

# Start instance
start_instance() {
    local instance_name="$1"
    local service_name="oracledb_exporter@${instance_name}"
    
    if ! systemctl list-unit-files | grep -q "${service_name}.service"; then
        log_error "Instance '$instance_name' not found"
        exit 1
    fi
    
    log_info "Starting instance: $instance_name"
    
    if systemctl start "$service_name"; then
        log_success "Instance started successfully"
        
        # Update registry status
        sed -i "s/^${instance_name}:\([^:]*\):\([^:]*\):.*/${instance_name}:\1:\2:enabled/" "${BASE_CONFIG_DIR}/instances.conf"
        
        # Wait and check status
        sleep 3
        if systemctl is-active --quiet "$service_name"; then
            log_success "Instance is running"
        else
            log_warning "Instance may have failed to start properly"
            log_info "Check logs with: $0 logs $instance_name"
        fi
    else
        log_error "Failed to start instance"
        exit 1
    fi
}

# Stop instance
stop_instance() {
    local instance_name="$1"
    local service_name="oracledb_exporter@${instance_name}"
    
    if ! systemctl list-unit-files | grep -q "${service_name}.service"; then
        log_error "Instance '$instance_name' not found"
        exit 1
    fi
    
    log_info "Stopping instance: $instance_name"
    
    if systemctl stop "$service_name"; then
        log_success "Instance stopped successfully"
        
        # Update registry status
        sed -i "s/^${instance_name}:\([^:]*\):\([^:]*\):.*/${instance_name}:\1:\2:disabled/" "${BASE_CONFIG_DIR}/instances.conf"
    else
        log_error "Failed to stop instance"
        exit 1
    fi
}

# Restart instance
restart_instance() {
    local instance_name="$1"
    local service_name="oracledb_exporter@${instance_name}"
    
    if ! systemctl list-unit-files | grep -q "${service_name}.service"; then
        log_error "Instance '$instance_name' not found"
        exit 1
    fi
    
    log_info "Restarting instance: $instance_name"
    
    if systemctl restart "$service_name"; then
        log_success "Instance restarted successfully"
        
        # Wait and check status
        sleep 3
        if systemctl is-active --quiet "$service_name"; then
            log_success "Instance is running"
        else
            log_warning "Instance may have failed to restart properly"
            log_info "Check logs with: $0 logs $instance_name"
        fi
    else
        log_error "Failed to restart instance"
        exit 1
    fi
}

# Show logs for instance
show_logs() {
    local instance_name="$1"
    local service_name="oracledb_exporter@${instance_name}"
    
    if ! systemctl list-unit-files | grep -q "${service_name}.service"; then
        log_error "Instance '$instance_name' not found"
        exit 1
    fi
    
    log_info "Showing logs for instance: $instance_name"
    echo "Use Ctrl+C to exit log view"
    echo
    
    journalctl -u "$service_name" -f
}

# Install systemd template service
install_template_service() {
    log_info "Installing systemd template service"
    
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local template_service="/etc/systemd/system/oracledb_exporter@.service"
    
    if [[ -f "${script_dir}/oracledb_exporter@.service" ]]; then
        cp "${script_dir}/oracledb_exporter@.service" "$template_service"
        log_success "Installed systemd template service"
    else
        log_warning "Template service file not found, creating basic template"
        
        cat > "$template_service" << EOF
[Unit]
Description=Prometheus Oracle DB Exporter for %i
After=network-online.target
Wants=network-online.target

[Service]
User=${EXPORTER_USER}
Group=${EXPORTER_GROUP}
Type=simple
Restart=on-failure
RestartSec=5

# Instance-specific configuration directory
EnvironmentFile=/etc/oracledb_exporter/%i/connection.conf

ExecStart=${INSTALL_DIR}/oracledb_exporter \\
  --web.listen-address=":\${EXPORTER_PORT}" \\
  --custom.metrics="/etc/oracledb_exporter/%i/custom-metrics.toml" \\
  --default.metrics=true \\
  --log.level=info

# Resource limits
MemoryLimit=256M
CPUQuota=50%

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/tmp

[Install]
WantedBy=multi-user.target
EOF
        log_success "Created systemd template service"
    fi
    
    systemctl daemon-reload
}

# Setup base system
setup_system() {
    log_info "Setting up Oracle Multi-Instance Exporter base system"
    
    check_root
    create_user
    install_exporter
    setup_base_config
    install_template_service
    
    log_success "Base system setup complete"
    log_info "You can now add Oracle instances with: $0 add <instance-name> [options]"
}

# Main script logic
case "${1:-}" in
    setup)
        setup_system
        ;;
    add)
        if [[ $# -lt 2 ]]; then
            log_error "Instance name required for 'add' command"
            show_usage
            exit 1
        fi
        check_root
        add_instance "${@:2}"
        ;;
    remove)
        if [[ $# -lt 2 ]]; then
            log_error "Instance name required for 'remove' command"
            exit 1
        fi
        check_root
        remove_instance "$2"
        ;;
    list)
        list_instances
        ;;
    status)
        show_status "${2:-}"
        ;;
    start)
        if [[ $# -lt 2 ]]; then
            log_error "Instance name required for 'start' command"
            exit 1
        fi
        check_root
        start_instance "$2"
        ;;
    stop)
        if [[ $# -lt 2 ]]; then
            log_error "Instance name required for 'stop' command"
            exit 1
        fi
        check_root
        stop_instance "$2"
        ;;
    restart)
        if [[ $# -lt 2 ]]; then
            log_error "Instance name required for 'restart' command"
            exit 1
        fi
        check_root
        restart_instance "$2"
        ;;
    logs)
        if [[ $# -lt 2 ]]; then
            log_error "Instance name required for 'logs' command"
            exit 1
        fi
        show_logs "$2"
        ;;
    --help|-h|help)
        show_usage
        ;;
    "")
        log_error "Command required"
        show_usage
        exit 1
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac